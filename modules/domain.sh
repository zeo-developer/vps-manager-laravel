#!/usr/bin/env bash
# modules/domain.sh
# Bộ điều phối quản lý Domain tập trung (Thêm, Xóa, Xem, Sửa, Alias)
#-----------------------------------------------------------------------------
# Hàm:          generate_nginx_config
# Mô tả:        Tạo file cấu hình Nginx từ template và tạo symlink kích hoạt.
# Biến toàn cục: SCRIPT_DIR
# Tham số:      $1 - Tên miền chính (Primary domain)
#               $2 - Tên các máy chủ trỏ về (Server names - cách nhau bằng khoảng trắng)
#               $3 - Phiên bản PHP (Ví dụ: 8.3)
# Trả về:       Không có
#-----------------------------------------------------------------------------
generate_nginx_config() {
    local primary="$1"
    local server_names="$2"
    local php_ver="$3"
    local nginx_conf="/etc/nginx/sites-available/${primary}"
    
    sed "s/{{APP_DOMAIN}}/${primary}/g; \
         s/{{PHP_VERSION}}/${php_ver}/g; \
         s/{{SERVER_NAMES}}/${server_names}/g" \
        "$SCRIPT_DIR/configs/nginx-template.conf" > "$nginx_conf"
        
    ln -nfs "$nginx_conf" "/etc/nginx/sites-enabled/${primary}"
}

#-----------------------------------------------------------------------------
# Hàm:          check_domain_alias_conflict
# Mô tả:        Kiểm tra xem tên miền đã được sử dụng làm Alias ở Website nào chưa.
# Biến toàn cục: SCRIPT_DIR
# Tham số:      $1 - Tên miền cần kiểm tra
# Trả về:       Đường dẫn file .env chứa alias bị trùng nếu có, hoặc chuỗi rỗng
#-----------------------------------------------------------------------------
check_domain_alias_conflict() {
    local target_domain="$1"
    local env_file
    for env_file in "$SCRIPT_DIR/sites/".env.*; do
        [ -f "$env_file" ] || continue
        if grep "^DOMAIN_ALIASES=" "$env_file" 2>/dev/null | grep -qw "$target_domain"; then
            echo "$env_file"
            return 0
        fi
    done
    return 0
}

#-----------------------------------------------------------------------------
# Hàm:          run_domain_action
# Mô tả:        Nạp động các sub-module domain tương ứng và thực thi hành động.
# Biến toàn cục: SCRIPT_DIR
# Tham số:      $1 - Tên hành động (add, delete, info, rename, manage-alias, add-alias, remove-alias)
#               $@ - Các đối số còn lại truyền cho hành động con
# Trả về:       Mã exit code hoặc kết quả thực thi
#-----------------------------------------------------------------------------
run_domain_action() {
    local action="$1"
    shift

    case "$action" in
        add)
            load_module "domain/add.sh" || return 1
            run_add_site "$@"
            ;;
        delete)
            load_module "domain/delete.sh" || return 1
            run_remove_site "$@"
            ;;
        info)
            load_module "domain/info.sh" || return 1
            run_site_info "$@"
            ;;
        rename)
            load_module "domain/rename.sh" || return 1
            run_rename_domain "$@"
            ;;
        add-alias|remove-alias|manage-alias)
            load_module "domain/alias.sh" || return 1
            if [ "$action" = "add-alias" ]; then
                run_add_alias "$@"
            elif [ "$action" = "remove-alias" ]; then
                run_remove_alias "$@"
            else
                run_manage_alias "$@"
            fi
            ;;
        menu)
            run_domain_management_menu
            ;;
        *)
            error "Hành động domain không hợp lệ: $action"
            return 1
            ;;
    esac
}

#-----------------------------------------------------------------------------
# Function:     run_domain_management_menu
# Description:  Interactive submenu to manage all site domains (Add/Rename/Info/Alias/Delete).
# Globals:      CYAN, NC, GREEN, RED, YELLOW
# Arguments:    None
# Returns:      None
#-----------------------------------------------------------------------------
run_domain_management_menu() {
    while true; do
        clear || true
        echo -e "${CYAN}==========================================${NC}"
        echo -e "${CYAN}        QUẢN LÝ WEBSITE (DOMAIN)          ${NC}"
        echo -e "${CYAN}==========================================${NC}"
        echo -e " ${GREEN}1.${NC} Thêm Website mới"
        echo -e " ${GREEN}2.${NC} Đổi tên miền Website (Sửa)"
        echo -e " ${GREEN}3.${NC} Xem thông tin Website"
        echo -e " ${GREEN}4.${NC} Quản lý Domain Alias"
        echo -e " ${GREEN}5.${NC} Xóa hoàn toàn Website"
        echo -e " ${RED}0.${NC} Quay lại Menu chính"
        echo -e "------------------------------------------"
        local choice
        read -p "Nhập lựa chọn (0-5): " choice

        local DOMAIN_PROMPT=""
        local NEW_DOMAIN_PROMPT=""
        case "$choice" in
            1)
                read -p "Nhập domain mới (vd: demo.com): " DOMAIN_PROMPT
                DOMAIN_PROMPT=$(sanitize_input "$DOMAIN_PROMPT")
                if [ -n "$DOMAIN_PROMPT" ]; then
                    run_domain_action "add" "$DOMAIN_PROMPT"
                fi
                ;;
            2)
                DOMAIN_PROMPT=$(select_site_menu "Chọn domain cần đổi tên")
                [ $? -ne 0 ] && continue
                read -p "Nhập domain MỚI: " NEW_DOMAIN_PROMPT
                NEW_DOMAIN_PROMPT=$(sanitize_input "$NEW_DOMAIN_PROMPT")
                if [ -n "$NEW_DOMAIN_PROMPT" ]; then
                    local domain_regex='^([a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?)(\.([a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?))*\.[a-zA-Z]{2,}$'
                    if [[ ! "$NEW_DOMAIN_PROMPT" =~ $domain_regex ]] || [ ${#NEW_DOMAIN_PROMPT} -gt 253 ]; then
                        error "Tên miền mới '$NEW_DOMAIN_PROMPT' không đúng định dạng!"
                    else
                        run_domain_action "rename" "$DOMAIN_PROMPT" "$NEW_DOMAIN_PROMPT"
                    fi
                fi
                ;;
            3)
                DOMAIN_PROMPT=$(select_site_menu "Chọn domain xem thông tin")
                [ $? -ne 0 ] && continue
                run_domain_action "info" "$DOMAIN_PROMPT"
                ;;
            4)
                DOMAIN_PROMPT=$(select_site_menu "Chọn domain quản lý Alias")
                [ $? -ne 0 ] && continue
                run_domain_action "manage-alias" "$DOMAIN_PROMPT"
                ;;
            5)
                DOMAIN_PROMPT=$(select_site_menu "Chọn domain CẦN XÓA")
                [ $? -ne 0 ] && continue
                run_domain_action "delete" "$DOMAIN_PROMPT"
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
