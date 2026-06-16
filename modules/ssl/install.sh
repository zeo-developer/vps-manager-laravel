#!/usr/bin/env bash
# modules/ssl/install.sh
# Xử lý cài đặt mới chứng chỉ SSL Let's Encrypt cho website.

#-----------------------------------------------------------------------------
# Hàm:          check_certbot_installed
# Mô tả:        Kiểm tra và tự động cài đặt Certbot nếu chưa có trên hệ thống.
# Biến toàn cục: Không có
# Tham số:      Không có
# Trả về:       0 nếu sẵn sàng, 1 nếu cài đặt thất bại
#-----------------------------------------------------------------------------
check_certbot_installed() {
    if ! command -v certbot &> /dev/null; then
        warn "Certbot chưa được cài đặt trên hệ thống. Đang tiến hành cài đặt..."
        export DEBIAN_FRONTEND=noninteractive
        apt-get update -y -q
        if apt-get install -y certbot python3-certbot-nginx; then
            info "Cài đặt Certbot thành công!"
            return 0
        else
            error "Không thể cài đặt Certbot. Vui lòng tự cài đặt bằng tay."
            return 1
        fi
    fi
    return 0
}

#-----------------------------------------------------------------------------
# Hàm:          install_ssl
# Mô tả:        Tiến hành cài đặt SSL Let's Encrypt cho tên miền chính và các alias.
# Biến toàn cục: DOMAIN_ALIASES
# Tham số:      $1 - Tên miền chính (Domain)
# Trả về:       0 nếu thành công, 1 nếu thất bại
#-----------------------------------------------------------------------------
install_ssl() {
    local domain="$1"
    info "Đang chuẩn bị cài đặt SSL Let's Encrypt cho: ${domain}..."
    warn "Yêu cầu bắt buộc: Đảm bảo DNS của domain đã được trỏ về IP máy chủ này."

    # Kiểm tra xem cấu hình Nginx của site đã tồn tại chưa
    if [ ! -f "/etc/nginx/sites-available/$domain" ]; then
        error "Lỗi: Không tìm thấy tệp cấu hình Nginx cho site này (Vui lòng chạy chức năng Thêm Website trước)."
        return 1
    fi

    # Đảm bảo Certbot đã được cài đặt
    check_certbot_installed || return 1

    # Tạo chuỗi tham số -d cho certbot từ tên miền chính và các tên miền phụ (alias)
    local d_flags="-d ${domain}"
    local aliases="${DOMAIN_ALIASES:-}"
    if [ -n "$aliases" ]; then
        info "Phát hiện các tên miền phụ (Alias): ${aliases}"
        info "Đang tạo chứng chỉ SSL SAN tích hợp (Tên miền chính + Tên miền phụ)..."
        local alias
        for alias in $aliases; do
            d_flags="${d_flags} -d ${alias}"
        done
    fi

    # Kiểm tra nếu chứng chỉ đã tồn tại trước đó thì thêm flag mở rộng
    local expand_flag=""
    if [ -d "/etc/letsencrypt/live/${domain}" ]; then
        expand_flag="--expand"
        info "Phát hiện chứng chỉ đã tồn tại, đang tiến hành mở rộng (--expand)..."
    fi

    # Thực thi lệnh Certbot cài đặt SSL tự động tích hợp Nginx
    # shellcheck disable=SC2086 # Tách từ có chủ đích cho biến d_flags
    if certbot --nginx $d_flags $expand_flag \
            --non-interactive --agree-tos --register-unsafely-without-email; then
        info "================================================================="
        info " CÀI ĐẶT THÀNH CÔNG: Đã cấu hình SSL cho [ ${domain} ]"
        [ -n "$aliases" ] && info " Danh sách tên miền phụ: ${aliases}"
        info "================================================================="
        return 0
    else
        error "Lỗi: Cài đặt SSL thất bại. Vui lòng kiểm tra lại DNS hoặc logs của Certbot."
        return 1
    fi
}
