#!/usr/bin/env bash
# modules/db/remote.sh
# Xử lý cấu hình cho phép hoặc chặn kết nối Database từ xa (Remote Connection)

#-----------------------------------------------------------------------------
# Hàm:          enable_remote_db
# Mô tả:        Cấu hình MySQL/MariaDB lắng nghe 0.0.0.0, mở port 3306 trên UFW, và cấp quyền cho User Remote.
# Biến toàn cục: SCRIPT_DIR, DB_USER, DB_NAME, DB_PASSWORD, GREEN, NC, CYAN
# Tham số:      $1 - Tên miền chính (Domain)
# Trả về:       0 nếu thành công, 1 nếu thất bại
#-----------------------------------------------------------------------------
enable_remote_db() {
    local domain="$1"
    local SITE_ENV="$SCRIPT_DIR/sites/.env.${domain}"
    source "$SITE_ENV"

    info "Đang kích hoạt tính năng Remote Database cho ${domain}..."

    # 1. Cấu hình bind-address (Hỗ trợ cả MySQL và MariaDB)
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
    local remote_type
    read -p "Lựa chọn: " remote_type
    
    local allow_ip="%"
    if [ "$remote_type" = "1" ]; then
        local user_ip
        read -p "Nhập IP của bạn: " user_ip
        allow_ip=$(sanitize_input "$user_ip")
        if [ -z "$allow_ip" ]; then error "IP không hợp lệ."; return 1; fi
    fi

    # 2. Tạo User Remote cho domain này
    run_mysql_secure "CREATE USER IF NOT EXISTS '${DB_USER}'@'${allow_ip}' IDENTIFIED BY '${DB_PASSWORD}';"
    run_mysql_secure "GRANT ALL PRIVILEGES ON \`${DB_NAME}\`.* TO '${DB_USER}'@'${allow_ip}';"
    run_mysql_secure "FLUSH PRIVILEGES;"

    # 3. Mở Port 3306 trên UFW (Tường lửa)
    if command -v ufw > /dev/null; then
        ufw allow 3306/tcp > /dev/null
        info "Đã mở Port 3306 trên Tường lửa (UFW)."
    fi

    local ip_address
    ip_address=$(hostname -I | awk '{print $1}')
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

#-----------------------------------------------------------------------------
# Hàm:          disable_remote_db
# Mô tả:        Gỡ bỏ tài khoản người dùng remote và thu hồi quyền truy cập từ xa.
# Biến toàn cục: SCRIPT_DIR, DB_USER, DB_NAME
# Tham số:      $1 - Tên miền chính (Domain)
# Trả về:       Không có
#-----------------------------------------------------------------------------
disable_remote_db() {
    local domain="$1"
    local SITE_ENV="$SCRIPT_DIR/sites/.env.${domain}"
    source "$SITE_ENV"

    info "Đang tắt Remote Database cho ${domain}..."

    # 1. Xoá User Remote
    run_mysql_secure "REVOKE ALL PRIVILEGES ON \`${DB_NAME}\`.* FROM '${DB_USER}'@'%';" || true
    run_mysql_secure "DROP USER IF EXISTS '${DB_USER}'@'%';" || true
    run_mysql_secure "FLUSH PRIVILEGES;"

    info "================================================================="
    info "🔒 THÀNH CÔNG: REMOTE DATABASE CHO [ ${domain} ] ĐÃ BỊ TẮT."
    info "Chỉ cho phép kết nối nội bộ (localhost)."
    info "================================================================="
}
