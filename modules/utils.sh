#!/usr/bin/env bash
# modules/utils.sh
# Các hàm tiện ích dùng chung cho Hệ thống VPS Manager

# Màu hiển thị log Terminal
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

info() { echo -e "${GREEN}[INFO] $1${NC}"; }
warn() { echo -e "${YELLOW}[WARN] $1${NC}"; }
error() { 
    echo -e "${RED}[ERROR] $1${NC}"
    return 1 2>/dev/null || exit 1 
}


# Lọc bỏ ký tự nguy hiểm đầu vào
sanitize_input() {
    local input="$1"
    # Chỉ cho phép chữ cái, chữ số, dấu chấm, dấu gạch ngang, gạch dưới
    echo "${input}" | sed 's/[^a-zA-Z0-9._-]//g'
}

# Thắt chặt quyền file cấu hình nhạy cảm (.env)
harden_permissions() {
    local target="$1"
    if [ -f "$target" ]; then
        chmod 600 "$target"
    fi
}

# Wrapper thực thi lệnh MySQL an toàn giấu mật khẩu
# Usage: run_mysql_secure "QUERY"
run_mysql_secure() {
    local query="$1"
    
    # Kiểm tra biến môi trường root pass
    if [ -z "$DB_ROOT_PASSWORD" ]; then
        # Thử load env nếu chưa có
        [ -f "$SCRIPT_DIR/.env" ] && source "$SCRIPT_DIR/.env"
    fi
    
    if [ -z "$DB_ROOT_PASSWORD" ]; then
        error "Không tìm thấy DB_ROOT_PASSWORD. Hãy chạy install.sh trước."
    fi

    local tmp_cnf="/tmp/.vps_mysql_$RANDOM.cnf"
    
    # Tạo cấu hình tạm
    cat > "$tmp_cnf" <<EOF
[client]
user=root
password="${DB_ROOT_PASSWORD}"
EOF
    chmod 600 "$tmp_cnf"
    
    # Thực thi (Không in lỗi pass ra console)
    mysql --defaults-extra-file="$tmp_cnf" -e "$query" 2>/dev/null
    
    # Dọn dẹp
    rm -f "$tmp_cnf"
}
