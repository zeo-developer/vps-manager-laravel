#!/usr/bin/env bash
# modules/laravel/queue.sh
# Xử lý thêm các Supervisor Config cho 1 dự án riêng biệt (Custom Queue).



#-----------------------------------------------------------------------------
# Hàm:          setup_default_queue_worker
# Mô tả:        Hàm tiện ích dùng chung để cấu hình Default Queue Worker (tránh lặp code).
#-----------------------------------------------------------------------------
setup_default_queue_worker() {
    local domain="$1"
    local app_user="$2"
    local php_version="${3:-8.3}"
    local safe_domain=$(get_safe_domain "$domain")
    local supervisor_conf="/etc/supervisor/conf.d/${safe_domain}.conf"
    local php_bin="php${php_version}"

    if [ ! -f "$supervisor_conf" ]; then
        return 1
    fi

    if ! grep -q "^\[program:${safe_domain}-worker\]" "$supervisor_conf"; then
        cat <<EOF >> "$supervisor_conf"

[program:${safe_domain}-worker]
process_name=%(program_name)s_%(process_num)02d
command=${php_bin} /var/www/${domain}/current/artisan queue:work --sleep=3 --tries=3 --max-time=3600
directory=/var/www/${domain}/current
autostart=true
autorestart=true
stopasgroup=true
killasgroup=true
user=${app_user}
numprocs=2
redirect_stderr=true
stdout_logfile=/var/www/${domain}/shared/storage/logs/worker.log
stopwaitsecs=3600
EOF
        add_supervisor_program "$domain" "${safe_domain}-worker"
        return 0
    fi
    return 1
}

