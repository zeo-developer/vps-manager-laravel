#!/usr/bin/env bash
# modules/deploy/deploy.sh
# Bộ điều phối quy trình Deploy Zero-Downtime & Rollback

# Nạp các sub-module chuyên biệt
load_module "deploy/main.sh" || return 1
load_module "deploy/rollback.sh" || return 1

#-----------------------------------------------------------------------------
# Hàm:          run_deploy_menu
# Mô tả:        Giao diện menu phụ để chọn Deploy hoặc Rollback cho một domain.
# Biến toàn cục: CYAN, NC, BLUE, GREEN, RED
# Tham số:      $1 - Tên miền chính (Domain)
# Trả về:       Không có (Hoặc trả về 2 để quay lại menu chính)
#-----------------------------------------------------------------------------
run_deploy_menu() {
    local domain="$1"
    while true; do
        echo -e "${CYAN}==========================================${NC}"
        echo -e "${CYAN}      TRIỂN KHAI & KHÔI PHỤC MÃ NGUỒN     ${NC}"
        echo -e "${CYAN}==========================================${NC}"
        echo -e " ${BLUE}Tên miền:${NC} ${domain}"
        echo -e " ${GREEN}1.${NC} Triển khai mã nguồn (Zero-Downtime)"
        echo -e " ${GREEN}2.${NC} Khôi phục phiên bản (Rollback)"
        echo -e " ${RED}0.${NC} Quay lại Menu chính"
        echo -e "------------------------------------------"
        local choice
        read -p "Lựa chọn của bạn (0-2): " choice

        case "$choice" in
            1) run_deploy ;;
            2) run_rollback ;;
            0) return 2 ;;
            *) warn "Lựa chọn không hợp lệ." ;;
        esac
        echo -e ""
        read -p "Nhấn [Enter] để tiếp tục..."
    done
}
