#!/usr/bin/env bash
# modules/site.sh
# Xử lý Logic Tạo Mới một Website hoàn chỉnh (Config, DB, SSL, Queue)

run_add_site() {
    local domain="$1"
    info "Đang khởi tạo Hệ sinh thái riêng cho Tên miền Dự Án: ${domain} ..."

    # 1. Tạo file cấu hình riêng .env.$domain
    mkdir -p "$SCRIPT_DIR/sites"
    local SITE_ENV="$SCRIPT_DIR/sites/.env.${domain}"
    
    if [ -f "$SITE_ENV" ]; then
        error "Site $domain đã tồn tại file cấu hình .env. Quá trình Add-site bị huỷ để bảo vệ code cũ."
    fi

    cp "$SCRIPT_DIR/.env.site.example" "$SITE_ENV"
    harden_permissions "$SITE_ENV"

    
    # 1.1 Chọn phiên bản PHP cho dự án
    echo -e "${CYAN}Chọn phiên bản PHP cho Website:${NC}"
    echo -e "  ${GREEN}1.${NC} PHP 8.1"
    echo -e "  ${GREEN}2.${NC} PHP 8.2"
    echo -e "  ${GREEN}3.${NC} PHP 8.3"
    echo -e "  ${GREEN}4.${NC} PHP 8.4"
    read -p "Lựa chọn (mặc định 3): " php_choice
    
    case $php_choice in
        1) PHP_VER_SELECTED="8.1" ;;
        2) PHP_VER_SELECTED="8.2" ;;
        4) PHP_VER_SELECTED="8.4" ;;
        *) PHP_VER_SELECTED="8.3" ;;
    esac
    sed -i "s/^PHP_VERSION=.*/PHP_VERSION=\"${PHP_VER_SELECTED}\"/" "$SITE_ENV"
    info "Đã chọn PHP ${PHP_VER_SELECTED} cho ${domain}."

    # [FIX V18.2] Tự động cài đặt PHP PHP_VER_SELECTED nếu hệ thống chưa có
    if [ ! -d "/etc/php/${PHP_VER_SELECTED}/fpm" ]; then
        info "⚠️ Phát hiện PHP ${PHP_VER_SELECTED} chưa được cài đặt. Đang tiến hành cài đặt dặm..."
        apt-get update -y
        local php_pkgs=(
            "php${PHP_VER_SELECTED}-cli" "php${PHP_VER_SELECTED}-fpm" "php${PHP_VER_SELECTED}-mysql"
            "php${PHP_VER_SELECTED}-mbstring" "php${PHP_VER_SELECTED}-xml" "php${PHP_VER_SELECTED}-zip"
            "php${PHP_VER_SELECTED}-bcmath" "php${PHP_VER_SELECTED}-curl" "php${PHP_VER_SELECTED}-intl"
            "php${PHP_VER_SELECTED}-gd" "php${PHP_VER_SELECTED}-redis"
        )
        apt-get install -y "${php_pkgs[@]}"
        systemctl enable "php${PHP_VER_SELECTED}-fpm"
        systemctl start "php${PHP_VER_SELECTED}-fpm"
        info "✅ Đã cài đặt xong PHP ${PHP_VER_SELECTED}."
    fi


    # 1.2 Cấu hình nâng cao (JWT, SSR)
    read -p "Dự án có sử dụng JWT không? (y/n, mặc định n): " jwt_choice
    local use_jwt="false"
    [[ "$jwt_choice" =~ ^[Yy]$ ]] && use_jwt="true"
    sed -i "s/^USE_JWT=.*/USE_JWT=\"${use_jwt}\"/" "$SITE_ENV"

    read -p "Dự án có sử dụng Inertia SSR không? (y/n, mặc định n): " ssr_choice
    local use_ssr="false"
    local ssr_port="13714"
    if [[ "$ssr_choice" =~ ^[Yy]$ ]]; then
        use_ssr="true"
        # Tìm port lớn nhất hiện có và cộng 1
        local last_port=$(grep -rh "SSR_PORT=" "$SCRIPT_DIR/sites/" | grep -oP '(?<=")\d+(?=")' | sort -n | tail -1)
        if [ ! -z "$last_port" ]; then
            ssr_port=$((last_port + 1))
        fi
    fi
    sed -i "s/^USE_SSR=.*/USE_SSR=\"${use_ssr}\"/" "$SITE_ENV"
    sed -i "s/^SSR_PORT=.*/SSR_PORT=\"${ssr_port}\"/" "$SITE_ENV"

    # 1.3 Sinh SSH Key độc lập (Multi-Git Support)
    # [FIX V22.0] Di dời Key ra khỏi /root để www-data có thể đọc được
    local ssh_key_dir="/var/www/.vps_keys"
    local app_user=${APP_USER:-"www-data"}
    local ssh_key_path="${ssh_key_dir}/id_ed25519_${domain}"

    mkdir -p "$ssh_key_dir"
    chown "$app_user":"$app_user" "$ssh_key_dir"
    chmod 700 "$ssh_key_dir"
    
    if [ ! -f "$ssh_key_path" ]; then
        info "Đang khởi tạo mã SSH Key riêng biệt cho [ $domain ]..."
        ssh-keygen -t ed25519 -f "$ssh_key_path" -N "" -q -C "deploy_${domain}"
    fi

    # Cấp quyền sở hữu và bảo mật cho Key
    chown "$app_user":"$app_user" "$ssh_key_path"*
    chmod 600 "$ssh_key_path"
    chmod 644 "${ssh_key_path}.pub"

    # Đảm bảo github.com có trong known_hosts của hệ thống (cho mọi user)
    if ! grep -q "github.com" /etc/ssh/ssh_known_hosts 2>/dev/null; then
        ssh-keyscan github.com >> /etc/ssh/ssh_known_hosts 2>/dev/null
    fi

    sed -i "s|^SSH_KEY_PATH=.*|SSH_KEY_PATH=\"${ssh_key_path}\"|g" "$SITE_ENV"
    harden_permissions "$SITE_ENV"

    
    # Random DB Credentials
    # Xoá dấu gạch ngang/chấm trong tên miền để làm tên DB cho an toàn (Tránh lỗi cú pháp SQL)
    local raw_db_name="db_$(echo $domain | sed 's/[^a-zA-Z0-9]/_/g' | cut -c1-24)"
    local raw_db_pass=$(tr -dc A-Za-z0-9 </dev/urandom | head -c 20 ; echo '')

    # Sắp xếp sửa file env
    sed -i "s/^APP_DOMAIN=.*/APP_DOMAIN=\"${domain}\"/" "$SITE_ENV"
    sed -i "s/^DB_NAME=.*/DB_NAME=\"${raw_db_name}\"/" "$SITE_ENV"
    sed -i "s/^DB_USER=.*/DB_USER=\"${raw_db_name}\"/" "$SITE_ENV"
    sed -i "s/^DB_PASSWORD=.*/DB_PASSWORD=\"${raw_db_pass}\"/" "$SITE_ENV"

    info "File cấu hình môi trường đã được tạo tại: sites/.env.${domain}"

    # 2. Xây dứng cấu trúc thư mục Server /var/www/
    local target_dir="/var/www/$domain"
    # Giả định APP_USER vẫn cấu hình toàn cục trong file .env gốc (www-data)
    local app_user=${APP_USER:-"www-data"}

    mkdir -p "$target_dir/current/public"
    
    # [FIX V27.2] Khởi tạo cấu trúc đầy đủ bằng lệnh tường minh (Tránh lỗi Brace Expansion)
    info "Khởi tạo cấu trúc Shared Storage (Logs, Cache, Sessions)..."
    mkdir -p "$target_dir/shared/storage/logs"
    mkdir -p "$target_dir/shared/storage/app/public"
    mkdir -p "$target_dir/shared/storage/framework/cache"
    mkdir -p "$target_dir/shared/storage/framework/sessions"
    mkdir -p "$target_dir/shared/storage/framework/views"
    
    # Khéo léo trả cái index.html vắn tắt để certbot nhận diện pass challenge nhanh
    echo "<h1>${domain} đang được setup bởi VPS Manager CLI...</h1>" > "$target_dir/current/public/index.html"
    chown -R "$app_user":"$app_user" "$target_dir"
    chmod 755 "$target_dir"

    # 3. Tạo Database cho Web
    info "Khởi tạo MySQL Database [ ${raw_db_name} ] Cấp quyền độc quyền..."
    export DEBIAN_FRONTEND="noninteractive"
    run_mysql_secure "CREATE DATABASE IF NOT EXISTS \`${raw_db_name}\` CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;"
    run_mysql_secure "CREATE USER IF NOT EXISTS '${raw_db_name}'@'localhost' IDENTIFIED BY '${raw_db_pass}';"
    run_mysql_secure "GRANT ALL PRIVILEGES ON \`${raw_db_name}\`.* TO '${raw_db_name}'@'localhost';"
    run_mysql_secure "FLUSH PRIVILEGES;"

    # 4. Triển khai Nginx HTTP (Chưa cài SSL)
    info "Đăng ký Nginx WebServer (Cấu hình HTTP)..."
    local nginx_conf="/etc/nginx/sites-available/$domain"
    
    # Đọc template ghi đè biến
    local php_ver=$(grep -oP "(?<=^PHP_VERSION=\")[^\"]+" "$SITE_ENV" || echo "8.3")
    cat "$SCRIPT_DIR/configs/nginx-template.conf" \
        | sed "s/{{APP_DOMAIN}}/$domain/g" \
        | sed "s/{{PHP_VERSION}}/$php_ver/g" \
        > "$nginx_conf"

    ln -nfs "$nginx_conf" "/etc/nginx/sites-enabled/$domain"
    systemctl reload nginx

    # 5. Cài cắm Supervisor Worker (Chỉ tạo cấu hình - Kích hoạt khi Deploy)
    info "Đã gắn cấu hình Supervisor Queue Worker cho $domain (Chờ Deploy để kích hoạt)..."
    local supervisor_conf="/etc/supervisor/conf.d/worker-${domain}.conf"
    
    cat "$SCRIPT_DIR/configs/supervisor-queue.conf" \
        | sed "s/{{APP_DOMAIN}}/$domain/g" \
        | sed "s/{{APP_USER}}/$app_user/g" \
        | sed "s/laravel-worker/worker-${domain}/g" \
        > "$supervisor_conf"

    # 5.1 Cài SSR Supervisor (Nếu có - Chỉ tạo cấu hình)
    if [ "$use_ssr" = "true" ]; then
        info "Đã gắn cấu hình Supervisor SSR cho $domain (Chờ Deploy để kích hoạt)..."
        local ssr_supervisor_conf="/etc/supervisor/conf.d/ssr-${domain}.conf"
        cat "$SCRIPT_DIR/configs/supervisor-ssr.conf" \
            | sed "s/{{APP_DOMAIN}}/$domain/g" \
            | sed "s/{{APP_USER}}/$app_user/g" \
            | sed "s/{{SSR_PORT}}/$ssr_port/g" \
            > "$ssr_supervisor_conf"
    fi

    # [FIX V20.1] Bước nạp Crontab sẽ được chuyển sang giai đoạn Deploy để đảm bảo đường dẫn tồn tại

    info "================================================================="
    info "🚀 THÀNH CÔNG: DỰ ÁN [ $domain ] ĐÃ SETUP HOÀN TẤT TRÊN SERVER."
    info "👉 Cấu trúc Web Dir  : $target_dir"
    info "👉 Database Name/User: $raw_db_name"
    info "👉 Database Pass     : $raw_db_pass"
    if [ "$use_ssr" = "true" ]; then
        info "👉 SSR Port          : $ssr_port"
    fi
    info ""
    info "🔑 SSH PUBLIC KEY (Copy cái này add vào Deploy Keys của GitHub):"
    echo -e "${YELLOW}"
    cat "${ssh_key_path}.pub"
    echo -e "${NC}"
    info ""
    info "Lưu ý cài đặt Private/Public Key Git rồi chạy lệnh:"
    info "   ./vps.sh deploy $domain"
    info ""
    info "Khi đã trỏ IP Domain thành công, hãy cài SSL tại Menu Số 2."
    info "================================================================="
}
