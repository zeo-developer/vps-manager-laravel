#!/usr/bin/env bash
# modules/queue.sh
# Xử lý thêm các Supervisor Config cho 1 dự án riêng biệt (Custom Queue).

run_add_queue() {
    local domain="$1"
    
    info "Cấu hình thêm bộ Queue Worker đệm riêng cho website: $domain"
    
    # Validation cơ bản
    if [ ! -d "/var/www/$domain/current" ]; then
        error "Không tìm thấy đường dẫn hệ thống của Website này. Hãy chắc chắn bạn đã Deploy ít nhất 1 lần."
    fi
    
    read -p "Nhập Tên Queue Channel (vd: mailer, ai_process, high_priority...): " queue_name
    
    if [ -z "$queue_name" ]; then error "Tên Queue không hợp lệ, thao tác bị huỷ!"; fi
    
    read -p "Nhập số lượng Luồng Worker song song muốn kích hoạt (vd: 1, 2, 4): " num_procs
    
    if [[ ! $num_procs =~ ^[0-9]+$ ]]; then error "Số luồng phải là chữ số."; fi

    # Tên của file và program
    local program_name="worker-${domain}-${queue_name}"
    local supervisor_conf="/etc/supervisor/conf.d/${program_name}.conf"
    local app_user=${APP_USER:-"www-data"}

    info "Đang tiến hành sinh file luồng chạy ẩn Supervisor Worker tại $supervisor_conf"
    
    # Sinh file ghi đè tham số name và queue channel
    # Kế thừa file conf gốc và thay thế lệnh command += --queue=
    
    cat "$SCRIPT_DIR/configs/supervisor-queue.conf" \
        | sed "s/{{APP_DOMAIN}}/$domain/g" \
        | sed "s/{{APP_USER}}/$app_user/g" \
        | sed "s/{{PHP_VERSION}}/$PHP_VERSION/g" \
        | sed "s/laravel-worker/${program_name}/g" \
        | sed "s/numprocs=2/numprocs=${num_procs}/g" \
        > "$supervisor_conf"

    # Append thêm cờ queue nếu chưa có
    # Cách tốt nhất là chèn "--queue=$queue_name" vào ngay cuối dòng "command=" trong file
    sed -i "s|queue:work .*|& --queue=${queue_name}|g" "$supervisor_conf"

    # Nạp và khởi động Worker
    supervisorctl reread
    supervisorctl update
    supervisorctl start "${program_name}:*"

    info "================================================================="
    info "🔥🔥 ĐÃ TẠO LUỒNG MULTI-WORKER [ $queue_name ] THÀNH CÔNG CHO [ $domain ]."
    info "Đang chạy với $num_procs Threads ngầm song song."
    info "================================================================="
}
