# modules/deploy/phases/build.sh

# -------------------------------------------------------------------------
# PHASE 3: CÀI ĐẶT & BIÊN DỊCH (INSTALL & BUILD)
# -------------------------------------------------------------------------
cd "$NEW_RELEASE"
if [ -f "composer.json" ]; then
    sudo -u "$APP_USER" php${PHP_VERSION} /usr/local/bin/composer install --no-interaction --prefer-dist --optimize-autoloader --no-dev || { cleanup_failed_release; error "Lỗi khi chạy composer install"; return 1; }
fi

if [ -f "package.json" ]; then
    info "Tự động cài đặt & Build NPM packages bằng Node.js ${NODE_VERSION:-20}.x..."
    sudo -u "$APP_USER" npm${NODE_VERSION:-20} install || { cleanup_failed_release; error "Lỗi khi chạy npm install"; return 1; }
    run_npm_build "$APP_DOMAIN" "$APP_USER" "$NEW_RELEASE" || { cleanup_failed_release; return 1; }
fi
