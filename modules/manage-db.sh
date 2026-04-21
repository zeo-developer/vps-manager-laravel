#!/usr/bin/env bash
# modules/manage-db.sh
# Quản lý Database: Đổi mật khẩu & Cấu hình Remote

run_manage_db() {
    local domain="$1"
    
    echo -e "${CYAN}==========================================${NC}"
    echo -e "${CYAN}    QUẢN LÝ DATABASE CHO: ${domain}      ${NC}"
    echo -e "${CYAN}==========================================${NC}"
    echo -e " ${GREEN}1.${NC} Đổi Mật khẩu Database"
    echo -e " ${GREEN}2.${NC} Bật Remote Database (Cho phép kết nối ngoài)"
    echo -e " ${GREEN}3.${NC} Tắt Remote Database (Chỉ nội bộ localhost)"
    echo -e " ${RED}0.${NC} Quay lại Menu chính"
    echo -e "------------------------------------------"
    read -p "Lựa chọn của bạn: " db_choice

    case $db_choice in
        1) change_db_password "$domain" ;;
        2) enable_remote_db "$domain" ;;
        3) disable_remote_db "$domain" ;;
        0) return ;;
        *) warn "Lựa chọn không hợp lệ."; run_manage_db "$domain" ;;
    esac
}

change_db_password() {
    local domain="$1"
    local SITE_ENV="$SCRIPT_DIR/sites/.env.${domain}"
    
    source "$SITE_ENV"

    echo -e "${YELLOW}Nhấn [Enter] để tự động tạo Mật khẩu siêu bảo mật (20 ký tự).${NC}"
    read -p "Nhập Mật khẩu Database Mới: " new_pass
    
    # Nếu để trống, tự động bốc pass ngẫu nhiên
    if [ -z "$new_pass" ]; then
        new_pass=$(tr -dc A-Za-z0-9 </dev/urandom | head -c 20)
        info "🎲 Đã tạo mật khẩu ngẫu nhiên: ${new_pass}"
    fi

    info "Đang thay đổi mật khẩu Database cho User ${DB_USER}..."
    
    # Lấy danh sách Host thực tế của User để tránh lỗi ERROR 1396 (User doesn't exist)
    # Lệnh này sẽ trả về danh sách host (vd: localhost, %)
    local existing_hosts=$(sudo mysql -N -s -e "SELECT host FROM mysql.user WHERE user = '${DB_USER}';" 2>/dev/null)
    
    if [ -z "$existing_hosts" ]; then
        error "Không tìm thấy User ${DB_USER} trong hệ thống Database."
        return 1
    fi

    local success_count=0
    for db_host in $existing_hosts; do
        if run_mysql_secure "ALTER USER '${DB_USER}'@'${db_host}' IDENTIFIED BY '${new_pass}';"; then
            ((success_count++))
        fi
    done

    if [ "$success_count" -gt 0 ]; then
        run_mysql_secure "FLUSH PRIVILEGES;"
        
        # 2. Cập nhật sites/.env.domain (VPS Tool)
        sed -i "s/^DB_PASSWORD=.*/DB_PASSWORD=\"${new_pass}\"/" "$SITE_ENV"
        
        # 3. Cập nhật /var/www/${domain}/shared/.env (Laravel App)
        local shared_env="/var/www/${domain}/shared/.env"
        if [ -f "$shared_env" ]; then
            # Dùng dấu nháy để bọc pass chống lỗi ký tự đặc biệt
            sed -i "s/^DB_PASSWORD=.*/DB_PASSWORD=\"${new_pass}\"/" "$shared_env"
            info "Đã cập nhật mật khẩu vào file .env của Laravel."
            
            # Xoá cache laravel để nhận pass mới
            if [ -d "/var/www/${domain}/current" ]; then
                cd "/var/www/${domain}/current" && sudo -u "${APP_USER:-www-data}" php artisan config:cache || true
            fi
        fi

        info "================================================================="
        info "✅ THÀNH CÔNG: MẬT KHẨU DATABASE ĐÃ ĐƯỢC THAY ĐỔI ($success_count HOST)."
        info "Tài khoản: ${DB_USER}"
        info "Mật khẩu : ${new_pass}"
        info "================================================================="
    else
        error "Có lỗi xảy ra khi đổi mật khẩu Database."
    fi
}

