#!/usr/bin/env bash
# modules/swap/delete.sh
# Tắt và gỡ bỏ hoàn toàn file SWAP ra khỏi hệ thống.

#-----------------------------------------------------------------------------
# Function:     remove_swap
# Description:  Deactivates swap, removes /swapfile and cleans up /etc/fstab.
# Globals:      YELLOW, NC
# Arguments:    None
# Returns:      0 on success, 1 on failure
#-----------------------------------------------------------------------------
remove_swap() {
    if [ ! -f /swapfile ]; then
        error "Lỗi: Hệ thống không tồn tại file /swapfile."
        return 1
    fi

    warn "CẢNH BÁO: Xác nhận xóa hoàn toàn SWAP và file /swapfile?"
    local confirm
    read -p "Nhập 'y' để đồng ý hoặc phím bất kỳ để hủy: " confirm
    if [[ "$confirm" =~ ^[Yy]$ ]]; then
        info "Đang tắt SWAP..."
        if ! swapoff /swapfile 2>/dev/null; then
            error "Không thể tắt swap. Có thể swap đang được sử dụng nhiều hoặc chưa kích hoạt."
            return 1
        fi
        
        info "Đang xóa tệp /swapfile..."
        rm -f /swapfile
        
        info "Đang dọn dẹp cấu hình trong /etc/fstab..."
        sed -i '\/swapfile/d' /etc/fstab
        
        info "Đã xóa bỏ hoàn toàn SWAP thành công."
        return 0
    else
        info "Đã hủy thao tác gỡ bỏ SWAP."
        return 0
    fi
}
