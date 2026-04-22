#!/usr/bin/env bash
# modules/alias.sh
# Quản lý Domain Alias — nhiều domain cùng trỏ về 1 web root

# ─────────────────────────────────────────────────────────────────────────────
# Hàm nội bộ: Rebuild nginx config với danh sách alias mới nhất
# ─────────────────────────────────────────────────────────────────────────────
rebuild_nginx_with_aliases() {
    local primary="$1"
    local aliases="${2:-}"

    local SITE_ENV="$SCRIPT_DIR/sites/.env.${primary}"
    local php_ver
    php_ver=$(grep -oP '(?<=^PHP_VERSION=")[^"]+' "$SITE_ENV" 2>/dev/null || echo "8.3")

    # Build SERVER_NAMES: primary + aliases (nếu có) — không có dấu cách thừa
    local server_names="$primary"
    if [ -n "$aliases" ]; then
        server_names="$primary $aliases"
    fi

    local nginx_conf="/etc/nginx/sites-available/${primary}"

    sed "s/{{APP_DOMAIN}}/${primary}/g; \
         s/{{PHP_VERSION}}/${php_ver}/g; \
         s/{{SERVER_NAMES}}/${server_names}/g" \
        "$SCRIPT_DIR/configs/nginx-template.conf" > "$nginx_conf"

    ln -nfs "$nginx_conf" "/etc/nginx/sites-enabled/${primary}"
    systemctl reload nginx

    if [ -n "$aliases" ]; then
        info "Cập nhật Nginx server_name: ${server_names}"
    else
        info "Nginx server_name cập nhật: ${primary} (không có alias)"
    fi
}

# ─────────────────────────────────────────────────────────────────────────────
# Thêm alias domain vào site
# ─────────────────────────────────────────────────────────────────────────────
run_add_alias() {
    local primary="$1"
    local alias_domain="$2"

    local SITE_ENV="$SCRIPT_DIR/sites/.env.${primary}"

    # ── Validate ──────────────────────────────────────────────────────────────
    if [ ! -f "$SITE_ENV" ]; then
        error "Lỗi: Site '${primary}' không tồn tại."
        return 1
    fi

    # Alias không được trùng với primary
    if [ "$alias_domain" = "$primary" ]; then
        error "Lỗi: Alias trùng với domain chính."
        return 1
    fi

    # Alias không được là domain chính của site khác
    if [ -f "$SCRIPT_DIR/sites/.env.${alias_domain}" ]; then
        error "Lỗi: '${alias_domain}' đang là domain chính của site khác."
        return 1
    fi

    # Alias không được đã tồn tại trong DOMAIN_ALIASES của bất kỳ site nào
    if grep -rh "^DOMAIN_ALIASES=" "$SCRIPT_DIR/sites/" 2>/dev/null | grep -qw "$alias_domain"; then
        error "Lỗi: '${alias_domain}' đã được sử dụng làm alias."
        return 1
    fi

    validate_env_file "$SITE_ENV" || return 1
    source "$SITE_ENV"

    local current_aliases="${DOMAIN_ALIASES:-}"

    # Kiểm tra alias chưa có trong danh sách hiện tại
    if echo "$current_aliases" | grep -qw "$alias_domain"; then
        info "Domain '${alias_domain}' đã tồn tại trong danh sách alias."
        return 0
    fi

    # ── Cập nhật DOMAIN_ALIASES ───────────────────────────────────────────────
    local new_aliases
    if [ -z "$current_aliases" ]; then
        new_aliases="$alias_domain"
    else
        new_aliases="$current_aliases $alias_domain"
    fi

    if grep -q "^DOMAIN_ALIASES=" "$SITE_ENV"; then
        sed -i "s|^DOMAIN_ALIASES=.*|DOMAIN_ALIASES=\"${new_aliases}\"|" "$SITE_ENV"
    else
        echo "DOMAIN_ALIASES=\"${new_aliases}\"" >> "$SITE_ENV"
    fi

    # ── Rebuild Nginx ─────────────────────────────────────────────────────────
    info "Đang cập nhật cấu hình Nginx ..."
    rebuild_nginx_with_aliases "$primary" "$new_aliases"

    # ── Hỏi cài SSL ──────────────────────────────────────────────────────────
    echo -e ""
    warn "Yêu cầu: Cấu hình DNS cho alias trước khi cài SSL."
    read -p "Cài đặt SSL cho alias '${alias_domain}'? (y/n): " ssl_choice
    if [[ "$ssl_choice" =~ ^[Yy]$ ]]; then
        source "$SCRIPT_DIR/modules/ssl.sh"
        install_ssl "$primary"
    else
        info "Gợi ý: Cài SSL sau bằng lệnh: ./vps.sh ssl ${primary}"
    fi

    info "================================================================="
    info " THÀNH CÔNG: Đã thêm alias cho site [ ${primary} ]"
    info "-----------------------------------------------------------------"
    info " Alias mới : ${alias_domain}"
    info " Danh sách : ${new_aliases}"
    info "================================================================="
}

