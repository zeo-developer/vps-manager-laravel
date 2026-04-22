#!/usr/bin/env bash
# modules/swap.sh
# Quản lý bộ nhớ ảo SWAP cho server

show_swap_status() {
    echo -e "${CYAN}------------------------------------------${NC}"
    echo -e " ${BLUE}Trạng thái SWAP hiện tại:${NC}"
    echo -e "${CYAN}------------------------------------------${NC}"
    swapon --show
    echo ""
    free -h
    echo -e "${CYAN}------------------------------------------${NC}"
    echo -ne " ${BLUE}Chỉ số Swappiness hiện tại:${NC} "
    cat /proc/sys/vm/swappiness
}

create_swap() {
    if [ -f /swapfile ]; then
        error "Lỗi: File /swapfile đã tồn tại trên hệ thống."
        return 1
    fi

    echo -e "Chọn dung lượng SWAP muốn tạo:"
    echo -e " ${GREEN}1.${NC} 1GB"
    echo -e " ${GREEN}2.${NC} 2GB"
    echo -e " ${GREEN}3.${NC} 4GB"
    echo -e " ${GREEN}4.${NC} Nhập dung lượng tùy chỉnh (ví dụ: 8G)"
    read -p "Lựa chọn: " choice

    local size
    case $choice in
        1) size="1G" ;;
        2) size="2G" ;;
        3) size="4G" ;;
        4) read -p "Nhập dung lượng (vd: 512M, 8G): " size ;;
        *) error "Lựa chọn không hợp lệ."; return 1 ;;
    esac

    info "Đang khởi tạo file SWAP dung lượng ${size}..."
    
    # Tạo file swap (dùng fallocate nhanh hơn dd)
    fallocate -l "$size" /swapfile || dd if=/dev/zero of=/swapfile bs=1M count=$(( $(echo $size | sed 's/[^0-9]//g') * 1024 ))
    
    chmod 600 /swapfile
    mkswap /swapfile
    swapon /swapfile

    # Cấu hình tự động kích hoạt khi reboot
    if ! grep -q "/swapfile" /etc/fstab; then
        echo '/swapfile none swap sw 0 0' >> /etc/fstab
    fi

    info "Xử lý Swappiness..."
    set_swappiness 10

    info "THÀNH CÔNG: Đã kích hoạt ${size} SWAP."
}

remove_swap() {
    if [ ! -f /swapfile ]; then
        error "Lỗi: Hệ thống không có file /swapfile."
        return 1
    fi

    warn "Xác nhận xóa hoàn toàn SWAP và file /swapfile? (y/n)"
    read -p "Xác nhận: " confirm
    if [[ "$confirm" =~ ^[Yy]$ ]]; then
        info "Đang gỡ bỏ SWAP..."
        swapoff /swapfile
        rm -f /swapfile
        sed -i '\/swapfile/d' /etc/fstab
        info "Đã dọn dẹp cấu hình SWAP."
    else
        info "Đã hủy thao tác."
    fi
}

set_swappiness() {
    local val="${1:-10}"
    info "Thiết lập vm.swappiness = $val..."
    sysctl vm.swappiness="$val"
    
    if grep -q "vm.swappiness" /etc/sysctl.conf; then
        sed -i "s/^vm.swappiness=.*/vm.swappiness=$val/" /etc/sysctl.conf
    else
        echo "vm.swappiness=$val" >> /etc/sysctl.conf
    fi
}

run_swap_manager() {
    while true; do
        echo -e "${CYAN}==========================================${NC}"
        echo -e "${CYAN}         SWAP MEMORY MANAGER              ${NC}"
        echo -e "${CYAN}==========================================${NC}"
        show_swap_status
        echo -e "------------------------------------------"
        echo -e " ${GREEN}1.${NC} Tạo mới SWAP"
        echo -e " ${GREEN}2.${NC} Xóa bỏ SWAP hiện tại"
        echo -e " ${GREEN}3.${NC} Tối ưu Swappiness (về 10)"
        echo -e " ${RED}0.${NC} Quay lại Menu chính"
        echo -e "------------------------------------------"
        read -p "Lựa chọn: " swap_choice

        case $swap_choice in
            1) create_swap ;;
            2) remove_swap ;;
            3) set_swappiness 10 ;;
            0) break ;;
            *) warn "Lựa chọn không hợp lệ." ;;
        esac
        echo -e "\nNhấn phím bất kỳ để tiếp tục..."
        read -n 1
    done
}
