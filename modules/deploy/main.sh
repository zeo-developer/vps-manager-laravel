#!/usr/bin/env bash
# modules/deploy/main.sh
# Xử lý quy trình Deploy Zero-Downtime cho ứng dụng

# =============================================================================
# KHU VỰC KHAI BÁO HÀM (HELPER FUNCTIONS)
# =============================================================================

#-----------------------------------------------------------------------------
# Hàm:          run_migration_with_detection
# Mô tả:        Thực thi database migrations và phát hiện xem có bảng/cột mới nào không.
#-----------------------------------------------------------------------------
run_migration_with_detection() {
    local app_path="${1:-/var/www/$APP_DOMAIN/current}"
    local migrate_output=""
    local status=0

    MIGRATE_NEW=false

    migrate_output=$(sudo -u "$APP_USER" php${PHP_VERSION} "${app_path}/artisan" migrate --force 2>&1)
    status=$?

    echo "$migrate_output"

    if [[ "$migrate_output" != *"Nothing to migrate"* ]]; then
        MIGRATE_NEW=true
    fi

    return $status
}

#-----------------------------------------------------------------------------
# Hàm:          rollback_new_migrations_if_needed
# Mô tả:        Tự động khôi phục cấu trúc DB nếu tiến trình build bị lỗi sau khi migrate.
#-----------------------------------------------------------------------------
rollback_new_migrations_if_needed() {
    local app_path="${1:-/var/www/$APP_DOMAIN/current}"
    if [ "$MIGRATE_NEW" = true ]; then
        warn "Phát hiện migration mới. Đang rollback database tại $app_path..."
        sudo -u "$APP_USER" php${PHP_VERSION} "${app_path}/artisan" migrate:rollback --force || warn "⚠️ Rollback DB tự động thất bại"
    fi
}

#-----------------------------------------------------------------------------
# Hàm:          cleanup_failed_release
# Mô tả:        Dọn dẹp thư mục release mới nếu quy trình deploy thất bại.
# Tham số:      (Đọc các biến local từ hàm run_deploy thông qua scope động của Bash)
#-----------------------------------------------------------------------------
cleanup_failed_release() {
    if [ -d "$NEW_RELEASE" ]; then
        cd "$NEW_RELEASE" || return 1
        rollback_new_migrations_if_needed "$NEW_RELEASE"
        cd "$RELEASES_DIR" || cd /tmp
        warn "Lỗi tiến trình build. Đang dọn dẹp release: $TIMESTAMP"
        rm -rf "$NEW_RELEASE"
    fi
}

# =============================================================================
# LUỒNG THỰC THI CHÍNH (MAIN DEPLOY PIPELINE)
# =============================================================================

run_deploy() {
    # Nạp tuần tự các Phase của tiến trình Deploy
    # Dùng source để các phase script có thể dùng chung biến local của hàm này
    source "$SCRIPT_DIR/modules/deploy/phases/preflight.sh" || return 1
    source "$SCRIPT_DIR/modules/deploy/phases/fetch.sh" || return 1
    source "$SCRIPT_DIR/modules/deploy/phases/build.sh" || return 1
    source "$SCRIPT_DIR/modules/deploy/phases/artisan.sh" || return 1
    source "$SCRIPT_DIR/modules/deploy/phases/service.sh" || return 1
    source "$SCRIPT_DIR/modules/deploy/phases/cleanup.sh" || return 1
}
