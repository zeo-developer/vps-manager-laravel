#!/usr/bin/env bash
# modules/utils.sh
# Các hàm tiện ích dùng chung cho Hệ thống VPS Manager
# Lưu ý: Không đặt 'set -uo pipefail' trong file này vì nó là library (source'd),
# việc đặt set option trong sourced file sẽ contaminate toàn bộ parent shell.

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

# Tạo định danh an toàn (Safe Domain) cho các dịch vụ hệ thống (Supervisor, DB...)
get_safe_domain() {
    local domain="$1"
    # Chuyển site.com -> site_com, my-site.com -> my_site_com
    echo "$domain" | sed 's/[^a-zA-Z0-9]/_/g'
}

# Thắt chặt quyền file cấu hình nhạy cảm (.env)
harden_permissions() {
    local target="$1"
    if [ -f "$target" ]; then
        chmod 600 "$target"
    fi
}

# Kiểm tra file .env không chứa lệnh shell nguy hiểm trước khi source
# Usage: validate_env_file "/path/to/.env" && source "/path/to/.env"
validate_env_file() {
    local file="$1"
    if [ ! -f "$file" ]; then
        error "File cấu hình không tồn tại: $file"
        return 1
    fi
    # Từ chối nếu có cú pháp shell nguy hiểm ngoài comment và assignment
    # Cho phép: VAR=value, VAR="value", #comment, dòng trống
    if grep -qvE '^\s*(#.*)?$|^[A-Za-z_][A-Za-z0-9_]*=.*$' "$file" 2>/dev/null; then
        error "File '$file' chứa cú pháp không hợp lệ (chỉ cho phép KEY=VALUE hoặc comment)."
        return 1
    fi
    # Chặn thêm subshell và backtick dù nằm trong value (Bỏ qua các dòng comment)
    if grep -vE '^\s*#' "$file" | grep -qE '\$\(|`' 2>/dev/null; then
        error "File '$file' chứa lệnh nhúng nguy hiểm (\$() hoặc backtick). Từ chối nạp."
        return 1
    fi
    return 0
}

# Wrapper thực thi lệnh MySQL an toàn giấu mật khẩu
# Usage: run_mysql_secure "QUERY"
run_mysql_secure() {
    local query="$1"

    # Kiểm tra biến môi trường root pass
    if [ -z "${DB_ROOT_PASSWORD:-}" ]; then
        # Thử load env nếu chưa có
        [ -f "$SCRIPT_DIR/.env" ] && source "$SCRIPT_DIR/.env"
    fi

    if [ -z "${DB_ROOT_PASSWORD:-}" ]; then
        error "Không tìm thấy DB_ROOT_PASSWORD. Hãy chạy install.sh trước."
        return 1
    fi

    # Tạo file tạm an toàn: mktemp sinh tên ngẫu nhiên mạnh hơn $RANDOM
    local tmp_cnf
    tmp_cnf=$(mktemp /tmp/.vps_mysql_XXXXXX.cnf)
    # chmod 600 TRƯỚC khi ghi nội dung để tránh race condition TOCTOU
    chmod 600 "$tmp_cnf"

    # Dùng printf thay vì sed để tránh injection khi password chứa ký tự đặc biệt (/, &, \)
    printf '[client]\nuser=root\npassword=%s\n' "$DB_ROOT_PASSWORD" > "$tmp_cnf"

    # Thực thi (Dùng sudo để chắc chắn có quyền truy cập socket)
    sudo mysql --defaults-extra-file="$tmp_cnf" -e "$query"
    local _exit_code=$?

    # Dọn dẹp — luôn xóa dù lệnh thành công hay thất bại
    rm -f "$tmp_cnf"
    return $_exit_code
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
