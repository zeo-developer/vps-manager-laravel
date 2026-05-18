#!/usr/bin/env bash
# modules/node-version.sh
# Quản lý Node.js version riêng cho từng site bằng 'n' + wrapper bin theo domain.

NODE_SUPPORTED_VERSIONS=("18" "20" "22" "24")

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
        sed -i "s|^${key}=.*|${key}=${value}|" "$env_file"
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
    local site_env
    site_env=$(get_site_node_env_file "$domain")

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
    local site_env
    site_env=$(get_site_node_env_file "$domain")

    [ ! -f "$site_env" ] && return 1
    [ ! -f "$app_env" ] && return 0

    source "$site_env"
    if [ "${USE_SSR:-false}" = "true" ]; then
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

normalize_node_version() {
    local version="$1"
    version="${version#v}"
    version="${version%%.*}"
    echo "$version"
}

is_supported_node_version() {
    local version="$1"
    local item
    for item in "${NODE_SUPPORTED_VERSIONS[@]}"; do
        [ "$item" = "$version" ] && return 0
    done
    return 1
}

get_site_node_bin_dir() {
    local domain="$1"
    echo "/var/www/${domain}/node-bin"
}

get_site_node_env_file() {
    local domain="$1"
    echo "$SCRIPT_DIR/sites/.env.${domain}"
}

resolve_n_node_version_dir() {
    local target_ver
    target_ver=$(normalize_node_version "$1")
    local versions_root="/usr/local/n/versions/node"
    local exact_dir="${versions_root}/${target_ver}"

    if [ -x "${exact_dir}/bin/node" ]; then
        echo "$exact_dir"
        return 0
    fi

    local matched_dir
    matched_dir=$(find "$versions_root" -maxdepth 1 -mindepth 1 -type d -name "${target_ver}.*" 2>/dev/null | sort -V | tail -n 1)
    if [ -n "$matched_dir" ] && [ -x "${matched_dir}/bin/node" ]; then
        echo "$matched_dir"
        return 0
    fi

    return 1
}

ensure_node_manager() {
    if ! command -v node >/dev/null 2>&1; then
        local bootstrap_ver="${NODE_VERSION:-20}"
        info "Node.js chưa có. Bootstrap Node.js ${bootstrap_ver}.x bằng NodeSource..."
        curl -fsSL "https://deb.nodesource.com/setup_${bootstrap_ver}.x" | bash -
        apt-get install -y nodejs
    fi

    if ! command -v npm >/dev/null 2>&1; then
        error "Không tìm thấy npm. Vui lòng kiểm tra cài đặt Node.js."
        return 1
    fi

    if ! command -v n >/dev/null 2>&1; then
        info "Cài đặt Node version manager: n"
        npm install -g n
    fi
}

install_node_runtime() {
    local target_ver
    target_ver=$(normalize_node_version "$1")

    if ! is_supported_node_version "$target_ver"; then
        error "Node.js $target_ver không được hỗ trợ. Hỗ trợ: ${NODE_SUPPORTED_VERSIONS[*]}"
        return 1
    fi

    ensure_node_manager || return 1
    info "Đảm bảo Node.js ${target_ver}.x đã được cài trong n..."
    n "$target_ver"
    hash -r 2>/dev/null || true

    if ! resolve_n_node_version_dir "$target_ver" >/dev/null; then
        error "Không tìm thấy Node.js ${target_ver}.x trong /usr/local/n/versions/node sau khi cài."
        return 1
    fi
}

