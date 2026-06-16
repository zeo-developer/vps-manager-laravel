#!/usr/bin/env bash
# modules/db/password.sh
# Xử lý thay đổi mật khẩu tài khoản Database cho từng Website

#-----------------------------------------------------------------------------
# Hàm:          change_db_password
# Mô tả:        Thay đổi mật khẩu MySQL/MariaDB của website và cập nhật tệp tin cấu hình .env.
# Biến toàn cục: SCRIPT_DIR, YELLOW, NC, DB_USER, DB_PASSWORD, DB_NAME, APP_USER, PHP_VERSION
# Tham số:      $1 - Tên miền chính (Domain)
# Trả về:       0 nếu thành công, 1 nếu thất bại
#-----------------------------------------------------------------------------
change_db_password() {
    local domain="$1"
    local SITE_ENV="$SCRIPT_DIR/sites/.env.${domain}"
    
    # Nạp cấu hình riêng của site
    source "$SITE_ENV"

    echo -e "${YELLOW}Nhấn [Enter] để tự động tạo Mật khẩu siêu bảo mật (20 ký tự).${NC}"
    local new_pass
    read -p "Nhập Mật khẩu Database Mới: " new_pass
    
    # Nếu để trống, tự động tạo ngẫu nhiên
    if [ -z "$new_pass" ]; then
        new_pass=$(tr -dc A-Za-z0-9 </dev/urandom | head -c 20)
        info "🎲 Đã tạo mật khẩu ngẫu nhiên: ${new_pass}"
    fi

    info "Đang thay đổi mật khẩu Database cho người dùng ${DB_USER}..."
    
    # Lấy danh sách Host thực tế của User để tránh lỗi ERROR 1396 (User doesn't exist)
    local existing_hosts
    existing_hosts=$(sudo mysql -N -s -e "SELECT host FROM mysql.user WHERE user = '${DB_USER}';" 2>/dev/null)
    
    if [ -z "$existing_hosts" ]; then
        error "Không tìm thấy User ${DB_USER} trong hệ thống Database."
        return 1
    fi

    local success_count=0
    local db_host
    for db_host in $existing_hosts; do
        if run_mysql_secure "ALTER USER '${DB_USER}'@'${db_host}' IDENTIFIED BY '${new_pass}';"; then
            ((success_count++))
        fi
    done

    if [ "$success_count" -gt 0 ]; then
        run_mysql_secure "FLUSH PRIVILEGES;"
        
        # Cập nhật cấu hình của VPS Tool (.env.domain)
        sed -i "s/^DB_PASSWORD=.*/DB_PASSWORD=\"${new_pass}\"/" "$SITE_ENV"
        
        # Cập nhật cấu hình của Laravel Application (shared/.env)
        local shared_env="/var/www/${domain}/shared/.env"
        if [ -f "$shared_env" ]; then
            sed -i "s/^DB_PASSWORD=.*/DB_PASSWORD=\"${new_pass}\"/" "$shared_env"
            info "Đã cập nhật mật khẩu vào file .env của Laravel."
            
            # Xóa cấu hình cache cũ của Laravel để nhận thông tin mới
            if [ -d "/var/www/${domain}/current" ]; then
                # Cần nạp file để lấy phiên bản PHP chính xác của site
                local current_php_ver
                current_php_ver=$(grep -oP "(?<=^PHP_VERSION=\")[^\"]+" "$SITE_ENV" || echo "8.3")
                cd "/var/www/${domain}/current" && sudo -u "${APP_USER:-www-data}" php${current_php_ver} artisan config:cache || true
            fi
        fi

        info "================================================================="
        info "✅ THÀNH CÔNG: MẬT KHẨU DATABASE ĐÃ ĐƯỢC THAY ĐỔI ($success_count HOST)."
        info "Tài khoản: ${DB_USER}"
        info "Mật khẩu : ${new_pass}"
        info "================================================================="
        return 0
    else
        error "Có lỗi xảy ra khi đổi mật khẩu Database."
        return 1
    fi
}
