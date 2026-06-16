#!/usr/bin/env bash
# modules/domain/add.sh
# Xử lý Logic Tạo Mới một Website hoàn chỉnh (Cấu hình, DB, SSL, Queue)

#-----------------------------------------------------------------------------
# Hàm:          run_add_site
# Mô tả:        Tạo thư mục dự án, sinh SSH keys, cấu hình Nginx/Supervisor và tạo DB cho site.
# Biến toàn cục: SCRIPT_DIR, CYAN, GREEN, NC
# Tham số:      $1 - Tên miền cần thêm
# Trả về:       Không có
#-----------------------------------------------------------------------------
run_add_site() {
    local domain="$1"

    if ! is_valid_domain "$domain"; then
        error "Lỗi: Tên miền '$domain' không đúng định dạng (VD: example.com, sub.domain.vn)."
        return 1
    fi

    info "Khởi tạo môi trường cho domain: ${domain}..."

    # 1. Tạo file cấu hình riêng .env.$domain
    mkdir -p "$SCRIPT_DIR/sites"
    local SITE_ENV="$SCRIPT_DIR/sites/.env.${domain}"
    
    if [ -f "$SITE_ENV" ]; then
        error "Lỗi: Cấu hình site '$domain' đã tồn tại. Hủy thao tác."
        return 1
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
    update_env_var "PHP_VERSION" "${PHP_VER_SELECTED}" "$SITE_ENV"
    info "Phiên bản PHP đã chọn: ${PHP_VER_SELECTED}"

    # 1.1b Chọn phiên bản Node.js riêng cho dự án
    load_module "runtime/runtime.sh" || return 1
    echo -e "${CYAN}Chọn phiên bản Node.js cho Website:${NC}"
    echo -e "  ${GREEN}1.${NC} Node.js 18.x"
    echo -e "  ${GREEN}2.${NC} Node.js 20.x"
    echo -e "  ${GREEN}3.${NC} Node.js 22.x"
    echo -e "  ${GREEN}4.${NC} Node.js 24.x"
    read -p "Lựa chọn (mặc định 2): " node_choice
    case $node_choice in
        1) NODE_VER_SELECTED="18" ;;
        3) NODE_VER_SELECTED="22" ;;
        4) NODE_VER_SELECTED="24" ;;
        *) NODE_VER_SELECTED="20" ;;
    esac
    update_env_var "NODE_VERSION" "${NODE_VER_SELECTED}" "$SITE_ENV"
    info "Phiên bản Node.js đã chọn: ${NODE_VER_SELECTED}.x"

    # Tự động cài đặt PHP PHP_VER_SELECTED nếu hệ thống chưa có
    if [ ! -d "/etc/php/${PHP_VER_SELECTED}/fpm" ]; then
        info "PHP ${PHP_VER_SELECTED} chưa được cài đặt. Bắt đầu cài đặt..."
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
        info "Hoàn tất cài đặt PHP ${PHP_VER_SELECTED}."
    fi

    # 1.2 Sinh SSH Key độc lập (Hỗ trợ Multi-Git)
    # Di dời Key ra khỏi /root để www-data có thể đọc được
    local ssh_key_dir="/var/www/.vps_keys"
    local app_user=${APP_USER:-"www-data"}
    local ssh_key_path="${ssh_key_dir}/id_ed25519_${domain}"

    mkdir -p "$ssh_key_dir"
    chown "$app_user":"$app_user" "$ssh_key_dir"
    chmod 700 "$ssh_key_dir"
    
    if [ ! -f "$ssh_key_path" ]; then
        info "Khởi tạo SSH Key cho domain: ${domain}..."
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

    update_env_var "SSH_KEY_PATH" "${ssh_key_path}" "$SITE_ENV"
    harden_permissions "$SITE_ENV"

    # Khởi tạo DB Credentials ngẫu nhiên
    local SAFE_DOMAIN=$(get_safe_domain "$domain")
    local raw_db_name="db_$(echo $SAFE_DOMAIN | cut -c1-24)"
    local raw_db_pass=$(tr -dc A-Za-z0-9 </dev/urandom | head -c 20 ; echo '')

    # Ghi cấu hình vào env file
    update_env_var "APP_DOMAIN" "${domain}" "$SITE_ENV"
    update_env_var "DB_NAME" "${raw_db_name}" "$SITE_ENV"
    update_env_var "DB_USER" "${raw_db_name}" "$SITE_ENV"
    update_env_var "DB_PASSWORD" "${raw_db_pass}" "$SITE_ENV"
    update_env_var "DOMAIN_ALIASES" "" "$SITE_ENV"

    info "Đã tạo file cấu hình: sites/.env.${domain}"

    # 2. Xây dựng cấu trúc thư mục Server /var/www/
    local target_dir="/var/www/$domain"
    mkdir -p "$target_dir/current/public"
    
    info "Khởi tạo cấu trúc Shared Storage..."
    mkdir -p "$target_dir/shared/storage/logs"
    mkdir -p "$target_dir/shared/storage/app/public"
    mkdir -p "$target_dir/shared/storage/framework/cache"
    mkdir -p "$target_dir/shared/storage/framework/sessions"
    mkdir -p "$target_dir/shared/storage/framework/views"
    
    # Khởi tạo file index.html tạm để kiểm tra Certbot
    echo "<h1>${domain} đang được setup bởi VPS Manager CLI...</h1>" > "$target_dir/current/public/index.html"
    chown -R "$app_user":"$app_user" "$target_dir"
    chmod 755 "$target_dir"

    # 3. Tạo Database MySQL cho Web
    info "Khởi tạo MySQL Database: [ ${raw_db_name} ]..."
    export DEBIAN_FRONTEND="noninteractive"
    run_mysql_secure "CREATE DATABASE IF NOT EXISTS \`${raw_db_name}\` CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;"
    run_mysql_secure "CREATE USER IF NOT EXISTS '${raw_db_name}'@'localhost' IDENTIFIED BY '${raw_db_pass}';"
    run_mysql_secure "GRANT ALL PRIVILEGES ON \`${raw_db_name}\`.* TO '${raw_db_name}'@'localhost';"
    run_mysql_secure "FLUSH PRIVILEGES;"

    # 4. Triển khai Nginx HTTP (Chưa cài SSL)
    info "Cấu hình Nginx (HTTP)..."
    local php_ver=$(grep -oP "(?<=^PHP_VERSION=\")[^\"]+" "$SITE_ENV" || echo "8.3")
    generate_nginx_config "$domain" "$domain" "$php_ver"
    systemctl reload nginx

    # 5. Khởi tạo file Supervisor rỗng (Chờ Bật các dịch vụ qua Menu Laravel)
    info "Khởi tạo file Supervisor rỗng: [ ${SAFE_DOMAIN} ]"
    local supervisor_conf="/etc/supervisor/conf.d/${SAFE_DOMAIN}.conf"
    
    cat <<EOF > "$supervisor_conf"
; File cấu hình Supervisor cho domain: ${domain}
; Sử dụng Menu Quản lý Laravel (./vps.sh manage-laravel) để bật tắt các dịch vụ (SSR, Queue Worker)
EOF
    chmod 644 "$supervisor_conf"

    info "================================================================="
    info " THÀNH CÔNG: Site [ $domain ] đã được khởi tạo."
    info "-----------------------------------------------------------------"
    info " Web Root     : $target_dir"
    info " DB Name/User : $raw_db_name"
    info " DB Password  : $raw_db_pass"
    info " DB Password  : $raw_db_pass"
    info " Node.js      : ${NODE_VER_SELECTED}.x"
    info "-----------------------------------------------------------------"
    info " SSH Public Key (Thêm vào Deploy Keys trên GitHub):"
    echo -e "${YELLOW}$(cat "${ssh_key_path}.pub")${NC}"
    info "-----------------------------------------------------------------"
    info " Thực hiện deploy: ./vps.sh deploy $domain"
    info " Cấu hình SSL   : ./vps.sh ssl $domain"
    info "================================================================="
}
