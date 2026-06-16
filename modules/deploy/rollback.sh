#!/usr/bin/env bash
# modules/deploy/rollback.sh
# Xử lý quy trình Rollback khôi phục phiên bản cũ cho ứng dụng

#-----------------------------------------------------------------------------
# Hàm:          run_rollback
# Mô tả:        Khôi phục mã nguồn và cấu trúc database về phiên bản triển khai trước đó.
# Biến toàn cục: APP_DOMAIN, SCRIPT_DIR, APP_USER, PHP_VERSION
# Tham số:      Không có
# Trả về:       0 nếu thành công, 1 nếu thất bại
#-----------------------------------------------------------------------------
run_rollback() {
    # Khởi tạo các đường dẫn động dựa trên APP_DOMAIN
    local BASE_DIR="/var/www/${APP_DOMAIN}"
    local RELEASES_DIR="${BASE_DIR}/releases"
    local CURRENT_DIR="${BASE_DIR}/current"
    local SITE_ENV_FILE="$SCRIPT_DIR/sites/.env.${APP_DOMAIN}"

    # Kiểm tra Website có tồn tại thật hay không
    if [ ! -d "$BASE_DIR" ] || [ ! -f "$SITE_ENV_FILE" ]; then
        error "Lỗi: Site '${APP_DOMAIN}' không tồn tại hoặc chưa cấu hình."
        return 1
    fi

    info "Khởi động thủ tục Rollback cho domain: ${APP_DOMAIN}..."

    # Kiểm tra sự tồn tại của thư mục releases
    if [ ! -d "$RELEASES_DIR" ]; then
        error "Lỗi: Thư mục 'releases' không tồn tại. Không tìm thấy bản triển khai cũ."
        return 1
    fi

    cd "$RELEASES_DIR" || { error "Không tìm kiếm được thư mục $RELEASES_DIR"; return 1; }
    
    # Xác định bản hiện tại (bản lỗi) và bản trước đó để khôi phục (rollback)
    local CURRENT_FAILED_RELEASE_NAME
    local PREV_RELEASE_NAME
    CURRENT_FAILED_RELEASE_NAME=$(ls -1t | sed -n '1p')
    PREV_RELEASE_NAME=$(ls -1t | sed -n '2p')
    
    if [ -z "$PREV_RELEASE_NAME" ]; then
        error "Lỗi: Không tìm thấy bản release cũ để khôi phục."
        return 1
    fi
    
    local TARGET_ROLLBACK="${RELEASES_DIR}/${PREV_RELEASE_NAME}"
    local CURRENT_FAILED_RELEASE="${RELEASES_DIR}/${CURRENT_FAILED_RELEASE_NAME}"

    # Cảnh báo và hỏi xác nhận Rollback Database
    echo ""
    warn "=========================================================================="
    warn "                CẢNH BÁO QUAN TRỌNG VỀ DATABASE                           "
    warn "=========================================================================="
    warn "Việc Rollback Migrations sẽ làm thay đổi cấu trúc dữ liệu."
    warn " - Dữ liệu tại các cột/bảng mới vừa tạo sẽ bị xóa vĩnh viễn."
    warn " - Chỉ thực hiện nếu thực sự cần thiết cho code cũ hoạt động."
    warn "=========================================================================="
    
    # Lựa chọn mặc định là Không (y/N)
    local confirm_db
    read -p "Xác nhận khôi phục cấu trúc Database (Rollback Migrations)? (y/N): " confirm_db
    
    if [[ "$confirm_db" =~ ^[Yy]$ ]]; then
        if [ -f "${CURRENT_FAILED_RELEASE}/artisan" ]; then
            info "Hành động được xác nhận. Đang tiến hành khôi phục cấu trúc Database..."
            cd "$CURRENT_FAILED_RELEASE" && sudo -u "$APP_USER" php${PHP_VERSION} artisan migrate:rollback --force || warn "⚠️ Không thể rollback database tự động. Anh hãy kiểm tra thủ công!"
        else
            warn "⚠️ Không tìm thấy file artisan trong bản lỗi để thực hiện Rollback DB."
        fi
    else
        info "Đã bỏ qua quy trình Rollback Database."
    fi

    # Tiếp tục rollback phần Code bằng cách trỏ lại Symlink 'current'
    info "Khôi phục symlink current về phiên bản: $PREV_RELEASE_NAME..."
    sudo -u "$APP_USER" ln -nfs "$TARGET_ROLLBACK" "$CURRENT_DIR" || { error "Lỗi: Không thể hoán đổi symlink"; return 1; }

    # Xóa bỏ hoàn toàn bản release lỗi để giải phóng dung lượng đĩa cứng
    if [ -d "$CURRENT_FAILED_RELEASE" ]; then
        info "Xóa bản release bị lỗi để giải phóng dung lượng..."
        rm -rf "$CURRENT_FAILED_RELEASE"
        info "Hoàn tất xóa bản lỗi."
    fi
    
    # Xoá views cache để load source cũ an toàn
    cd "$TARGET_ROLLBACK"
    sudo -u "$APP_USER" php${PHP_VERSION} artisan view:clear || true
    sudo -u "$APP_USER" php${PHP_VERSION} artisan config:clear || true
    
    # Khởi động lại PHP pool và Supervisor
    systemctl reload "php${PHP_VERSION}-fpm"
    local SAFE_DOMAIN=$(get_safe_domain "$APP_DOMAIN")
    info "Khởi động lại các dịch vụ Supervisor: group [ ${SAFE_DOMAIN} ]..."
    supervisorctl restart "${SAFE_DOMAIN}:*" || true
    
    info "================================================================="
    info " THÀNH CÔNG: Đã khôi phục về bản release: $PREV_RELEASE_NAME"
    info "================================================================="
}
