#!/usr/bin/env bash

# File Cài đặt Khởi Đầu - Đầu não Hệ thống VPS Manager (One-Click Deploy OS)
# CHỈ CẦN CHẠY MỘT LẦN DUY NHẤT LÚC MỚI MUA VPS.

set -e

# Lấy đường dẫn chuẩn của file thực (Gold Standard for Symlink)
SOURCE="${BASH_SOURCE[0]}"
while [ -h "$SOURCE" ]; do
  DIR="$( cd -P "$( dirname "$SOURCE" )" >/dev/null 2>&1 && pwd )"
  SOURCE="$(readlink "$SOURCE")"
  [[ $SOURCE != /* ]] && SOURCE="$DIR/$SOURCE"
done
DIR="$( cd -P "$( dirname "$SOURCE" )" >/dev/null 2>&1 && pwd )"
export SCRIPT_DIR="$DIR"



# 0. Khai báo Tiện ích & Màu sắc
source "$SCRIPT_DIR/modules/utils.sh"

# Kiểm tra quyền root
if [ "$EUID" -ne 0 ]; then
    error "Bạn phải dùng \`sudo ./install.sh\` để cấp quyền cài Cốt lõi Hệ điều hành!"
fi

# Nạp file môi trường gốc tổng
if [ -f "$SCRIPT_DIR/.env" ]; then
    source "$SCRIPT_DIR/.env"
else
    warn "Chưa thấy file .env chung, sẽ Copy cấu hình chuẩn từ .env.global.example ..."
    cp "$SCRIPT_DIR/.env.global.example" "$SCRIPT_DIR/.env"
    harden_permissions "$SCRIPT_DIR/.env"
    source "$SCRIPT_DIR/.env"
fi

echo -e "${CYAN}================================================================${NC}"
echo -e "${CYAN}    CHÀO MỪNG BẠN ĐẾN VỚI TRÌNH CÀI ĐẶT VPS MANAGER (LARAVEL)   ${NC}"
echo -e "${CYAN}================================================================${NC}"
echo -e ""
echo -e "Trình cài đặt này sẽ tiêm ngầm và lột xác máy chủ Ubuntu của bạn thành"
echo -e "một Pháo Đài Web Server vững chắc. Bao gồm:"
echo -e " 1. Bảo mật Firewall, Fail2ban, Auto Tạo Git Key."
echo -e " 2. Cài Nginx, PHP (FastCGI), Redis, NodeJS LTS, Supervisor."
echo -e " 3. Ráp lõi Database MySQL 8 và kích hoạt Auto-Backup hằng đêm."
echo -e ""
warn "⚠️ Bạn ĐÃ SẴN SÀNG khởi động Trình cài đặt khoảng 3-5 Phút này chứ?"
read -p "Nhấn [ENTER] để tiếp tục, hoặc nhấn [Ctrl+C] để huỷ bỏ..."

echo "--------------------------------------------------------"
for i in {3..1}; do 
    echo -e "${RED}Cốt lõi sẽ được nhúng vào HĐH sau $i giây...${NC}"
    sleep 1
done

echo -e "\n\n${CYAN}>>> [PHASE 1] THỰC THI OS SYSTEM SECURITY Lõi Bảo Mật...${NC}"
source "$SCRIPT_DIR/modules/system-setup.sh"
run_system_setup

echo -e "\n\n${CYAN}>>> [PHASE 2] THỰC THI ENVIRONMENT Sinh Môi Trường Tốc Độ Cao...${NC}"
source "$SCRIPT_DIR/modules/env-setup.sh"
run_env_setup

echo -e "\n\n${CYAN}>>> [PHASE 3] NẠP ENGINE DATABASE Lỗ hổng Trái Tim...${NC}"
source "$SCRIPT_DIR/modules/db-setup.sh"
run_db_setup

echo -e "\n\n${CYAN}>>> [PHASE FINAL] BINDING MENU QUẢN TRỊ GLOBAL...${NC}"

# Tạo 1 link global vps trỏ đến file vps.sh manager
chmod +x "$SCRIPT_DIR/vps.sh"
ln -nfs "$SCRIPT_DIR/vps.sh" "/usr/local/bin/vps"
ln -nfs "$SCRIPT_DIR/vps.sh" "/usr/bin/vps"

echo -e "${GREEN}======================================================================${NC}"
echo -e "${GREEN} BÙM!!! MÁY CHỦ BẠN ĐÃ LỘT XÁC THÀNH CÔNG THÀNH SIÊU MÁY CHỦ LARAVEL!  ${NC}"
echo -e "${GREEN}======================================================================${NC}"
echo -e ""
echo -e "Từ giờ phút này, bạn ở bất cứ thư mục Server nào hằng ngày..."
echo -e "Bạn chỉ cần gõ 3 chữ: ${CYAN}vps${NC} (rồi Enter)"
echo -e "Menu tương tác Thêm Domain / Triển khai Web Tool quản trị sẽ bật lên!"
echo -e ""
echo -e "Chúc bạn Deploy ngàn Đơn Hàng may mắn! 🚀"