create_site_node_wrappers() {
    local domain="$1"
    local target_ver
    target_ver=$(normalize_node_version "$2")
    local bin_dir
    bin_dir=$(get_site_node_bin_dir "$domain")
    local node_dir
    node_dir=$(resolve_n_node_version_dir "$target_ver") || { error "Không tìm thấy Node binary cho Node.js ${target_ver}.x trong /usr/local/n/versions/node"; return 1; }
    local node_path="${node_dir}/bin/node"
    local npm_path="${node_dir}/bin/npm"
    local npx_path="${node_dir}/bin/npx"

    if [ ! -x "$node_path" ]; then
        error "Không tìm thấy Node binary: $node_path"
        return 1
    fi

    mkdir -p "$bin_dir"
    cat > "${bin_dir}/node" <<EOF
#!/usr/bin/env bash
exec "${node_path}" "\$@"
EOF
    cat > "${bin_dir}/npm" <<EOF
#!/usr/bin/env bash
export PATH="${node_dir}/bin:\$PATH"
exec "${npm_path}" "\$@"
EOF
    if [ -x "$npx_path" ]; then
        cat > "${bin_dir}/npx" <<EOF
#!/usr/bin/env bash
export PATH="${node_dir}/bin:\$PATH"
exec "${npx_path}" "\$@"
EOF
    fi

    chmod +x "${bin_dir}/node" "${bin_dir}/npm" 2>/dev/null || true
    [ -f "${bin_dir}/npx" ] && chmod +x "${bin_dir}/npx"
    chown -R "${APP_USER:-www-data}":"${APP_USER:-www-data}" "$bin_dir" 2>/dev/null || true
}

set_site_node_version() {
    local domain="$1"
    local target_ver
    target_ver=$(normalize_node_version "$2")
    local site_env
    site_env=$(get_site_node_env_file "$domain")

    [ ! -f "$site_env" ] && { error "Không tìm thấy cấu hình site: $site_env"; return 1; }
    install_node_runtime "$target_ver" || return 1
    create_site_node_wrappers "$domain" "$target_ver" || return 1

    if grep -q "^NODE_VERSION=" "$site_env"; then
        sed -i "s/^NODE_VERSION=.*/NODE_VERSION=\"${target_ver}\"/" "$site_env"
    else
        echo "NODE_VERSION=\"${target_ver}\"" >> "$site_env"
    fi
    harden_permissions "$site_env"

    info "Site [${domain}] dùng Node.js ${target_ver}.x"
    info "Wrapper: $(get_site_node_bin_dir "$domain")"
    patch_site_ssr_supervisor_env "$domain"
}

patch_site_ssr_supervisor_env() {
    local domain="$1"
    local safe_domain
    safe_domain=$(get_safe_domain "$domain")
    local supervisor_conf="/etc/supervisor/conf.d/${safe_domain}.conf"
    local bin_dir
    bin_dir=$(get_site_node_bin_dir "$domain")
    local env_line="environment=PATH=\"${bin_dir}:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin\""

    [ ! -f "$supervisor_conf" ] && return 0
    grep -q "^\[program:${safe_domain}-ssr\]" "$supervisor_conf" || return 0

    if sed -n "/^\[program:${safe_domain}-ssr\]/,/^\[/p" "$supervisor_conf" | grep -q "^environment="; then
        sed -i "/^\[program:${safe_domain}-ssr\]/,/^\[/ s|^environment=.*|${env_line}|" "$supervisor_conf"
    else
        sed -i "/^\[program:${safe_domain}-ssr\]/,/^\[/ s|^stopwaitsecs=.*|&\n${env_line}|" "$supervisor_conf"
    fi

    supervisorctl reread >/dev/null 2>&1 || true
    supervisorctl update >/dev/null 2>&1 || true
    supervisorctl restart "${safe_domain}:${safe_domain}-ssr" >/dev/null 2>&1 || true
    info "Đã cập nhật Supervisor SSR PATH cho ${domain}"
}

ensure_site_node_version() {
    local domain="$1"
    local target_ver="${2:-${NODE_VERSION:-20}}"
    target_ver=$(normalize_node_version "$target_ver")
    set_site_node_version "$domain" "$target_ver"
}

run_site_node_cmd() {
    local domain="$1"
    shift
    local bin_dir
    bin_dir=$(get_site_node_bin_dir "$domain")
    PATH="${bin_dir}:$PATH" "$@"
}

