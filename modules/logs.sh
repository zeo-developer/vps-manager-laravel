#!/usr/bin/env bash
# modules/logs.sh
# Trình theo dõi Luồng Lỗi Real-time (Laravel Exceptions & Nginx Logs)

#-----------------------------------------------------------------------------
# Hàm:          run_logs
# Mô tả:        Giao diện menu chọn và theo dõi realtime các luồng log của website.
# Biến toàn cục: CYAN, NC, GREEN, RED, YELLOW
# Tham số:      $1 - Tên miền chính (Domain)
# Trả về:       Không có (Hoặc trả về 2 để quay lại menu chính)
#-----------------------------------------------------------------------------
run_logs() {
    local domain="$1"
    
    while true; do
        echo -e "${CYAN}==========================================${NC}"
        echo -e "${CYAN}        GIÁM SÁT LOG CHO: ${domain}        ${NC}"
        echo -e "${CYAN}==========================================${NC}"
        echo -e " ${GREEN}1.${NC} Xem Log lỗi Laravel (laravel.log)"
        echo -e " ${GREEN}2.${NC} Xem Log lỗi Nginx (error.log)"
        echo -e " ${GREEN}3.${NC} Xem Log truy cập Nginx (access.log)"
        echo -e " ${GREEN}4.${NC} Xem gộp chung Laravel & Nginx Error Log"
        echo -e " ${RED}0.${NC} Quay lại Menu chính"
        echo -e "------------------------------------------"
        local choice
        read -p "Nhập lựa chọn của bạn (0-4): " choice

        local target_files=""
        case "$choice" in
            1)
                target_files="/var/www/$domain/shared/storage/logs/laravel.log"
                ;;
            2)
                target_files="/var/log/nginx/error.log"
                ;;
            3)
                target_files="/var/log/nginx/access.log"
                ;;
            4)
                local laravel_log="/var/www/$domain/shared/storage/logs/laravel.log"
                local nginx_error_log="/var/log/nginx/error.log"
                [ -f "$laravel_log" ] && target_files="$laravel_log"
                [ -f "$nginx_error_log" ] && target_files="$target_files $nginx_error_log"
                ;;
            0)
                return 2
                ;;
            *)
                warn "Lựa chọn không hợp lệ."
                continue
                ;;
        esac

        # Kiểm tra sự tồn tại thực tế của các file log được chọn
        local file
        local valid_files=""
        for file in $target_files; do
            if [ -f "$file" ]; then
                valid_files="$valid_files $file"
            else
                warn "Không tìm thấy file log: $file"
            fi
        done

        if [ -z "$valid_files" ]; then
            error "Không tìm thấy tệp tin log khả dụng nào để theo dõi."
            continue
        fi

        info "Đang trích xuất luồng log trực tiếp..."
        info "(Nhấn Ctrl + C để dừng xem và quay lại menu giám sát log)"
        echo -e "${CYAN}--- BẮT ĐẦU THEO DÕI REALTIME ---${NC}"
        
        # Thực thi lệnh tail -f gộp các file log hợp lệ
        # shellcheck disable=SC2086 # Tách từ có chủ đích cho các file log gộp
        tail -f $valid_files
        
        echo -e ""
    done
}
