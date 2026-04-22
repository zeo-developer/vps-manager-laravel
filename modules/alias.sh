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

    local nginx_conf="/etc/nginx/sites-available/${primary}"

    sed "s/{{APP_DOMAIN}}/${primary}/g; \
         s/{{PHP_VERSION}}/${php_ver}/g; \
         s/{{DOMAIN_ALIASES}}/${aliases}/g" \
        "$SCRIPT_DIR/configs/nginx-template.conf" > "$nginx_conf"

    ln -nfs "$nginx_conf" "/etc/nginx/sites-enabled/${primary}"
    systemctl reload nginx

    if [ -n "$aliases" ]; then
        info "Nginx server_name cập nhật: ${primary} ${aliases}"
    else
        info "Nginx server_name cập nhật: ${primary} (không còn alias)"
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
        error "Site '${primary}' không tồn tại trong hệ thống."
        return 1
    fi

    # Alias không được trùng với primary
    if [ "$alias_domain" = "$primary" ]; then
        error "Domain alias không được trùng với domain chính."
        return 1
    fi

    # Alias không được là domain chính của site khác
    if [ -f "$SCRIPT_DIR/sites/.env.${alias_domain}" ]; then
        error "Domain '${alias_domain}' đã là domain chính của một site khác."
        return 1
    fi

    # Alias không được đã tồn tại trong DOMAIN_ALIASES của bất kỳ site nào
    if grep -rh "^DOMAIN_ALIASES=" "$SCRIPT_DIR/sites/" 2>/dev/null | grep -qw "$alias_domain"; then
        error "Domain '${alias_domain}' đã được đăng ký làm alias ở một site khác."
        return 1
    fi

    validate_env_file "$SITE_ENV" || return 1
    source "$SITE_ENV"

    local current_aliases="${DOMAIN_ALIASES:-}"

    # Kiểm tra alias chưa có trong danh sách hiện tại
    if echo "$current_aliases" | grep -qw "$alias_domain"; then
        warn "Domain '${alias_domain}' đã là alias của site '${primary}' rồi."
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
    echo -e " ${YELLOW}Lưu ý:${NC} Alias domain cần được trỏ DNS về IP server trước khi cài SSL."
    read -p "Cài/cập nhật SSL để cover alias '${alias_domain}' ngay bây giờ? (y/n): " ssl_choice
    if [[ "$ssl_choice" =~ ^[Yy]$ ]]; then
        source "$SCRIPT_DIR/modules/ssl.sh"
        install_ssl "$primary"
    else
        info "Có thể cài SSL sau bằng Menu số 2 hoặc: ./vps.sh ssl ${primary}"
    fi

    info "================================================================="
    info "✅ ĐÃ THÊM ALIAS THÀNH CÔNG"
    info "   Site chính : ${primary}"
    info "   Alias mới  : ${alias_domain}"
    info "   Tất cả alias: ${new_aliases}"
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
        error "Site '${primary}' không tồn tại trong hệ thống."
        return 1
    fi

    validate_env_file "$SITE_ENV" || return 1
    source "$SITE_ENV"

    local current_aliases="${DOMAIN_ALIASES:-}"

    if [ -z "$current_aliases" ]; then
        error "Site '${primary}' hiện không có alias nào."
        return 1
    fi

    # Kiểm tra alias có trong danh sách không
    if ! echo "$current_aliases" | grep -qw "$alias_domain"; then
        error "Domain '${alias_domain}' không phải alias của site '${primary}'."
        return 1
    fi

    warn "Bạn đang xóa alias '${alias_domain}' khỏi site '${primary}'."
    read -p "Xác nhận? (y/n): " confirm
    [[ "$confirm" =~ ^[Yy]$ ]] || { info "Đã hủy."; return 0; }

    # ── Xóa alias khỏi danh sách ─────────────────────────────────────────────
    local new_aliases
    new_aliases=$(echo "$current_aliases" | tr ' ' '\n' | grep -v "^${alias_domain}$" | tr '\n' ' ' | xargs)

    sed -i "s|^DOMAIN_ALIASES=.*|DOMAIN_ALIASES=\"${new_aliases}\"|" "$SITE_ENV"

    # ── Rebuild Nginx ─────────────────────────────────────────────────────────
    info "Đang cập nhật cấu hình Nginx ..."
    rebuild_nginx_with_aliases "$primary" "$new_aliases"

    # ── Thông báo về SSL ─────────────────────────────────────────────────────
    if [ -d "/etc/letsencrypt/live/${primary}" ]; then
        warn "SSL cert hiện tại vẫn còn cover '${alias_domain}'."
        warn "Nếu muốn loại khỏi cert, chạy lại: ./vps.sh ssl ${primary}"
    fi

    info "================================================================="
    info "✅ ĐÃ XÓA ALIAS THÀNH CÔNG"
    info "   Đã xóa    : ${alias_domain}"
    info "   Còn lại   : ${new_aliases:-'(không có alias)'}"
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
    echo -e "${CYAN}   QUẢN LÝ DOMAIN ALIAS: ${primary}     ${NC}"
    echo -e "${CYAN}==========================================${NC}"
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
