#!/usr/bin/env bash
# modules/logs.sh
# Trình theo dõi Luồng Lỗi Real-time (Laravel Exceptions & Nginx 5xx)

run_logs() {
    local domain="$1"
    
    info "Đang trích xuất Luồng Logs Trực Tiếp cho Website: $domain"
    info "(Nhấn Ctrl + C để thoát khỏi màn hình xem)"
    
    local laravel_log="/var/www/$domain/shared/storage/logs/laravel.log"
    local nginx_error_log="/var/log/nginx/error.log"

    # Kiểm tra tồn tại để tránh lỗi báo file not found làm đứng UI
    if [ ! -f "$laravel_log" ]; then
        warn "Không tìm thấy file laravel.log (Web có thể chưa ghi lỗi nào hoặc chưa Deploy)."
        laravel_log=""
    fi
    
    if [ ! -f "$nginx_error_log" ]; then
        nginx_error_log=""
    fi
    
    # Theo dõi gộp Log
    if [ -z "$laravel_log" ] && [ -z "$nginx_error_log" ]; then
        error "Không tìm thấy bất kỳ luồng log nào của máy chủ để the dõi."
    fi

    echo -e "${CYAN}--- BẮT ĐẦU THEO DÕI REALTIME ---${NC}"
    tail -f $laravel_log $nginx_error_log
}
