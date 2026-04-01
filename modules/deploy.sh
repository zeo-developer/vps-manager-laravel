#!/usr/bin/env bash
# modules/deploy.sh
# Xử lý quy trình Deploy Zero-Downtime & Rollback

# Các biến đường dẫn sẽ được khởi tạo động bên trong hàm run_deploy

run_deploy() {
    # [FIX V31.0] Kiểm tra Website có tồn tại thật hay không (Dựa trên file env của site)
    local SITE_ENV_FILE="$SCRIPT_DIR/sites/.env.${APP_DOMAIN}"
    if [ ! -f "$SITE_ENV_FILE" ]; then
        error "❌ Lỗi: Website [ ${APP_DOMAIN} ] chưa được khởi tạo. Vui lòng sử dụng lệnh 'vps add-site' trước!"
        return 1
    fi

    info "Bắt đầu quy trình Deploy Zero-Downtime (Domain: $APP_DOMAIN)..."

    # [FIX V18.2] Khởi tạo các đường dẫn động dựa trên APP_DOMAIN
    local BASE_DIR="/var/www/${APP_DOMAIN}"
    local RELEASES_DIR="${BASE_DIR}/releases"
    local SHARED_DIR="${BASE_DIR}/shared"
    local CURRENT_DIR="${BASE_DIR}/current"

    # [FIX V18.2] Đảm bảo quyền sở hữu cho APP_USER
    chown -R "$APP_USER":"$APP_USER" "$BASE_DIR"

    # [FIX V26.0] Kiểm tra và Hỏi Git Repo nếu chưa có
    if [ -z "$GIT_REPO" ] || [ "$GIT_REPO" = "git_repo_url" ]; then
        info "⚠️ Cần cấu hình Git Repository cho website [ ${APP_DOMAIN} ]."
        while true; do
            read -p "Nhập Git Repo URL (vd: git@github.com:user/repo.git): " input_repo
            
            # Gỡ bỏ khoảng trắng thừa
            input_repo=$(echo "$input_repo" | xargs)

            # [FIX V26.0] Logic Tự động chuyển đổi HTTPS sang SSH (GitHub/GitLab/Bitbucket)
            if [[ "$input_repo" =~ ^https://(github\.com|gitlab\.com|bitbucket\.org)/(.+) ]]; then
                local provider="${BASH_REMATCH[1]}"
                local path="${BASH_REMATCH[2]}"
                # Loại bỏ đuôi .git nếu có để chuẩn hóa
                path="${path%.git}"
                
                local ssh_url="git@${provider}:${path}.git"
                warn "⚠️ Bạn đang sử dụng URL HTTPS. SSH Key sẽ KHÔNG có tác dụng với HTTPS."
                read -p "Bạn có muốn tự động chuyển sang SSH URL: [ ${ssh_url} ]? (y/n): " convert_choice
                if [[ "$convert_choice" =~ ^[Yy]$ ]]; then
                    input_repo="$ssh_url"
                    info "✅ Đã chuyển đổi sang giao thức SSH."
                fi
            fi

            if [[ "$input_repo" =~ ^git@ ]]; then
                GIT_REPO="$input_repo"
                local site_env_file="$SCRIPT_DIR/sites/.env.${APP_DOMAIN}"
                # Cập nhật hoặc Thêm mới dòng GIT_REPO
                if grep -q "^GIT_REPO=" "$site_env_file"; then
                    sed -i "s|^GIT_REPO=.*|GIT_REPO=\"${GIT_REPO}\"|g" "$site_env_file"
                else
                    echo "GIT_REPO=\"${GIT_REPO}\"" >> "$site_env_file"
                fi
                info "✅ Đã lưu Git Repo: ${GIT_REPO}"
                break
            elif [[ "$input_repo" =~ ^https:// ]]; then
                warn "⚠️ Cảnh báo: Sử dụng HTTPS có thể yêu cầu mật khẩu thủ công."
                GIT_REPO="$input_repo"
                break
            else
                warn "❌ Định dạng URL không hợp lệ! Nên sử dụng dạng 'git@...' để chạy mượt nhất."
            fi
        done
    fi

    # [FIX V27.2] Đảm bảo toàn bộ cấu trúc log tồn tại bằng lệnh tường minh (Tránh lỗi Brace Expansion)
    mkdir -p "${RELEASES_DIR}"
    mkdir -p "${SHARED_DIR}/storage/logs"
    mkdir -p "${SHARED_DIR}/storage/app/public"
    mkdir -p "${SHARED_DIR}/storage/framework/cache"
    mkdir -p "${SHARED_DIR}/storage/framework/sessions"
    mkdir -p "${SHARED_DIR}/storage/framework/views"

    chown -R "$APP_USER":"$APP_USER" "${RELEASES_DIR}" "${SHARED_DIR}"

    local TIMESTAMP=$(date +"%Y%m%d%H%M%S")
    local NEW_RELEASE="${RELEASES_DIR}/${TIMESTAMP}"

    # [FIX V25.1] Hàm dọn dẹp nội bộ nếu quy trình build thất bại
    cleanup_failed_release() {
        if [ -d "$NEW_RELEASE" ]; then
            # [FIX V25.2] Quay về thư mục an toàn trước khi xóa thư mục hiện hành
            cd "$RELEASES_DIR" || cd /tmp
            warn "Phát hiện lỗi trong quá trình build. Đang dọn dẹp release dở dang: $TIMESTAMP"
            rm -rf "$NEW_RELEASE"

            # [FIX V28.1] Dọn dẹp Supervisor nếu là lần deploy ĐẦU TIÊN thất bại
            # Nếu CURRENT_DIR không phải là symlink (tức là chưa từng deploy thành công)
            if [ ! -L "$CURRENT_DIR" ]; then
                warn "Phát hiện deploy lần đầu thất bại. Đang tạm gỡ cấu hình Supervisor..."
                rm -f "/etc/supervisor/conf.d/worker-${APP_DOMAIN}.conf"
                rm -f "/etc/supervisor/conf.d/ssr-${APP_DOMAIN}.conf"
                # Nạp lại để Supervisor không báo lỗi file config rác
                supervisorctl reread > /dev/null 2>&1
                supervisorctl update > /dev/null 2>&1
            fi
        fi
    }

    # Clone bằng quyền user ứng dụng với SSH Key riêng biệt
    info "Sử dụng SSH Key riêng biệt: $SSH_KEY_PATH"
    # [FIX V18.2] Cho phép hiển thị lỗi git clone để dễ debug
    sudo -u "$APP_USER" GIT_SSH_COMMAND="ssh -i ${SSH_KEY_PATH} -o StrictHostKeyChecking=no" \
        git clone "$GIT_REPO" "$NEW_RELEASE" || { cleanup_failed_release; error "Lỗi: Không thể clone mã nguồn từ Git!"; return 1; }

    # 2. Xử lý Shared Storage và Env
    info "Liên kết file .env và thư mục /storage/ ..."
    # Lần đầu Clone web: Trộn file .env.example của Mã nguồn Laravel với Cấu hình Tốc độ Của Server
    if [ ! -f "${SHARED_DIR}/.env" ]; then
        info "Khởi tạo file .env đầu tiên cho Laravel từ thư mục mã nguồn..."
        if [ -f "${NEW_RELEASE}/.env.example" ]; then
            cp "${NEW_RELEASE}/.env.example" "${SHARED_DIR}/.env"
        else
            touch "${SHARED_DIR}/.env"
        fi
        
        # Tiêm tự động (Inject) Thông số Database và Domain ngầm vào .env của Laravel
        if [ -f "$SCRIPT_DIR/sites/.env.${APP_DOMAIN}" ]; then
            source "$SCRIPT_DIR/sites/.env.${APP_DOMAIN}"
            
            sed -i "s|^APP_URL=.*|APP_URL=https://${APP_DOMAIN}|g" "${SHARED_DIR}/.env"
            sed -i "s/^DB_DATABASE=.*/DB_DATABASE=${DB_NAME}/g" "${SHARED_DIR}/.env"
            sed -i "s/^DB_USERNAME=.*/DB_USERNAME=${DB_USER}/g" "${SHARED_DIR}/.env"
            sed -i "s/^DB_PASSWORD=.*/DB_PASSWORD=${DB_PASSWORD}/g" "${SHARED_DIR}/.env"

            # Đổi môi trường cơ bản thành Production
            sed -i "s/^APP_ENV=.*/APP_ENV=production/g" "${SHARED_DIR}/.env"
            sed -i "s/^APP_DEBUG=.*/APP_DEBUG=false/g" "${SHARED_DIR}/.env"
        fi
        
        chown "$APP_USER":"$APP_USER" "${SHARED_DIR}/.env"
        
        # [FIX V24.1] Khối này sẽ được dời xuống sau Composer Install để đảm bảo có vendor/autoload.php
        info "Chuẩn bị file .env trong shared..."
    fi
    
    # Xoá storage rỗng của git clone và chèn symlink tới shared/storage
    rm -rf "${NEW_RELEASE}/storage"
    sudo -u "$APP_USER" ln -s "${SHARED_DIR}/storage" "${NEW_RELEASE}/storage" || { cleanup_failed_release; error "Không thể tạo symlink cho storage"; return 1; }
    
    # [FIX V24.1] Đảm bảo xoá file .env cũ trong source (nếu có) trước khi link
    rm -f "${NEW_RELEASE}/.env"
    sudo -u "$APP_USER" ln -s "${SHARED_DIR}/.env" "${NEW_RELEASE}/.env" || { cleanup_failed_release; error "Không thể tạo symlink cho .env"; return 1; }

    # 3. Build Dependencies
    info "Trỏ đến $NEW_RELEASE: Cài đặt Composer Packages (Sử dụng PHP ${PHP_VERSION})..."
    cd "$NEW_RELEASE" || error "Không thể truy cập thư mục release: $NEW_RELEASE"
    
    # [FIX V24.1] Ép chạy Composer bằng phiên bản PHP của dự án
    if [ -f "composer.json" ]; then
        sudo -u "$APP_USER" php${PHP_VERSION} /usr/local/bin/composer install --no-interaction --prefer-dist --optimize-autoloader --no-dev || { cleanup_failed_release; error "Lỗi khi chạy composer install"; return 1; }
    fi

    # [FIX V24.1] Di dời key:generate xuống sau khi đã có vendor/
    if [ -f "artisan" ]; then
        # Kiểm tra nếu chưa có APP_KEY trong .env thì mới tạo
        if ! grep -q "APP_KEY=base64:" "${SHARED_DIR}/.env"; then
            info "Tạo APP_KEY cho dự án mới..."
            sudo -u "$APP_USER" php${PHP_VERSION} artisan key:generate --force || { cleanup_failed_release; error "Lỗi khi tạo APP_KEY"; return 1; }
        fi
    fi
    
    # [FIX V24.1] Sửa quyền NPM Cache để tránh lỗi EACCES
    mkdir -p /var/www/.npm
    chown -R "$APP_USER":"$APP_USER" /var/www/.npm

    # Kiểm tra file package.json trước khi chạy npm
    if [ -f "package.json" ]; then
        info "Cài đặt và Build NPM Packages (Vite)..."
        sudo -u "$APP_USER" npm install || { cleanup_failed_release; error "Lỗi khi chạy npm install"; return 1; }
        sudo -u "$APP_USER" npm run build || { cleanup_failed_release; error "Lỗi khi chạy npm run build"; return 1; }
    fi

    # 4. Laravel Artisan commands (Sử dụng PHP ${PHP_VERSION})
    info "Chạy Migrations và Optimizing Caches..."
    if [ -f "artisan" ]; then
        sudo -u "$APP_USER" php${PHP_VERSION} artisan migrate --force || { cleanup_failed_release; error "Lỗi khi chạy migration"; return 1; }
        sudo -u "$APP_USER" php${PHP_VERSION} artisan optimize:clear || { cleanup_failed_release; error "Lỗi khi clear optimize"; return 1; }
        sudo -u "$APP_USER" php${PHP_VERSION} artisan config:cache || { cleanup_failed_release; error "Lỗi khi cache config"; return 1; }
        sudo -u "$APP_USER" php${PHP_VERSION} artisan route:cache || { cleanup_failed_release; error "Lỗi khi cache route"; return 1; }
        sudo -u "$APP_USER" php${PHP_VERSION} artisan view:cache || { cleanup_failed_release; error "Lỗi khi cache view"; return 1; }
    else
        warn "⚠️ Không tìm thấy file 'artisan', bỏ qua các lệnh Laravel."
    fi

    # 4.1 Xử lý JWT Secret (Nếu có)
    if [ "$USE_JWT" = "true" ]; then
        info "Đang tạo JWT Secret phục vụ xác thực..."
        sudo -u "$APP_USER" php${PHP_VERSION} artisan jwt:secret --force || true
    fi

    # 4.2 Xử lý Inertia SSR (Nếu có)
    if [ "$USE_SSR" = "true" ]; then
        info "Đang Build Inertia SSR..."
        # Kiểm tra lệnh build ssr trong package.json
        if grep -q "build:ssr" "$NEW_RELEASE/package.json"; then
            sudo -u "$APP_USER" npm run build:ssr || { cleanup_failed_release; error "Lỗi khi build SSR"; return 1; }
        else
            warn "Không tìm thấy script 'build:ssr', bỏ qua bước build SSR."
        fi
    fi

    # 5. Kích hoạt Zero-Downtime Symlink
    info "Hoán đổi symlink gốc 'current' sang bản Release mới nhất..."
    sudo -u "$APP_USER" ln -nfs "$NEW_RELEASE" "$CURRENT_DIR" || { cleanup_failed_release; error "Không thể hoán đổi symlink current"; return 1; }
    
    # Restart php-fpm mềm để giải phóng OPcache cũ
    systemctl reload "php${PHP_VERSION}-fpm"
    
    # [FIX V20.1] Kích hoạt Supervisor (Lần đầu hoặc Cập nhật)
    info "Đang nạp cấu hình Supervisor và kích hoạt Workers..."
    supervisorctl reread
    supervisorctl update
    
    # Restart/Start Laravel Queue workers / SSR
    info "Khởi động lại các tác vụ Supervisor cho [ ${APP_DOMAIN} ]..."
    supervisorctl restart "worker-${APP_DOMAIN}:*" || supervisorctl start "worker-${APP_DOMAIN}:*" || true
    if [ "$USE_SSR" = "true" ]; then
        supervisorctl restart "ssr-${APP_DOMAIN}" || supervisorctl start "ssr-${APP_DOMAIN}" || true
    fi

    # [FIX V20.1] Đăng ký Cronjob Laravel Scheduler (Chỉ chạy khi có code)
    info "Đảm bảo Laravel Scheduler (Cronjob) đã được đăng ký..."
    local CRON_CMD="* * * * * cd ${CURRENT_DIR} && php artisan schedule:run >> /dev/null 2>&1"
    if ! sudo -u "$APP_USER" crontab -l 2>/dev/null | grep -q "cd ${CURRENT_DIR}"; then
        (sudo -u "$APP_USER" crontab -l 2>/dev/null; echo "$CRON_CMD") | sudo -u "$APP_USER" crontab -
        info "✅ Crontab Scheduler cho domain [ ${APP_DOMAIN} ] đã được kích hoạt."
    fi

    # 6. Dọn dẹp bản release cũ (giữ lại 3 bản gần nhất)
    info "Dọn dẹp Releases cũ (Giữ lại 3 bản)..."
    cd "$RELEASES_DIR"
    ls -1t | tail -n +4 | xargs -r rm -rf

    info "================================================================="
    info "TRIỂN KHAI THÀNH CÔNG \n RELEASE MỚI VÀO: $NEW_RELEASE !"
    info "================================================================="
    
    # Móc call API Report (Module monitor)
    # bash monitor.sh send_telegram "Deploy Thành Công lên release: ${TIMESTAMP}"
}

run_rollback() {
    # [FIX V30.0] Khởi tạo các đường dẫn động dựa trên APP_DOMAIN
    local BASE_DIR="/var/www/${APP_DOMAIN}"
    local RELEASES_DIR="${BASE_DIR}/releases"
    local CURRENT_DIR="${BASE_DIR}/current"
    local SITE_ENV_FILE="$SCRIPT_DIR/sites/.env.${APP_DOMAIN}"

    # Kiểm tra Website có tồn tại thật hay không
    if [ ! -d "$BASE_DIR" ] || [ ! -f "$SITE_ENV_FILE" ]; then
        error "❌ Lỗi: Website [ ${APP_DOMAIN} ] không tồn tại hoặc chưa được cấu hình!"
        return 1
    fi

    info "Bắt đầu thủ tục Rollback cho [ ${APP_DOMAIN} ]..."

    # Kiểm tra thư mục releases
    if [ ! -d "$RELEASES_DIR" ]; then
        error "❌ Lỗi: Thư mục releases không tồn tại. Chưa có bản deploy nào để rollback!"
        return 1
    fi

    cd "$RELEASES_DIR" || { error "Không tìm kiếm được thư mục $RELEASES_DIR"; return 1; }
    
    # Lấy danh sách release cũ tới mới nhất (có thể chứa 3-5 thư mục)
    # format ls -1t -> từ mới đến cũ. (dòng số 2 là dòng trước current)
    local PREV_RELEASE=$(ls -1t | sed -n '2p')
    
    if [ -z "$PREV_RELEASE" ]; then
        error "Không có release lưu trữ trước đó để rollback!"
    fi
    
    local TARGET_ROLLBACK="${RELEASES_DIR}/${PREV_RELEASE}"
    info "Hạ cấp symlink current về phiên bản: $PREV_RELEASE"
    
    sudo -u "$APP_USER" ln -nfs "$TARGET_ROLLBACK" "$CURRENT_DIR"
    
    # Xoá views cache để load source cũ an toàn
    cd "$TARGET_ROLLBACK"
    sudo -u "$APP_USER" php${PHP_VERSION} artisan view:clear || true
    sudo -u "$APP_USER" php${PHP_VERSION} artisan config:clear || true
    
    # Restart pool php và supervisor
    systemctl reload "php${PHP_VERSION}-fpm"
    supervisorctl restart all || true
    
    info "================================================================="
    info "ĐÃ ROLLBACK (Khôi phục) THÀNH CÔNG VỀ BẢN: $PREV_RELEASE !"
    info "================================================================="
}