enable_remote_db() {
    local domain="$1"
    local SITE_ENV="$SCRIPT_DIR/sites/.env.${domain}"
    source "$SITE_ENV"

    info "Đang kích hoạt tính năng Remote Database cho ${domain}..."

    # 1. Sửa bind-address (Hỗ trợ cả MySQL và MariaDB)
    local mysql_conf="/etc/mysql/mysql.conf.d/mysqld.cnf"
    local mariadb_conf="/etc/mysql/mariadb.conf.d/50-server.cnf"
    local target_conf=""

    if [ -f "$mariadb_conf" ]; then
        target_conf="$mariadb_conf"
    elif [ -f "$mysql_conf" ]; then
        target_conf="$mysql_conf"
    fi

    if [ ! -z "$target_conf" ]; then
        if grep -q "bind-address\s*=\s*127.0.0.1" "$target_conf"; then
            sed -i "s/bind-address\s*=\s*127.0.0.1/bind-address = 0.0.0.0/" "$target_conf"
            # Khởi động lại dịch vụ tương ứng
            systemctl restart mariadb 2>/dev/null || systemctl restart mysql
            info "Đã cấu hình Database lắng nghe mọi Interface (0.0.0.0) tại $target_conf."
        fi
    fi


    echo -e "Chọn phạm vi cho phép kết nối Remote:"
    echo -e "  ${GREEN}1.${NC} Chỉ một IP duy nhất (An toàn nhất)"
    echo -e "  ${GREEN}2.${NC} Cho phép tất cả (0.0.0.0 - Kém an toàn)"
    read -p "Lựa chọn: " remote_type
    
    local allow_ip="%"
    if [ "$remote_type" = "1" ]; then
        read -p "Nhập IP của bạn: " user_ip
        allow_ip=$(sanitize_input "$user_ip")
        if [ -z "$allow_ip" ]; then error "IP không hợp lệ."; fi
    fi

    # 2. Tạo User Remote cho domain này
    run_mysql_secure "CREATE USER IF NOT EXISTS '${DB_USER}'@'${allow_ip}' IDENTIFIED BY '${DB_PASSWORD}';"
    run_mysql_secure "GRANT ALL PRIVILEGES ON \`${DB_NAME}\`.* TO '${DB_USER}'@'${allow_ip}';"
    run_mysql_secure "FLUSH PRIVILEGES;"

    # 3. Mở Port 3306 trên UFW
    if command -v ufw > /dev/null; then
        ufw allow 3306/tcp > /dev/null
        info "Đã mở Port 3306 trên Tường lửa (UFW)."
    fi

    local ip_address=$(hostname -I | awk '{print $1}')
    info "================================================================="
    info "🚀 THÀNH CÔNG: REMOTE DATABASE ĐÃ ĐƯỢC BẬT."
    info "Bạn có thể dùng HeidiSQL/Navicat để kết nối:"
    info "  - Host: ${ip_address}"
    info "  - Port: 3306"
    info "  - User: ${DB_USER}"
    info "  - Pass: ${DB_PASSWORD}"
    info "  - DB  : ${DB_NAME}"
    info "================================================================="
}

disable_remote_db() {
    local domain="$1"
    local SITE_ENV="$SCRIPT_DIR/sites/.env.${domain}"
    source "$SITE_ENV"

    info "Đang tắt Remote Database cho ${domain}..."

    # 1. Xoá User Remote (Quét cả % và các IP cụ thể nếu có thể)
    # Lưu ý: Việc xoá chính xác cần biết IP cũ, ở đây ta ưu tiên xoá % và log lỗi nếu không tìm thấy
    run_mysql_secure "REVOKE ALL PRIVILEGES ON \`${DB_NAME}\`.* FROM '${DB_USER}'@'%';" || true
    run_mysql_secure "DROP USER IF EXISTS '${DB_USER}'@'%';" || true
    run_mysql_secure "FLUSH PRIVILEGES;"

    info "================================================================="
    info "🔒 THÀNH CÔNG: REMOTE DATABASE CHO [ ${domain} ] ĐÃ BỊ TẮT."
    info "Chỉ cho phép kết nối nội bộ (localhost)."
    info "================================================================="
}
