#!/usr/bin/env bash
# modules/runtime.sh
# Bộ điều phối quản lý phiên bản PHP & Node.js (Runtime) cho các website

# Nạp các sub-module chuyên biệt
load_module "runtime/php.sh" || return 1
load_module "runtime/node.sh" || return 1

#-----------------------------------------------------------------------------
# Hàm:          run_runtime_manager
# Mô tả:        Hiển thị menu quản trị phiên bản PHP & Node.js cho một website cụ thể.
# Biến toàn cục: CYAN, NC, BLUE, GREEN, RED
# Tham số:      $1 - Tên miền chính (Domain)
# Trả về:       Không có (Hoặc trả về 2 để quay lại menu chính)
#-----------------------------------------------------------------------------
run_runtime_manager() {
    local domain="$1"
    
    while true; do
        echo -e "${CYAN}==========================================${NC}"
        echo -e "${CYAN}    QUẢN LÝ PHIÊN BẢN RUNTIME (PHP/NODE)  ${NC}"
        echo -e "${CYAN}==========================================${NC}"
        echo -e " ${BLUE}Tên miền:${NC} ${domain}"
        echo -e " ${GREEN}1.${NC} Quản lý phiên bản PHP"
        echo -e " ${GREEN}2.${NC} Quản lý phiên bản Node.js"
        echo -e " ${RED}0.${NC} Quay lại Menu chính"
        echo -e "------------------------------------------"
        local choice
        read -p "Nhập lựa chọn (0-2): " choice

        case "$choice" in
            1) run_change_php "$domain" ;;
            2) run_node_manager "$domain" ;;
            0) return 2 ;;
            *) warn "Lựa chọn không hợp lệ." ;;
        esac
        echo -e ""
        read -p "Nhấn [Enter] để quay lại..."
    done
}
