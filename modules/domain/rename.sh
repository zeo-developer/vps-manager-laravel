#!/usr/bin/env bash
# modules/domain/rename.sh
# Đổi tên miền chính của một Website (giữ nguyên Database, SSH Key được rename)

#-----------------------------------------------------------------------------
# Hàm:          run_rename_domain
# Mô tả:        Đổi tên miền chính của Website: rename thư mục web, cập nhật cấu hình Nginx/Supervisor/Cron,
#               cập nhật file env và dọn dẹp SSL cũ.
# Biến toàn cục: SCRIPT_DIR, APP_USER, CYAN, BLUE, YELLOW, NC
# Tham số:      $1 - Tên miền cũ
#               $2 - Tên miền mới
# Trả về:       0 nếu thành công, 1 nếu lỗi
#-----------------------------------------------------------------------------
run_rename_domain() {
    local old_domain="$1"
    local new_domain="$2"

    local OLD_ENV="$SCRIPT_DIR/sites/.env.${old_domain}"
    local NEW_ENV="$SCRIPT_DIR/sites/.env.${new_domain}"

    # ── 1. Kiểm tra tính hợp lệ (Validate) ──────────────────────────────────
    if [ ! -f "$OLD_ENV" ]; then
        error "Lỗi: Site '$old_domain' không tồn tại."
        return 1
    fi
    if [ -f "$NEW_ENV" ]; then
        error "Domain '$new_domain' đã là domain chính của một dự án khác."
        return 1
    fi

    # Kiểm tra xem new_domain có đang được dùng làm alias ở bất kỳ web nào không
    local conflict_file=$(check_domain_alias_conflict "$new_domain")
    if [ -n "$conflict_file" ]; then
        # Trích xuất tên domain chính đang giữ alias từ tên file (vd: .env.site.com -> site.com)
        local conflict_domain=$(basename "$conflict_file" | sed 's/^\.env\.//')
        
        error "Lỗi: Domain '${new_domain}' đang là Alias của site '${conflict_domain}'."
        error "Yêu cầu gỡ Alias tại site '${conflict_domain}' trước khi đổi tên."
        return 1
    fi

    validate_env_file "$OLD_ENV" || return 1
    source "$OLD_ENV"

    local OLD_SAFE
    OLD_SAFE=$(get_safe_domain "$old_domain")
    local NEW_SAFE
    NEW_SAFE=$(get_safe_domain "$new_domain")
    local app_user="${APP_USER:-www-data}"

    echo -e "${CYAN}==========================================${NC}"
    echo -e "${CYAN}         DOMAIN RENAME MANAGER            ${NC}"
    echo -e "${CYAN}==========================================${NC}"
    echo -e " ${BLUE}Domain cũ    :${NC} ${old_domain}"
    echo -e " ${BLUE}Domain mới   :${NC} ${new_domain}"
    echo -e " ${BLUE}Database     :${NC} ${DB_NAME} (giữ nguyên)"
    echo -e "------------------------------------------"
    warn "Yêu cầu sau khi thay đổi:"
    warn "  1. Cấu hình DNS của domain mới về IP máy chủ"
    warn "  2. Khởi tạo SSL: ./vps.sh ssl ${new_domain}"
    echo -e "------------------------------------------"
    read -p "Gõ 'YES' để xác nhận đổi domain: " confirm
    if [ "$confirm" != "YES" ]; then
        info "Hủy thao tác đổi domain."
        return 0
    fi

    # ── 2. Tạo file env mới ──────────────────────────────────────────────────
    info "Khởi tạo cấu hình: sites/.env.${new_domain}..."
    cp "$OLD_ENV" "$NEW_ENV"
    update_env_var "APP_DOMAIN" "${new_domain}" "$NEW_ENV"
    # Cập nhật đường dẫn SSH key trỏ đến key mới
    local old_key_file="id_ed25519_${old_domain}"
    local new_key_file="id_ed25519_${new_domain}"
    local current_ssh_path=$(grep -oP "(?<=^SSH_KEY_PATH=\")[^\"]+" "$NEW_ENV" || echo "")
    if [ -n "$current_ssh_path" ]; then
        local new_ssh_path=${current_ssh_path//$old_key_file/$new_key_file}
        update_env_var "SSH_KEY_PATH" "$new_ssh_path" "$NEW_ENV"
    fi
    harden_permissions "$NEW_ENV"

    # ── 3. Đổi tên SSH Key ────────────────────────────────────────────────────
    local old_key="/var/www/.vps_keys/id_ed25519_${old_domain}"
    local new_key="/var/www/.vps_keys/id_ed25519_${new_domain}"
    if [ -f "$old_key" ]; then
        info "Cập nhật SSH Key..."
        mv "$old_key"     "$new_key"
        mv "${old_key}.pub" "${new_key}.pub" 2>/dev/null || true
    fi

    # ── 4. mv Web Root & Sửa Lại Các Đường dẫn Symlink ───────────────────────
    if [ -d "/var/www/${old_domain}" ]; then
        info "Di chuyển Web Root..."
        mv "/var/www/${old_domain}" "/var/www/${new_domain}"

        # Sửa symlink current → release mới nhất
        local releases_dir="/var/www/${new_domain}/releases"
        local latest_release
        latest_release=$(ls -1t "$releases_dir" 2>/dev/null | head -1)
        if [ -n "$latest_release" ]; then
            info "Cấu hình symlink 'current'..."
            ln -nfs "${releases_dir}/${latest_release}" "/var/www/${new_domain}/current"

            # Sửa symlinks storage & .env bên trong từng release (đường dẫn tuyệt đối bị hỏng sau di chuyển)
            for rel_dir in "${releases_dir}"/*/; do
                [ -d "$rel_dir" ] || continue
                ln -nfs "/var/www/${new_domain}/shared/storage" "${rel_dir}storage"
                ln -nfs "/var/www/${new_domain}/shared/.env"    "${rel_dir}.env"
            done
            info "Cập nhật symlinks thành công."
        fi
    fi

    # ── 5. Cấu hình Nginx ────────────────────────────────────────────────────
    info "Cấu hình Nginx..."
    local php_ver="${PHP_VERSION:-8.3}"
    local aliases_str="${DOMAIN_ALIASES:-}"
    # Xây dựng danh sách SERVER_NAMES: domain mới + các alias (nếu có)
    local server_names="$new_domain"
    [ -n "$aliases_str" ] && server_names="$new_domain $aliases_str"

    generate_nginx_config "$new_domain" "$server_names" "$php_ver"
    rm -f "/etc/nginx/sites-enabled/${old_domain}"
    rm -f "/etc/nginx/sites-available/${old_domain}"
    systemctl reload nginx

    # ── 6. Cấu hình Supervisor ───────────────────────────────────────────────
    info "Cấu hình Supervisor..."
    local old_sup="/etc/supervisor/conf.d/${OLD_SAFE}.conf"
    local new_sup="/etc/supervisor/conf.d/${NEW_SAFE}.conf"
    if [ -f "$old_sup" ]; then
        cp "$old_sup" "$new_sup"
        
        # Cập nhật đường dẫn web root trong file cấu hình mới
        sed -i "s|/var/www/${old_domain}/|/var/www/${new_domain}/|g" "$new_sup"
        
        # Cập nhật các định danh nhóm và chương trình Supervisor
        sed -i "s|group:${OLD_SAFE}\]|group:${NEW_SAFE}\]|g" "$new_sup"
        sed -i "s|program:${OLD_SAFE}-|program:${NEW_SAFE}-|g" "$new_sup"
        sed -i "s|programs=${OLD_SAFE}-|programs=${NEW_SAFE}-|g" "$new_sup"
        sed -i "s|,${OLD_SAFE}-|,${NEW_SAFE}-|g" "$new_sup"

        chmod 644 "$new_sup"
        rm -f "$old_sup"
        supervisorctl reread
        supervisorctl update
        
        # Khởi động lại các tác vụ nếu đã deploy thành công trước đó (tồn tại liên kết current)
        if [ -L "/var/www/${new_domain}/current" ]; then
            supervisorctl restart "${NEW_SAFE}:*" 2>/dev/null || true
        else
            info "Bỏ qua khởi động Supervisor (Chưa deploy mã nguồn)."
        fi
    fi

    # ── 7. Cập nhật APP_URL trong shared/.env Laravel ────────────────────────
    local shared_env="/var/www/${new_domain}/shared/.env"
    if [ -f "$shared_env" ]; then
        info "Cập nhật APP_URL..."
        update_env_var "APP_URL" "https://${new_domain}" "$shared_env"
    fi

    # ── 8. Cập nhật Crontab của App User ──────────────────────────────────────
    if sudo -u "$app_user" crontab -l 2>/dev/null | grep -q "cd /var/www/${old_domain}/current"; then
        info "Cập nhật Crontab..."
        sudo -u "$app_user" crontab -l \
            | sed "s|cd /var/www/${old_domain}/current|cd /var/www/${new_domain}/current|g" \
            | sudo -u "$app_user" crontab -
    fi

    # ── 9. Xóa SSL Certificate cũ ────────────────────────────────────────────
    if [ -d "/etc/letsencrypt/live/${old_domain}" ]; then
        info "Gỡ bỏ SSL certificate cũ..."
        certbot delete --cert-name "${old_domain}" --non-interactive 2>/dev/null \
            || warn "Không thể xóa cert tự động. Xóa thủ công bằng lệnh: certbot delete --cert-name ${old_domain}"
    fi

    # ── 10. Dọn dẹp File Env cũ ──────────────────────────────────────────────
    rm -f "$OLD_ENV"
    info "Xóa cấu hình cũ: .env.${old_domain}"

    info "================================================================="
    info " THÀNH CÔNG: Thay đổi domain hoàn tất."
    info "-----------------------------------------------------------------"
    info " Miền cũ : ${old_domain}"
    info " Miền mới: ${new_domain}"
    info "-----------------------------------------------------------------"
    info " Bước tiếp theo:"
    info "  1. Kiểm tra DNS domain '${new_domain}'"
    info "  2. Khởi tạo SSL: ./vps.sh ssl ${new_domain}"
    info "================================================================="
}