show_site_node_status() {
    local domain="$1"
    local site_env
    site_env=$(get_site_node_env_file "$domain")
    local configured="20"
    [ -f "$site_env" ] && configured=$(grep -oP '(?<=^NODE_VERSION=")[^"]+' "$site_env" 2>/dev/null || echo "20")
    local bin_dir
    bin_dir=$(get_site_node_bin_dir "$domain")

    echo -e "${CYAN}------------------------------------------${NC}"
    echo -e "${YELLOW} NODE.JS SITE STATUS: ${domain}${NC}"
    echo -e "${CYAN}------------------------------------------${NC}"
    echo -e " Config NODE_VERSION : ${GREEN}${configured}${NC}"
    echo -e " Wrapper Bin         : ${bin_dir}"
    if [ -x "${bin_dir}/node" ]; then
        echo -e " Site Node.js        : ${GREEN}$(${bin_dir}/node -v)${NC}"
        echo -e " Site NPM            : ${GREEN}$(${bin_dir}/npm -v 2>/dev/null || echo 'n/a')${NC}"
    else
        echo -e " Site Node.js        : ${YELLOW}Chưa tạo wrapper${NC}"
    fi
    command -v node >/dev/null 2>&1 && echo -e " System Node.js      : $(node -v) ($(command -v node))"
    command -v n >/dev/null 2>&1 && { echo -e " Installed by n      :"; n ls 2>/dev/null || true; }
    echo -e "${CYAN}------------------------------------------${NC}"
}

select_node_version_menu() {
    local current_major="${1:-}"
    echo -e "${CYAN}Chọn phiên bản Node.js:${NC}" >&2
    local i=1
    local version label
    for version in "${NODE_SUPPORTED_VERSIONS[@]}"; do
        label="Node.js ${version}.x"
        [ "$current_major" = "$version" ] && label="${label} [Đang dùng]"
        echo -e "  ${GREEN}${i}.${NC} ${label}" >&2
        i=$((i + 1))
    done
    echo -e "  ${RED}0.${NC} Quay lại" >&2

    local choice
    read -r -p "Lựa chọn (0-$((i-1))): " choice
    [ "$choice" = "0" ] && return 1
    if [[ "$choice" =~ ^[0-9]+$ ]] && [ "$choice" -ge 1 ] && [ "$choice" -lt "$i" ]; then
        echo "${NODE_SUPPORTED_VERSIONS[$((choice-1))]}"
        return 0
    fi

    error "Lựa chọn không hợp lệ."
    return 1
}

remove_node_version() {
    local target_ver
    target_ver=$(normalize_node_version "$1")

    if ! command -v n >/dev/null 2>&1; then
        error "Chưa cài 'n' manager. Không có phiên bản để gỡ."
        return 1
    fi

    warn "Sắp gỡ Node.js ${target_ver}.x khỏi n manager. Không gỡ nếu site còn dùng."
    read -p "Nhập YES để xác nhận: " confirm
    [ "$confirm" != "YES" ] && { warn "Đã hủy."; return 0; }

    n rm "$target_ver" || true
    hash -r 2>/dev/null || true
    info "Đã xử lý gỡ Node.js ${target_ver}.x"
}

run_node_manager() {
    local domain="$1"
    if [ -z "$domain" ]; then
        error "Cần cung cấp domain: ./vps.sh manage-node demo.com"
        return 1
    fi

    local site_env
    site_env=$(get_site_node_env_file "$domain")
    [ ! -f "$site_env" ] && { error "Site '$domain' không tồn tại."; return 1; }

    while true; do
        local current_ver
        current_ver=$(grep -oP '(?<=^NODE_VERSION=")[^"]+' "$site_env" 2>/dev/null || echo "20")
        echo -e "${CYAN}==========================================${NC}"
        echo -e "${CYAN}    NODE.JS VERSION MANAGER: ${domain}    ${NC}"
        echo -e "${CYAN}==========================================${NC}"
        echo -e " ${GREEN}1.${NC} Xem trạng thái Node.js site"
        echo -e " ${GREEN}2.${NC} Cài/Chuyển Node.js cho site"
        echo -e " ${YELLOW}3.${NC} Gỡ phiên bản Node.js khỏi n manager"
        echo -e " ${RED}0.${NC} Quay lại"
        echo -e "------------------------------------------"
        read -p "Nhập lựa chọn (0-3): " choice

        case "$choice" in
            1) show_site_node_status "$domain" ;;
            2)
                local target_ver
                target_ver=$(select_node_version_menu "$current_ver") || continue
                set_site_node_version "$domain" "$target_ver"
                ;;
            3)
                local target_remove
                target_remove=$(select_node_version_menu) || continue
                remove_node_version "$target_remove"
                ;;
            0) return 2 ;;
            *) warn "Lựa chọn không hợp lệ." ;;
        esac
        echo -e ""
        read -p "Nhấn [Enter] để tiếp tục..."
    done
}
