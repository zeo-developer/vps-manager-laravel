#!/usr/bin/env bash
# modules/deploy/deploy.sh
# Xử lý quy trình Deploy Zero-Downtime cho ứng dụng

#-----------------------------------------------------------------------------
# Hàm:          run_migration_with_detection
# Mô tả:        Thực thi database migrations và phát hiện xem có bảng/cột mới nào không.
# Biến toàn cục: PHP_VERSION, APP_USER, MIGRATE_NEW
# Tham số:      Không có
# Trả về:       Mã exit code của lệnh migrate
#-----------------------------------------------------------------------------
run_migration_with_detection() {
    local migrate_output=""
    local status=0

    MIGRATE_NEW=false

    migrate_output=$(sudo -u "$APP_USER" php${PHP_VERSION} artisan migrate --force 2>&1)
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
# Biến toàn cục: MIGRATE_NEW, APP_USER, PHP_VERSION
# Tham số:      Không có
# Trả về:       Không có
#-----------------------------------------------------------------------------
rollback_new_migrations_if_needed() {
    if [ "$MIGRATE_NEW" = true ]; then
        warn "Phát hiện migration mới. Đang rollback database..."
        sudo -u "$APP_USER" php${PHP_VERSION} artisan migrate:rollback --force || warn "⚠️ Rollback DB tự động thất bại"
    fi
}

#-----------------------------------------------------------------------------
# Hàm:          run_deploy
# Mô tả:        Bắt đầu quy trình triển khai mã nguồn dạng Zero-Downtime an toàn.
# Biến toàn cục: APP_DOMAIN, SCRIPT_DIR, NODE_VERSION, APP_USER, GIT_REPO,
#               SSH_KEY_PATH, DB_NAME, DB_USER, DB_PASSWORD, USE_SSR, SSR_PORT, USE_JWT
# Tham số:      Không có
# Trả về:       0 nếu thành công, 1 nếu thất bại
#-----------------------------------------------------------------------------
run_deploy() {
    # Kiểm tra Website có tồn tại thật hay không (Dựa trên file env của site)
    local SITE_ENV_FILE="$SCRIPT_DIR/sites/.env.${APP_DOMAIN}"
    if [ ! -f "$SITE_ENV_FILE" ]; then
        error "Lỗi: Site '${APP_DOMAIN}' chưa được khởi tạo. Vui lòng chạy: vps add-site"
        return 1
    fi

    info "Bắt đầu Zero-Downtime Deploy: $APP_DOMAIN..."

    # Nạp công cụ quản lý phiên bản Node và đảm bảo phiên bản chính xác
    load_module "runtime.sh" || return 1
    ensure_site_node_version "$APP_DOMAIN" "${NODE_VERSION:-20}" || return 1

    # Khởi tạo các đường dẫn động dựa trên APP_DOMAIN
    local BASE_DIR="/var/www/${APP_DOMAIN}"
    local RELEASES_DIR="${BASE_DIR}/releases"
    local SHARED_DIR="${BASE_DIR}/shared"
    local CURRENT_DIR="${BASE_DIR}/current"

    # "Nhảy" vào vùng an toàn (BASE_DIR) để tránh lỗi getcwd() của www-data
    cd "$BASE_DIR" || cd /tmp

    MIGRATE_NEW=false

    # Đảm bảo quyền sở hữu cho APP_USER
    chown -R "$APP_USER":"$APP_USER" "$BASE_DIR"

    # Kiểm tra và Hỏi Git Repo nếu chưa có trong cấu hình site
    if [ -z "$GIT_REPO" ] || [ "$GIT_REPO" = "git_repo_url" ]; then
        info "Yêu cầu: Cấu hình Git Repository cho site '${APP_DOMAIN}'."
        while true; do
            read -p "Nhập Git Repo URL (vd: git@github.com:user/repo.git): " input_repo
            
            # Gỡ bỏ khoảng trắng thừa
            input_repo=$(echo "$input_repo" | xargs)

            # Tự động chuyển đổi từ HTTPS sang SSH cho các git provider phổ biến
            if [[ "$input_repo" =~ ^https://(github\.com|gitlab\.com|bitbucket\.org)/(.+) ]]; then
                local provider="${BASH_REMATCH[1]}"
                local path="${BASH_REMATCH[2]}"
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

    # Đảm bảo toàn bộ cấu trúc log/shared tồn tại bằng lệnh tường minh
    mkdir -p "${RELEASES_DIR}"
    mkdir -p "${SHARED_DIR}/storage/logs"
    mkdir -p "${SHARED_DIR}/storage/app/public"
    mkdir -p "${SHARED_DIR}/storage/framework/cache"
    mkdir -p "${SHARED_DIR}/storage/framework/sessions"
    mkdir -p "${SHARED_DIR}/storage/framework/views"

    chown -R "$APP_USER":"$APP_USER" "${RELEASES_DIR}" "${SHARED_DIR}"

    # Cấu hình dấu mốc thời gian cho bản build mới
    local TIMESTAMP=$(date +"%Y%m%d%H%M%S")
    local NEW_RELEASE="${RELEASES_DIR}/${TIMESTAMP}"

    # Hàm dọn dẹp nội bộ nếu quy trình build thất bại
    cleanup_failed_release() {
        if [ -d "$NEW_RELEASE" ]; then
            cd "$NEW_RELEASE" || return 1
            rollback_new_migrations_if_needed
            cd "$RELEASES_DIR" || cd /tmp
            warn "Lỗi tiến trình build. Đang dọn dẹp release: $TIMESTAMP"
            rm -rf "$NEW_RELEASE"
        fi
    }

    # Bước 1: Clone mã nguồn từ Git
    info "Sử dụng SSH Key: $SSH_KEY_PATH"
    sudo -u "$APP_USER" GIT_SSH_COMMAND="ssh -i ${SSH_KEY_PATH} -o StrictHostKeyChecking=no" \
        git clone "$GIT_REPO" "$NEW_RELEASE" || { cleanup_failed_release; error "Lỗi: Không thể clone mã nguồn từ Git!"; return 1; }

    # Bước 2: Xử lý Shared Storage và Env
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

    # Đồng bộ cấu hình .env
    source "$SCRIPT_DIR/sites/.env.${APP_DOMAIN}"
    sed -i "s|^APP_URL=.*|APP_URL=https://${APP_DOMAIN}|g" "${SHARED_DIR}/.env"
    sed -i "s/^DB_DATABASE=.*/DB_DATABASE=${DB_NAME}/g" "${SHARED_DIR}/.env"
    sed -i "s/^DB_USERNAME=.*/DB_USERNAME=${DB_USER}/g" "${SHARED_DIR}/.env"
    sed -i "s/^DB_PASSWORD=.*/DB_PASSWORD=${DB_PASSWORD}/g" "${SHARED_DIR}/.env"
    sed -i "s/^APP_ENV=.*/APP_ENV=production/g" "${SHARED_DIR}/.env"
    sed -i "s/^APP_DEBUG=.*/APP_DEBUG=false/g" "${SHARED_DIR}/.env"
    
    # Cấu hình Inertia SSR nếu được kích hoạt
    if [ "${USE_SSR:-false}" = "true" ]; then
        if [ -z "${SSR_PORT:-}" ]; then
            local last_port
            last_port=$(grep -rh '^SSR_PORT=' "$SCRIPT_DIR/sites/" 2>/dev/null | sed -E 's/^SSR_PORT="?([0-9]+)"?.*/\1/' | sort -n | tail -1)
            SSR_PORT=$(( ${last_port:-13713} + 1 ))
            echo "SSR_PORT=\"${SSR_PORT}\"" >> "$SCRIPT_DIR/sites/.env.${APP_DOMAIN}"
            info "Đã cấp SSR_PORT=${SSR_PORT} cho ${APP_DOMAIN}"
        fi
        
        if grep -q "^INERTIA_SSR_ENABLED=" "${SHARED_DIR}/.env"; then
            sed -i "s|^INERTIA_SSR_ENABLED=.*|INERTIA_SSR_ENABLED=true|g" "${SHARED_DIR}/.env"
        else
            echo "INERTIA_SSR_ENABLED=true" >> "${SHARED_DIR}/.env"
        fi

        if grep -q "^VITE_INERTIA_SSR_PORT=" "${SHARED_DIR}/.env"; then
            sed -i "s|^VITE_INERTIA_SSR_PORT=.*|VITE_INERTIA_SSR_PORT=${SSR_PORT}|g" "${SHARED_DIR}/.env"
        else
            echo "VITE_INERTIA_SSR_PORT=${SSR_PORT}" >> "${SHARED_DIR}/.env"
        fi

        if grep -q "^INERTIA_SSR_URL=" "${SHARED_DIR}/.env"; then
            sed -i "s|^INERTIA_SSR_URL=.*|INERTIA_SSR_URL=http://127.0.0.1:${SSR_PORT}|g" "${SHARED_DIR}/.env"
        else
            echo "INERTIA_SSR_URL=http://127.0.0.1:${SSR_PORT}" >> "${SHARED_DIR}/.env"
        fi
    else
        if grep -q "^INERTIA_SSR_ENABLED=" "${SHARED_DIR}/.env"; then
            sed -i "s|^INERTIA_SSR_ENABLED=.*|INERTIA_SSR_ENABLED=false|g" "${SHARED_DIR}/.env"
        else
            echo "INERTIA_SSR_ENABLED=false" >> "${SHARED_DIR}/.env"
        fi
    fi
    
    # Tạo liên kết tượng trưng (symlinks) cho storage và env sang thư mục release mới
    rm -rf "${NEW_RELEASE}/storage"
    sudo -u "$APP_USER" ln -s "${SHARED_DIR}/storage" "${NEW_RELEASE}/storage"
    rm -f "${NEW_RELEASE}/.env"
    sudo -u "$APP_USER" ln -s "${SHARED_DIR}/.env" "${NEW_RELEASE}/.env"

    # Bước 3: Cài đặt các thư viện PHP (Composer)
    cd "$NEW_RELEASE"
    if [ -f "composer.json" ]; then
        sudo -u "$APP_USER" php${PHP_VERSION} /usr/local/bin/composer install --no-interaction --prefer-dist --optimize-autoloader --no-dev || { cleanup_failed_release; error "Lỗi khi chạy composer install"; return 1; }
    fi

    # Tạo khoá APP_KEY nếu là lần đầu tiên deploy
    if [ -f "artisan" ]; then
        if ! grep -q "APP_KEY=base64:" "${SHARED_DIR}/.env"; then
            sudo -u "$APP_USER" php${PHP_VERSION} artisan key:generate --force || { cleanup_failed_release; error "Lỗi khi tạo APP_KEY"; return 1; }
        fi
    fi

    # Cài đặt và biên dịch các gói NPM
    if [ -f "package.json" ]; then
        info "Cài đặt & Build NPM packages bằng Node.js ${NODE_VERSION:-20}.x..."
        sudo -u "$APP_USER" npm${NODE_VERSION:-20} install || { cleanup_failed_release; error "Lỗi khi chạy npm install"; return 1; }
        sudo -u "$APP_USER" npm${NODE_VERSION:-20} run build || { cleanup_failed_release; error "Lỗi khi chạy npm run build"; return 1; }
    fi

    # Bước 4: Thực thi các câu lệnh Laravel Artisan
    if [ -f "artisan" ]; then
        sudo -u "$APP_USER" php${PHP_VERSION} artisan storage:link --force || warn "⚠️ Không thể tạo storage:link"
        run_migration_with_detection || { cleanup_failed_release; error "Lỗi khi chạy migration"; return 1; }

        if [ "$USE_JWT" = "true" ]; then
            if ! grep -q "^JWT_SECRET=.\+" "${SHARED_DIR}/.env" 2>/dev/null; then
                info "Khởi tạo JWT Secret..."
                sudo -u "$APP_USER" php${PHP_VERSION} artisan jwt:secret --force || true
            fi
        fi

        # Dọn dẹp cache và lưu cache cấu hình tối ưu hiệu năng
        sudo -u "$APP_USER" php${PHP_VERSION} artisan optimize:clear || { cleanup_failed_release; error "Lỗi khi clear optimize"; return 1; }
        sudo -u "$APP_USER" php${PHP_VERSION} artisan config:cache || { cleanup_failed_release; error "Lỗi khi cache config"; return 1; }
        sudo -u "$APP_USER" php${PHP_VERSION} artisan route:cache || { cleanup_failed_release; error "Lỗi khi cache route"; return 1; }
        sudo -u "$APP_USER" php${PHP_VERSION} artisan view:cache || { cleanup_failed_release; error "Lỗi khi cache view"; return 1; }
    fi

    # Khởi chạy SSR nếu sử dụng Inertia
    if [ "$USE_SSR" = "true" ] && [ -f "package.json" ]; then
        if grep -q "build:ssr" "$NEW_RELEASE/package.json"; then
            sudo -u "$APP_USER" npm${NODE_VERSION:-20} run build:ssr || { cleanup_failed_release; error "Lỗi khi build SSR"; return 1; }
        fi
    fi

    # Bước 5: Cập nhật liên kết tượng trưng (Symlink) sang release mới
    if [ -d "$CURRENT_DIR" ] && [ ! -L "$CURRENT_DIR" ]; then
        rm -rf "$CURRENT_DIR"
    fi
    sudo -u "$APP_USER" ln -nfs "$NEW_RELEASE" "$CURRENT_DIR" || { cleanup_failed_release; error "Không thể hoán đổi symlink current"; return 1; }
    
    # Reload lại PHP-FPM để nhận OPcache mới
    systemctl reload "php${PHP_VERSION}-fpm"
    
    # Cấu hình lại Supervisor nếu có sử dụng SSR
    local SAFE_DOMAIN=$(get_safe_domain "$APP_DOMAIN")
    local supervisor_conf="/etc/supervisor/conf.d/${SAFE_DOMAIN}.conf"
    local node_dir
    node_dir=$(resolve_n_node_version_dir "${NODE_VERSION:-20}")
    local env_line="environment=PATH=\"${node_dir}/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin\""
    
    if [ -f "$supervisor_conf" ] && grep -q "^\[program:${SAFE_DOMAIN}-ssr\]" "$supervisor_conf"; then
        if sed -n "/^\[program:${SAFE_DOMAIN}-ssr\]/,/^\[/p" "$supervisor_conf" | grep -q "^environment="; then
            sed -i "/^\[program:${SAFE_DOMAIN}-ssr\]/,/^\[/ s|^environment=.*|${env_line}|" "$supervisor_conf"
        else
            sed -i "/^\[program:${SAFE_DOMAIN}-ssr\]/,/^\[/ s|^stopwaitsecs=.*|&\n${env_line}|" "$supervisor_conf"
        fi
        info "Đã cập nhật PATH cho Supervisor SSR (${APP_DOMAIN})"
    fi
    
    # Cập nhật và khởi động lại Supervisor
    supervisorctl reread
    supervisorctl update
    sleep 1
    info "Khởi chạy các dịch vụ Supervisor: group [ ${SAFE_DOMAIN} ]..."
    supervisorctl restart "${SAFE_DOMAIN}:*" || supervisorctl start "${SAFE_DOMAIN}:*" || warn "Cảnh báo: Không thể khởi động nhóm dịch vụ Supervisor"

    # Thiết lập Cronjob chạy schedule hàng phút cho Laravel Task Scheduling
    local CRON_CMD="* * * * * cd ${CURRENT_DIR} && php${PHP_VERSION} artisan schedule:run >> /dev/null 2>&1"
    if ! sudo -u "$APP_USER" crontab -l 2>/dev/null | grep -q "cd ${CURRENT_DIR}"; then
        (sudo -u "$APP_USER" crontab -l 2>/dev/null; echo "$CRON_CMD") | sudo -u "$APP_USER" crontab -
    fi

    # Bước 6: Dọn dẹp các bản release cũ hơn (chỉ giữ lại 3 bản gần nhất)
    info "Dọn dẹp các bản release cũ..."
    cd "$RELEASES_DIR"
    ls -1t | tail -n +4 | xargs -r rm -rf

    info "================================================================="
    info " THÀNH CÔNG: Triển khai Zero-Downtime hoàn tất."
    info " Bản phát hành: $TIMESTAMP"
    info "================================================================="
}
