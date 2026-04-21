#!/usr/bin/env bash
# modules/info.sh
# Xem thông tin cấu hình chi tiết của 1 Website

run_site_info() {
    local domain="$1"
    local SITE_ENV="$SCRIPT_DIR/sites/.env.${domain}"
    
    if [ ! -f "$SITE_ENV" ]; then
        error "Không tìm thấy cấu hình cho site: $domain"
    fi

    # Load env của site
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

    # Kiểm tra SSR Worker
    local ssr_status="${RED}Không chạy${NC}"
    if supervisorctl status "ssr-${domain}" > /dev/null 2>&1 | grep -q "RUNNING"; then
        ssr_status="${GREEN}Đang hoạt động (Cổng: ${SSR_PORT:-13714})${NC}"
    fi

    # Lấy SSH Public Key
    local public_key="Không tìm thấy SSH Key"
    if [ -f "${SSH_KEY_PATH}.pub" ]; then
        public_key=$(cat "${SSH_KEY_PATH}.pub")
    fi

    echo -e "${CYAN}==========================================${NC}"
    echo -e "${CYAN}      THÔNG TIN WEBSITE: ${domain}        ${NC}"
    echo -e "${CYAN}==========================================${NC}"
    echo -e " ${BLUE}Domain        :${NC} ${domain}"
    echo -e " ${BLUE}PHP Version   :${NC} ${PHP_VERSION}"
    echo -e " ${BLUE}Web Root      :${NC} /var/www/${domain}"
    echo -e " ${BLUE}Database Name :${NC} ${DB_NAME}"
    echo -e " ${BLUE}Database User :${NC} ${DB_USER}"
    echo -e " ${BLUE}Database Pass :${NC} ${DB_PASSWORD}"
    echo -e " ${BLUE}SSL Status    :${NC} ${ssl_status}"
    echo -e " ${BLUE}Nginx Config  :${NC} ${nginx_status}"
    echo -e " ${BLUE}Queue Worker  :${NC} ${queue_status}"
    echo -e " ${BLUE}SSR Service   :${NC} ${ssr_status}"
    echo -e "------------------------------------------"
    echo -e " ${CYAN}🔑 SSH PUBLIC KEY (Deploy Key):${NC}"
    echo -e "${YELLOW}${public_key}${NC}"
    echo -e "------------------------------------------"
}
