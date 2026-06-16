#!/usr/bin/env bash
# modules/swap.sh
# Bộ nạp và quản lý bộ nhớ ảo SWAP (Status, Create, Delete, Swappiness)

# Nạp các sub-module chuyên biệt
load_module "swap/status.sh" || return 1
load_module "swap/create.sh" || return 1
load_module "swap/delete.sh" || return 1
load_module "swap/swappiness.sh" || return 1

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

