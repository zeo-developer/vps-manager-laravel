#!/usr/bin/env bash
# modules/swap/create.sh
# Khởi tạo và kích hoạt file SWAP mới trên hệ điều hành.

#-----------------------------------------------------------------------------
# Function:     create_swap
# Description:  Asks for swap size, checks disk space, creates the swapfile,
#               and registers it in /etc/fstab.
# Globals:      GREEN, RED, YELLOW, NC, SCRIPT_DIR
# Arguments:    None
# Returns:      0 on success, 1 on failure
#-----------------------------------------------------------------------------
create_swap() {
    if [ -f /swapfile ]; then
        error "Lỗi: File /swapfile đã tồn tại trên hệ thống."
        return 1
    fi

    echo -e "Chọn dung lượng SWAP muốn tạo:"
    echo -e " ${GREEN}1.${NC} 1GB"
    echo -e " ${GREEN}2.${NC} 2GB"
    echo -e " ${GREEN}3.${NC} 4GB"
    echo -e " ${GREEN}4.${NC} Nhập dung lượng tùy chỉnh (ví dụ: 8G, 512M)"
    local choice
    read -p "Lựa chọn (1-4): " choice

    local size=""
    case "$choice" in
        1) size="1G" ;;
        2) size="2G" ;;
        3) size="4G" ;;
        4) 
            read -p "Nhập dung lượng (vd: 512M, 8G): " size 
            size=$(sanitize_input "$size")
            ;;
        *) 
            error "Lựa chọn không hợp lệ."
            return 1 
            ;;
    esac

    # Parse size to MB for calculation and dd fallback
    local size_mb=0
    if [[ "$size" =~ ^([0-9]+)[Gg]$ ]]; then
        size_mb=$(( ${BASH_REMATCH[1]} * 1024 ))
    elif [[ "$size" =~ ^([0-9]+)[Mm]$ ]]; then
        size_mb=${BASH_REMATCH[1]}
    elif [[ "$size" =~ ^([0-9]+)$ ]]; then
        size_mb=$(( size * 1024 ))
        size="${size}G"
    else
        error "Kích thước swap không hợp lệ. Ví dụ đúng: 1G, 512M, 2G"
        return 1
    fi

    if [ "$size_mb" -le 0 ]; then
        error "Dung lượng swap phải lớn hơn 0."
        return 1
    fi

    # Check free disk space in the root partition (/)
    local free_kb
    free_kb=$(df -k / | awk 'NR==2 {print $4}')
    local required_kb=$(( size_mb * 1024 ))

    # Reserve a safety buffer of 500MB
    local safety_buffer_kb=$(( 500 * 1024 ))
    local total_needed_kb=$(( required_kb + safety_buffer_kb ))

    if [ "$free_kb" -lt "$total_needed_kb" ]; then
        error "Lỗi: Không đủ dung lượng đĩa trống."
        error "Yêu cầu: ${size} (~$((required_kb / 1024)) MB) + 500MB bộ đệm an toàn."
        error "Hiện tại chỉ còn trống: $((free_kb / 1024)) MB."
        return 1
    fi

    info "Đang khởi tạo file SWAP dung lượng ${size}..."
    
    # Try fallocate first as it is much faster than dd. Fallback to dd if filesystem doesn't support fallocate
    if ! fallocate -l "${size_mb}M" /swapfile 2>/dev/null; then
        warn "Không thể dùng fallocate. Đang thử tạo file bằng dd (có thể mất vài phút)..."
        if ! dd if=/dev/zero of=/swapfile bs=1M count="$size_mb" status=progress; then
            error "Lỗi: Không thể phân bổ không gian cho /swapfile."
            rm -f /swapfile
            return 1
        fi
    fi
    
    chmod 600 /swapfile
    if ! mkswap /swapfile; then
        error "Lỗi: Tạo cấu trúc SWAP thất bại."
        rm -f /swapfile
        return 1
    fi

    if ! swapon /swapfile; then
        error "Lỗi: Kích hoạt SWAP thất bại."
        rm -f /swapfile
        return 1
    fi

    # Configure auto-enable on reboot in /etc/fstab
    if ! grep -q "/swapfile" /etc/fstab; then
        echo '/swapfile none swap sw 0 0' >> /etc/fstab
    fi

    # Set default swappiness to 10 for servers
    info "Đang thiết lập vm.swappiness mặc định = 10..."
    set_swappiness_value 10

    info "THÀNH CÔNG: Đã kích hoạt ${size} SWAP."
    return 0
}
