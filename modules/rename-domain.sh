#!/usr/bin/env bash
# modules/rename-domain.sh
# Đổi tên miền chính của một Website (giữ nguyên Database, SSH Key được rename)

run_rename_domain() {
    local old_domain="$1"
    local new_domain="$2"

    local OLD_ENV="$SCRIPT_DIR/sites/.env.${old_domain}"
    local NEW_ENV="$SCRIPT_DIR/sites/.env.${new_domain}"

    # ── 1. Validate ──────────────────────────────────────────────────────────
    if [ ! -f "$OLD_ENV" ]; then
        error "Site '$old_domain' không tồn tại trong hệ thống."
        return 1
    fi
    if [ -f "$NEW_ENV" ]; then
        error "Domain '$new_domain' đã tồn tại. Hủy để bảo vệ cấu hình cũ."
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
    echo -e "${CYAN}     ĐỔI TÊN MIỀN WEBSITE                ${NC}"
    echo -e "${CYAN}==========================================${NC}"
    echo -e " ${BLUE}Domain cũ    :${NC} ${old_domain}"
    echo -e " ${BLUE}Domain mới   :${NC} ${new_domain}"
    echo -e " ${BLUE}Database     :${NC} ${DB_NAME} (giữ nguyên)"
    echo -e "------------------------------------------"
    warn "Sau khi đổi, anh CẦN:"
    warn "  1. Trỏ DNS ${new_domain} về IP server này"
    warn "  2. Chạy: ./vps.sh ssl ${new_domain} để cài SSL mới"
    echo -e "------------------------------------------"
    read -p "Gõ 'YES' để xác nhận đổi domain: " confirm
    if [ "$confirm" != "YES" ]; then
        info "Đã hủy thao tác đổi domain."
        return 0
    fi

    # ── 2. Tạo file env mới ──────────────────────────────────────────────────
    info "Tạo file cấu hình mới sites/.env.${new_domain} ..."
    cp "$OLD_ENV" "$NEW_ENV"
    sed -i "s|^APP_DOMAIN=.*|APP_DOMAIN=\"${new_domain}\"|" "$NEW_ENV"
    # Cập nhật đường dẫn SSH key trỏ đến key mới
    sed -i "s|id_ed25519_${old_domain}|id_ed25519_${new_domain}|g" "$NEW_ENV"
    harden_permissions "$NEW_ENV"

    # ── 3. Rename SSH Key ────────────────────────────────────────────────────
    local old_key="/var/www/.vps_keys/id_ed25519_${old_domain}"
    local new_key="/var/www/.vps_keys/id_ed25519_${new_domain}"
    if [ -f "$old_key" ]; then
        info "Đổi tên SSH Key: id_ed25519_${old_domain} → id_ed25519_${new_domain}"
        mv "$old_key"     "$new_key"
        mv "${old_key}.pub" "${new_key}.pub" 2>/dev/null || true
    fi

    # ── 4. mv Web Root + Fix Symlinks ────────────────────────────────────────
    if [ -d "/var/www/${old_domain}" ]; then
        info "Di chuyển Web Root: /var/www/${old_domain} → /var/www/${new_domain} ..."
        mv "/var/www/${old_domain}" "/var/www/${new_domain}"

        # Fix symlink current → release mới nhất
        local releases_dir="/var/www/${new_domain}/releases"
        local latest_release
        latest_release=$(ls -1t "$releases_dir" 2>/dev/null | head -1)
        if [ -n "$latest_release" ]; then
            info "Rebuild symlink 'current' → releases/${latest_release} ..."
            ln -nfs "${releases_dir}/${latest_release}" "/var/www/${new_domain}/current"

            # Fix symlinks storage + .env bên trong từng release (đường dẫn tuyệt đối bị hỏng sau mv)
            for rel_dir in "${releases_dir}"/*/; do
                [ -d "$rel_dir" ] || continue
                ln -nfs "/var/www/${new_domain}/shared/storage" "${rel_dir}storage"
                ln -nfs "/var/www/${new_domain}/shared/.env"    "${rel_dir}.env"
            done
            info "Đã rebuild symlinks cho tất cả releases."
        fi
    fi

    # ── 5. Nginx Config ──────────────────────────────────────────────────────
    info "Tạo lại cấu hình Nginx cho domain mới ..."
    local php_ver="${PHP_VERSION:-8.3}"
    local aliases_str="${DOMAIN_ALIASES:-}"
    local nginx_conf="/etc/nginx/sites-available/${new_domain}"

    sed "s/{{APP_DOMAIN}}/${new_domain}/g; \
         s/{{PHP_VERSION}}/${php_ver}/g; \
         s/{{DOMAIN_ALIASES}}/${aliases_str}/g" \
        "$SCRIPT_DIR/configs/nginx-template.conf" > "$nginx_conf"

    ln -nfs "$nginx_conf" "/etc/nginx/sites-enabled/${new_domain}"
    rm -f "/etc/nginx/sites-enabled/${old_domain}"
    rm -f "/etc/nginx/sites-available/${old_domain}"
    systemctl reload nginx

    # ── 6. Supervisor Config ─────────────────────────────────────────────────
    info "Cập nhật cấu hình Supervisor ..."
    local old_sup="/etc/supervisor/conf.d/${OLD_SAFE}.conf"
    local new_sup="/etc/supervisor/conf.d/${NEW_SAFE}.conf"
    if [ -f "$old_sup" ]; then
        sed "s|${old_domain}|${new_domain}|g; s|${OLD_SAFE}|${NEW_SAFE}|g" \
            "$old_sup" > "$new_sup"
        chmod 644 "$new_sup"
        rm -f "$old_sup"
        supervisorctl reread
        supervisorctl update
        supervisorctl restart "${NEW_SAFE}:*" 2>/dev/null || true
    fi

    # ── 7. Cập nhật APP_URL trong shared/.env Laravel ────────────────────────
    local shared_env="/var/www/${new_domain}/shared/.env"
    if [ -f "$shared_env" ]; then
        info "Cập nhật APP_URL trong Laravel .env ..."
        sed -i "s|^APP_URL=.*|APP_URL=https://${new_domain}|g" "$shared_env"
    fi

    # ── 8. Cập nhật Crontab ──────────────────────────────────────────────────
    if sudo -u "$app_user" crontab -l 2>/dev/null | grep -q "cd /var/www/${old_domain}/current"; then
        info "Cập nhật Crontab scheduler ..."
        sudo -u "$app_user" crontab -l \
            | sed "s|cd /var/www/${old_domain}/current|cd /var/www/${new_domain}/current|g" \
            | sudo -u "$app_user" crontab -
    fi

    # ── 9. Xóa SSL Cert cũ ───────────────────────────────────────────────────
    if [ -d "/etc/letsencrypt/live/${old_domain}" ]; then
        info "Xóa SSL cert cũ của ${old_domain} ..."
        certbot delete --cert-name "${old_domain}" --non-interactive 2>/dev/null \
            || warn "Không thể xóa cert tự động. Xóa thủ công: certbot delete --cert-name ${old_domain}"
    fi

    # ── 10. Xóa env cũ ───────────────────────────────────────────────────────
    rm -f "$OLD_ENV"
    info "Đã xóa file cấu hình cũ: sites/.env.${old_domain}"

    # ── Hoàn tất ─────────────────────────────────────────────────────────────
    info "================================================================="
    info "✅ ĐÃ ĐỔI DOMAIN THÀNH CÔNG: ${old_domain} → ${new_domain}"
    info "   Database : ${DB_NAME} (giữ nguyên, không bị đổi)"
    info ""
    warn "VIỆC CẦN LÀM TIẾP THEO:"
    warn "  1. Trỏ DNS bản ghi A của '${new_domain}' về IP server"
    warn "  2. Sau khi DNS propagate (5-30 phút), chạy:"
    warn "     ./vps.sh ssl ${new_domain}"
    info "================================================================="
}
