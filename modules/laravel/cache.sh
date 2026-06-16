#!/usr/bin/env bash
# modules/laravel/cache.sh
# Dọn dẹp cache và tối ưu hóa bộ nhớ cho ứng dụng Laravel.

#-----------------------------------------------------------------------------
# Hàm:          run_clear_cache
# Mô tả:        Xóa toàn bộ các loại cache view, config, route, và application.
# Biến toàn cục: Không có
# Tham số:      $1 - Tên miền chính (Domain)
#               $2 - Tên tài khoản user ứng dụng (App User)
#               $3 - Đường dẫn/Lệnh thực thi PHP
#               $4 - Đường dẫn thư mục dự án (Tùy chọn, mặc định: current)
# Trả về:       0 nếu thành công, 1 nếu thất bại
#-----------------------------------------------------------------------------
run_clear_cache() {
    local domain="$1"
    local app_user="$2"
    local php_bin="$3"
    local app_path="${4:-/var/www/$domain/current}"
    local artisan_path="${app_path}/artisan"

    info "Đang tiến hành dọn dẹp bộ nhớ cache (Clear Cache) cho $domain..."
    
    sudo -u "$app_user" "$php_bin" "$artisan_path" cache:clear || warn "Không thể clear cache"
    sudo -u "$app_user" "$php_bin" "$artisan_path" config:clear || warn "Không thể clear config"
    sudo -u "$app_user" "$php_bin" "$artisan_path" route:clear || warn "Không thể clear route"
    sudo -u "$app_user" "$php_bin" "$artisan_path" view:clear || warn "Không thể clear view"

    info "Dọn dẹp cache hoàn tất."
    return 0
}

#-----------------------------------------------------------------------------
# Hàm:          run_optimize_cache
# Mô tả:        Lưu cache config, route, view để tối ưu hiệu năng trên môi trường Production.
# Biến toàn cục: Không có
# Tham số:      $1 - Tên miền chính (Domain)
#               $2 - Tên tài khoản user ứng dụng (App User)
#               $3 - Đường dẫn/Lệnh thực thi PHP
#               $4 - Đường dẫn thư mục dự án (Tùy chọn, mặc định: current)
# Trả về:       0 nếu thành công, 1 nếu thất bại
#-----------------------------------------------------------------------------
run_optimize_cache() {
    local domain="$1"
    local app_user="$2"
    local php_bin="$3"
    local app_path="${4:-/var/www/$domain/current}"
    local artisan_path="${app_path}/artisan"

    info "Đang lưu cấu hình và tối ưu hóa hiệu năng (Config/Route/View Cache)..."
    
    # Dọn sạch các cache cũ trước khi thực hiện tối ưu hóa
    sudo -u "$app_user" "$php_bin" "$artisan_path" config:clear &>/dev/null
    sudo -u "$app_user" "$php_bin" "$artisan_path" route:clear &>/dev/null
    
    # Thực hiện lưu cache cấu hình
    local success=0
    if sudo -u "$app_user" "$php_bin" "$artisan_path" config:cache && \
       sudo -u "$app_user" "$php_bin" "$artisan_path" route:cache && \
       sudo -u "$app_user" "$php_bin" "$artisan_path" view:cache; then
        success=1
    fi

    if [ "$success" -eq 1 ]; then
        info "Tối ưu hóa hiệu năng và lưu cache thành công."
        return 0
    else
        error "Lỗi: Không thể cấu hình cache tối ưu (Vui lòng kiểm tra lại lỗi cú pháp code)."
        return 1
    fi
}

