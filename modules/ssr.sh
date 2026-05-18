#!/usr/bin/env bash
# modules/ssr.sh
# Quản lý cấu hình Inertia SSR cho từng site:
#   - Port allocation (SSR_PORT trong sites/.env.<domain>)
#   - Sync sang Laravel shared/.env thành INERTIA_SSR_* / VITE_INERTIA_SSR_PORT
#   - Patch Supervisor SSR để dùng đúng node-bin wrapper
#
# Source of truth:  sites/.env.<domain>  →  SSR_PORT
# Runtime env:      /var/www/<domain>/shared/.env  →  INERTIA_SSR_ENABLED, VITE_INERTIA_SSR_PORT, INERTIA_SSR_URL
# Supervisor:       chỉ cần PATH=node-bin, không cần port

# ---------------------------------------------------------------------------
# [Helper] upsert_env_value <env_file> <KEY> <value>
# Update key nếu đã tồn tại trong file, append nếu chưa có.
# Dùng chung cho cả sites/.env.<domain> và Laravel shared/.env
# ---------------------------------------------------------------------------
upsert_env_value() {
    local env_file="$1"
    local key="$2"
    local value="$3"

    [ ! -f "$env_file" ] && touch "$env_file"
    if grep -q "^${key}=" "$env_file"; then
        # Dùng awk thay sed để an toàn với value chứa ký tự đặc biệt (/, |, &, ...)
        awk -v key="${key}" -v val="${value}" \
            'BEGIN{FS="="} /^[[:space:]]*#/{print;next} $1==key{print key"="val;next} {print}' \
            "$env_file" > "${env_file}.tmp" && mv "${env_file}.tmp" "$env_file"
    else
        echo "${key}=${value}" >> "$env_file"
    fi
}

# ---------------------------------------------------------------------------
# [Helper] get_next_ssr_port
# Scan tất cả SSR_PORT trong sites/, lấy port lớn nhất + 1.
# Base port mặc định là 13714 nếu chưa có site nào dùng SSR.
# Mỗi site SSR phải có port riêng để tránh conflict khi chạy nhiều site.
# ---------------------------------------------------------------------------
get_next_ssr_port() {
    local base_port=13714
    local last_port

    last_port=$(grep -rh '^SSR_PORT=' "$SCRIPT_DIR/sites/" 2>/dev/null \
        | sed -E 's/^SSR_PORT="?([0-9]+)"?.*/\1/' \
        | sort -n \
        | tail -1)

    if [ -n "$last_port" ]; then
        echo $((last_port + 1))
    else
        echo "$base_port"
    fi
}

# ---------------------------------------------------------------------------
# [Helper] ensure_site_ssr_port <domain>
# Kiểm tra site có USE_SSR=true không.
# Nếu SSR_PORT chưa được set trong sites/.env.<domain> thì tự động cấp port mới.
# Gọi trước khi sync sang Laravel .env để đảm bảo port hợp lệ.
# ---------------------------------------------------------------------------
ensure_site_ssr_port() {
    local domain="$1"
    local site_env="$SCRIPT_DIR/sites/.env.${domain}"

    [ ! -f "$site_env" ] && return 1
    source "$site_env"

    [ "${USE_SSR:-false}" != "true" ] && return 0
    if [ -z "${SSR_PORT:-}" ]; then
        local port
        port=$(get_next_ssr_port)
        upsert_env_value "$site_env" "SSR_PORT" "\"${port}\""
        SSR_PORT="$port"
        harden_permissions "$site_env" 2>/dev/null || true
        info "Đã bổ sung SSR_PORT=${port} cho ${domain}"
    fi
}

# ---------------------------------------------------------------------------
# [Helper] sync_inertia_ssr_to_laravel_env <domain>
# Đọc SSR_PORT từ sites/.env.<domain> (source of truth của VPS Manager).
# Ghi sang /var/www/<domain>/shared/.env thành biến Inertia chuẩn:
#   INERTIA_SSR_ENABLED=true
#   VITE_INERTIA_SSR_PORT=<port>  (prefix VITE_ để Vite/SSR đọc qua import.meta.env)
#   INERTIA_SSR_URL=http://127.0.0.1:<port>
# Phải gọi TRƯỚC khi chạy npm run build để build biết đúng port.
# Laravel app đọc từ shared/.env, không đọc sites/.env.<domain> trực tiếp.
# ---------------------------------------------------------------------------
sync_inertia_ssr_to_laravel_env() {
    local domain="$1"
    local app_env="/var/www/${domain}/shared/.env"
    local site_env="$SCRIPT_DIR/sites/.env.${domain}"

    [ ! -f "$site_env" ] && return 1
    [ ! -f "$app_env" ] && return 0

    source "$site_env"
    if [ "${USE_SSR:-false}" = "true" ]; then
        # ensure_site_ssr_port sẽ source lại $site_env nếu cần cấp SSR_PORT mới.
        # Sau đó source lại để đảm bảo biến SSR_PORT được cập nhật trong shell hiện tại.
        ensure_site_ssr_port "$domain" || return 1
        source "$site_env"
        local port="${SSR_PORT:-13714}"
        upsert_env_value "$app_env" "INERTIA_SSR_ENABLED" "true"
        upsert_env_value "$app_env" "VITE_INERTIA_SSR_PORT" "$port"
        upsert_env_value "$app_env" "INERTIA_SSR_URL" "http://127.0.0.1:${port}"
        info "Đã sync Inertia SSR port ${port} vào Laravel .env"
    else
        upsert_env_value "$app_env" "INERTIA_SSR_ENABLED" "false"
    fi
    chown "${APP_USER:-www-data}":"${APP_USER:-www-data}" "$app_env" 2>/dev/null || true
}

# ---------------------------------------------------------------------------
# [Helper] patch_site_ssr_supervisor_env <domain>
# Cập nhật environment trong Supervisor conf của SSR process.
# Chỉ patch PATH để process dùng đúng node-bin wrapper của site.
# Không cần truyền port vào Supervisor — Laravel app đọc từ shared/.env.
# Hàm NÀY CHỈ PATCH FILE CONF, không tự restart supervisor.
# Sau khi gọi hàm này, deploy sẽ tự làm supervisorctl reread/update/restart toàn group.
# ---------------------------------------------------------------------------
patch_site_ssr_supervisor_env() {
    local domain="$1"
    local safe_domain
    safe_domain=$(get_safe_domain "$domain")
    local supervisor_conf="/etc/supervisor/conf.d/${safe_domain}.conf"
    local bin_dir="/var/www/${domain}/node-bin"
    local env_line="environment=PATH=\"${bin_dir}:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin\""

    [ ! -f "$supervisor_conf" ] && return 0
    grep -q "^\[program:${safe_domain}-ssr\]" "$supervisor_conf" || return 0

    if sed -n "/^\[program:${safe_domain}-ssr\]/,/^\[/p" "$supervisor_conf" | grep -q "^environment="; then
        sed -i "/^\[program:${safe_domain}-ssr\]/,/^\[/ s|^environment=.*|${env_line}|" "$supervisor_conf"
    else
        sed -i "/^\[program:${safe_domain}-ssr\]/,/^\[/ s|^stopwaitsecs=.*|&\n${env_line}|" "$supervisor_conf"
    fi

    info "Đã patch Supervisor SSR conf cho ${domain} (chưa restart)"
}
