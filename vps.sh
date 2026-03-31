#!/usr/bin/env bash

# File chạy chính - VPS Manager (Multi-Site Version)
# Khuyến nghị chạy bằng `sudo ./vps.sh` khi thao tác System/Env/DB

set -e

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)"
export SCRIPT_DIR="$DIR"

# 1. Khai báo Tiện ích & Màu sắc
source "$SCRIPT_DIR/modules/utils.sh"

require_root() {
    if [ "$EUID" -ne 0 ]; then
        error "Tính năng này cần quyền root (sudo). Vui lòng thử lại: sudo ./vps.sh"
    fi
}

# Quản lý Đọc Config (Global & Domain-Specific)
load_env() {
    local domain="$1"
    # Load Global Settings (Telegram mappers, Default PHP...)
    if [ -f "$SCRIPT_DIR/.env" ]; then
        harden_permissions "$SCRIPT_DIR/.env"
        source "$SCRIPT_DIR/.env"
    else
        warn "Không tìm thấy cấu hình chung .env tại $SCRIPT_DIR, dùng .env.global.example..."
        source "$SCRIPT_DIR/.env.global.example"
    fi

    # Load Domain Settings (nếu có site dc truyền vào)
    if [ ! -z "$domain" ]; then
        local site_env="$SCRIPT_DIR/sites/.env.$domain"
        if [ -f "$site_env" ]; then
            harden_permissions "$site_env"
            source "$site_env"
        elif [ "$2" != "--skip-check" ]; then
            error "Không tìm thấy cấu hình cho site: $domain (tại sites/.env.$domain)"
        fi
    fi
}

show_cli_menu() {
    while true; do
        clear || true
        echo -e "${CYAN}==========================================${NC}"
        echo -e "${CYAN}     VPS MANAGER CLI - PRO EDITION        ${NC}"
        echo -e "${CYAN}==========================================${NC}"
        echo -e " ${GREEN}1.${NC} Thêm Website (Add Site)"
        echo -e " ${GREEN}2.${NC} Cài đặt / Quản lý SSL (SSL Manager)"
        echo -e " ${GREEN}3.${NC} Triển khai Mã nguồn (Deploy Zero-Downtime)"
        echo -e " ${GREEN}4.${NC} Khôi phục Khẩn cấp (Rollback Release)"
        echo -e " ${GREEN}5.${NC} Xóa toàn bộ Website (Remove Site)"
        echo -e " ${GREEN}6.${NC} Xem Thông tin Website (Site Info)"
        echo -e " ${GREEN}7.${NC} Thay đổi Phiên bản PHP"
        echo -e " ${GREEN}8.${NC} Quản lý Cơ sở dữ liệu (Database Manager)"
        echo -e " ${GREEN}9.${NC} Trình Xem Logs (View Realtime Logs)"
        echo -e " ${GREEN}10.${NC} Thêm Custom Queue Worker"
        echo -e " ${YELLOW}11.${NC} Cập nhật Lõi Máy chủ (OS Updater)"
        echo -e " ${YELLOW}12.${NC} Cấu hình & Bật Giám sát Telegram (Monitor/Cron)"
        echo -e " ${RED}0.${NC} Thoát Tool"
        echo -e "------------------------------------------"
        read -p "Xin mời nhập lựa chọn (0-12): " choice

        DOMAIN_PROMPT=""
        case $choice in
            1) 
               read -p "Nhập Tên miền cho dự án mới (vd: demo.com): " DOMAIN_PROMPT
               DOMAIN_PROMPT=$(sanitize_input "$DOMAIN_PROMPT")
               execute_action "add-site" "$DOMAIN_PROMPT" 
               ;;
            2) 
               read -p "Nhập Tên miền cần quản lý SSL: " DOMAIN_PROMPT
               DOMAIN_PROMPT=$(sanitize_input "$DOMAIN_PROMPT")
               execute_action "ssl" "$DOMAIN_PROMPT" 
               ;;
            3) 
               read -p "Nhập Tên miền cần Deploy (vd: demo.com): " DOMAIN_PROMPT
               DOMAIN_PROMPT=$(sanitize_input "$DOMAIN_PROMPT")
               execute_action "deploy" "$DOMAIN_PROMPT" 
               ;;
            4) 
               read -p "Nhập Tên miền cần phục hồi Rollback: " DOMAIN_PROMPT
               DOMAIN_PROMPT=$(sanitize_input "$DOMAIN_PROMPT")
               execute_action "rollback" "$DOMAIN_PROMPT" 
               ;;
            5) 
               read -p "Nhập Tên miền CẦN XÓA HOÀN TOÀN: " DOMAIN_PROMPT
               DOMAIN_PROMPT=$(sanitize_input "$DOMAIN_PROMPT")
               execute_action "remove-site" "$DOMAIN_PROMPT" 
               ;;
            6) 
               read -p "Nhập Tên miền cần xem thông tin: " DOMAIN_PROMPT
               DOMAIN_PROMPT=$(sanitize_input "$DOMAIN_PROMPT")
               execute_action "info" "$DOMAIN_PROMPT" 
               ;;
            7) 
               read -p "Nhập Tên miền cần Đổi PHP Version: " DOMAIN_PROMPT
               DOMAIN_PROMPT=$(sanitize_input "$DOMAIN_PROMPT")
               execute_action "change-php" "$DOMAIN_PROMPT" 
               ;;
            8) 
               read -p "Nhập Tên miền quản lý Database: " DOMAIN_PROMPT
               DOMAIN_PROMPT=$(sanitize_input "$DOMAIN_PROMPT")
               execute_action "manage-db" "$DOMAIN_PROMPT" 
               ;;
            9) 
               read -p "Nhập Tên miền cần Xem Logs (VD: demo.com): " DOMAIN_PROMPT
               DOMAIN_PROMPT=$(sanitize_input "$DOMAIN_PROMPT")
               execute_action "logs" "$DOMAIN_PROMPT" 
               ;;
            10) 
               read -p "Nhập Tên miền Web muốn thêm Queue Worker: " DOMAIN_PROMPT
               DOMAIN_PROMPT=$(sanitize_input "$DOMAIN_PROMPT")
               execute_action "add-queue" "$DOMAIN_PROMPT" 
               ;;
            11) execute_action "update" ;;
            12) execute_action "monitor" ;;
            0) exit 0 ;;
            *) warn "Lựa chọn không hợp lệ." ;;
        esac
        echo -e ""
        read -p "Nhấn [Enter] để quay lại Menu..."
    done
}

execute_action() {
    local cmd="$1"
    local domain_arg="$2"
    
    # Kiểm tra tính hợp lệ của định dạng Tên Miền (Nếu có tham số domain)
    if [ ! -z "$domain_arg" ]; then
        if [[ ! "$domain_arg" =~ ^[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$ ]]; then
            error "Tên miền '$domain_arg' bị sai định dạng chuẩn! Vui lòng nhập đúng (VD: example.com, sub.demo.vn)"
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
            run_deploy "$domain_arg"
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
        *)
            error "Lệnh '${cmd}' không tồn tại."
            ;;
    esac
}

# Entry Point Workflow
if [ $# -eq 0 ]; then
    show_cli_menu
else
    # Gõ thẳng command
    execute_action "$1" "$2"
fi
