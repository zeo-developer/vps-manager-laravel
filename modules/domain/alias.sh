#!/usr/bin/env bash
# modules/domain/alias.sh
# Quản lý Domain Alias — cấu hình nhiều domain cùng trỏ về 1 thư mục gốc (Web Root)

#-----------------------------------------------------------------------------
# Hàm:          run_add_alias
# Mô tả:        Thêm một tên miền alias mới cho Website.
# Biến toàn cục: SCRIPT_DIR, DOMAIN_ALIASES
# Tham số:      $1 - Tên miền chính
#               $2 - Tên miền alias cần thêm
# Trả về:       0 nếu thành công, 1 nếu lỗi
#-----------------------------------------------------------------------------
run_add_alias() {
    local primary="$1"
    local alias_domain="$2"

    local SITE_ENV="$SCRIPT_DIR/sites/.env.${primary}"

    # Kiểm tra tính hợp lệ (Validate)
    if [ ! -f "$SITE_ENV" ]; then
        error "Lỗi: Site '${primary}' không tồn tại."
        return 1
    fi

    # Alias không được trùng với primary
    if [ "$alias_domain" = "$primary" ]; then
        error "Lỗi: Alias trùng với domain chính."
        return 1
    fi

    # Alias không được trùng với domain chính của bất kỳ site nào khác
    if [ -f "$SCRIPT_DIR/sites/.env.${alias_domain}" ]; then
        error "Lỗi: '${alias_domain}' đang là domain chính của site khác."
        return 1
    fi

    # Alias không được trùng với alias của bất kỳ site nào khác
    local conflict_file=$(check_domain_alias_conflict "$alias_domain")
    if [ -n "$conflict_file" ]; then
        local conflict_domain=$(basename "$conflict_file" | sed 's/^\.env\.//')
        error "Lỗi: '${alias_domain}' đã được sử dụng làm alias cho site '${conflict_domain}'."
        return 1
    fi

    validate_env_file "$SITE_ENV" || return 1
    source "$SITE_ENV"

    local current_aliases="${DOMAIN_ALIASES:-}"

    # Kiểm tra xem alias đã có trong danh sách hiện tại chưa
    if echo "$current_aliases" | grep -qw "$alias_domain"; then
        info "Domain '${alias_domain}' đã tồn tại trong danh sách alias."
        return 0
    fi

    # ── Cập nhật biến cấu hình DOMAIN_ALIASES ────────────────────────────────
    local new_aliases
    if [ -z "$current_aliases" ]; then
        new_aliases="$alias_domain"
    else
        new_aliases="$current_aliases $alias_domain"
    fi

    update_env_var "DOMAIN_ALIASES" "${new_aliases}" "$SITE_ENV"

    # ── Biên dịch lại cấu hình Nginx ─────────────────────────────────────────
    info "Đang cập nhật cấu hình Nginx ..."
    local php_ver=$(grep -oP '(?<=^PHP_VERSION=")[^"]+' "$SITE_ENV" 2>/dev/null || echo "8.3")
    generate_nginx_config "$primary" "$primary $new_aliases" "$php_ver"
    systemctl reload nginx

    # ── Hỏi ý kiến về việc cài đặt SSL ───────────────────────────────────────
    echo -e ""
    warn "Yêu cầu: Cấu hình DNS cho alias trước khi cài SSL."
    read -p "Cài đặt SSL cho alias '${alias_domain}'? (y/n): " ssl_choice
    if [[ "$ssl_choice" =~ ^[Yy]$ ]]; then
        load_module "ssl.sh" || return 1
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

#-----------------------------------------------------------------------------
# Hàm:          run_remove_alias
# Mô tả:        Gỡ bỏ một tên miền alias khỏi Website.
# Biến toàn cục: SCRIPT_DIR, DOMAIN_ALIASES
# Tham số:      $1 - Tên miền chính
#               $2 - Tên miền alias cần gỡ
# Trả về:       0 nếu thành công, 1 nếu lỗi
#-----------------------------------------------------------------------------
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
        error "Lỗi: Site '${primary}' không có alias nào để xóa."
        return 1
    fi

    # Kiểm tra xem alias có thực sự trong danh sách hay không
    if ! echo "$current_aliases" | grep -qw "$alias_domain"; then
        error "Lỗi: '${alias_domain}' không thuộc danh sách alias của '${primary}'."
        return 1
    fi

    warn "Xác nhận xóa alias '${alias_domain}' khỏi site '${primary}'?"
    read -p "Xác nhận (y/n): " confirm
    [[ "$confirm" =~ ^[Yy]$ ]] || { info "Hủy thao tác."; return 0; }

    # ── Gỡ alias ra khỏi danh sách ──────────────────────────────────────────
    local new_aliases
    new_aliases=$(echo "$current_aliases" | tr ' ' '\n' | grep -v "^${alias_domain}$" | tr '\n' ' ' | xargs)

    update_env_var "DOMAIN_ALIASES" "${new_aliases}" "$SITE_ENV"

    # ── Cập nhật cấu hình Nginx ──────────────────────────────────────────────
    info "Cập nhật cấu hình Nginx..."
    local php_ver=$(grep -oP '(?<=^PHP_VERSION=")[^"]+' "$SITE_ENV" 2>/dev/null || echo "8.3")
    local server_names="$primary"
    [ -n "$new_aliases" ] && server_names="$primary $new_aliases"
    
    generate_nginx_config "$primary" "$server_names" "$php_ver"
    systemctl reload nginx

    # ── Cảnh báo về vấn đề SSL Cert cũ ───────────────────────────────────────
    if [ -d "/etc/letsencrypt/live/${primary}" ]; then
        warn "Chứng chỉ SSL cũ vẫn lưu thông tin domain '${alias_domain}'."
        warn "Để cập nhật lại chứng chỉ SSL mới, hãy chạy: ./vps.sh ssl ${primary}"
    fi

    info "================================================================="
    info " THÀNH CÔNG: Đã xóa alias khỏi site [ ${primary} ]"
    info "-----------------------------------------------------------------"
    info " Đã xóa  : ${alias_domain}"
    info " Còn lại : ${new_aliases:-'(không có)'}"
    info "================================================================="
}

#-----------------------------------------------------------------------------
# Hàm:          run_manage_alias
# Mô tả:        Hiển thị menu quản lý domain alias trực quan của 1 Website.
# Biến toàn cục: SCRIPT_DIR, CYAN, BLUE, YELLOW, RED, GREEN, NC
# Tham số:      $1 - Tên miền chính
# Trả về:       Mã exit code (0 thành công, 1 lỗi, 2 quay lại)
#-----------------------------------------------------------------------------
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
        0) return 2 ;;
        *) warn "Lựa chọn không hợp lệ." ;;
    esac
}
