#!/usr/bin/env bash

#=============================================================================
# Tiêu đề:        vps.sh (Trình quản lý VPS Multi-Site CLI)
# Mô tả:          File chạy chính điều phối quản lý website, cài đặt SSL, deploy,
#                 cơ sở dữ liệu, quản lý phiên bản PHP/Node.js và giám sát.
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

# 1. Nạp bộ thư viện Tiện ích & Màu sắc
if [ ! -f "$SCRIPT_DIR/modules/utils.sh" ]; then
    echo -e "\033[0;31m[ERROR]\033[0m Không tìm thấy bộ tiện ích (utils.sh) tại: $SCRIPT_DIR/modules/utils.sh"
    exit 1
fi
# shellcheck source=modules/utils.sh
source "$SCRIPT_DIR/modules/utils.sh"


#-----------------------------------------------------------------------------
# Hàm:          reset_env_vars
# Mô tả:        Reset các biến môi trường của site để tránh rò rỉ dữ liệu (leak)
#               giữa các phiên làm việc của các site khác nhau.
# Biến toàn cục: SCRIPT_DIR
# Tham số:      $1 - Tên miền cũ để unset biến cụ thể (tùy chọn)
# Trả về:       Không có
#-----------------------------------------------------------------------------
reset_env_vars() {
    local old_domain="${1:-}"
    
    # Unset các biến môi trường cụ thể nếu có tên miền cũ được chỉ định
    if [ -n "$old_domain" ]; then
        local old_env="$SCRIPT_DIR/sites/.env.$old_domain"
        if [ -f "$old_env" ]; then
            local key
            while IFS='=' read -r key _; do
                [[ "$key" =~ ^[A-Z_][A-Z0-9_]*$ ]] && unset "$key"
            done < <(grep -E '^[A-Z_][A-Z0-9_]*=' "$old_env" 2>/dev/null)
        fi
    fi
    
    # Fallback: dọn dẹp các biến tĩnh phổ biến để đảm bảo an toàn
    unset APP_DOMAIN PHP_VERSION USE_JWT USE_SSR SSR_PORT SSH_KEY_PATH
    unset DB_NAME DB_USER DB_PASSWORD GIT_REPO HEALTH_CHECK_URL
}

#-----------------------------------------------------------------------------
# Hàm:          load_env
# Mô tả:        Nạp cấu hình chung (global) và cấu hình riêng của từng tên miền.
# Biến toàn cục: SCRIPT_DIR
# Tham số:      $1 - Tên miền cần nạp (tùy chọn)
#               $2 - Tham số bỏ qua kiểm tra (ví dụ: --skip-check)
# Trả về:       Không có
#-----------------------------------------------------------------------------
load_env() {
    reset_env_vars
    local domain="${1:-}"
    local skip_check="${2:-}"
    
    # Nạp cấu hình Global
    if [ -f "$SCRIPT_DIR/.env" ]; then
        harden_permissions "$SCRIPT_DIR/.env"
        validate_env_file "$SCRIPT_DIR/.env" && source "$SCRIPT_DIR/.env"
    else
        warn "Không tìm thấy cấu hình .env toàn cục tại $SCRIPT_DIR. Đang dùng tạm cấu hình ví dụ .env.global.example..."
        validate_env_file "$SCRIPT_DIR/.env.global.example" && source "$SCRIPT_DIR/.env.global.example"
    fi

    # Nạp cấu hình riêng của Tên Miền
    if [ -n "$domain" ]; then
        local site_env="$SCRIPT_DIR/sites/.env.$domain"
        if [ -f "$site_env" ]; then
            harden_permissions "$site_env"
            validate_env_file "$site_env" && source "$site_env"
        elif [ "$skip_check" != "--skip-check" ]; then
            error "Không tìm thấy cấu hình riêng của site: $domain (tại sites/.env.$domain)"
        fi
    fi
}

