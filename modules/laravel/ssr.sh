#!/usr/bin/env bash
# modules/laravel/ssr.sh
# Xử lý cấu hình Inertia SSR và dịch vụ Supervisor cho từng Website riêng biệt.

#-----------------------------------------------------------------------------
# Hàm:          run_manage_ssr
# Mô tả:        Quản lý trạng thái Inertia SSR (Bật/Tắt/Restart), gọi build ngầm,
#               và tự động cấu hình Supervisor.
# Biến toàn cục: SCRIPT_DIR, PHP_VERSION, USE_SSR, SSR_PORT
# Tham số:      $1 - Tên miền chính (Domain)
#               $2 - Tên tài khoản user ứng dụng (App User)
# Trả về:       0 nếu thành công, 1 nếu thất bại
#-----------------------------------------------------------------------------
run_manage_ssr() {
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

    # Kiểm tra trạng thái hiện tại bằng cách check block cấu hình Supervisor
    if grep -q "^\[program:${safe_domain}-ssr\]" "$supervisor_conf"; then
        echo -e "\n Trạng thái SSR: ${GREEN}ĐANG BẬT${NC}"
        echo -e " 1. Khởi động lại dịch vụ (Restart)"
        echo -e " 2. Tắt dịch vụ (Disable)"
        echo -e " 0. Hủy bỏ"
        local action
        read -p " Lựa chọn thao tác (0-2): " action
        case "$action" in
            1) run_restart_ssr "$domain" ;;
            2)
                info "Tiến hành TẮT SSR..."
                
                if [ -f "$shared_env" ]; then
                    sed -i "s|^INERTIA_SSR_ENABLED=.*|INERTIA_SSR_ENABLED=false|g" "$shared_env"
                fi
                
                # Xóa cấu hình chương trình ssr ra khỏi file supervisor conf
                remove_supervisor_program "$domain" "${safe_domain}-ssr"
                
                # Đọc lại cấu hình Supervisor và dừng dịch vụ
                supervisorctl reread
                supervisorctl update
                info "Đã TẮT Inertia SSR và dọn dẹp cấu hình Supervisor."
                ;;
            0) return 0 ;;
            *) warn "Lựa chọn không hợp lệ." ;;
        esac
        return 0
    else
        echo -e "\n Trạng thái SSR: ${RED}ĐANG TẮT${NC}"
        local confirm
        read -p " Bạn có muốn BẬT Inertia SSR không? (y/n): " confirm
        if [[ "$confirm" =~ ^[Yy]$ ]]; then
            info "Tiến hành BẬT SSR..."
            
            # Tích hợp chạy lệnh build ssr ngầm trước khi khởi tạo Supervisor.
            run_npm_build_ssr "$domain" "$app_user" || {
                error "Lỗi: Build SSR thất bại. Vui lòng kiểm tra lại package.json hoặc mã nguồn."
                return 1
            }

            # Quét port SSR lớn nhất hiện tại từ các file .env của Laravel để tự động cấp port mới (tránh xung đột)
            local last_port
            last_port=$(grep -rh "^VITE_INERTIA_SSR_PORT=" /var/www/*/shared/.env 2>/dev/null | sed -E 's/^VITE_INERTIA_SSR_PORT="?([0-9]+)"?.*/\1/' | sort -n | tail -1)
            local ssr_port=$(( ${last_port:-13713} + 1 ))
            
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
                load_module "runtime/runtime.sh" || return 1
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
            add_supervisor_program "$domain" "${safe_domain}-ssr"

            # Reload lại supervisor để nhận diện dịch vụ mới và khởi chạy
            supervisorctl reread
            supervisorctl update
            supervisorctl start "${safe_domain}:${safe_domain}-ssr" || warn "Không thể tự khởi động dịch vụ SSR. Hãy kiểm tra lại."
            
            info "Đã BẬT Inertia SSR thành công trên Port $ssr_port."
        fi
        return 0
    fi


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
