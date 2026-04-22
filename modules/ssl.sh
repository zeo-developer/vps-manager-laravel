#!/usr/bin/env bash
# modules/ssl.sh
# Quản lý Chứng chỉ SSL Let's Encrypt (Cài mới & Renew)

run_ssl_manager() {
    local domain="$1"
    
    echo -e "${CYAN}==========================================${NC}"
    echo -e "${CYAN}    QUẢN LÝ SSL CHO: ${domain}           ${NC}"
    echo -e "${CYAN}==========================================${NC}"
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
    info "Bắt đầu quy trình cài đặt SSL Let's Encrypt cho ${domain}..."
    warn "Đảm bảo bạn đã trỏ IP Domain về Server thành công trước khi cài."

    # Kiểm tra xem domain đã được cấu hình nginx chưa
    if [ ! -f "/etc/nginx/sites-available/$domain" ]; then
        error "Không tìm thấy file cấu hình Nginx cho ${domain}. Hãy Add Site trước."
        return 1
    fi

    # ―― Build chuỗi -d flags từ APP_DOMAIN + DOMAIN_ALIASES ―――――――――――――――――――
    local d_flags="-d ${domain}"
    local aliases="${DOMAIN_ALIASES:-}"
    if [ -n "$aliases" ]; then
        info "Phát hiện alias: ${aliases}"
        info "Đang cài SSL SAN cert cover cả domain chính và alias..."
        for alias in $aliases; do
            d_flags="${d_flags} -d ${alias}"
        done
    fi

    # ―― Xác định cự dùng --expand (cert đã có) hay cài mới ―――――――――――――――――
    local expand_flag=""
    if [ -d "/etc/letsencrypt/live/${domain}" ]; then
        expand_flag="--expand"
        info "Cert đã tồn tại — dùng --expand để mở rộng thêm domain mới vào cert..."
    fi

    # ―― Chạy certbot ――――――――――――――――――――――――――――――――――――――――
    # shellcheck disable=SC2086  # Word splitting intentional cho d_flags
    if certbot --nginx $d_flags $expand_flag \
            --non-interactive --agree-tos --register-unsafely-without-email; then
        info "================================================================="
        info "✅ THÀNH CÔNG: SSL ĐÃ ĐƯỢC CÀI/CẬP NHẬT CHO [ ${domain} ]"
        if [ -n "$aliases" ]; then
            info "   Cert cover thêm: ${aliases}"
        fi
        info "================================================================="
    else
        warn "Cài đặt SSL thất bại. Vui lòng kiểm tra lại DNS hoặc Logs của Certbot."
    fi
}

renew_ssl_all() {
    info "Đang tiến hành kiểm tra và gia hạn thủ công toàn bộ Chứng chỉ SSL..."
    if certbot renew; then
        info "Quá trình kiểm tra/gia hạn hoàn tất."
        systemctl reload nginx
    else
        warn "Có lỗi xảy ra trong quá trình gia hạn SSL."
    fi
}
