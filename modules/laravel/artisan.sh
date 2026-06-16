#!/usr/bin/env bash
# modules/laravel/artisan.sh
# Các lệnh Laravel Artisan liên quan đến database và tiện ích chạy dưới quyền App User.

#-----------------------------------------------------------------------------
# Hàm:          run_artisan_migrate
# Mô tả:        Chạy lệnh php artisan migrate --force để cập nhật database.
# Biến toàn cục: Không có
# Tham số:      $1 - Tên miền (Domain)
#               $2 - Tên user ứng dụng (App User)
#               $3 - Đường dẫn/Lệnh thực thi PHP
#               $4 - Đường dẫn thư mục dự án (Tùy chọn, mặc định: current)
# Trả về:       0 nếu thành công, 1 nếu thất bại
#-----------------------------------------------------------------------------
run_artisan_migrate() {
    local domain="$1"
    local app_user="$2"
    local php_bin="$3"
    local app_path="${4:-/var/www/$domain/current}"

    info "Đang chạy Database Migration (migrate --force) cho $domain tại $app_path..."
    if sudo -u "$app_user" "$php_bin" "${app_path}/artisan" migrate --force; then
        info "Đã chạy Migration thành công."
        return 0
    else
        error "Lỗi: Migration thất bại."
        return 1
    fi
}

#-----------------------------------------------------------------------------
# Hàm:          run_artisan_rollback
# Mô tả:        Chạy lệnh php artisan migrate:rollback --force để khôi phục db.
# Biến toàn cục: Không có
# Tham số:      $1 - Tên miền (Domain)
#               $2 - Tên user ứng dụng (App User)
#               $3 - Đường dẫn/Lệnh thực thi PHP
#               $4 - Đường dẫn thư mục dự án (Tùy chọn, mặc định: current)
# Trả về:       0 nếu thành công, 1 nếu thất bại
#-----------------------------------------------------------------------------
run_artisan_rollback() {
    local domain="$1"
    local app_user="$2"
    local php_bin="$3"
    local app_path="${4:-/var/www/$domain/current}"

    warn "CẢNH BÁO: Sếp chuẩn bị khôi phục lại (Rollback) các migration vừa chạy!"
    local confirm
    read -p "Nhập 'y' để xác nhận hoặc phím bất kỳ để hủy: " confirm
    if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
        info "Đã hủy thao tác rollback."
        return 0
    fi

    info "Đang chạy rollback migration cho $domain tại $app_path..."
    if sudo -u "$app_user" "$php_bin" "${app_path}/artisan" migrate:rollback --force; then
        info "Đã rollback thành công."
        return 0
    else
        error "Lỗi: Rollback thất bại."
        return 1
    fi
}

#-----------------------------------------------------------------------------
# Hàm:          run_artisan_key_generate
# Mô tả:        Chạy lệnh php artisan key:generate để tạo Application Key.
# Biến toàn cục: Không có
# Tham số:      $1 - Tên miền (Domain)
#               $2 - Tên user ứng dụng (App User)
#               $3 - Đường dẫn/Lệnh thực thi PHP
#               $4 - Đường dẫn thư mục dự án (Tùy chọn, mặc định: current)
# Trả về:       0 nếu thành công, 1 nếu thất bại
#-----------------------------------------------------------------------------
run_artisan_key_generate() {
    local domain="$1"
    local app_user="$2"
    local php_bin="$3"
    local app_path="${4:-/var/www/$domain/current}"

    info "Đang tạo Application Key cho $domain tại $app_path..."
    if sudo -u "$app_user" "$php_bin" "${app_path}/artisan" key:generate --force; then
        info "Đã tạo Application Key thành công."
        return 0
    else
        error "Lỗi: Tạo Application Key thất bại."
        return 1
    fi
}

#-----------------------------------------------------------------------------
# Hàm:          run_artisan_jwt_secret
# Mô tả:        Chạy lệnh php artisan jwt:secret để sinh khóa JWT mới.
# Biến toàn cục: Không có
# Tham số:      $1 - Tên miền (Domain)
#               $2 - Tên user ứng dụng (App User)
#               $3 - Đường dẫn/Lệnh thực thi PHP
#               $4 - Đường dẫn thư mục dự án (Tùy chọn, mặc định: current)
# Trả về:       0 nếu thành công, 1 nếu thất bại
#-----------------------------------------------------------------------------
run_artisan_jwt_secret() {
    local domain="$1"
    local app_user="$2"
    local php_bin="$3"
    local app_path="${4:-/var/www/$domain/current}"

    # Kiểm tra sự tồn tại của lệnh jwt:secret trong danh sách lệnh của Laravel
    if ! sudo -u "$app_user" "$php_bin" "${app_path}/artisan" list | grep -q "jwt:secret"; then
        error "Lỗi: Dự án của sếp không cài đặt gói tymon/jwt-auth (Không tìm thấy lệnh jwt:secret)."
        return 1
    fi

    info "Đang sinh khóa bí mật JWT secret cho $domain tại $app_path..."
    if sudo -u "$app_user" "$php_bin" "${app_path}/artisan" jwt:secret --force; then
        info "Đã sinh khóa JWT secret thành công."
        return 0
    else
        error "Lỗi: Sinh JWT secret thất bại."
        return 1
    fi
}

#-----------------------------------------------------------------------------
# Hàm:          run_artisan_storage_link
# Mô tả:        Chạy lệnh php artisan storage:link để liên kết thư mục public storage.
# Biến toàn cục: Không có
# Tham số:      $1 - Tên miền (Domain)
#               $2 - Tên user ứng dụng (App User)
#               $3 - Đường dẫn/Lệnh thực thi PHP
#               $4 - Đường dẫn thư mục dự án (Tùy chọn, mặc định: current)
# Trả về:       0 nếu thành công, 1 nếu thất bại
#-----------------------------------------------------------------------------
run_artisan_storage_link() {
    local domain="$1"
    local app_user="$2"
    local php_bin="$3"
    local app_path="${4:-/var/www/$domain/current}"

    info "Đang tạo Storage Symlink cho $domain tại $app_path..."
    if sudo -u "$app_user" "$php_bin" "${app_path}/artisan" storage:link; then
        info "Đã tạo liên kết storage:link thành công."
        return 0
    else
        error "Lỗi: Tạo storage symlink thất bại."
        return 1
    fi
}

