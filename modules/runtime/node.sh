#!/usr/bin/env bash
# modules/runtime/node.sh
# Quản lý phiên bản Node.js toàn cục thông qua 'n' và tích hợp vào từng Website.

NODE_SUPPORTED_VERSIONS=("18" "20" "22" "24")

#-----------------------------------------------------------------------------
# Hàm:          normalize_node_version
# Mô tả:        Chuẩn hóa chuỗi phiên bản Node.js (ví dụ: v20.10.0 -> 20).
#-----------------------------------------------------------------------------
normalize_node_version() {
    local version="$1"
    version="${version#v}"
    version="${version%%.*}"
    echo "$version"
}

#-----------------------------------------------------------------------------
# Hàm:          is_supported_node_version
# Mô tả:        Kiểm tra xem phiên bản Node.js có được hệ thống hỗ trợ không.
#-----------------------------------------------------------------------------
is_supported_node_version() {
    local version="$1"
    local item
    for item in "${NODE_SUPPORTED_VERSIONS[@]}"; do
        [ "$item" = "$version" ] && return 0
    done
    return 1
}

#-----------------------------------------------------------------------------
# Hàm:          get_site_node_env_file
# Mô tả:        Lấy đường dẫn tệp cấu hình .env riêng của website.
#-----------------------------------------------------------------------------
get_site_node_env_file() {
    local domain="$1"
    echo "$SCRIPT_DIR/sites/.env.${domain}"
}

#-----------------------------------------------------------------------------
# Hàm:          resolve_n_node_version_dir
# Mô tả:        Tìm thư mục cài đặt Node.js thực tế của trình quản lý phiên bản 'n'.
#-----------------------------------------------------------------------------
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

#-----------------------------------------------------------------------------
# Hàm:          ensure_node_manager
# Mô tả:        Đảm bảo hệ thống đã cài đặt sẵn Node.js cơ sở và trình quản lý 'n'.
#-----------------------------------------------------------------------------
ensure_node_manager() {
    if ! command -v node >/dev/null 2>&1; then
        local bootstrap_ver="${NODE_VERSION:-20}"
        info "Node.js chưa có trên máy chủ. Đang cài đặt Node.js ${bootstrap_ver}.x bằng NodeSource..."
        curl -fsSL "https://deb.nodesource.com/setup_${bootstrap_ver}.x" | bash -
        apt-get install -y nodejs
    fi

    if ! command -v npm >/dev/null 2>&1; then
        error "Không tìm thấy npm. Vui lòng kiểm tra lại cấu hình cài đặt Node.js của hệ thống."
        return 1
    fi

    if ! command -v n >/dev/null 2>&1; then
        info "Đang cài đặt trình quản lý phiên bản Node.js: n..."
        npm install -g n
    fi
}

#-----------------------------------------------------------------------------
# Hàm:          create_global_node_wrappers
# Mô tả:        Tạo các wrapper/symlink toàn cục node${version}, npm${version}, npx${version}
#               trong thư mục /usr/local/bin/.
#-----------------------------------------------------------------------------
create_global_node_wrappers() {
    local target_ver
    target_ver=$(normalize_node_version "$1")
    local node_dir
    node_dir=$(resolve_n_node_version_dir "$target_ver") || { error "Không tìm thấy thư mục cài đặt Node cho Node.js ${target_ver}.x"; return 1; }
    
    local node_path="${node_dir}/bin/node"
    local npm_path="${node_dir}/bin/npm"
    local npx_path="${node_dir}/bin/npx"

    info "Đang tạo liên kết thực thi toàn cục node${target_ver}, npm${target_ver}, npx${target_ver}..."

    # Tạo symlink node toàn cục
    ln -nfs "$node_path" "/usr/local/bin/node${target_ver}"

    # Tạo wrapper npm toàn cục đảm bảo chạy đúng node tương ứng
    cat > "/usr/local/bin/npm${target_ver}" <<EOF
#!/usr/bin/env bash
export PATH="${node_dir}/bin:\$PATH"
exec "${npm_path}" "\$@"
EOF
    chmod +x "/usr/local/bin/npm${target_ver}"

    # Tạo wrapper npx toàn cục
    if [ -x "$npx_path" ]; then
        cat > "/usr/local/bin/npx${target_ver}" <<EOF
#!/usr/bin/env bash
export PATH="${node_dir}/bin:\$PATH"
exec "${npx_path}" "\$@"
EOF
        chmod +x "/usr/local/bin/npx${target_ver}"
    fi
}