#-----------------------------------------------------------------------------
# Hàm:          show_cli_menu
# Mô tả:        Hiển thị menu tương tác trên Terminal để quản lý VPS.
# Biến toàn cục: CYAN, GREEN, YELLOW, RED, NC
# Tham số:      Không có
# Trả về:       Không có
#-----------------------------------------------------------------------------
show_cli_menu() {
    local choice DOMAIN_PROMPT NEW_DOMAIN_PROMPT
    while true; do
        clear || true
        echo -e "${CYAN}==========================================${NC}"
        echo -e "${CYAN}        VPS MANAGER DASHBOARD             ${NC}"
        echo -e "${CYAN}==========================================${NC}"
        echo -e " ${GREEN}1.${NC} Quản lý Website (Domain, Alias)"
        echo -e " ${GREEN}2.${NC} Quản lý SSL Let's Encrypt"
        echo -e " ${GREEN}3.${NC} Triển khai & Khôi phục (Deploy/Rollback)"
        echo -e " ${GREEN}4.${NC} Quản lý phiên bản PHP & Node.js (Runtime)"
        echo -e " ${GREEN}5.${NC} Quản lý Cơ sở dữ liệu"
        echo -e " ${GREEN}6.${NC} Xem Logs (Realtime)"
        echo -e " ${YELLOW}7.${NC} Cập nhật máy chủ (OS Update)"
        echo -e " ${YELLOW}8.${NC} Quản lý SWAP Memory"
        echo -e " ${RED}0.${NC} Thoát"
        echo -e "------------------------------------------"
        read -p "Nhập lựa chọn (0-8): " choice

        DOMAIN_PROMPT=""
        case $choice in
            1) 
               execute_action "manage-domain"
               ;;
            2) 
               DOMAIN_PROMPT=$(select_site_menu "Quản lý SSL cho domain")
               [ $? -ne 0 ] && continue
               execute_action "ssl" "$DOMAIN_PROMPT" 
               [ $? -eq 2 ] && continue
               ;;
            3) 
               DOMAIN_PROMPT=$(select_site_menu "Chọn domain triển khai/khôi phục")
               [ $? -ne 0 ] && continue
               execute_action "deploy-menu" "$DOMAIN_PROMPT"
               [ $? -eq 2 ] && continue
               ;;
            4) 
               DOMAIN_PROMPT=$(select_site_menu "Chọn domain quản lý PHP/Node.js")
               [ $? -ne 0 ] && continue
               execute_action "runtime" "$DOMAIN_PROMPT"
               [ $? -eq 2 ] && continue
               ;;
            5) 
               DOMAIN_PROMPT=$(select_site_menu "Chọn domain quản lý Database")
               [ $? -ne 0 ] && continue
               execute_action "db" "$DOMAIN_PROMPT" 
               [ $? -eq 2 ] && continue
               ;;
            6) 
               DOMAIN_PROMPT=$(select_site_menu "Chọn domain xem logs")
               [ $? -ne 0 ] && continue
               execute_action "logs" "$DOMAIN_PROMPT" 
               ;;
            7) 
               execute_action "update" 
               ;;
            8) 
               execute_action "manage-swap"
               ;;
            0) exit 0 ;;
            *) warn "Lựa chọn không hợp lệ." ;;
        esac
        echo -e ""
        read -p "Nhấn [Enter] để quay lại Menu..."
    done
}

