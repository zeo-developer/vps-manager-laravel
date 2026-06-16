#!/usr/bin/env bash
# modules/laravel/scheduler.sh
# Quản lý trạng thái Bật/Tắt Laravel Scheduler cronjob cho từng website.

#-----------------------------------------------------------------------------
# Hàm:          toggle_laravel_scheduler
# Mô tả:        Bật hoặc Tắt cronjob Laravel Scheduler (artisan schedule:run) cho site.
# Biến toàn cục: SCRIPT_DIR, APP_USER, PHP_VERSION, CYAN, NC, BLUE, GREEN, RED
# Tham số:      $1 - Tên miền Website (Domain)
# Trả về:       0 nếu thành công, 1 nếu thất bại
#-----------------------------------------------------------------------------
toggle_laravel_scheduler() {
    local domain="$1"
    local app_user="${APP_USER:-www-data}"
    
    # Sử dụng trực tiếp lệnh PHP toàn cục tương ứng với site
    local php_bin="php${PHP_VERSION:-8.3}"

    local cron_keyword="cd /var/www/$domain/current"
    local has_cron=0
    if sudo -u "$app_user" crontab -l 2>/dev/null | grep -q "$cron_keyword"; then
        has_cron=1
    fi

    echo -e "${CYAN}------------------------------------------${NC}"
    echo -e " ${BLUE}Trạng thái Laravel Scheduler cho $domain:${NC}"
    echo -e "${CYAN}------------------------------------------${NC}"
    
    if [ "$has_cron" -eq 1 ]; then
        echo -e " Trạng thái: ${GREEN}ĐANG BẬT (ENABLED)${NC}"
        local current_cron
        current_cron=$(sudo -u "$app_user" crontab -l 2>/dev/null | grep "$cron_keyword")
        echo -e " Chi tiết:   $current_cron"
        echo -e "------------------------------------------"
        local confirm
        read -p "Sếp có muốn TẮT Scheduler này đi không? (y/n): " confirm
        if [[ "$confirm" =~ ^[Yy]$ ]]; then
            info "Đang gỡ bỏ Laravel Scheduler..."
            sudo -u "$app_user" crontab -l 2>/dev/null | grep -v "$cron_keyword" | sudo -u "$app_user" crontab -
            info "Đã tắt Laravel Scheduler thành công."
        fi
    else
        echo -e " Trạng thái: ${RED}ĐANG TẮT (DISABLED)${NC}"
        echo -e "------------------------------------------"
        local confirm
        read -p "Sếp có muốn BẬT Scheduler này lên không? (y/n): " confirm
        if [[ "$confirm" =~ ^[Yy]$ ]]; then
            info "Đang kích hoạt Laravel Scheduler..."
            local cron_cmd="* * * * * cd /var/www/$domain/current && $php_bin artisan schedule:run >> /dev/null 2>&1"
            (sudo -u "$app_user" crontab -l 2>/dev/null; echo "$cron_cmd") | sudo -u "$app_user" crontab -
            info "Đã bật Laravel Scheduler thành công."
        fi
    fi
    return 0
}