# ─────────────────────────────────────────────────────────────────────────────
# Xóa alias domain khỏi site
# ─────────────────────────────────────────────────────────────────────────────
run_remove_alias() {
    local primary="$1"
    local alias_domain="$2"

    local SITE_ENV="$SCRIPT_DIR/sites/.env.${primary}"

    if [ ! -f "$SITE_ENV" ]; then
        error "Lỗi: Site '${primary}' không tồn tại."
        return 1
    fi

    validate_env_file "$SITE_ENV" || return 1
    source "$SITE_ENV"

    local current_aliases="${DOMAIN_ALIASES:-}"

    if [ -z "$current_aliases" ]; then
        error "Lỗi: Site '${primary}' không có alias."
        return 1
    fi

    # Kiểm tra alias có trong danh sách không
    if ! echo "$current_aliases" | grep -qw "$alias_domain"; then
        error "Lỗi: '${alias_domain}' không thuộc danh sách alias của '${primary}'."
        return 1
    fi

    warn "Xác nhận xóa alias '${alias_domain}' khỏi site '${primary}'?"
    read -p "Xác nhận (y/n): " confirm
    [[ "$confirm" =~ ^[Yy]$ ]] || { info "Hủy thao tác."; return 0; }

    # ── Xóa alias khỏi danh sách ─────────────────────────────────────────────
    local new_aliases
    new_aliases=$(echo "$current_aliases" | tr ' ' '\n' | grep -v "^${alias_domain}$" | tr '\n' ' ' | xargs)

    sed -i "s|^DOMAIN_ALIASES=.*|DOMAIN_ALIASES=\"${new_aliases}\"|" "$SITE_ENV"

    # ── Rebuild Nginx ─────────────────────────────────────────────────────────
    info "Cập nhật cấu hình Nginx..."
    rebuild_nginx_with_aliases "$primary" "$new_aliases"

    # ── Thông báo về SSL ─────────────────────────────────────────────────────
    if [ -d "/etc/letsencrypt/live/${primary}" ]; then
        warn "SSL certificate hiện tại vẫn bao gồm '${alias_domain}'."
        warn "Để cập nhật certificate, chạy: ./vps.sh ssl ${primary}"
    fi

    info "================================================================="
    info " THÀNH CÔNG: Đã xóa alias khỏi site [ ${primary} ]"
    info "-----------------------------------------------------------------"
    info " Đã xóa  : ${alias_domain}"
    info " Còn lại : ${new_aliases:-'(không có)'}"
    info "================================================================="
}

# ─────────────────────────────────────────────────────────────────────────────
# Hiển thị menu quản lý alias cho 1 site
# ─────────────────────────────────────────────────────────────────────────────
run_manage_alias() {
    local primary="$1"
    local SITE_ENV="$SCRIPT_DIR/sites/.env.${primary}"

    validate_env_file "$SITE_ENV" || return 1
    source "$SITE_ENV"

    local current_aliases="${DOMAIN_ALIASES:-}"

    echo -e "${CYAN}==========================================${NC}"
    echo -e "${CYAN}        DOMAIN ALIAS MANAGER              ${NC}"
    echo -e "${CYAN}==========================================${NC}"
    echo -e " ${BLUE}Site chính:${NC} ${primary}"
    if [ -n "$current_aliases" ]; then
        echo -e " ${BLUE}Alias hiện tại:${NC} ${current_aliases}"
    else
        echo -e " ${YELLOW}Chưa có alias nào.${NC}"
    fi
    echo -e "------------------------------------------"
    echo -e " ${GREEN}1.${NC} Thêm Alias Domain Mới"
    echo -e " ${GREEN}2.${NC} Xóa Alias Domain"
    echo -e " ${RED}0.${NC} Quay lại"
    echo -e "------------------------------------------"
    read -p "Lựa chọn: " alias_choice

    case $alias_choice in
        1)
            read -p "Nhập domain alias muốn thêm (vd: mysite.vn): " new_alias
            new_alias=$(sanitize_input "$new_alias")
            if [ -z "$new_alias" ]; then
                error "Domain alias không được để trống."
                return 1
            fi
            run_add_alias "$primary" "$new_alias"
            ;;
        2)
            if [ -z "$current_aliases" ]; then
                warn "Không có alias nào để xóa."
                return 0
            fi
            echo -e "${YELLOW}Alias hiện tại: ${current_aliases}${NC}"
            read -p "Nhập domain alias muốn xóa: " del_alias
            run_remove_alias "$primary" "$del_alias"
            ;;
        0) return 0 ;;
        *) warn "Lựa chọn không hợp lệ." ;;
    esac
}
