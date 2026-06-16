#!/usr/bin/env bash
# modules/update/run.sh
# Xử lý cập nhật và tối ưu hệ điều hành Ubuntu/Debian.

#-----------------------------------------------------------------------------
# Hàm:          run_update
# Mô tả:        Cập nhật các gói phần mềm hệ thống, giải phóng RAM cache,
#               dọn dẹp log hệ thống cũ và kiểm tra yêu cầu khởi động lại (Reboot).
# Biến toàn cục: DEBIAN_FRONTEND, YELLOW, NC, GREEN
# Tham số:      Không có
# Trả về:       Không có
#-----------------------------------------------------------------------------
run_update() {
    info "Đang tiến hành đồng bộ và cập nhật hệ điều hành máy chủ..."
    warn "Quá trình này có thể mất từ 1-5 phút tuỳ thuộc vào số lượng gói phần mềm cần nâng cấp."
    info "Vui lòng không tắt kết nối Terminal trong lúc này!"

    # 1. Quét và cập nhật các gói phần mềm hệ thống
    echo "Tiến hành quét các bản cập nhật mới (apt update)..."
    apt-get update -y -q
    
    echo "Tiến hành áp dụng bản vá bảo mật và nâng cấp (apt upgrade)..."
    # Tránh việc hiện giao diện tương tác hỏi cấu hình thay đổi làm đứng script
    export DEBIAN_FRONTEND=noninteractive
    apt-get upgrade -y -q -o Dpkg::Options::="--force-confdef" -o Dpkg::Options::="--force-confold"

    # 2. Dọn dẹp rác hệ thống (Apt clean)
    echo "Dọn dẹp các gói phần mềm dư thừa (apt autoremove)..."
    apt-get autoremove -y -q
    apt-get clean

    # 3. Dọn dẹp Log hệ thống journald để giải phóng dung lượng đĩa
    if command -v journalctl &> /dev/null; then
        echo "Đang dọn dẹp các tệp log hệ thống cũ (giới hạn log tối đa 100MB)..."
        journalctl --vacuum-size=100M || true
    fi

    # 4. Giải phóng bộ nhớ đệm RAM (Drop Cache)
    echo "Đang thực hiện giải phóng bộ nhớ đệm RAM dư thừa (RAM Caches)..."
    sync
    if echo 3 > /proc/sys/vm/drop_caches 2>/dev/null; then
        info "Đã giải phóng RAM Cache thành công!"
    else
        warn "Không có quyền ghi vào drop_caches để giải phóng RAM (Yêu quyền Root thực tế)."
    fi

    info "================================================================="
    info "✅ HOÀN TẤT: HỆ ĐIỀU HÀNH MÁY CHỦ ĐÃ ĐƯỢC TỐI ƯU VÀ CẬP NHẬT."
    info "================================================================="

    # 5. Kiểm tra xem hệ thống có yêu cầu khởi động lại không
    if [ -f "/var/run/reboot-required" ]; then
        echo ""
        warn "⚠️ CẢNH BÁO QUAN TRỌNG: Máy chủ yêu cầu KHỞI ĐỘNG LẠI (Reboot Required)"
        warn "  Để áp dụng các bản vá nhân hệ điều hành (Kernel) mới cài đặt."
        warn "  Sếp có thể khởi động lại thủ công bằng cách chạy lệnh: sudo reboot"
        echo ""
    fi
}
