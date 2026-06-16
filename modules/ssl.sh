#!/usr/bin/env bash
# modules/ssl.sh
# Bộ nạp và quản lý Chứng chỉ SSL Let's Encrypt

# Nạp các sub-module chuyên biệt
load_module "ssl/install.sh" || return 1
load_module "ssl/renew.sh" || return 1

#-----------------------------------------------------------------------------
# Hàm:          run_ssl_manager
# Mô tả:        Giao diện menu quản lý SSL cho một domain cụ thể.
# Biến toàn cục: CYAN, NC, BLUE, GREEN, RED
# Tham số:      $1 - Tên miền chính (Domain)
# Trả về:       Không có (Hoặc trả về 2 nếu quay lại menu chính)
#-----------------------------------------------------------------------------
run_ssl_manager() {
    local domain="$1"
    
    echo -e "${CYAN}==========================================${NC}"
    echo -e "${CYAN}        QUẢN LÝ CHỨNG CHỈ SSL             ${NC}"
    echo -e "${CYAN}==========================================${NC}"
    echo -e " ${BLUE}Tên miền:${NC} ${domain}"
    echo -e " ${GREEN}1.${NC} Cài đặt SSL Mới (Let's Encrypt)"
    echo -e " ${GREEN}2.${NC} Ép gia hạn nạp lại toàn bộ SSL (Renew All)"
    echo -e " ${RED}0.${NC} Quay lại Menu chính"
    echo -e "------------------------------------------"
    local ssl_choice
    read -p "Lựa chọn của bạn: " ssl_choice
 
    case $ssl_choice in
        1) install_ssl "$domain" ;;
        2) renew_ssl_all ;;
        0) return 2 ;;
        *) warn "Lựa chọn không hợp lệ."; run_ssl_manager "$domain" ;;
    esac
}


