#!/usr/bin/env bash
# modules/swap.sh
# System SWAP Memory Management module for Ubuntu/Debian.

#-----------------------------------------------------------------------------
# Function:     show_swap_status
# Description:  Displays the current active SWAP configuration, RAM usage,
#               and system swappiness value.
# Globals:      CYAN, NC, BLUE
# Arguments:    None
# Returns:      None
#-----------------------------------------------------------------------------
show_swap_status() {
    echo -e "${CYAN}------------------------------------------${NC}"
    echo -e " ${BLUE}Trạng thái SWAP hiện tại:${NC}"
    echo -e "${CYAN}------------------------------------------${NC}"
    if command -v swapon &> /dev/null; then
        swapon --show
    else
        echo "Lệnh swapon không tồn tại."
    fi
    echo ""
    free -h
    echo -e "${CYAN}------------------------------------------${NC}"
    echo -ne " ${BLUE}Chỉ số Swappiness hiện tại:${NC} "
    if [ -f /proc/sys/vm/swappiness ]; then
        cat /proc/sys/vm/swappiness
    else
        echo "N/A"
    fi
}

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
    # df output block size is in KB
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
    
    # Try fallocate first as it is much faster than dd. Fallback to dd if filesystem doesn't support fallocate (e.g. Btrfs/ZFS)
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

#-----------------------------------------------------------------------------
# Function:     set_swappiness_value
# Description:  Helper function to modify vm.swappiness settings persistently.
# Globals:      None
# Arguments:    $1 - Value (0-100)
# Returns:      None
#-----------------------------------------------------------------------------
set_swappiness_value() {
    local val="${1:-10}"
    sysctl vm.swappiness="$val"
    
    if grep -q "vm.swappiness" /etc/sysctl.conf; then
        sed -i "s/^vm.swappiness=.*/vm.swappiness=$val/" /etc/sysctl.conf
    else
        echo "vm.swappiness=$val" >> /etc/sysctl.conf
    fi
}

#-----------------------------------------------------------------------------
# Function:     configure_swappiness
# Description:  Prompts user for a custom swappiness value and applies it.
# Globals:      None
# Arguments:    None
# Returns:      0 on success, 1 on failure
#-----------------------------------------------------------------------------
configure_swappiness() {
    local val
    read -p "Nhập chỉ số swappiness muốn thiết lập (0-100, khuyên dùng: 10): " val
    val=$(sanitize_input "$val")
    
    if [[ ! "$val" =~ ^[0-9]+$ ]] || [ "$val" -lt 0 ] || [ "$val" -gt 100 ]; then
        error "Chỉ số không hợp lệ. Phải là số nguyên từ 0 đến 100."
        return 1
    fi

    info "Đang cấu hình chỉ số swappiness về $val..."
    set_swappiness_value "$val"
    info "Đã cập nhật swappiness thành công."
    return 0
}

#-----------------------------------------------------------------------------
# Function:     run_swap_manager
# Description:  Main menu coordinator for SWAP Memory Management.
# Globals:      CYAN, NC, GREEN, RED
# Arguments:    None
# Returns:      None
#-----------------------------------------------------------------------------
run_swap_manager() {
    while true; do
        clear || true
        echo -e "${CYAN}==========================================${NC}"
        echo -e "${CYAN}         QUẢN LÝ BỘ NHỚ ẢO (SWAP)          ${NC}"
        echo -e "${CYAN}==========================================${NC}"
        show_swap_status
        echo -e "------------------------------------------"
        echo -e " ${GREEN}1.${NC} Tạo mới SWAP"
        echo -e " ${GREEN}2.${NC} Xóa bỏ SWAP hiện tại"
        echo -e " ${GREEN}3.${NC} Cấu hình chỉ số Swappiness tùy chỉnh"
        echo -e " ${RED}0.${NC} Quay lại Menu chính"
        echo -e "------------------------------------------"
        local swap_choice
        read -p "Lựa chọn (0-3): " swap_choice

        case "$swap_choice" in
            1) 
                create_swap 
                ;;
            2) 
                remove_swap 
                ;;
            3) 
                configure_swappiness 
                ;;
            0) 
                break 
                ;;
            *) 
                warn "Lựa chọn không hợp lệ." 
                ;;
        esac
        echo -e "\nNhấn phím bất kỳ để tiếp tục..."
        read -n 1
    done
}
