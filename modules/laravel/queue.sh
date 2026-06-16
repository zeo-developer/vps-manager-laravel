#!/usr/bin/env bash
# modules/laravel/queue.sh
# Xử lý thêm các Supervisor Config cho 1 dự án riêng biệt (Custom Queue).

#-----------------------------------------------------------------------------
# Hàm:          run_add_queue
# Mô tả:        Cấu hình thêm Custom Queue Worker (Laravel) chạy ngầm qua Supervisor.
# Biến toàn cục: APP_USER, PHP_VERSION
# Tham số:      $1 - Tên miền Website (Domain)
# Trả về:       0 nếu thành công, 1 nếu thất bại
#-----------------------------------------------------------------------------
run_add_queue() {
    local domain="$1"
    
    info "Cấu hình Custom Queue Worker cho domain: $domain..."
    
    # Kiểm tra tính hợp lệ cơ bản
    if [ ! -d "/var/www/$domain/current" ]; then
        error "Lỗi: Không tìm thấy thư mục 'current'. Vui lòng thực hiện Deploy trước."
        return 1
    fi
    
    local queue_name
    read -p "Nhập Tên Queue Channel (vd: mailer, ai_process, high_priority...): " queue_name
    
    if [ -z "$queue_name" ]; then 
        error "Lỗi: Tên Queue không được để trống."
        return 1
    fi
    
    local num_procs
    read -p "Nhập số lượng Luồng Worker song song muốn kích hoạt (vd: 1, 2, 4): " num_procs
    
    if [[ ! $num_procs =~ ^[0-9]+$ ]]; then 
        error "Lỗi: Số lượng luồng worker phải là chữ số."
        return 1
    fi

    # Chuẩn hóa tên chương trình và đường dẫn cấu hình
    local SAFE_DOMAIN=$(get_safe_domain "$domain")
    local supervisor_conf="/etc/supervisor/conf.d/${SAFE_DOMAIN}.conf"
    local app_user=${APP_USER:-"www-data"}

    if [ ! -f "$supervisor_conf" ]; then
        error "Lỗi: Không tìm thấy cấu hình Supervisor cho site này."
        return 1
    fi

    local new_program="${SAFE_DOMAIN}-q-${queue_name}"
    local php_bin="php${PHP_VERSION:-8.3}"

    info "Thêm Queue '${queue_name}' vào group '${SAFE_DOMAIN}'..."
    
    # 1. Thêm cấu hình chương trình Supervisor mới vào cuối file
    cat <<EOF >> "$supervisor_conf"

[program:${new_program}]
process_name=%(program_name)s_%(process_num)02d
command=${php_bin} /var/www/${domain}/current/artisan queue:work --sleep=3 --tries=3 --max-time=3600 --queue=${queue_name}
autostart=true
autorestart=true
stopasgroup=true
killasgroup=true
user=${app_user}
numprocs=${num_procs}
redirect_stderr=true
stdout_logfile=/var/www/${domain}/shared/storage/logs/worker-${queue_name}.log
stopwaitsecs=3600
EOF

    # 2. Cập nhật dòng programs= trong block [group:...]
    # Thêm tên chương trình mới vào danh sách ngăn cách bằng dấu phẩy
    sed -i "/^\[group:${SAFE_DOMAIN}\]/,/^programs=/ s/^programs=\(.*\)/programs=\1,${new_program}/" "$supervisor_conf"

    # Đọc lại Supervisor và khởi động Worker mới
    supervisorctl reread
    supervisorctl update
    supervisorctl start "${SAFE_DOMAIN}:${new_program}:*"

    info "================================================================="
    info " THÀNH CÔNG: Danh sách Queue Worker đã được cập nhật."
    info "-----------------------------------------------------------------"
    info " Queue Name : $queue_name"
    info " Threads    : $num_procs"
    info " Program    : ${new_program}"
    info "================================================================="
    return 0
}