#-----------------------------------------------------------------------------
# Hàm:          execute_action
# Mô tả:        Điều phối và chạy các lệnh CLI bằng cách nạp module tương ứng.
# Biến toàn cục: SCRIPT_DIR
# Tham số:      $1 - Tên hành động/lệnh cần chạy
#               $2 - Tên miền của website (tùy chọn)
#               $3 - Tham số phụ nâng cao (tùy chọn)
# Trả về:       0 nếu thành công, 1 nếu thất bại
#-----------------------------------------------------------------------------
execute_action() {
    local cmd="$1"
    local domain_arg="${2:-}"
    local extra_arg="${3:-}"
    
    # Kiểm duyệt định dạng tên miền theo tiêu chuẩn RFC 1035 nếu có truyền vào
    if [ -n "$domain_arg" ]; then
        local domain_regex='^([a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?)(\.[a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?)*\.[a-zA-Z]{2,}$'
        if [[ ! "$domain_arg" =~ $domain_regex ]] || [ ${#domain_arg} -gt 253 ]; then
            error "Lỗi: Định dạng tên miền '$domain_arg' không hợp lệ."
            return 1
        fi
    fi
    
    case "$cmd" in
        add-site)
            require_root
            if [ -z "$domain_arg" ]; then error "Cần cung cấp tên miền: ./vps.sh add-site demo.com"; fi
            load_env "$domain_arg" "--skip-check"
            load_module "domain/domain.sh" || return 1
            run_domain_action "add" "$domain_arg"
            ;;
        ssl)
            require_root
            if [ -z "$domain_arg" ]; then error "Cần cung cấp tên miền."; fi
            load_env "$domain_arg"
            load_module "ssl/ssl.sh" || return 1
            run_ssl_manager "$domain_arg"
            ;;
        deploy-menu)
            if [ -z "$domain_arg" ]; then error "Cần cung cấp tên miền."; fi
            load_env "$domain_arg"
            load_module "deploy/deploy.sh" || return 1
            run_deploy_menu "$domain_arg"
            ;;
        remove-site)
            require_root
            if [ -z "$domain_arg" ]; then error "Cần cung cấp tên miền muốn xóa bỏ."; fi
            load_env "$domain_arg"
            load_module "domain/domain.sh" || return 1
            run_domain_action "delete" "$domain_arg"
            ;;
        runtime)
            require_root
            if [ -z "$domain_arg" ]; then error "Cần cung cấp tên miền."; fi
            load_env "$domain_arg"
            load_module "runtime/runtime.sh" || return 1
            run_runtime_manager "$domain_arg"
            ;;
        logs)
            if [ -z "$domain_arg" ]; then error "Cần cung cấp tên miền."; fi
            load_env "$domain_arg"
            load_module "logs/logs.sh" || return 1
            run_logs "$domain_arg"
            ;;

        info)
            if [ -z "$domain_arg" ]; then error "Cần cung cấp tên miền."; fi
            load_env "$domain_arg"
            load_module "domain/domain.sh" || return 1
            run_domain_action "info" "$domain_arg"
            ;;
        db)
            require_root
            if [ -z "$domain_arg" ]; then error "Cần cung cấp tên miền."; fi
            load_env "$domain_arg"
            load_module "db/db.sh" || return 1
            run_db_manager "$domain_arg"
            ;;
        update)
            require_root
            load_env
            load_module "update/update.sh" || return 1
            run_update
            ;;

        rename-domain)
            require_root
            if [ -z "$domain_arg" ] || [ -z "$extra_arg" ]; then 
                error "Cú pháp đúng: ./vps.sh rename-domain domain_cu.com domain_moi.com"
                return 1
            fi
            # Xác thực định dạng tên miền mới
            local domain_regex='^([a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?)(\.([a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?))*\.[a-zA-Z]{2,}$'
            if [[ ! "$extra_arg" =~ $domain_regex ]] || [ ${#extra_arg} -gt 253 ]; then
                error "Tên miền mới '$extra_arg' không đúng định dạng!"
                return 1
            fi
            load_module "domain/domain.sh" || return 1
            run_domain_action "rename" "$domain_arg" "$extra_arg"
            ;;
        add-alias)
            require_root
            if [ -z "$domain_arg" ]; then error "Cú pháp đúng: ./vps.sh add-alias primary.com alias.com"; return 1; fi
            load_env "$domain_arg"
            load_module "domain/domain.sh" || return 1
            run_domain_action "add-alias" "$domain_arg" "$extra_arg"
            ;;
        remove-alias)
            require_root
            if [ -z "$domain_arg" ]; then error "Cú pháp đúng: ./vps.sh remove-alias primary.com alias.com"; return 1; fi
            load_env "$domain_arg"
            load_module "domain/domain.sh" || return 1
            run_domain_action "remove-alias" "$domain_arg" "$extra_arg"
            ;;
        manage-alias)
            require_root
            if [ -z "$domain_arg" ]; then error "Cần cung cấp tên miền."; fi
            load_env "$domain_arg"
            load_module "domain/domain.sh" || return 1
            run_domain_action "manage-alias" "$domain_arg"
            ;;
        manage-swap)
            require_root
            load_module "swap/swap.sh" || return 1
            run_swap_manager
            ;;
        manage-domain)
            require_root
            load_module "domain/domain.sh" || return 1
            run_domain_action "menu"
            ;;
        *)
            error "Lệnh '${cmd}' không tồn tại trên hệ thống."
            ;;
    esac
}

# Quy trình điểm khởi chạy (Entry Point)
if [ $# -eq 0 ]; then
    show_cli_menu
else
    # Chạy lệnh trực tiếp với tối đa 3 tham số đầu vào
    execute_action "$1" "${2:-}" "${3:-}"
fi
