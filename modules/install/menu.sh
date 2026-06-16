#!/usr/bin/env bash
# modules/install/menu.sh
# Giao diện chào mừng và bộ đếm ngược trước khi cài đặt

#-----------------------------------------------------------------------------
# Hàm:          run_install_menu
# Mô tả:        Hiển thị danh sách các thành phần cài đặt và đếm ngược 3 giây.
# Biến toàn cục: CYAN, NC, YELLOW, RED, WARN
# Tham số:      Không có
# Trả về:       Không có
#-----------------------------------------------------------------------------
run_install_menu() {
    echo -e "${CYAN}================================================================${NC}"
    echo -e "${CYAN}             TRÌNH CÀI ĐẶT VPS MANAGER (LARAVEL)                ${NC}"
    echo -e "${CYAN}================================================================${NC}"
    echo -e ""
    echo -e "Trình cài đặt sẽ tự động cấu hình máy chủ Ubuntu của bạn, bao gồm:"
    echo -e " 1. Bảo mật: Tường lửa (Firewall), Fail2ban, SSH Security."
    echo -e " 2. Web Stack: Nginx, PHP-FPM, Redis, Node.js, Supervisor."
    echo -e " 3. Database: MySQL 8 & Tự động sao lưu (Auto-Backup)."
    echo -e ""
    warn "Thời gian cài đặt dự kiến: 3-5 phút."
    read -p "Nhấn [ENTER] để bắt đầu cài đặt, hoặc [Ctrl+C] để hủy bỏ..."

    echo "--------------------------------------------------------"
    local i
    for i in {3..1}; do 
        echo -e "${RED}Tiến trình cài đặt sẽ bắt đầu sau $i giây...${NC}"
        sleep 1
    done
}
