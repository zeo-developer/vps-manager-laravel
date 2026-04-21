#!/usr/bin/env bash
# modules/remove-site.sh
# Xóa vĩnh viễn cấu hình, cơ sở dữ liệu và source code của Website

run_remove_site() {
    local domain="$1"

    # Kiểm tra sự tồn tại của Site trước khi hỏi xoá
    local SITE_ENV="$SCRIPT_DIR/sites/.env.${domain}"
    if [ ! -f "$SITE_ENV" ]; then
        error "Tên miền [ $domain ] không tồn tại hoặc đã bị xóa trước đó."
        return
    fi
    
    warn "!!! CẢNH BÁO NGUY HIỂM !!!"
    warn "Bạn đang yêu cầu XÓA VĨNH VIỄN Website: $domain"
    warn "Tất cả Mã nguồn, Database, Cấu hình SSL, và Files sẽ bị huỷ."
    read -p "Hành động này KHÔNG THỂ PHỤC HỒI. Gõ chữ 'YES' để xác nhận: " confirm
    
    if [ "$confirm" != "YES" ]; then
        info "Đã huỷ bỏ lệnh xoá."
        return
    fi


    info "Bắt đầu thủ tục HUỶ DIỆT dự án $domain ..."

    # 1. Xoá Database
    if [ ! -z "$DB_NAME" ] && [ ! -z "$DB_USER" ]; then
        info "Xoá Database: $DB_NAME ..."
        run_mysql_secure "DROP DATABASE IF EXISTS \`${DB_NAME}\`;"
        
        info "Xoá User Database: $DB_USER ..."
        run_mysql_secure "DROP USER IF EXISTS '${DB_USER}'@'localhost';"
        run_mysql_secure "DROP USER IF EXISTS '${DB_USER}'@'%';" || true
        run_mysql_secure "FLUSH PRIVILEGES;"
    else
        warn "Không tìm thấy thông tin DB_NAME trong cấu hình, bỏ qua bước xoá MySQL."
    fi

    # 2. Xoá cấu hình Nginx
    info "Đang gỡ bỏ cấu hình Nginx..."
    rm -f "/etc/nginx/sites-enabled/$domain"
    rm -f "/etc/nginx/sites-available/$domain"
    systemctl reload nginx

    # 3. Gỡ bỏ Supervisor Queue
    info "Đang gỡ bỏ các tác vụ chạy nền (Supervisor)..."
    rm -f "/etc/supervisor/conf.d/worker-${domain}"*.conf
    supervisorctl update

    # 4. Gỡ bỏ Cronjob Schedule
    info "Gỡ bỏ Cronjob hệ thống..."
    local app_user=${APP_USER:-"www-data"}
    if sudo -u "$app_user" crontab -l 2>/dev/null | grep -q "cd /var/www/${domain}/current"; then
        sudo -u "$app_user" crontab -l | grep -v "cd /var/www/${domain}/current" | sudo -u "$app_user" crontab -
    fi

    # 5. Xóa Files và Config
    info "Xóa sạch Web Directory & File Cấu hình..."
    rm -rf "/var/www/$domain"
    rm -f "$SITE_ENV"

    # 6. Xóa SSH Key riêng biệt
    info "Gỡ bỏ SSH Key của dự án..."
    rm -f "/var/www/.vps_keys/id_ed25519_${domain}"*

    info "================================================================="
    info "💀 THÀNH CÔNG: DỰ ÁN [ $domain ] ĐÃ BỊ XOÁ BỎ HOÀN TOÀN TỪ SERVER."
    info "================================================================="
}
