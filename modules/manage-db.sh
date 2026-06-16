#!/usr/bin/env bash
# modules/manage-db.sh
# Quản lý Database: Điều phối thay đổi mật khẩu & Cấu hình kết nối Remote

# Nạp các sub-module chuyên biệt
load_module "db/password.sh" || return 1
load_module "db/remote.sh" || return 1

#-----------------------------------------------------------------------------
# Hàm:          run_manage_db
# Mô tả:        Menu điều phối quản trị cơ sở dữ liệu của một website cụ thể.
# Biến toàn cục: CYAN, NC, GREEN, RED
# Tham số:      $1 - Tên miền chính (Domain)
# Trả về:       Không có (Hoặc trả về 2 để quay lại menu chính)
#-----------------------------------------------------------------------------
run_manage_db() {
    local domain="$1"
    
    echo -e "${CYAN}==========================================${NC}"
    echo -e "${CYAN}    QUẢN LÝ DATABASE CHO: ${domain}      ${NC}"
    echo -e "${CYAN}==========================================${NC}"
    echo -e " ${GREEN}1.${NC} Đổi Mật khẩu Database"
    echo -e " ${GREEN}2.${NC} Bật Remote Database (Cho phép kết nối ngoài)"
    echo -e " ${GREEN}3.${NC} Tắt Remote Database (Chỉ nội bộ localhost)"
    echo -e " ${RED}0.${NC} Quay lại Menu chính"
    echo -e "------------------------------------------"
    local db_choice
    read -p "Lựa chọn của bạn: " db_choice

    case $db_choice in
        1) change_db_password "$domain" ;;
        2) enable_remote_db "$domain" ;;
        3) disable_remote_db "$domain" ;;
        0) return 2 ;;
        *) warn "Lựa chọn không hợp lệ."; run_manage_db "$domain" ;;
    esac
}
