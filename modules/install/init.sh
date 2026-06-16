#!/usr/bin/env bash
# modules/install/init.sh
# Khởi tạo môi trường cài đặt ban đầu cho hệ thống

#-----------------------------------------------------------------------------
# Hàm:          run_install_init
# Mô tả:        Kiểm tra quyền root, nạp file cấu hình .env tổng, sinh mật khẩu CSDL ngẫu nhiên.
# Biến toàn cục: SCRIPT_DIR, DB_ROOT_PASSWORD
# Tham số:      Không có
# Trả về:       Không có
#-----------------------------------------------------------------------------
run_install_init() {
    # Kiểm tra quyền root (Sử dụng hàm từ utils.sh)
    require_root

    # Nạp file môi trường gốc tổng (.env)
    if [ -f "$SCRIPT_DIR/.env" ]; then
        source "$SCRIPT_DIR/.env"
    else
        warn "Không tìm thấy file .env. Đang khởi tạo từ cấu hình ví dụ .env.global.example..."
        cp "$SCRIPT_DIR/.env.global.example" "$SCRIPT_DIR/.env"
        harden_permissions "$SCRIPT_DIR/.env"
        source "$SCRIPT_DIR/.env"
    fi

    # Tự động sinh mật khẩu ngẫu nhiên cho MySQL Root nếu chưa được cấu hình
    if [ -z "$DB_ROOT_PASSWORD" ] || [ "$DB_ROOT_PASSWORD" = "root_password_secure" ]; then
        info "Khởi tạo mật khẩu ngẫu nhiên cho tài khoản root MySQL..."
        local new_db_pass
        new_db_pass=$(tr -dc A-Za-z0-9 </dev/urandom | head -c 24)
        update_env_var "DB_ROOT_PASSWORD" "$new_db_pass" "$SCRIPT_DIR/.env"
        export DB_ROOT_PASSWORD="$new_db_pass"
        info "Mật khẩu MySQL root mới sinh: [ ${new_db_pass} ]"
        info "(Đã tự động lưu vào file .env)"
        info "--------------------------------------------------------"
    fi
}