#-----------------------------------------------------------------------------
# Hàm:          install_node_runtime
# Mô tả:        Tải và cài đặt một phiên bản Node.js runtime cụ thể thông qua 'n'
#               và tạo các wrapper toàn cục.
#-----------------------------------------------------------------------------
install_node_runtime() {
    local target_ver
    target_ver=$(normalize_node_version "$1")

    if ! is_supported_node_version "$target_ver"; then
        error "Phiên bản Node.js $target_ver không được hỗ trợ. Các bản hỗ trợ: ${NODE_SUPPORTED_VERSIONS[*]}"
        return 1
    fi

    ensure_node_manager || return 1
    info "Đảm bảo phiên bản Node.js ${target_ver}.x đã được tải trong trình quản lý 'n'..."
    n "$target_ver"
    hash -r 2>/dev/null || true

    create_global_node_wrappers "$target_ver" || return 1
}

#-----------------------------------------------------------------------------
# Hàm:          setup_site_node_wrappers
# Mô tả:        Cài đặt phiên bản Node và lưu thông tin vào file cấu hình site.
#               (Không tạo wrapper cục bộ, không khởi động lại Supervisor SSR).
#-----------------------------------------------------------------------------
setup_site_node_wrappers() {
    local domain="$1"
    local target_ver
    target_ver=$(normalize_node_version "$2")
    local site_env
    site_env=$(get_site_node_env_file "$domain")

    [ ! -f "$site_env" ] && { error "Không tìm thấy cấu hình site: $site_env"; return 1; }
    install_node_runtime "$target_ver" || return 1

    if grep -q "^NODE_VERSION=" "$site_env"; then
        sed -i "s/^NODE_VERSION=.*/NODE_VERSION=\"${target_ver}\"/" "$site_env"
    else
        echo "NODE_VERSION=\"${target_ver}\"" >> "$site_env"
    fi
    harden_permissions "$site_env"
    info "Website [${domain}] đã được liên kết với Node.js ${target_ver}.x toàn cục thành công."
}

#-----------------------------------------------------------------------------
# Hàm:          set_site_node_version
# Mô tả:        Cấu hình phiên bản Node cho site, cập nhật cấu hình Supervisor SSR
#               và khởi động lại dịch vụ SSR.
#-----------------------------------------------------------------------------
set_site_node_version() {
    local domain="$1"
    local target_ver
    target_ver=$(normalize_node_version "$2")

    setup_site_node_wrappers "$domain" "$target_ver" || return 1

    # Cập nhật đường dẫn node thực tế cho Supervisor quản lý SSR
    local safe_domain
    safe_domain=$(get_safe_domain "$domain")
    local supervisor_conf="/etc/supervisor/conf.d/${safe_domain}.conf"
    
    local node_dir
    node_dir=$(resolve_n_node_version_dir "$target_ver") || return 1
    local env_line="environment=PATH=\"${node_dir}/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin\""
    
    if [ -f "$supervisor_conf" ] && grep -q "^\[program:${safe_domain}-ssr\]" "$supervisor_conf" 2>/dev/null; then
        if sed -n "/^\[program:${safe_domain}-ssr\]/,/^\[/p" "$supervisor_conf" | grep -q "^environment="; then
            sed -i "/^\[program:${safe_domain}-ssr\]/,/^\[/ s|^environment=.*|${env_line}|" "$supervisor_conf"
        else
            sed -i "/^\[program:${safe_domain}-ssr\]/,/^\[/ s|^stopwaitsecs=.*|&\n${env_line}|" "$supervisor_conf"
        fi
        
        # Đọc lại Supervisor và khởi động lại dịch vụ SSR
        supervisorctl reread >/dev/null 2>&1 || true
        supervisorctl update >/dev/null 2>&1 || true
        supervisorctl restart "${safe_domain}:${safe_domain}-ssr" >/dev/null 2>&1 || true
        info "Đã cập nhật cấu hình PATH Supervisor SSR cho ${domain} trỏ tới Node.js ${target_ver}.x."
    fi
}

#-----------------------------------------------------------------------------
# Hàm:          ensure_site_node_version
# Mô tả:        Đảm bảo phiên bản Node.js của website đã sẵn sàng (gọi từ deploy).
#-----------------------------------------------------------------------------
ensure_site_node_version() {
    local domain="$1"
    local target_ver="${2:-${NODE_VERSION:-20}}"
    target_ver=$(normalize_node_version "$target_ver")
    setup_site_node_wrappers "$domain" "$target_ver"
}

#-----------------------------------------------------------------------------
# Hàm:          run_site_node_cmd
# Mô tả:        Hàm tương thích cũ - Chạy lệnh với PATH trỏ thẳng tới node bin của 'n'.
#-----------------------------------------------------------------------------
run_site_node_cmd() {
    local domain="$1"
    shift
    local site_env
    site_env=$(get_site_node_env_file "$domain")
    local configured_ver="20"
    [ -f "$site_env" ] && configured_ver=$(grep -oP '(?<=^NODE_VERSION=")[^"]+' "$site_env" 2>/dev/null || echo "20")
    
    local node_dir
    node_dir=$(resolve_n_node_version_dir "$configured_ver") || return 1
    PATH="${node_dir}/bin:$PATH" "$@"
}

