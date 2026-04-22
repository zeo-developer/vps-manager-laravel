#!/usr/bin/env bash
# modules/ssl.sh
# Quản lý Chứng chỉ SSL Let's Encrypt (Cài mới & Renew)

run_ssl_manager() {
    local domain="$1"
    
    echo -e "${CYAN}==========================================${NC}"
    echo -e "${CYAN}        SSL CERTIFICATE MANAGER           ${NC}"
    echo -e "${CYAN}==========================================${NC}"
    echo -e " ${BLUE}Domain:${NC} ${domain}"
    echo -e " ${GREEN}1.${NC} Cài đặt SSL Mới (Let's Encrypt)"
    echo -e " ${GREEN}2.${NC} Ép gia hạn nạp lại toàn bộ SSL (Renew All)"
    echo -e " ${RED}0.${NC} Quay lại Menu chính"
    echo -e "------------------------------------------"
    read -p "Lựa chọn của bạn: " ssl_choice

    case $ssl_choice in
        1) install_ssl "$domain" ;;
        2) renew_ssl_all ;;
        0) return 2 ;;
        *) warn "Lựa chọn không hợp lệ."; run_ssl_manager "$domain" ;;
    esac
}

install_ssl() {
    local domain="$1"
    info "Cài đặt SSL Let's Encrypt: ${domain}..."
    warn "Yêu cầu: Đảm bảo DNS domain đã được trỏ về IP máy chủ."

    # Kiểm tra xem domain đã được cấu hình nginx chưa
    if [ ! -f "/etc/nginx/sites-available/$domain" ]; then
        error "Lỗi: Không tìm thấy file cấu hình Nginx (Vui lòng chạy add-site)."
        return 1
    fi

    # ―― Build chuỗi -d flags từ APP_DOMAIN + DOMAIN_ALIASES ―――――――――――――――――――
    local d_flags="-d ${domain}"
    local aliases="${DOMAIN_ALIASES:-}"
    if [ -n "$aliases" ]; then
        info "Phát hiện Alias: ${aliases}"
        info "Khởi tạo SSL SAN (Primary + Aliases)..."
        for alias in $aliases; do
            d_flags="${d_flags} -d ${alias}"
        done
    fi

    # ―― Xác định cự dùng --expand (cert đã có) hay cài mới ―――――――――――――――――
    local expand_flag=""
    if [ -d "/etc/letsencrypt/live/${domain}" ]; then
        expand_flag="--expand"
        info "Mở rộng SSL certificate (--expand)..."
    fi

    # ―― Chạy certbot ――――――――――――――――――――――――――――――――――――――――
    # shellcheck disable=SC2086  # Word splitting intentional cho d_flags
    if certbot --nginx $d_flags $expand_flag \
            --non-interactive --agree-tos --register-unsafely-without-email; then
        info "================================================================="
        info " THÀNH CÔNG: Đã cài đặt SSL cho [ ${domain} ]"
        [ -n "$aliases" ] && info " Danh sách SAN: ${aliases}"
        info "================================================================="
    else
        error "Lỗi: Cài đặt SSL thất bại (Kiểm tra DNS hoặc Certbot logs)."
    fi
}

renew_ssl_all() {
    info "Đang gia hạn toàn bộ SSL certificate..."
    if certbot renew; then
        info "Quá trình kiểm tra/gia hạn hoàn tất."
        systemctl reload nginx
    else
        warn "Có lỗi xảy ra trong quá trình gia hạn SSL."
    fi
}
