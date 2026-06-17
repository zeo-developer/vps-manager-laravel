# modules/deploy/phases/artisan.sh

# -------------------------------------------------------------------------
# PHASE 4: TỐI ƯU HÓA BACKEND (ARTISAN TASKS)
# -------------------------------------------------------------------------
if [ -f "artisan" ]; then
    if ! grep -q "APP_KEY=base64:" "${SHARED_DIR}/.env"; then
        run_artisan_key_generate "$APP_DOMAIN" "$APP_USER" "php${PHP_VERSION}" "$NEW_RELEASE" || { cleanup_failed_release; return 1; }
    fi

    if grep -q "^JWT_SECRET=$" "${SHARED_DIR}/.env"; then
        info "Phát hiện cấu hình JWT_SECRET rỗng. Tiến hành tự động tạo khóa JWT..."
        run_artisan_jwt_secret "$APP_DOMAIN" "$APP_USER" "php${PHP_VERSION}" "$NEW_RELEASE" || warn "⚠️ Không thể tự động tạo JWT Secret"
    fi

    run_artisan_storage_link "$APP_DOMAIN" "$APP_USER" "php${PHP_VERSION}" "$NEW_RELEASE" || warn "⚠️ Không thể tạo storage:link"
    
    info "Thực thi Database Migrations..."
    run_migration_with_detection "$NEW_RELEASE" || { cleanup_failed_release; error "Lỗi khi chạy migration"; return 1; }

    info "Tiến hành Tối ưu hóa Cache hệ thống..."
    run_optimize_cache "$APP_DOMAIN" "$APP_USER" "php${PHP_VERSION}" "$NEW_RELEASE" || { cleanup_failed_release; return 1; }
fi

local SAFE_DOMAIN=$(get_safe_domain "$APP_DOMAIN")
local supervisor_conf="/etc/supervisor/conf.d/${SAFE_DOMAIN}.conf"

if [ -f "$supervisor_conf" ] && grep -q "^\[program:${SAFE_DOMAIN}-ssr\]" "$supervisor_conf" && [ -f "package.json" ]; then
    if grep -q "build:ssr" "$NEW_RELEASE/package.json"; then
        info "Tự động Build ứng dụng Inertia SSR..."
        run_npm_build_ssr "$APP_DOMAIN" "$APP_USER" "$NEW_RELEASE" || { cleanup_failed_release; return 1; }
    fi
fi
