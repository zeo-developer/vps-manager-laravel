#!/usr/bin/env bash
# modules/deploy/helpers/ssr.sh
# Xử lý tự động cấu hình Inertia SSR cho quá trình Deploy.

#-----------------------------------------------------------------------------
# Hàm:          setup_default_ssr_worker
# Mô tả:        Cấu hình tự động Inertia SSR Worker cho Supervisor nếu dự án có hỗ trợ.
#-----------------------------------------------------------------------------
setup_default_ssr_worker() {
    local domain="$1"
    local app_user="$2"
    local php_version="${3:-8.3}"
    local node_version="${4:-20}"
    
    local safe_domain=$(get_safe_domain "$domain")
    local supervisor_conf="/etc/supervisor/conf.d/${safe_domain}.conf"
    local shared_env="/var/www/$domain/shared/.env"

    if [ ! -f "$supervisor_conf" ]; then
        return 1
    fi

    # Nếu cấu hình đã có thì không cần tạo lại
    if grep -q "^\[program:${safe_domain}-ssr\]" "$supervisor_conf"; then
        return 0
    fi

    info "Cấu hình tự động Inertia SSR Worker cho $domain..."

    # Cấp phát cổng ngẫu nhiên / tăng dần
    local last_port
    last_port=$(grep -rh "^VITE_INERTIA_SSR_PORT=" /var/www/*/shared/.env 2>/dev/null | sed -E 's/^VITE_INERTIA_SSR_PORT="?([0-9]+)"?.*/\1/' | sort -n | tail -1)
    local ssr_port=$(( ${last_port:-13713} + 1 ))
    
    if [ -f "$shared_env" ]; then
        if grep -q "^INERTIA_SSR_ENABLED=" "$shared_env"; then
            sed -i "s|^INERTIA_SSR_ENABLED=.*|INERTIA_SSR_ENABLED=true|g" "$shared_env"
        else
            echo "INERTIA_SSR_ENABLED=true" >> "$shared_env"
        fi
        
        if grep -q "^VITE_INERTIA_SSR_PORT=" "$shared_env"; then
            sed -i "s|^VITE_INERTIA_SSR_PORT=.*|VITE_INERTIA_SSR_PORT=${ssr_port}|g" "$shared_env"
        else
            echo "VITE_INERTIA_SSR_PORT=${ssr_port}" >> "$shared_env"
        fi

        if grep -q "^INERTIA_SSR_URL=" "$shared_env"; then
            sed -i "s|^INERTIA_SSR_URL=.*|INERTIA_SSR_URL=http://127.0.0.1:${ssr_port}|g" "$shared_env"
        else
            echo "INERTIA_SSR_URL=http://127.0.0.1:${ssr_port}" >> "$shared_env"
        fi
    fi

    local node_dir
    node_dir=$(resolve_n_node_version_dir "$node_version")

    cat <<EOF >> "$supervisor_conf"

[program:${safe_domain}-ssr]
process_name=%(program_name)s
command=php${php_version} /var/www/${domain}/current/artisan inertia:start-ssr
directory=/var/www/${domain}/current
autostart=true
autorestart=true
stopasgroup=true
killasgroup=true
user=${app_user}
redirect_stderr=true
stdout_logfile=/var/www/${domain}/shared/storage/logs/ssr.log
stopwaitsecs=10
environment=PATH="${node_dir}/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"
EOF

    add_supervisor_program "$domain" "${safe_domain}-ssr"
    info "Đã thiết lập mặc định SSR Worker trên port $ssr_port."
    return 0
}
