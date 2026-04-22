#!/usr/bin/env bash
# modules/deploy.sh
# Xử lý quy trình Deploy Zero-Downtime & Rollback

# Các biến đường dẫn sẽ được khởi tạo động bên trong hàm run_deploy

run_deploy() {
    local DEPLOY_MODE="${1:-zdt}"
    # Kiểm tra Website có tồn tại thật hay không (Dựa trên file env của site)
    local SITE_ENV_FILE="$SCRIPT_DIR/sites/.env.${APP_DOMAIN}"
    if [ ! -f "$SITE_ENV_FILE" ]; then
        error "Lỗi: Site '${APP_DOMAIN}' chưa được khởi tạo. Vui lòng chạy: vps add-site"
        return 1
    fi

    if [ "$DEPLOY_MODE" == "quick" ]; then
        info "Bắt đầu Quick Deploy: $APP_DOMAIN..."
    else
        info "Bắt đầu Zero-Downtime Deploy: $APP_DOMAIN..."
    fi

    # Khởi tạo các đường dẫn động dựa trên APP_DOMAIN
    local BASE_DIR="/var/www/${APP_DOMAIN}"
    local RELEASES_DIR="${BASE_DIR}/releases"
    local SHARED_DIR="${BASE_DIR}/shared"
    local CURRENT_DIR="${BASE_DIR}/current"

    # "Nhảy" vào vùng an toàn (BASE_DIR) để tránh lỗi getcwd() của www-data
    # Nếu đang đứng ở /root, user www-data sẽ không có quyền truy cập vào CWD hiện tại.
    cd "$BASE_DIR" || cd /tmp

    # Đảm bảo quyền sở hữu cho APP_USER
    chown -R "$APP_USER":"$APP_USER" "$BASE_DIR"

    # Kiểm tra và Hỏi Git Repo nếu chưa có
    if [ -z "$GIT_REPO" ] || [ "$GIT_REPO" = "git_repo_url" ]; then
        info "Yêu cầu: Cấu hình Git Repository cho site '${APP_DOMAIN}'."
        while true; do
            read -p "Nhập Git Repo URL (vd: git@github.com:user/repo.git): " input_repo
            
            # Gỡ bỏ khoảng trắng thừa
            input_repo=$(echo "$input_repo" | xargs)

            # Logic Tự động chuyển đổi HTTPS sang SSH (GitHub/GitLab/Bitbucket)
            if [[ "$input_repo" =~ ^https://(github\.com|gitlab\.com|bitbucket\.org)/(.+) ]]; then
                local provider="${BASH_REMATCH[1]}"
                local path="${BASH_REMATCH[2]}"
                # Loại bỏ đuôi .git nếu có để chuẩn hóa
                path="${path%.git}"
                
                local ssh_url="git@${provider}:${path}.git"
                warn "Cảnh báo: URL HTTPS không sử dụng được với SSH Key."
                read -p "Tự động chuyển đổi sang SSH URL: [ ${ssh_url} ]? (y/n): " convert_choice
                if [[ "$convert_choice" =~ ^[Yy]$ ]]; then
                    input_repo="$ssh_url"
                    info "Đã chuyển đổi sang giao thức SSH."
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
                info "Đã lưu Git Repo: ${GIT_REPO}"
                break
            elif [[ "$input_repo" =~ ^https:// ]]; then
                warn "Lưu ý: HTTPS yêu cầu xác thực thủ công khi clone/pull."
                GIT_REPO="$input_repo"
                break
            else
                error "Lỗi: Định dạng URL không hợp lệ. Đề xuất sử dụng giao thức SSH (git@...)"
            fi
        done
    fi

    # Đảm bảo toàn bộ cấu trúc log tồn tại bằng lệnh tường minh (Tránh lỗi Brace Expansion)
    mkdir -p "${RELEASES_DIR}"
    mkdir -p "${SHARED_DIR}/storage/logs"
    mkdir -p "${SHARED_DIR}/storage/app/public"
    mkdir -p "${SHARED_DIR}/storage/framework/cache"
    mkdir -p "${SHARED_DIR}/storage/framework/sessions"
    mkdir -p "${SHARED_DIR}/storage/framework/views"

    chown -R "$APP_USER":"$APP_USER" "${RELEASES_DIR}" "${SHARED_DIR}"

    # --- PHÂN NHÁNH LOGIC DEPLOY ---
    if [ "$DEPLOY_MODE" == "quick" ]; then
        # CHẾ ĐỘ QUICK DEPLOY
        if [ ! -L "$CURRENT_DIR" ]; then
            error "Lỗi: Site chưa từng được triển khai Zero-Downtime thành công."
            error "Vui lòng thực hiện Deploy (chế độ ZDT) ít nhất một lần để khởi tạo."
            return 1
        fi

        info "Đang cập nhật mã nguồn (git pull)..."
        cd "$CURRENT_DIR" || { error "Không thể truy cập thư mục current"; return 1; }
        
        # Pull code
        sudo -u "$APP_USER" GIT_SSH_COMMAND="ssh -i ${SSH_KEY_PATH} -o StrictHostKeyChecking=no" \
            git pull origin main || { error "Lỗi khi chạy git pull"; return 1; }

        # Cài đặt Composer (nhanh)
            info "Cài đặt Composer dependencies..."
            sudo -u "$APP_USER" php${PHP_VERSION} /usr/local/bin/composer install --no-interaction --prefer-dist --optimize-autoloader --no-dev || { error "Lỗi khi chạy composer install"; return 1; }
        fi

        # Laravel commands
        if [ -f "artisan" ]; then
            info "Thực thi Migrations & Clear Cache..."
            sudo -u "$APP_USER" php${PHP_VERSION} artisan migrate --force || { error "Lỗi khi chạy migration"; return 1; }
            sudo -u "$APP_USER" php${PHP_VERSION} artisan optimize:clear || { error "Lỗi khi clear optimize"; return 1; }
        fi

        # Reload PHP-FPM
        systemctl reload "php${PHP_VERSION}-fpm"

        info "================================================================="
        info " THÀNH CÔNG: Quick Deploy hoàn tất."
        info "================================================================="
    else
        # CHẾ ĐỘ ZERO-DOWNTIME DEPLOYMENT (Giữ nguyên logic cũ)
        local TIMESTAMP=$(date +"%Y%m%d%H%M%S")
        local NEW_RELEASE="${RELEASES_DIR}/${TIMESTAMP}"

        # Hàm dọn dẹp nội bộ nếu quy trình build thất bại
        cleanup_failed_release() {
            if [ -d "$NEW_RELEASE" ]; then
                cd "$RELEASES_DIR" || cd /tmp
                warn "Lỗi tiến trình build. Đang dọn dẹp release: $TIMESTAMP"
                rm -rf "$NEW_RELEASE"
            fi
        }

        # Clone
        info "Sử dụng SSH Key: $SSH_KEY_PATH"
        sudo -u "$APP_USER" GIT_SSH_COMMAND="ssh -i ${SSH_KEY_PATH} -o StrictHostKeyChecking=no" \
            git clone "$GIT_REPO" "$NEW_RELEASE" || { cleanup_failed_release; error "Lỗi: Không thể clone mã nguồn từ Git!"; return 1; }

        # 2. Xử lý Shared Storage và Env
        info "Liên kết file .env và thư mục storage..."
        if [ ! -f "${SHARED_DIR}/.env" ]; then
            info "Khởi tạo file .env đầu tiên cho Laravel..."
            if [ -f "${NEW_RELEASE}/.env.example" ]; then
                cp "${NEW_RELEASE}/.env.example" "${SHARED_DIR}/.env"
            else
                touch "${SHARED_DIR}/.env"
            fi
            chown "$APP_USER":"$APP_USER" "${SHARED_DIR}/.env"
        fi

        # Đồng bộ .env
        source "$SCRIPT_DIR/sites/.env.${APP_DOMAIN}"
        sed -i "s|^APP_URL=.*|APP_URL=https://${APP_DOMAIN}|g" "${SHARED_DIR}/.env"
        sed -i "s/^DB_DATABASE=.*/DB_DATABASE=${DB_NAME}/g" "${SHARED_DIR}/.env"
        sed -i "s/^DB_USERNAME=.*/DB_USERNAME=${DB_USER}/g" "${SHARED_DIR}/.env"
        sed -i "s/^DB_PASSWORD=.*/DB_PASSWORD=${DB_PASSWORD}/g" "${SHARED_DIR}/.env"
        sed -i "s/^APP_ENV=.*/APP_ENV=production/g" "${SHARED_DIR}/.env"
        
        # Link storage & env
        rm -rf "${NEW_RELEASE}/storage"
        sudo -u "$APP_USER" ln -s "${SHARED_DIR}/storage" "${NEW_RELEASE}/storage"
        rm -f "${NEW_RELEASE}/.env"
        sudo -u "$APP_USER" ln -s "${SHARED_DIR}/.env" "${NEW_RELEASE}/.env"

        # 3. Build Dependencies (PHP)
        cd "$NEW_RELEASE"
        if [ -f "composer.json" ]; then
            sudo -u "$APP_USER" php${PHP_VERSION} /usr/local/bin/composer install --no-interaction --prefer-dist --optimize-autoloader --no-dev || { cleanup_failed_release; error "Lỗi khi chạy composer install"; return 1; }
        fi

        if [ -f "artisan" ]; then
            if ! grep -q "APP_KEY=base64:" "${SHARED_DIR}/.env"; then
                sudo -u "$APP_USER" php${PHP_VERSION} artisan key:generate --force || { cleanup_failed_release; error "Lỗi khi tạo APP_KEY"; return 1; }
            fi
        fi

        # 3. Build Dependencies (NPM)
        if [ -f "package.json" ]; then
            info "Cài đặt & Build NPM packages..."
            sudo -u "$APP_USER" npm install || { cleanup_failed_release; error "Lỗi khi chạy npm install"; return 1; }
            sudo -u "$APP_USER" npm run build || { cleanup_failed_release; error "Lỗi khi chạy npm run build"; return 1; }
        fi

        # 4. Laravel commands
        if [ -f "artisan" ]; then
            sudo -u "$APP_USER" php${PHP_VERSION} artisan storage:link --force || warn "⚠️ Không thể tạo storage:link"
            sudo -u "$APP_USER" php${PHP_VERSION} artisan migrate --force || { cleanup_failed_release; error "Lỗi khi chạy migration"; return 1; }
            sudo -u "$APP_USER" php${PHP_VERSION} artisan optimize:clear || { cleanup_failed_release; error "Lỗi khi clear optimize"; return 1; }
            sudo -u "$APP_USER" php${PHP_VERSION} artisan config:cache || { cleanup_failed_release; error "Lỗi khi cache config"; return 1; }
            sudo -u "$APP_USER" php${PHP_VERSION} artisan route:cache || { cleanup_failed_release; error "Lỗi khi cache route"; return 1; }
            sudo -u "$APP_USER" php${PHP_VERSION} artisan view:cache || { cleanup_failed_release; error "Lỗi khi cache view"; return 1; }
        fi

        # 4.1 JWT Secret (Check if exists)
        if [ "$USE_JWT" = "true" ] && [ -f "artisan" ]; then
            if ! grep -q "JWT_SECRET=" "${SHARED_DIR}/.env" 2>/dev/null; then
                info "Khởi tạo JWT Secret..."
                sudo -u "$APP_USER" php${PHP_VERSION} artisan jwt:secret --force || true
            fi
        fi

        # 4.2 Inertia SSR
        if [ "$USE_SSR" = "true" ] && [ -f "package.json" ]; then
            if grep -q "build:ssr" "$NEW_RELEASE/package.json"; then
                sudo -u "$APP_USER" npm run build:ssr || { cleanup_failed_release; error "Lỗi khi build SSR"; return 1; }
            fi
        fi

        # 5. Kích hoạt Symlink
        if [ -d "$CURRENT_DIR" ] && [ ! -L "$CURRENT_DIR" ]; then
            rm -rf "$CURRENT_DIR"
        fi
        sudo -u "$APP_USER" ln -nfs "$NEW_RELEASE" "$CURRENT_DIR" || { cleanup_failed_release; error "Không thể hoán đổi symlink current"; return 1; }
        
        systemctl reload "php${PHP_VERSION}-fpm"
        
        # Supervisor
        local SAFE_DOMAIN=$(get_safe_domain "$APP_DOMAIN")
        supervisorctl reread
        supervisorctl update
        sleep 1
        info "Khởi chạy các dịch vụ Supervisor: group [ ${SAFE_DOMAIN} ]..."
        supervisorctl restart "${SAFE_DOMAIN}:*" || supervisorctl start "${SAFE_DOMAIN}:*" || warn "Cảnh báo: Không thể khởi động nhóm dịch vụ Supervisor"

        # Cronjob
        local CRON_CMD="* * * * * cd ${CURRENT_DIR} && php${PHP_VERSION} artisan schedule:run >> /dev/null 2>&1"
        if ! sudo -u "$APP_USER" crontab -l 2>/dev/null | grep -q "cd ${CURRENT_DIR}"; then
            (sudo -u "$APP_USER" crontab -l 2>/dev/null; echo "$CRON_CMD") | sudo -u "$APP_USER" crontab -
        fi

        # 6. Dọn dẹp
        info "Dọn dẹp các bản release cũ..."
        cd "$RELEASES_DIR"
        ls -1t | tail -n +4 | xargs -r rm -rf

        info "================================================================="
        info " THÀNH CÔNG: Triển khai Zero-Downtime hoàn tất."
        info " Release: $TIMESTAMP"
        info "================================================================="
    fi

    # Móc call API Report (Module monitor)
    # bash monitor.sh send_telegram "Deploy Thành Công lên release: ${TIMESTAMP}"
}

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

    # Kiểm tra thư mục releases
    if [ ! -d "$RELEASES_DIR" ]; then
        error "Lỗi: Thư mục 'releases' không tồn tại. Không tìm thấy bản triển khai cũ."
        return 1
    fi

    cd "$RELEASES_DIR" || { error "Không tìm kiếm được thư mục $RELEASES_DIR"; return 1; }
    
    # Xác định bản hiện tại (lỗi) và bản trước đó (để rollback)
    local CURRENT_FAILED_RELEASE_NAME=$(ls -1t | sed -n '1p')
    local PREV_RELEASE_NAME=$(ls -1t | sed -n '2p')
    
    if [ -z "$PREV_RELEASE_NAME" ]; then
        error "Lỗi: Không tìm thấy bản release cũ để khôi phục."
        return 1
    fi
    
    local TARGET_ROLLBACK="${RELEASES_DIR}/${PREV_RELEASE_NAME}"
    local CURRENT_FAILED_RELEASE="${RELEASES_DIR}/${CURRENT_FAILED_RELEASE_NAME}"

    # Kiểm tra & Hỏi xác nhận Rollback Database Thủ công
    echo ""
    warn "=========================================================================="
    warn "                CẢNH BÁO QUAN TRỌNG VỀ DATABASE                           "
    warn "=========================================================================="
    warn "Việc Rollback Migrations sẽ làm thay đổi cấu trúc dữ liệu."
    warn " - Dữ liệu tại các cột/bảng mới vừa tạo sẽ bị xóa vĩnh viễn."
    warn " - Chỉ thực hiện nếu thực sự cần thiết cho code cũ hoạt động."
    warn "=========================================================================="
    
    # Mặc định là Không (y/N)
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

    # Tiếp tục rollback phần Code (Symlink)
    info "Khôi phục symlink current về phiên bản: $PREV_RELEASE_NAME..."
    sudo -u "$APP_USER" ln -nfs "$TARGET_ROLLBACK" "$CURRENT_DIR" || { error "Lỗi: Không thể hoán đổi symlink"; return 1; }

    # Xóa bỏ hoàn toàn bản release lỗi để dọn dẹp hệ thống
    if [ -d "$CURRENT_FAILED_RELEASE" ]; then
        info "Xóa bản release bị lỗi để giải phóng dung lượng..."
        rm -rf "$CURRENT_FAILED_RELEASE"
        info "Hoàn tất xóa bản lỗi."
    fi
    
    # Xoá views cache để load source cũ an toàn
    cd "$TARGET_ROLLBACK"
    sudo -u "$APP_USER" php${PHP_VERSION} artisan view:clear || true
    sudo -u "$APP_USER" php${PHP_VERSION} artisan config:clear || true
    
    # Restart pool php và supervisor
    systemctl reload "php${PHP_VERSION}-fpm"
    local SAFE_DOMAIN=$(get_safe_domain "$APP_DOMAIN")
    info "Khởi động lại các dịch vụ Supervisor: group [ ${SAFE_DOMAIN} ]..."
    supervisorctl restart "${SAFE_DOMAIN}:*" || true
    
    info "================================================================="
    info " THÀNH CÔNG: Đã khôi phục về bản release: $PREV_RELEASE_NAME"
    info "================================================================="
}
