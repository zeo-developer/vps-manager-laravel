#!/usr/bin/env bash
# modules/ssl/renew.sh
# Xử lý gia hạn tự động tất cả các chứng chỉ Let's Encrypt trên hệ thống.

#-----------------------------------------------------------------------------
# Hàm:          renew_ssl_all
# Mô tả:        Gia hạn toàn bộ chứng chỉ SSL Let's Encrypt hiện có và reload Nginx.
# Biến toàn cục: Không có
# Tham số:      Không có
# Trả về:       Không có
#-----------------------------------------------------------------------------
renew_ssl_all() {
    info "Đang bắt đầu gia hạn toàn bộ chứng chỉ SSL Let's Encrypt..."
    
    # Đảm bảo Certbot đã được cài đặt (hàm check_certbot_installed được nạp từ ssl/install.sh)
    check_certbot_installed || return 1

    if certbot renew; then
        info "Kiểm tra và gia hạn hoàn tất!"
        systemctl reload nginx
    else
        warn "Đã xảy ra sự cố trong quá trình gia hạn SSL tự động."
    fi
}
