#!/usr/bin/env bash
# modules/laravel.sh
# Bộ điều phối Quản lý Laravel tập trung (Artisan, SSR, Cache, Build, Queue).

# Nạp các sub-module chuyên biệt
load_module "laravel/artisan.sh" || return 1
load_module "laravel/ssr.sh" || return 1
load_module "laravel/cache.sh" || return 1
load_module "laravel/build.sh" || return 1
load_module "laravel/scheduler.sh" || return 1
load_module "laravel/queue.sh" || return 1

#-----------------------------------------------------------------------------
# Hàm:          run_laravel_manager
# Mô tả:        Menu tương tác quản trị dự án Laravel (Artisan, SSR, Cache, Build, Queue).
# Biến toàn cục: CYAN, NC, YELLOW, GREEN, RED, APP_USER, PHP_VERSION
# Tham số:      $1 - Tên miền chính (Domain)
# Trả về:       Không có
#-----------------------------------------------------------------------------
run_laravel_manager() {
    local domain="$1"
    
    # Kiểm tra sự tồn tại của thư mục mã nguồn current
    if [ ! -d "/var/www/$domain/current" ]; then
        error "Lỗi: Không tìm thấy thư mục 'current'. Vui lòng triển khai (deploy) website trước."
        return 1
    fi
    
    local app_user="${APP_USER:-www-data}"
    
    # Xác định đúng lệnh PHP toàn cục cho website
    local php_bin="php${PHP_VERSION:-8.3}"

    while true; do
        clear || true
        echo -e "${CYAN}==========================================${NC}"
        echo -e "${CYAN}           QUẢN LÝ DỰ ÁN LARAVEL          ${NC}"
        echo -e "${CYAN}==========================================${NC}"
        echo -e " Tên miền: ${YELLOW}$domain${NC} (User: ${YELLOW}$app_user${NC})"
        echo -e "------------------------------------------"
        echo -e " ${GREEN}1.${NC} Chạy Database Migration (migrate)"
        echo -e " ${GREEN}2.${NC} Khôi phục Migration (migrate:rollback)"
        echo -e " ${GREEN}3.${NC} Bật/Tắt Inertia SSR"
        echo -e " ${GREEN}4.${NC} Khởi động lại dịch vụ Supervisor SSR"
        echo -e " ${GREEN}5.${NC} Tạo Application Key (key:generate)"
        echo -e " ${GREEN}6.${NC} Sinh khóa bí mật JWT (jwt:secret)"
        echo -e " ${GREEN}7.${NC} Tạo liên kết dữ liệu (storage:link)"
        echo -e " ${GREEN}8.${NC} Dọn dẹp cache hệ thống (Clear Cache)"
        echo -e " ${GREEN}9.${NC} Cache tối ưu cấu hình và hiệu năng"
        echo -e " ${GREEN}10.${NC} Biên dịch Asset front-end (npm run build)"
        echo -e " ${GREEN}11.${NC} Biên dịch Inertia SSR (npm run build:ssr)"
        echo -e " ${GREEN}12.${NC} Bật/Tắt Laravel Scheduler"
        echo -e " ${GREEN}13.${NC} Thêm Custom Queue Worker (Laravel)"
        echo -e " ${RED}0.${NC} Quay lại Menu chính"
        echo -e "------------------------------------------"
        local choice
        read -p "Lựa chọn (0-13): " choice

        case "$choice" in
            1) 
                run_artisan_migrate "$domain" "$app_user" "$php_bin" 
                ;;
            2) 
                run_artisan_rollback "$domain" "$app_user" "$php_bin" 
                ;;
            3) 
                run_toggle_ssr "$domain" "$app_user" 
                ;;
            4) 
                run_restart_ssr "$domain" 
                ;;
            5) 
                run_artisan_key_generate "$domain" "$app_user" "$php_bin" 
                ;;
            6) 
                run_artisan_jwt_secret "$domain" "$app_user" "$php_bin" 
                ;;
            7) 
                run_artisan_storage_link "$domain" "$app_user" "$php_bin" 
                ;;
            8) 
                run_clear_cache "$domain" "$app_user" "$php_bin" 
                ;;
            9) 
                run_optimize_cache "$domain" "$app_user" "$php_bin" 
                ;;
            10) 
                run_npm_build "$domain" "$app_user" 
                ;;
            11) 
                run_npm_build_ssr "$domain" "$app_user" 
                ;;
            12)
                toggle_laravel_scheduler "$domain"
                ;;
            13)
                run_add_queue "$domain"
                ;;
            0) 
                break 
                ;;
            *) 
                warn "Lựa chọn không hợp lệ." 
                ;;
        esac
        echo -e "\nNhấn phím bất kỳ để tiếp tục..."
        read -n 1
    done
}
