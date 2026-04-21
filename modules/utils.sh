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
    cat > "$tmp_cnf" <<'EOF'
[client]
user=root
password="${DB_ROOT_PASSWORD}"
EOF
    # Inject giá trị thực của biến vào file (Cách này an toàn hơn <<EOF trực tiếp khi có ký tự lạ)
    sed -i "s/\${DB_ROOT_PASSWORD}/${DB_ROOT_PASSWORD}/g" "$tmp_cnf"
    chmod 600 "$tmp_cnf"
    
    # Thực thi (Dùng sudo để chắc chắn có quyền truy cập socket)
    sudo mysql --defaults-extra-file="$tmp_cnf" -e "$query"

    
    # Dọn dẹp
    rm -f "$tmp_cnf"
}

# -------------------------------------------------------------------------
# CÁC HÀM QUẢN LÝ DANH SÁCH SITE
# -------------------------------------------------------------------------

# Trích xuất danh sách domain từ các file .env trong thư mục sites/
get_site_list() {
    local site_dir="${SCRIPT_DIR}/sites"
    if [ ! -d "$site_dir" ]; then
        return
    fi
    # Tìm các file .env.xxx và lấy phần xxx (tên miền)
    ls "${site_dir}"/.env.* 2>/dev/null | sed "s|${site_dir}/.env.||g"
}

# Hiển thị thực đơn chọn Website và trả về domain được chọn
select_site_menu() {
    local header="$1"
    local sites=($(get_site_list))
    
    if [ ${#sites[@]} -eq 0 ]; then
        error "Hiện chưa có Website nào được tạo! Vui lòng chọn mục '1. Thêm Website' trước." >&2
        echo -e "" >&2
        read -p "Nhấn [Enter] để tiếp tục..." >&2
        return 1
    fi

    echo -e "${CYAN}------------------------------------------${NC}" >&2
    echo -e "${YELLOW} ${header:-DANH SÁCH WEBSITE ĐANG CÓ:}${NC}" >&2
    echo -e "${CYAN}------------------------------------------${NC}" >&2
    
    local i=1
    for site in "${sites[@]}"; do
        echo -e " ${GREEN}$i.${NC} $site" >&2
        i=$((i + 1))
    done
    echo -e " ${RED}0.${NC} Quay lại Menu chính" >&2
    echo -e "${CYAN}------------------------------------------${NC}" >&2

    local choice
    while true; do
        read -p "Chọn Website (1-$((i-1))): " choice >&2
        if [[ "$choice" == "0" ]]; then
            echo "" >&2
            return 1
        fi
        if [[ "$choice" =~ ^[0-9]+$ ]] && [ "$choice" -ge 1 ] && [ "$choice" -lt "$i" ]; then
            local selected_site="${sites[$((choice-1))]}"
            # Trả về kết quả cho stdout để subshell bắt được
            echo "$selected_site"
            return 0
        fi
        warn "Lựa chọn không hợp lệ. Vui lòng chọn lại!" >&2
    done
}
