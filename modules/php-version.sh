#!/usr/bin/env bash
# modules/php-version.sh
# Xử lý cập nhật, thay đổi PHP Version cho một dự án cụ thể.

run_change_php() {
    local domain="$1"
    
    info "Đang cấu hình thay đổi PHP Version cho dự án: $domain"
    
    local old_version=$(grep -oP "(?<=^PHP_VERSION=\")[^\"]+" "$SCRIPT_DIR/sites/.env.${domain}" || echo "Unknown")
    
    echo -e "${CYAN}Chọn phiên bản PHP cho Website: ${domain}${NC}"
    
    v81_label="PHP 8.1"; [ "$old_version" = "8.1" ] && v81_label="${v81_label} [Đang dùng]"
    v82_label="PHP 8.2"; [ "$old_version" = "8.2" ] && v82_label="${v82_label} [Đang dùng]"
    v83_label="PHP 8.3"; [ "$old_version" = "8.3" ] && v83_label="${v83_label} [Đang dùng]"
    v84_label="PHP 8.4"; [ "$old_version" = "8.4" ] && v84_label="${v84_label} [Đang dùng]"

    echo -e "  ${GREEN}1.${NC} ${v81_label}"
    echo -e "  ${GREEN}2.${NC} ${v82_label}"
    echo -e "  ${GREEN}3.${NC} ${v83_label}"
    echo -e "  ${GREEN}4.${NC} ${v84_label}"
    read -p "Lựa chọn của bạn: " php_choice
    
    case $php_choice in
        1) target_ver="8.1" ;;
        2) target_ver="8.2" ;;
        3) target_ver="8.3" ;;
        4) target_ver="8.4" ;;
        *) error "Lựa chọn không hợp lệ." ;;
    esac
    
    # 1. Tải bản PHP mới nếu Sever chưa có sẵn
    info "Đang kiểm tra và cài đặt gốc PHP $target_ver (nếu bị thiếu)..."
    local pack_check=$(dpkg-query -W -f='${Status}' "php${target_ver}-fpm" 2>/dev/null | grep -c "ok installed")
    if [ "$pack_check" -eq 0 ]; then
        info "Đang cài đặt PHP Version: $target_ver"
        apt-get install -y \
            "php${target_ver}-cli" \
            "php${target_ver}-fpm" \
            "php${target_ver}-mysql" \
            "php${target_ver}-mbstring" \
            "php${target_ver}-xml" \
            "php${target_ver}-zip" \
            "php${target_ver}-bcmath" \
            "php${target_ver}-curl" \
            "php${target_ver}-intl" \
            "php${target_ver}-gd" \
            "php${target_ver}-redis"
            
        systemctl start "php${target_ver}-fpm"
        systemctl enable "php${target_ver}-fpm"
    else
        info "Server đã có sẵn PHP $target_ver. Tiếp tục móc nối..."
    fi

    # 2. Cập nhật biến trong file Config
    sed -i "s/^PHP_VERSION=.*/PHP_VERSION=\"${target_ver}\"/" "$SCRIPT_DIR/sites/.env.${domain}"

    # 3. Đổi Port Nginx fastcgi sock
    local vhost="/etc/nginx/sites-available/$domain"
    if [ -f "$vhost" ]; then
        info "Cập nhật Nginx Worker Vhost Sock..."
        sed -i "s/php[0-9.]*-fpm.sock/php${target_ver}-fpm.sock/g" "$vhost"
        systemctl reload nginx
        
        info "================================================================="
        info "✅ THÀNH CÔNG: WEBSITE [ $domain ] ĐÃ ĐƯỢC ĐỔI SANG CHẠY PHP $target_ver"
        info "================================================================="
        
        # Reload PHP cũ xoá bộ nhớ đệm
        if [ "$old_version" != "Unknown" ] && [ "$old_version" != "$target_ver" ]; then
             systemctl reload "php${old_version}-fpm" || true
        fi
    else
        error "Lỗi hệ thống: Không tìm thấy file Virtual host của website Nginx."
    fi
}