#-----------------------------------------------------------------------------
# Hàm:          show_site_node_status
# Mô tả:        Hiển thị trạng thái Node.js hiện tại của một website.
#-----------------------------------------------------------------------------
show_site_node_status() {
    local domain="$1"
    local site_env
    site_env=$(get_site_node_env_file "$domain")
    local configured="20"
    [ -f "$site_env" ] && configured=$(grep -oP '(?<=^NODE_VERSION=")[^"]+' "$site_env" 2>/dev/null || echo "20")

    echo -e "${CYAN}------------------------------------------${NC}"
    echo -e "${YELLOW} TRẠNG THÁI NODE.JS CỦA WEBSITE: ${domain}${NC}"
    echo -e "${CYAN}------------------------------------------${NC}"
    echo -e " Phiên bản cấu hình  : ${GREEN}${configured}${NC}"
    echo -e " Lệnh gọi toàn cục   : ${GREEN}node${configured} / npm${configured}${NC}"
    
    local node_dir
    node_dir=$(resolve_n_node_version_dir "$configured")
    if [ -n "$node_dir" ] && [ -x "${node_dir}/bin/node" ]; then
        echo -e " Phiên bản thực tế   : ${GREEN}$(${node_dir}/bin/node -v)${NC}"
        echo -e " Đường dẫn cài đặt   : ${node_dir}/bin/node"
    else
        echo -e " Phiên bản thực tế   : ${RED}Chưa cài đặt trên VPS${NC}"
    fi
    
    command -v node >/dev/null 2>&1 && echo -e " Node.js mặc định VPS: $(node -v) ($(command -v node))"
    echo -e "${CYAN}------------------------------------------${NC}"
}

#-----------------------------------------------------------------------------
# Hàm:          select_node_version_menu
# Mô tả:        Menu chọn phiên bản Node.js.
#-----------------------------------------------------------------------------
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
    read -r -p "Lựa chọn của bạn (0-$((i-1))): " choice
    [ "$choice" = "0" ] && return 1
    if [[ "$choice" =~ ^[0-9]+$ ]] && [ "$choice" -ge 1 ] && [ "$choice" -lt "$i" ]; then
        echo "${NODE_SUPPORTED_VERSIONS[$((choice-1))]}"
        return 0
    fi

    error "Lựa chọn không hợp lệ."
    return 1
}

#-----------------------------------------------------------------------------
# Hàm:          remove_node_version
# Mô tả:        Gỡ bỏ một phiên bản Node khỏi trình quản lý phiên bản 'n'.
#-----------------------------------------------------------------------------
remove_node_version() {
    local target_ver
    target_ver=$(normalize_node_version "$1")

    if ! command -v n >/dev/null 2>&1; then
        error "Chưa cài đặt trình quản lý 'n'. Không có phiên bản để gỡ bỏ."
        return 1
    fi

    warn "Bạn sắp sửa gỡ bỏ Node.js ${target_ver}.x khỏi hệ thống."
    warn "Hãy chắc chắn không còn website nào đang chạy phiên bản này."
    local confirm
    read -p "Nhập 'YES' để xác nhận hành động này: " confirm
    [ "$confirm" != "YES" ] && { warn "Đã hủy bỏ hành động."; return 0; }

    n rm "$target_ver" || true
    rm -f "/usr/local/bin/node${target_ver}" "/usr/local/bin/npm${target_ver}" "/usr/local/bin/npx${target_ver}" 2>/dev/null || true
    hash -r 2>/dev/null || true
    info "Đã xử lý xong việc gỡ bỏ Node.js ${target_ver}.x"
}

#-----------------------------------------------------------------------------
# Hàm:          run_node_manager
# Mô tả:        Giao diện menu quản trị Node.js cho một website.
#-----------------------------------------------------------------------------
run_node_manager() {
    local domain="$1"
    if [ -z "$domain" ]; then
        error "Cần cung cấp tên miền: ./vps.sh manage-node demo.com"
        return 1
    fi

    local site_env
    site_env=$(get_site_node_env_file "$domain")
    [ ! -f "$site_env" ] && { error "Website '$domain' không tồn tại."; return 1; }

    while true; do
        local current_ver
        current_ver=$(grep -oP '(?<=^NODE_VERSION=")[^"]+' "$site_env" 2>/dev/null || echo "20")
        echo -e "${CYAN}==========================================${NC}"
        echo -e "${CYAN}    QUẢN LÝ NODE.JS DÀNH CHO: ${domain}   ${NC}"
        echo -e "${CYAN}==========================================${NC}"
        echo -e " ${GREEN}1.${NC} Xem cấu hình & trạng thái Node.js"
        echo -e " ${GREEN}2.${NC} Thay đổi phiên bản Node.js cho site"
        echo -e " ${YELLOW}3.${NC} Gỡ cài đặt phiên bản Node.js khỏi máy chủ"
        echo -e " ${RED}0.${NC} Quay lại"
        echo -e "------------------------------------------"
        local choice
        read -p "Nhập lựa chọn của bạn (0-3): " choice

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
