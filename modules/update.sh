#!/usr/bin/env bash
# modules/update.sh
# Xử lý Cập nhật hệ điều hành Ubuntu và dọn dẹp bộ nhớ an toàn.

run_update() {
    info "Đang tiến hành Đồng bộ và Cập nhật Lõi Máy Chủa Hệ điều hành..."
    
    warn "Quá trình này có thể mất từ 1-5 phút tuỳ thuộc vào các gói phần mềm mới."
    info "Xin đừng tắt Terminal trong lúc này!"

    echo "Tiến hành quét các bản cập nhật mới (apt update)..."
    apt-get update -y
    
    echo "Tiến hành áp dụng bản vá bảo mật và nâng cấp (apt upgrade)..."
    # Dùng tuỳ chọn tránh việc nó hỏi popup khi update thay đổi config làm đứng script
    DEBIAN_FRONTEND=noninteractive apt-get -o Dpkg::Options::="--force-confdef" -o Dpkg::Options::="--force-confold" upgrade -y

    echo "Dọn dẹp rác hệ thống (apt autoremove)..."
    apt-get autoremove -y
    apt-get clean

    info "================================================================="
    info "✅ OKE! MÁY CHỦ CỦA BẠN ĐÃ ĐƯỢC CẬP NHẬT LÊN PHIÊN BẢN MỚI NHẤT."
    info "================================================================="
}
