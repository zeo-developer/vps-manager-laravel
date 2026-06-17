# modules/deploy/phases/service.sh

# -------------------------------------------------------------------------
# PHASE 5: HOÁN ĐỔI & KHỞI ĐỘNG LẠI (SWAP & RELOAD)
# -------------------------------------------------------------------------
if [ -d "$CURRENT_DIR" ] && [ ! -L "$CURRENT_DIR" ]; then
    rm -rf "$CURRENT_DIR"
fi
sudo -u "$APP_USER" ln -nfs "$NEW_RELEASE" "$CURRENT_DIR" || { cleanup_failed_release; error "Không thể hoán đổi symlink current"; return 1; }

systemctl reload "php${PHP_VERSION}-fpm"

local node_dir
node_dir=$(resolve_n_node_version_dir "${NODE_VERSION:-20}")
local env_line="environment=PATH=\"${node_dir}/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin\""

if [ -f "$supervisor_conf" ] && grep -q "^\[program:${SAFE_DOMAIN}-ssr\]" "$supervisor_conf"; then
    if sed -n "/^\[program:${SAFE_DOMAIN}-ssr\]/,/^\[/p" "$supervisor_conf" | grep -q "^environment="; then
        sed -i "/^\[program:${SAFE_DOMAIN}-ssr\]/,/^\[/ s|^environment=.*|${env_line}|" "$supervisor_conf"
    else
        sed -i "/^\[program:${SAFE_DOMAIN}-ssr\]/,/^\[/ s|^stopwaitsecs=.*|&\n${env_line}|" "$supervisor_conf"
    fi
    info "Đã cập nhật PATH cho Supervisor SSR (${APP_DOMAIN})"
fi

if [ "$is_first_deploy" -eq 1 ]; then
    setup_default_queue_worker "$APP_DOMAIN" "$APP_USER" "$PHP_VERSION"
    if [ $? -eq 0 ]; then
        info "Đã thiết lập mặc định Queue Worker cho website mới."
    fi

    if [ -f "$CURRENT_DIR/package.json" ] && grep -q '"build:ssr"' "$CURRENT_DIR/package.json"; then
        setup_default_ssr_worker "$APP_DOMAIN" "$APP_USER" "$PHP_VERSION" "${NODE_VERSION:-20}"
    fi
fi

supervisorctl reread
supervisorctl update
sleep 1
info "Khởi chạy các dịch vụ Supervisor: group [ ${SAFE_DOMAIN} ]..."
supervisorctl restart "${SAFE_DOMAIN}:*" || supervisorctl start "${SAFE_DOMAIN}:*" || warn "Cảnh báo: Không thể khởi động nhóm dịch vụ Supervisor"

if [ "$is_first_deploy" -eq 1 ]; then
    local CRON_CMD="* * * * * cd ${CURRENT_DIR} && php${PHP_VERSION} artisan schedule:run >> /dev/null 2>&1"
    if ! sudo -u "$APP_USER" crontab -l 2>/dev/null | grep -q "cd ${CURRENT_DIR}"; then
        (sudo -u "$APP_USER" crontab -l 2>/dev/null; echo "$CRON_CMD") | sudo -u "$APP_USER" crontab -
        info "Đã thiết lập mặc định Laravel Scheduler cho website mới."
    fi
fi
