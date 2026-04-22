#!/usr/bin/env bash

# File Cài đặt Khởi Đầu - Đầu não Hệ thống VPS Manager (One-Click Deploy OS)
# CHỈ CẦN CHẠY MỘT LẦN DUY NHẤT LÚC MỚI MUA VPS.

# set -e (Tạm thời bỏ để theo dõi lỗi cài đặt)


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
    error "Yêu cầu quyền root. Vui lòng chạy: sudo ./install.sh"
fi

# Nạp file môi trường gốc tổng
if [ -f "$SCRIPT_DIR/.env" ]; then
    source "$SCRIPT_DIR/.env"
else
    warn "Không tìm thấy .env. Khởi tạo từ .env.global.example..."
    cp "$SCRIPT_DIR/.env.global.example" "$SCRIPT_DIR/.env"
    harden_permissions "$SCRIPT_DIR/.env"
    source "$SCRIPT_DIR/.env"
fi

# Tự động sinh mật khẩu MySQL Root nếu chưa có hoặc đang dùng mặc định
if [ -z "$DB_ROOT_PASSWORD" ] || [ "$DB_ROOT_PASSWORD" = "root_password_secure" ]; then
    info "Khởi tạo mật khẩu ngẫu nhiên MySQL root..."
    NEW_DB_PASS=$(tr -dc A-Za-z0-9 </dev/urandom | head -c 24)
    # Fix cho file .env (Dùng dấu ngoặc kép bọc pass dẫu có ký tự lạ)
    sed -i "s/^DB_ROOT_PASSWORD=.*/DB_ROOT_PASSWORD=\"${NEW_DB_PASS}\"/" "$SCRIPT_DIR/.env"
    export DB_ROOT_PASSWORD="$NEW_DB_PASS"
    info "Mật khẩu MySQL root: [ ${NEW_DB_PASS} ]"
    info "(Đã lưu vào file .env)"
    info "--------------------------------------------------------"
fi


echo -e "${CYAN}================================================================${NC}"
echo -e "${CYAN}             VPS MANAGER INSTALLER (LARAVEL)                    ${NC}"
echo -e "${CYAN}================================================================${NC}"
echo -e ""
echo -e "Trình cài đặt sẽ thiết lập máy chủ Ubuntu của bạn, bao gồm:"
echo -e " 1. Security: Firewall, Fail2ban, SSH Security."
echo -e " 2. Web Stack: Nginx, PHP-FPM, Redis, Node.js, Supervisor."
echo -e " 3. Database: MySQL 8 & Auto-Backup."
echo -e ""
warn "Tiến trình cài đặt dự kiến: 3-5 phút."
read -p "Nhấn [ENTER] để tiếp tục, hoặc [Ctrl+C] để hủy..."

echo "--------------------------------------------------------"
for i in {3..1}; do 
    echo -e "${RED}Bắt đầu sau $i giây...${NC}"
    sleep 1
done

echo -e "\n\n${CYAN}>>> [PHASE 1] Cấu hình hệ thống & Bảo mật...${NC}"
source "$SCRIPT_DIR/modules/system-setup.sh"
run_system_setup

echo -e "\n\n${CYAN}>>> [PHASE 2] Cài đặt Web Stack...${NC}"
source "$SCRIPT_DIR/modules/env-setup.sh"
run_env_setup

echo -e "\n\n${CYAN}>>> [PHASE 3] Cấu hình Database...${NC}"
source "$SCRIPT_DIR/modules/db-setup.sh"
run_db_setup

echo -e "\n\n${CYAN}>>> [PHASE FINAL] Hoàn tất cấu hình...${NC}"

# Tạo 1 link global vps trỏ đến file vps.sh manager
chmod +x "$SCRIPT_DIR/vps.sh"
ln -nfs "$SCRIPT_DIR/vps.sh" "/usr/local/bin/vps"
ln -nfs "$SCRIPT_DIR/vps.sh" "/usr/bin/vps"

echo -e "${GREEN}======================================================================${NC}"
echo -e "${GREEN}                CÀI ĐẶT HOÀN TẤT THÀNH CÔNG!                          ${NC}"
echo -e "${GREEN}======================================================================${NC}"
echo -e ""
echo -e "Sử dụng lệnh: ${CYAN}vps${NC} để truy cập bảng điều khiển."
echo -e ""
