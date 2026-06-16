#!/usr/bin/env bash
# modules/laravel/ssr.sh
# Xử lý cấu hình Inertia SSR và dịch vụ Supervisor cho từng Website riêng biệt.

#-----------------------------------------------------------------------------
# Hàm:          run_toggle_ssr
# Mô tả:        Bật/Tắt trạng thái Inertia SSR, chỉnh sửa biến môi trường trong env,
#               và tự động quản lý cấu hình Supervisor.
# Biến toàn cục: SCRIPT_DIR, PHP_VERSION, USE_SSR, SSR_PORT
# Tham số:      $1 - Tên miền chính (Domain)
#               $2 - Tên tài khoản user ứng dụng (App User)
# Trả về:       0 nếu thành công, 1 nếu thất bại
#-----------------------------------------------------------------------------
run_toggle_ssr() {
    local domain="$1"
    local app_user="$2"
    local safe_domain=$(get_safe_domain "$domain")
    local supervisor_conf="/etc/supervisor/conf.d/${safe_domain}.conf"
    local site_env="$SCRIPT_DIR/sites/.env.$domain"
    local shared_env="/var/www/$domain/shared/.env"

    # Đảm bảo file cấu hình Supervisor của site đã được khởi tạo
    if [ ! -f "$supervisor_conf" ]; then
        error "Lỗi: Không tìm thấy file cấu hình Supervisor tại $supervisor_conf."
        return 1
    fi

    # Nạp cấu hình hiện tại của Website
    local USE_SSR="false"
    local SSR_PORT=""
    [ -f "$site_env" ] && source "$site_env"

    if [ "$USE_SSR" = "true" ]; then
        info "SSR hiện tại: ĐANG BẬT. Tiến hành TẮT..."
        update_env_var "USE_SSR" "false" "$site_env"
        
        if [ -f "$shared_env" ]; then
            sed -i "s|^INERTIA_SSR_ENABLED=.*|INERTIA_SSR_ENABLED=false|g" "$shared_env"
        fi
        
        # Xóa cấu hình chương trình ssr ra khỏi file supervisor conf
        # Xóa từ dòng [program:xxx-ssr] đến dòng trống gần nhất
        sed -i '/^\[program:'"${safe_domain}"'-ssr\]/,/^\s*$/d' "$supervisor_conf"
        sed -i 's/,'"${safe_domain}"'-ssr//g; s/'"${safe_domain}"'-ssr,//g' "$supervisor_conf"
        
        # Đọc lại cấu hình Supervisor và dừng dịch vụ
        supervisorctl reread
        supervisorctl update
        info "Đã TẮT Inertia SSR và dọn dẹp cấu hình Supervisor."
        return 0
    else
        info "SSR hiện tại: ĐANG TẮT. Tiến hành BẬT..."
        # Quét port SSR lớn nhất hiện tại để tự động cấp port mới (tránh xung đột)
        local last_port
        last_port=$(grep -rh "^SSR_PORT=" "$SCRIPT_DIR/sites/" 2>/dev/null | sed -E 's/^SSR_PORT="?([0-9]+)"?.*/\\1/' | sort -n | tail -1)
        local ssr_port=$(( ${last_port:-13713} + 1 ))
        
        update_env_var "USE_SSR" "true" "$site_env"
        update_env_var "SSR_PORT" "$ssr_port" "$site_env"
        
        if [ -f "$shared_env" ]; then
            # Đảm bảo các key cấu hình SSR tồn tại trong file .env của dự án
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

        # Ghi thêm block chương trình SSR vào file cấu hình Supervisor nếu chưa có
        if ! grep -q "^\[program:${safe_domain}-ssr\]" "$supervisor_conf"; then
            load_module "runtime.sh" || return 1
            local node_dir
            node_dir=$(resolve_n_node_version_dir "${NODE_VERSION:-20}")
            cat <<EOF >> "$supervisor_conf"

[program:${safe_domain}-ssr]
process_name=%(program_name)s
command=php${PHP_VERSION:-8.3} /var/www/${domain}/current/artisan inertia:start-ssr
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
        fi

        # Thêm chương trình vào nhóm group của Supervisor
        if ! sed -n "/^\[group:${safe_domain}\]/,/^programs=/p" "$supervisor_conf" | grep -q "${safe_domain}-ssr"; then
            sed -i "/^\[group:${safe_domain}\]/,/^programs=/ s/^programs=\(.*\)/programs=\1,${safe_domain}-ssr/" "$supervisor_conf"
        fi

        # Reload lại supervisor để nhận diện dịch vụ mới và khởi chạy
        supervisorctl reread
        supervisorctl update
        supervisorctl start "${safe_domain}:${safe_domain}-ssr" || warn "Không thể tự khởi động dịch vụ SSR. Hãy kiểm tra lại."
        
        info "Đã BẬT Inertia SSR thành công trên Port $ssr_port."
        return 0
    fi
}

#-----------------------------------------------------------------------------
# Hàm:          run_restart_ssr
# Description:  Khởi động lại tiến trình SSR trong Supervisor cho Website.
# Biến toàn cục: Không có
# Tham số:      $1 - Tên miền (Domain)
# Trả về:       0 nếu thành công, 1 nếu thất bại
#-----------------------------------------------------------------------------
run_restart_ssr() {
    local domain="$1"
    local safe_domain=$(get_safe_domain "$domain")

    info "Đang khởi động lại dịch vụ Supervisor SSR cho $domain..."
    if supervisorctl restart "${safe_domain}:${safe_domain}-ssr"; then
        info "Khởi động lại dịch vụ SSR thành công."
        return 0
    else
        error "Lỗi: Không thể khởi động lại dịch vụ SSR. Có thể SSR chưa được bật."
        return 1
    fi
}
