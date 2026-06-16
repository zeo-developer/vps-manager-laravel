#!/usr/bin/env bash
# modules/runtime/php.sh
# Xử lý cập nhật, thay đổi phiên bản PHP cho một dự án cụ thể.

#-----------------------------------------------------------------------------
# Hàm:          run_change_php
# Mô tả:        Thay đổi phiên bản PHP cho một website (cài PHP mới, cấu hình Nginx, Supervisor).
# Biến toàn cục: SCRIPT_DIR, CYAN, NC, GREEN, YELLOW, RED
# Tham số:      $1 - Tên miền chính (Domain)
# Trả về:       Không có (Hoặc trả về 1 nếu lỗi)
#-----------------------------------------------------------------------------
run_change_php() {
    local domain="$1"
    
    info "Đang cấu hình thay đổi phiên bản PHP cho dự án: $domain"
    
    # Lấy phiên bản PHP hiện tại trong cấu hình site
    local old_version
    old_version=$(grep -oP "(?<=^PHP_VERSION=\")[^\"]+" "$SCRIPT_DIR/sites/.env.${domain}" || echo "Unknown")
    
    echo -e "${CYAN}Chọn phiên bản PHP cho Website: ${domain}${NC}"
    
    local v81_label="PHP 8.1"; [ "$old_version" = "8.1" ] && v81_label="${v81_label} [Đang dùng]"
    local v82_label="PHP 8.2"; [ "$old_version" = "8.2" ] && v82_label="${v82_label} [Đang dùng]"
    local v83_label="PHP 8.3"; [ "$old_version" = "8.3" ] && v83_label="${v83_label} [Đang dùng]"
    local v84_label="PHP 8.4"; [ "$old_version" = "8.4" ] && v84_label="${v84_label} [Đang dùng]"

    echo -e "  ${GREEN}1.${NC} ${v81_label}"
    echo -e "  ${GREEN}2.${NC} ${v82_label}"
    echo -e "  ${GREEN}3.${NC} ${v83_label}"
    echo -e "  ${GREEN}4.${NC} ${v84_label}"
    local php_choice
    read -p "Lựa chọn của bạn: " php_choice
    
    local target_ver=""
    case $php_choice in
        1) target_ver="8.1" ;;
        2) target_ver="8.2" ;;
        3) target_ver="8.3" ;;
        4) target_ver="8.4" ;;
        *) error "Lựa chọn không hợp lệ." ; return 1 ;;
    esac
    
    # 1. Tải bản PHP mới nếu máy chủ chưa cài đặt sẵn
    info "Đang kiểm tra và cài đặt PHP $target_ver (nếu bị thiếu trên máy chủ)..."
    local pack_check
    pack_check=$(dpkg-query -W -f='${Status}' "php${target_ver}-fpm" 2>/dev/null | grep -c "ok installed")
    
    if [ "$pack_check" -eq 0 ]; then
        info "Đang tiến hành cài đặt PHP phiên bản: $target_ver..."
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
        info "Máy chủ đã cài sẵn PHP $target_ver. Bắt đầu cấu hình website..."
    fi

    # 2. Cập nhật biến trong file Config cấu hình của Site
    sed -i "s/^PHP_VERSION=.*/PHP_VERSION=\"${target_ver}\"/" "$SCRIPT_DIR/sites/.env.${domain}"

    # 3. Đổi liên kết Socket PHP-FPM trên cấu hình Nginx Virtual Host
    local vhost="/etc/nginx/sites-available/$domain"
    if [ -f "$vhost" ]; then
        info "Cập nhật Nginx Virtual Host Socket..."
        sed -i "s/php[0-9.]*-fpm.sock/php${target_ver}-fpm.sock/g" "$vhost"
        systemctl reload nginx

        # 4. Cập nhật cấu hình Supervisor (nếu có sử dụng Queue Worker / PHP-based processes)
        local safe_domain
        safe_domain=$(get_safe_domain "$domain")
        local supervisor_conf="/etc/supervisor/conf.d/${safe_domain}.conf"
        if [ -f "$supervisor_conf" ]; then
            info "Cập nhật các chương trình Supervisor chạy với PHP $target_ver..."
            sed -i "s|command=php[0-9.]*\s|command=php${target_ver} |g" "$supervisor_conf"
            
            # Đọc lại cấu hình mới và khởi động lại các tiến trình
            supervisorctl reread >/dev/null 2>&1 || true
            supervisorctl update >/dev/null 2>&1 || true
            supervisorctl restart "${safe_domain}:*" >/dev/null 2>&1 \
                || supervisorctl start "${safe_domain}:*" >/dev/null 2>&1 || true
            info "Đã khởi động lại nhóm dịch vụ Supervisor [${safe_domain}] với PHP $target_ver"
        fi
        
        info "================================================================="
        info "✅ THÀNH CÔNG: WEBSITE [ $domain ] ĐÃ CHUYỂN SANG CHẠY PHP $target_ver"
        info "================================================================="
        
        # Tải lại dịch vụ PHP-FPM phiên bản cũ để giải phóng bộ nhớ đệm
        if [ "$old_version" != "Unknown" ] && [ "$old_version" != "$target_ver" ]; then
             systemctl reload "php${old_version}-fpm" || true
        fi
    else
        error "Lỗi hệ thống: Không tìm thấy tệp Virtual Host Nginx của website."
        return 1
    fi
}
