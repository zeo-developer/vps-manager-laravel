#!/usr/bin/env bash

# File chạy chính - VPS Manager (Multi-Site Version)
# Khuyến nghị chạy bằng `sudo ./vps.sh` khi thao tác System/Env/DB

# set -e (Đã gỡ bỏ để duy trì Menu chính khi có lỗi)


# Lấy đường dẫn chuẩn của file thực (Gold Standard for Symlink)
SOURCE="${BASH_SOURCE[0]}"
while [ -h "$SOURCE" ]; do
  DIR="$( cd -P "$( dirname "$SOURCE" )" >/dev/null 2>&1 && pwd )"
  SOURCE="$(readlink "$SOURCE")"
  [[ $SOURCE != /* ]] && SOURCE="$DIR/$SOURCE"
done
DIR="$( cd -P "$( dirname "$SOURCE" )" >/dev/null 2>&1 && pwd )"
export SCRIPT_DIR="$DIR"

# 1. Khai báo Tiện ích & Màu sắc
if [ ! -f "$SCRIPT_DIR/modules/utils.sh" ]; then
    echo -e "\033[0;31m[ERROR]\033[0m Không tìm thấy bộ tiện ích (utils.sh) tại: $SCRIPT_DIR/modules/utils.sh"
    exit 1
fi
source "$SCRIPT_DIR/modules/utils.sh"
require_root() {
    if [ "$EUID" -ne 0 ]; then
        error "Quyền root (sudo) là bắt buộc. Vui lòng thử lại: sudo ./vps.sh"
    fi
}

# Xoá các biến môi trường của Site trước khi nạp Site mới để tránh rò rỉ dữ liệu (Env Leak)
# Nhận domain cũ (tuỳ chọn) để tự động unset biến từ env file đó
reset_env_vars() {
    local old_domain="${1:-}"
    # Nếu có domain cũ, unset tất cả biến được define trong env file của nó
    if [ -n "$old_domain" ]; then
        local old_env="$SCRIPT_DIR/sites/.env.$old_domain"
        if [ -f "$old_env" ]; then
            while IFS='=' read -r key _; do
                [[ "$key" =~ ^[A-Z_][A-Z0-9_]*$ ]] && unset "$key"
            done < <(grep -E '^[A-Z_][A-Z0-9_]*=' "$old_env" 2>/dev/null)
        fi
    fi
    # Fallback: unset danh sách biến cố định đã biết
    unset APP_DOMAIN PHP_VERSION USE_JWT USE_SSR SSR_PORT SSH_KEY_PATH
    unset DB_NAME DB_USER DB_PASSWORD GIT_REPO HEALTH_CHECK_URL
}

# Quản lý Đọc Config (Global & Domain-Specific)
load_env() {
    reset_env_vars
    local domain="${1:-}"
    # Load Global Settings (Telegram mappers, Default PHP...)
    if [ -f "$SCRIPT_DIR/.env" ]; then
        harden_permissions "$SCRIPT_DIR/.env"
        validate_env_file "$SCRIPT_DIR/.env" && source "$SCRIPT_DIR/.env"
    else
        warn "Không tìm thấy .env tại $SCRIPT_DIR. Sử dụng .env.global.example..."
        validate_env_file "$SCRIPT_DIR/.env.global.example" && source "$SCRIPT_DIR/.env.global.example"
    fi

    # Load Domain Settings (nếu có site dc truyền vào)
    if [ -n "$domain" ]; then
        local site_env="$SCRIPT_DIR/sites/.env.$domain"
        if [ -f "$site_env" ]; then
            harden_permissions "$site_env"
            validate_env_file "$site_env" && source "$site_env"
        elif [ "${2:-}" != "--skip-check" ]; then
            error "Không tìm thấy cấu hình cho site: $domain (tại sites/.env.$domain)"
        fi
    fi
}

show_cli_menu() {
    while true; do
        clear || true
        echo -e "${CYAN}==========================================${NC}"
        echo -e "${CYAN}        VPS MANAGER DASHBOARD             ${NC}"
        echo -e "${CYAN}==========================================${NC}"
        echo -e " ${GREEN}1.${NC} Thêm Website"
        echo -e " ${GREEN}2.${NC} Quản lý SSL"
        echo -e " ${GREEN}3.${NC} Triển khai mã nguồn (Zero-Downtime)"
        echo -e " ${GREEN}4.${NC} Khôi phục phiên bản (Rollback)"
        echo -e " ${GREEN}5.${NC} Xóa hoàn toàn Website"
        echo -e " ${GREEN}6.${NC} Xem thông tin Website"
        echo -e " ${GREEN}7.${NC} Thay đổi phiên bản PHP"
        echo -e " ${GREEN}8.${NC} Quản lý Cơ sở dữ liệu"
        echo -e " ${GREEN}9.${NC} Xem Logs (Realtime)"
        echo -e " ${GREEN}10.${NC} Thêm Custom Queue Worker"
        echo -e " ${YELLOW}11.${NC} Cập nhật máy chủ (OS Update)"
        echo -e " ${YELLOW}12.${NC} Giám sát hệ thống (Telegram Monitor)"
        echo -e " ${GREEN}13.${NC} Đổi tên miền Website"
        echo -e " ${GREEN}14.${NC} Quản lý Domain Alias"
        echo -e " ${YELLOW}15.${NC} Quản lý SWAP Memory"
        echo -e " ${RED}0.${NC} Thoát"
        echo -e "------------------------------------------"
        read -p "Nhập lựa chọn (0-15): " choice

        DOMAIN_PROMPT=""
        case $choice in
            1) 
               read -p "Nhập domain mới (vd: demo.com): " DOMAIN_PROMPT
               DOMAIN_PROMPT=$(sanitize_input "$DOMAIN_PROMPT")
               execute_action "add-site" "$DOMAIN_PROMPT" 
               ;;
            2) 
               DOMAIN_PROMPT=$(select_site_menu "Quản lý SSL cho domain")
               [ $? -ne 0 ] && continue
               execute_action "ssl" "$DOMAIN_PROMPT" 
               [ $? -eq 2 ] && continue
               ;;
            3) 
               DOMAIN_PROMPT=$(select_site_menu "Chọn domain triển khai (Deploy)")
               [ $? -ne 0 ] && continue
               
               echo -e "Chọn chế độ triển khai:"
               echo -e " ${GREEN}1.${NC} Zero-Downtime (Mặc định)"
               echo -e " ${YELLOW}2.${NC} Quick Deploy"
               read -p "Lựa chọn (1-2): " deploy_choice
               
               if [ "$deploy_choice" == "2" ]; then
                   execute_action "deploy" "$DOMAIN_PROMPT" "quick"
               else
                   execute_action "deploy" "$DOMAIN_PROMPT" "zdt"
               fi
               ;;
            4) 
               DOMAIN_PROMPT=$(select_site_menu "Chọn domain cần khôi phục (Rollback)")
               [ $? -ne 0 ] && continue
               execute_action "rollback" "$DOMAIN_PROMPT" 
               ;;
            5) 
               DOMAIN_PROMPT=$(select_site_menu "Chọn domain CẦN XÓA")
               [ $? -ne 0 ] && continue
               execute_action "remove-site" "$DOMAIN_PROMPT" 
               ;;
            6) 
               DOMAIN_PROMPT=$(select_site_menu "Chọn domain xem thông tin")
               [ $? -ne 0 ] && continue
               execute_action "info" "$DOMAIN_PROMPT" 
               ;;
            7) 
               DOMAIN_PROMPT=$(select_site_menu "Chọn domain đổi phiên bản PHP")
               [ $? -ne 0 ] && continue
               execute_action "change-php" "$DOMAIN_PROMPT" 
               ;;
            8) 
               DOMAIN_PROMPT=$(select_site_menu "Chọn domain quản lý Database")
               [ $? -ne 0 ] && continue
               execute_action "manage-db" "$DOMAIN_PROMPT" 
               [ $? -eq 2 ] && continue
               ;;
            9) 
               DOMAIN_PROMPT=$(select_site_menu "Chọn domain xem logs")
               [ $? -ne 0 ] && continue
               execute_action "logs" "$DOMAIN_PROMPT" 
               ;;
            10) 
               DOMAIN_PROMPT=$(select_site_menu "Chọn Tên miền Web muốn thêm Queue Worker")
               [ $? -ne 0 ] && continue
               execute_action "add-queue" "$DOMAIN_PROMPT" 
               ;;
            11) execute_action "update" ;;
            12) execute_action "monitor" ;;
            13)
               # Rename Domain: chọn domain cũ từ menu, rồi nhập domain mới
               DOMAIN_PROMPT=$(select_site_menu "Chọn domain CŨ cần đổi")
               [ $? -ne 0 ] && continue
               read -p "Nhập domain MỚI: " NEW_DOMAIN_PROMPT
               NEW_DOMAIN_PROMPT=$(sanitize_input "$NEW_DOMAIN_PROMPT")
               execute_action "rename-domain" "$DOMAIN_PROMPT" "$NEW_DOMAIN_PROMPT"
               ;;
            14)
               DOMAIN_PROMPT=$(select_site_menu "Chọn domain chính quản lý Alias")
               [ $? -ne 0 ] && continue
               execute_action "manage-alias" "$DOMAIN_PROMPT"
               ;;
            15)
               execute_action "manage-swap"
               ;;
            0) exit 0 ;;
            *) warn "Lựa chọn không hợp lệ." ;;
        esac
        echo -e ""
        read -p "Nhấn [Enter] để quay lại Menu..."
    done
}

execute_action() {
    local cmd="$1"
    local domain_arg="${2:-}"
    local extra_arg="${3:-}"
    
    # Kiểm tra tính hợp lệ của định dạng Tên Miền (Nếu có tham số domain)
    if [ -n "$domain_arg" ]; then
        # Regex chặt theo RFC 1035: mỗi label không bắt đầu/kết thúc bằng dấu gạch ngang
        # Không cho phép path traversal (/../), max 253 ký tự
        local domain_regex='^([a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?)(\.[a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?)*\.[a-zA-Z]{2,}$'
        if [[ ! "$domain_arg" =~ $domain_regex ]] || [ ${#domain_arg} -gt 253 ]; then
            error "Lỗi: Định dạng domain '$domain_arg' không hợp lệ."
            return 1
        fi
    fi
    
    case "$cmd" in
        add-site)
            require_root
            if [ -z "$domain_arg" ]; then error "Cần cung cấp tên miền: ./vps.sh add-site demo.com"; fi
            load_env "$domain_arg" "--skip-check"
            source "$SCRIPT_DIR/modules/site.sh"
            run_add_site "$domain_arg"
            ;;
        ssl)
            require_root
            if [ -z "$domain_arg" ]; then error "Cần cung cấp tên miền."; fi
            load_env "$domain_arg"
            source "$SCRIPT_DIR/modules/ssl.sh"
            run_ssl_manager "$domain_arg"
            ;;
        deploy)
            # Không bắt root cứng, để user app build mượt (tuỳ chọn)
            if [ -z "$domain_arg" ]; then error "Cần cung cấp tên miền deploy."; fi
            load_env "$domain_arg"
            source "$SCRIPT_DIR/modules/deploy.sh"
            run_deploy "$extra_arg"
            ;;
        rollback)
            if [ -z "$domain_arg" ]; then error "Cần cung cấp tên miền cần rollback."; fi
            load_env "$domain_arg"
            source "$SCRIPT_DIR/modules/deploy.sh"
            run_rollback "$domain_arg"
            ;;
        remove-site)
            require_root
            if [ -z "$domain_arg" ]; then error "Cần cung cấp tên miền để XÓA."; fi
            load_env "$domain_arg"
            source "$SCRIPT_DIR/modules/remove-site.sh"
            run_remove_site "$domain_arg"
            ;;
        change-php)
            require_root
            if [ -z "$domain_arg" ]; then error "Cần cung cấp tên miền."; fi
            load_env "$domain_arg"
            source "$SCRIPT_DIR/modules/php-version.sh"
            run_change_php "$domain_arg"
            ;;
        logs)
            if [ -z "$domain_arg" ]; then error "Cần cung cấp tên miền."; fi
            load_env "$domain_arg"
            source "$SCRIPT_DIR/modules/logs.sh"
            run_logs "$domain_arg"
            ;;
        add-queue)
            require_root
            if [ -z "$domain_arg" ]; then error "Cần cung cấp tên miền."; fi
            load_env "$domain_arg"
            source "$SCRIPT_DIR/modules/queue.sh"
            run_add_queue "$domain_arg"
            ;;
        info)
            if [ -z "$domain_arg" ]; then error "Cần cung cấp tên miền."; fi
            load_env "$domain_arg"
            source "$SCRIPT_DIR/modules/info.sh"
            run_site_info "$domain_arg"
            ;;
        manage-db)
            require_root
            if [ -z "$domain_arg" ]; then error "Cần cung cấp tên miền."; fi
            load_env "$domain_arg"
            source "$SCRIPT_DIR/modules/manage-db.sh"
            run_manage_db "$domain_arg"
            ;;
        update)
            require_root
            load_env
            source "$SCRIPT_DIR/modules/update.sh"
            run_update
            ;;
        monitor)
            load_env
            source "$SCRIPT_DIR/modules/monitor.sh"
            run_monitor
            ;;
        rename-domain)
            require_root
            if [ -z "$domain_arg" ]; then error "Cần cụ pháp: ./vps.sh rename-domain old.com new.com"; return 1; fi
            if [ -z "$extra_arg" ]; then error "Cần cự pháp: ./vps.sh rename-domain old.com new.com"; return 1; fi
            # Validate cả 2 domain
            local domain_regex='^([a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?)(\.([a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?))*\.[a-zA-Z]{2,}$'
            if [[ ! "$extra_arg" =~ $domain_regex ]] || [ ${#extra_arg} -gt 253 ]; then
                error "Tên miền mới '$extra_arg' bị sai định dạng!"
                return 1
            fi
            source "$SCRIPT_DIR/modules/rename-domain.sh"
            run_rename_domain "$domain_arg" "$extra_arg"
            ;;
        add-alias)
            require_root
            if [ -z "$domain_arg" ]; then error "Cần cụ pháp: ./vps.sh add-alias primary.com alias.com"; return 1; fi
            load_env "$domain_arg"
            source "$SCRIPT_DIR/modules/alias.sh"
            if [ -n "$extra_arg" ]; then
                # CLI mode: ./vps.sh add-alias primary.com alias.com
                run_add_alias "$domain_arg" "$extra_arg"
            else
                # Interactive mode: nhập alias từ bàn phím
                run_manage_alias "$domain_arg"
            fi
            ;;
        remove-alias)
            require_root
            if [ -z "$domain_arg" ]; then error "Cần cự pháp: ./vps.sh remove-alias primary.com alias.com"; return 1; fi
            load_env "$domain_arg"
            source "$SCRIPT_DIR/modules/alias.sh"
            if [ -n "$extra_arg" ]; then
                # CLI mode: ./vps.sh remove-alias primary.com alias.com
                run_remove_alias "$domain_arg" "$extra_arg"
            else
                # Interactive mode: mục 2 trong manage_alias
                run_manage_alias "$domain_arg"
            fi
            ;;
        manage-alias)
            require_root
            if [ -z "$domain_arg" ]; then error "Cần cung cấp tên miền."; fi
            load_env "$domain_arg"
            source "$SCRIPT_DIR/modules/alias.sh"
            run_manage_alias "$domain_arg"
            ;;
        manage-swap)
            require_root
            source "$SCRIPT_DIR/modules/swap.sh"
            run_swap_manager
            ;;
        *)
            error "Lệnh '${cmd}' không tồn tại."
            ;;
    esac
}

# Entry Point Workflow
if [ $# -eq 0 ]; then
    show_cli_menu
else
    # Gõ thẳng command (hỗ trợ đến 4 tham số)
    execute_action "$1" "${2:-}" "${3:-}"
fi
