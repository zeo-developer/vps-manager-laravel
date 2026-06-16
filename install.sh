#!/usr/bin/env bash

#=============================================================================
# Tiêu đề:        install.sh (Trình cài đặt hệ thống VPS Manager)
# Mô tả:          File điều phối chính của quá trình cài đặt hệ thống VPS Manager.
#                 Tải và thực hiện tuần tự các bước cài đặt hệ thống.
# Tác giả:        Zeo
# Yêu cầu:        Bash 4+, Hệ điều hành Ubuntu/Debian Linux, quyền root.
#=============================================================================

# Tìm đường dẫn tuyệt đối của thư mục chứa script để chạy chính xác (ngay cả khi gọi qua Symlink)
SOURCE="${BASH_SOURCE[0]}"
while [ -h "$SOURCE" ]; do
  DIR="$( cd -P "$( dirname "$SOURCE" )" >/dev/null 2>&1 && pwd )"
  SOURCE="$(readlink "$SOURCE")"
  [[ $SOURCE != /* ]] && SOURCE="$DIR/$SOURCE"
done
DIR="$( cd -P "$( dirname "$SOURCE" )" >/dev/null 2>&1 && pwd )"
export SCRIPT_DIR="$DIR"

# Nạp bộ tiện ích dùng chung
source "$SCRIPT_DIR/modules/utils.sh"

# 1. Khởi tạo môi trường
load_module "install/init.sh" || exit 1
run_install_init

# 2. Hiển thị menu giới thiệu và đếm ngược
load_module "install/menu.sh" || exit 1
run_install_menu

# 3. Chạy các Phase cài đặt
echo -e "\n\n${CYAN}>>> [PHASE 1] Đang cấu hình hệ thống & Bảo mật...${NC}"
load_module "install/system.sh" || exit 1
run_system_setup

echo -e "\n\n${CYAN}>>> [PHASE 2] Đang cài đặt Web Stack...${NC}"
load_module "install/env.sh" || exit 1
run_env_setup

echo -e "\n\n${CYAN}>>> [PHASE 3] Đang cấu hình Database...${NC}"
load_module "install/db.sh" || exit 1
run_db_setup

# 4. Hoàn tất cài đặt
load_module "install/finalize.sh" || exit 1
run_install_finalize

