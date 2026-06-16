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
        echo -e " ${GREEN}1.${NC} Quản lý Inertia SSR (Bật / Tắt / Khởi động lại)"
        echo -e " ${GREEN}2.${NC} Quản lý Default Queue Worker (Bật / Tắt / Khởi động lại)"
        echo -e " ${GREEN}3.${NC} Thêm Custom Queue Worker (Laravel)"
        echo -e " ${GREEN}4.${NC} Dọn dẹp cache hệ thống (Clear Cache)"
        echo -e " ${GREEN}5.${NC} Cache tối ưu cấu hình và hiệu năng"
        echo -e " ${GREEN}6.${NC} Bật/Tắt Laravel Scheduler"
        echo -e " ${RED}0.${NC} Quay lại Menu chính"
        echo -e "------------------------------------------"
        local choice
        read -p "Lựa chọn (0-6): " choice

        case "$choice" in
            1) run_manage_ssr "$domain" "$app_user" ;;
            2) run_manage_worker "$domain" "$app_user" ;;
            3) run_add_queue "$domain" ;;
            4) run_clear_cache "$domain" "$app_user" "$php_bin" ;;
            5) run_optimize_cache "$domain" "$app_user" "$php_bin" ;;
            6) toggle_laravel_scheduler "$domain" ;;
            0) break ;;
            *) warn "Lựa chọn không hợp lệ." ;;
        esac
        echo -e "\nNhấn phím bất kỳ để tiếp tục..."
        read -n 1
    done
}
