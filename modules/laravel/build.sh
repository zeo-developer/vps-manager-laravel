#!/usr/bin/env bash
# modules/laravel/build.sh
# Biên dịch tài nguyên front-end sử dụng npm${NODE_VERSION} toàn cục.

#-----------------------------------------------------------------------------
# Hàm:          run_npm_build
# Mô tả:        Biên dịch tài nguyên front-end bằng lệnh npm${NODE_VERSION} run build.
# Biến toàn cục: SCRIPT_DIR, NODE_VERSION
# Tham số:      $1 - Tên miền chính (Domain)
#               $2 - Tên tài khoản user ứng dụng (App User)
# Trả về:       0 nếu thành công, 1 nếu thất bại
#-----------------------------------------------------------------------------
run_npm_build() {
    local domain="$1"
    local app_user="$2"
    
    # Nạp cấu hình site nếu chưa có biến NODE_VERSION
    local node_ver="${NODE_VERSION:-20}"
    local site_env="$SCRIPT_DIR/sites/.env.$domain"
    [ -f "$site_env" ] && source "$site_env" && node_ver="${NODE_VERSION:-20}"

    # Kiểm tra xem package.json có tồn tại trong thư mục mã nguồn
    if [ ! -f "/var/www/$domain/current/package.json" ]; then
        error "Lỗi: Không tìm thấy package.json trong thư mục current của $domain."
        return 1
    fi

    info "Đang chạy biên dịch asset (npm${node_ver} run build) cho $domain..."
    
    # Chạy build trực tiếp bằng npm${node_ver} dưới quyền app_user
    if cd "/var/www/$domain/current" && sudo -u "$app_user" npm${node_ver} run build; then
        info "Biên dịch asset thành công."
        return 0
    else
        error "Lỗi: Biên dịch asset thất bại."
        return 1
    fi
}

#-----------------------------------------------------------------------------
# Hàm:          run_npm_build_ssr
# Mô tả:        Biên dịch build các file NodeJS phục vụ cho Inertia SSR (npm${NODE_VERSION} run build:ssr).
# Biến toàn cục: SCRIPT_DIR, NODE_VERSION
# Tham số:      $1 - Tên miền chính (Domain)
#               $2 - Tên tài khoản user ứng dụng (App User)
# Trả về:       0 nếu thành công, 1 nếu thất bại
#-----------------------------------------------------------------------------
run_npm_build_ssr() {
    local domain="$1"
    local app_user="$2"

    local node_ver="${NODE_VERSION:-20}"
    local site_env="$SCRIPT_DIR/sites/.env.$domain"
    [ -f "$site_env" ] && source "$site_env" && node_ver="${NODE_VERSION:-20}"

    if [ ! -f "/var/www/$domain/current/package.json" ]; then
        error "Lỗi: Không tìm thấy package.json trong thư mục current."
        return 1
    fi

    # Đọc script package.json kiểm tra xem có hỗ trợ build:ssr không
    if ! grep -q '"build:ssr"' "/var/www/$domain/current/package.json"; then
        error "Lỗi: File package.json không định nghĩa script 'build:ssr' (Inertia SSR)."
        return 1
    fi

    info "Đang chạy biên dịch Inertia SSR (npm${node_ver} run build:ssr) cho $domain..."
    
    if cd "/var/www/$domain/current" && sudo -u "$app_user" npm${node_ver} run build:ssr; then
        info "Biên dịch SSR (npm${node_ver} run build:ssr) thành công."
        return 0
    else
        error "Lỗi: Biên dịch SSR thất bại."
        return 1
    fi
}
