#!/usr/bin/env bash
# modules/database.sh
# Quản trị MySQL Server (Global), Cấu hình cron Backup tự động Multi-Site quét file Env

run_db_setup() {
    info "Bắt đầu thiết lập Máy chủ CSDT MySQL 8 Global..."

    export DEBIAN_FRONTEND="noninteractive"

    info "Cài đặt gói mysql-server..."
    apt-get install -y mysql-server
    
    systemctl start mysql
    systemctl enable mysql

    # Thiết lập mật khẩu Root MySQL nếu chưa có (Dùng cho Tool quản trị)
    info "Đang thiết lập bảo mật và mật khẩu Root cho MySQL..."
    
    # 1. Thử vào thẳng bằng sudo (Cơ chế auth_socket mặc định của Ubuntu)
    if sudo mysql -e "SELECT 1;" >/dev/null 2>&1; then
        info "Đồng bộ mật khẩu Root MySQL với file .env bằng quyền sudo..."
        sudo mysql -e "ALTER USER 'root'@'localhost' IDENTIFIED WITH mysql_native_password BY '${DB_ROOT_PASSWORD}';"
        sudo mysql -e "FLUSH PRIVILEGES;"
    else
        # 2. Nếu sudo thất bại, thử bằng pass hiện có trong .env (Trường hợp chạy lại lần 2)
        if mysql --user=root --password="${DB_ROOT_PASSWORD}" -e "SELECT 1;" >/dev/null 2>&1; then
            info "Mật khẩu Root MySQL đã được thiết lập đúng từ trước, bỏ qua bước đổi mật khẩu."
        else
            error "Không thể truy cập MySQL để thiết lập mật khẩu. Vui lòng kiểm tra dịch vụ MySQL."
        fi
    fi
    info "Mật khẩu Root MySQL đã được đồng bộ với file .env."


    # Setup thư mục backup data dùng chung cho Loop quét DB Backup 
    local BACKUP_DIR="/var/backups/mysql_multisite"
    info "Cấu hình cơ chế lưu trữ tự động Multi-Site Backup..."
    mkdir -p "$BACKUP_DIR"
    chown -R root:root "$BACKUP_DIR"
    chmod 700 "$BACKUP_DIR"

    # Tạo script shell vòng lặp dump database định kỳ
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

    # Cronjob Root 2h sáng
    if ! crontab -l 2>/dev/null | grep -q "mysql-multibackup.sh"; then
        (crontab -l 2>/dev/null; echo "0 2 * * * $BACKUP_SCRIPT >/dev/null 2>&1") | crontab -
        info "Đã gắn cronjob lập lịch hệ thống vào 2h sáng hàng ngày."
    else
        info "Cronjob Multi-Backup đã tồn tại, tự động bỏ qua nối thêm."
    fi

    # Cấu hình logrotate chung cho nhiều site bằng regex /*/shared/...
    info "Đăng ký chốt Logrotate /var/www/* quét Laravel logs ..."
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
    info "✅ THÀNH CÔNG: MÁY CHỦ MYSQL & MULTI-BACKUP ĐÃ HOÀN TẤT SETUP."
    info "Auto Backup nằm ở: $BACKUP_DIR"
    info "================================================================="
}
