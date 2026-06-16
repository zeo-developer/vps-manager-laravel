#!/usr/bin/env bash
# modules/install/db.sh
# Quản trị MySQL/MariaDB Server, lập lịch backup dữ liệu Multi-site (Phase 3)

#-----------------------------------------------------------------------------
# Hàm:          run_db_setup
# Mô tả:        Cài đặt MariaDB Server, bảo mật mật khẩu root, thiết lập script và cronjob backup dữ liệu.
# Biến toàn cục: DB_ROOT_PASSWORD, SCRIPT_DIR, APP_USER
# Tham số:      Không có
# Trả về:       Không có
#-----------------------------------------------------------------------------
run_db_setup() {
    info "Bắt đầu thiết lập Máy chủ CSDL MariaDB..."

    export DEBIAN_FRONTEND="noninteractive"

    info "Cài đặt mariadb-server..."
    apt-get install -y mariadb-server
    
    systemctl start mariadb
    systemctl enable mariadb

    # Thiết lập mật khẩu cho tài khoản Root MySQL
    info "Đang thiết lập bảo mật và mật khẩu Root cho MariaDB..."
    
    if sudo mariadb-admin -u root password "${DB_ROOT_PASSWORD}" >/dev/null 2>&1; then
        info "✅ [THÀNH CÔNG] MariaDB Root Password đã được thiết lập qua mariadb-admin."
    else
        # Nếu mariadb-admin thất bại (có thể đã đặt pass trước đó), cập nhật lại qua lệnh SQL trực tiếp
        if sudo mysql -e "SET PASSWORD FOR 'root'@'localhost' = PASSWORD('${DB_ROOT_PASSWORD}');" >/dev/null 2>&1; then
             info "✅ [THÀNH CÔNG] MariaDB Root Password đã được cập nhật qua SQL."
        else
            # Kiểm tra xem mật khẩu hiện tại trong môi trường đã đúng chưa
            if mysql --user=root --password="${DB_ROOT_PASSWORD}" -e "SELECT 1;" >/dev/null 2>&1; then
                info "ℹ️ Mật khẩu Root MariaDB đã được đồng bộ chính xác từ trước."
            else
                warn "⚠️ Cảnh báo: Không thể thiết lập mật khẩu MariaDB. Có thể do mật khẩu cũ không khớp."
                warn "Nếu đây là VPS mới mua, anh có thể bỏ qua hoặc kiểm tra lại file .env."
            fi
        fi
    fi
    sudo mysql -u root -p"${DB_ROOT_PASSWORD}" -e "FLUSH PRIVILEGES;" >/dev/null 2>&1 || sudo mysql -e "FLUSH PRIVILEGES;" >/dev/null 2>&1

    # Tạo thư mục sao lưu cơ sở dữ liệu
    local BACKUP_DIR="/var/backups/mysql_multisite"
    info "Cấu hình cơ chế lưu trữ tự động Multi-Site Backup..."
    mkdir -p "$BACKUP_DIR"
    chown -R root:root "$BACKUP_DIR"
    chmod 700 "$BACKUP_DIR"

    # Tạo tệp tin script chạy tác vụ sao lưu tự động các site
    local BACKUP_SCRIPT="/usr/local/bin/mysql-multibackup.sh"
    cat <<EOF > "$BACKUP_SCRIPT"
#!/usr/bin/env bash
# Script Backup MySQL Database Tự động quét config Env

DATE_STR=\$(date +"%Y-%m-%d_%H-%M-%S")
BACKUP_DIR="$BACKUP_DIR"
KEEP_DAYS=7

mkdir -p "\$BACKUP_DIR/\$DATE_STR"

# Quét tất cả sites configs để check ra DB_NAME
for env_file in $SCRIPT_DIR/sites/.env.*; do
    [ -f "\$env_file" ] || continue
    db_name=\$(grep -oP "(?<=^DB_NAME=\")[^\"]+" "\$env_file" || echo "")
    if [ ! -z "\$db_name" ]; then
        BACKUP_FILE="\$BACKUP_DIR/\$DATE_STR/\${db_name}.sql.gz"
        mysqldump "\$db_name" | gzip > "\$BACKUP_FILE"
    fi
done

# Xoá thư mục quá hạn
find "\$BACKUP_DIR" -maxdepth 1 -type d -mtime +\${KEEP_DAYS} -exec rm -rf {} \;
EOF
    chmod +x "$BACKUP_SCRIPT"

    # Cấu hình Cronjob cho tài khoản Root chạy tự động vào 2h sáng hàng ngày
    if ! crontab -l 2>/dev/null | grep -q "mysql-multibackup.sh"; then
        (crontab -l 2>/dev/null; echo "0 2 * * * $BACKUP_SCRIPT >/dev/null 2>&1") | crontab -
        info "Đã gắn cronjob lập lịch hệ thống vào 2h sáng hàng ngày."
    else
        info "Cronjob Multi-Backup đã tồn tại, tự động bỏ qua nối thêm."
    fi

    # Cấu hình logrotate cho Laravel Logs để tránh đầy dung lượng đĩa cứng
    info "Đăng ký cấu hình Logrotate /var/www/*/shared/storage/logs/ quét Laravel logs..."
    local app_user=${APP_USER:-"www-data"}
    cat <<EOF > /etc/logrotate.d/laravel_multisite
/var/www/*/shared/storage/logs/*.log {
    daily
    missingok
    rotate 14
    compress
    delaycompress
    notifempty
    create 0644 $app_user $app_user
}
EOF

    info "================================================================="
    info "✅ THÀNH CÔNG: MÁY CHỦ DATABASE & MULTI-BACKUP ĐÃ HOÀN TẤT SETUP."
    info "Thư mục Auto Backup nằm tại: $BACKUP_DIR"
    info "================================================================="
}
