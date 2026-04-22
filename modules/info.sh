#!/usr/bin/env bash
# modules/info.sh
# Xem thông tin cấu hình chi tiết của 1 Website
set -uo pipefail   # Bắt lỗi unbound variable và pipeline fail (không dùng -e để giữ menu cuầm khi có lỗi)

run_site_info() {
    local domain="$1"
    local SITE_ENV="$SCRIPT_DIR/sites/.env.${domain}"
    
    if [ ! -f "$SITE_ENV" ]; then
        error "Không tìm thấy cấu hình cho site: $domain"
        return 1
    fi

    # Load env của site (validate trước khi source để tránh code injection)
    validate_env_file "$SITE_ENV" || return 1
    source "$SITE_ENV"

    # Kiểm tra SSL
    local ssl_status="${RED}Chưa cài (HTTP)${NC}"
    if [ -d "/etc/letsencrypt/live/$domain" ]; then
        ssl_status="${GREEN}Đã cài (HTTPS)${NC}"
    fi

    # Kiểm tra Nginx
    local nginx_status="${RED}Không hoạt động${NC}"
    if [ -f "/etc/nginx/sites-enabled/$domain" ]; then
        nginx_status="${GREEN}Đang hoạt động${NC}"
    fi

    local SAFE_DOMAIN=$(get_safe_domain "$domain")

    # Kiểm tra Queue Worker (Hỗ trợ cả trường hợp numprocs > 1)
    local queue_status="${RED}Không chạy${NC}"
    if supervisorctl status "${SAFE_DOMAIN}:" 2>/dev/null | grep "${SAFE_DOMAIN}-worker" | grep -q "RUNNING"; then
        queue_status="${GREEN}Đang hoạt động${NC}"
    fi

    # Kiểm tra SSR Worker
    local ssr_status="${RED}Không chạy${NC}"
    if supervisorctl status "${SAFE_DOMAIN}:${SAFE_DOMAIN}-ssr" 2>/dev/null | grep -q "RUNNING"; then
        ssr_status="${GREEN}Đang hoạt động (Cổng: ${SSR_PORT:-13714})${NC}"
    fi

    # Lấy SSH Public Key (validate path để tránh path traversal)
    local public_key="Không tìm thấy SSH Key"
    if [ -n "${SSH_KEY_PATH:-}" ]; then
        local resolved_pub
        resolved_pub=$(realpath "${SSH_KEY_PATH}.pub" 2>/dev/null || true)
        local safe_key_dir
        safe_key_dir=$(realpath "$SCRIPT_DIR" 2>/dev/null || echo "$SCRIPT_DIR")
        # Chỉ đọc nếu file .pub nằm trong SCRIPT_DIR và đúng extension
        if [[ "$resolved_pub" == "${safe_key_dir}"* ]] && \
           [[ "$resolved_pub" == *.pub ]] && \
           [ -f "$resolved_pub" ]; then
            public_key=$(cat "$resolved_pub")
        else
            public_key="[INVALID PATH — xem lại SSH_KEY_PATH trong sites/.env.${domain}]"
        fi
    fi

    echo -e "${CYAN}==========================================${NC}"
    echo -e "${CYAN}      THÔNG TIN WEBSITE: ${domain}        ${NC}"
    echo -e "${CYAN}==========================================${NC}"
    echo -e " ${BLUE}Domain        :${NC} ${domain}"
    echo -e " ${BLUE}PHP Version   :${NC} ${PHP_VERSION}"
    echo -e " ${BLUE}Web Root      :${NC} /var/www/${domain}"
    echo -e " ${BLUE}Database Name :${NC} ${DB_NAME}"
    echo -e " ${BLUE}Database User :${NC} ${DB_USER}"
    # Che mật khẩu — không in plaintext ra terminal
    local masked_pass="[hidden]"
    if [ -n "${DB_PASSWORD:-}" ]; then
        local pass_len=${#DB_PASSWORD}
        masked_pass="${DB_PASSWORD:0:2}$(printf '%0.s*' $(seq 1 $((pass_len - 2))))  (${pass_len} ký tự)"
    fi
    echo -e " ${BLUE}Database Pass :${NC} ${masked_pass}"
    echo -e " ${BLUE}SSL Status    :${NC} ${ssl_status}"
    echo -e " ${BLUE}Nginx Config  :${NC} ${nginx_status}"
    echo -e " ${BLUE}Queue Worker  :${NC} ${queue_status}"
    echo -e " ${BLUE}SSR Service   :${NC} ${ssr_status}"
    echo -e "------------------------------------------"
    echo -e " ${CYAN}🔑 SSH PUBLIC KEY (Deploy Key):${NC}"
    echo -e "${YELLOW}${public_key}${NC}"
    echo -e "------------------------------------------"
}
