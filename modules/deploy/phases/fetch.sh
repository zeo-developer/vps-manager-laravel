# modules/deploy/phases/fetch.sh

# -------------------------------------------------------------------------
# PHASE 2: KÉO MÃ NGUỒN & CẤU HÌNH (FETCH & CONFIG)
# -------------------------------------------------------------------------
info "Sử dụng SSH Key: $SSH_KEY_PATH"
sudo -u "$APP_USER" GIT_SSH_COMMAND="ssh -i ${SSH_KEY_PATH} -o StrictHostKeyChecking=no" \
    git clone "$GIT_REPO" "$NEW_RELEASE" || { cleanup_failed_release; error "Lỗi: Không thể clone mã nguồn từ Git!"; return 1; }

info "Liên kết file .env và thư mục storage..."
if [ ! -f "${SHARED_DIR}/.env" ]; then
    info "Khởi tạo file .env đầu tiên cho Laravel..."
    if [ -f "${NEW_RELEASE}/.env.example" ]; then
        cp "${NEW_RELEASE}/.env.example" "${SHARED_DIR}/.env"
    else
        touch "${SHARED_DIR}/.env"
    fi
    chown "$APP_USER":"$APP_USER" "${SHARED_DIR}/.env"
fi

source "$SITE_ENV_FILE"
sed -i "s|^APP_URL=.*|APP_URL=https://${APP_DOMAIN}|g" "${SHARED_DIR}/.env"
sed -i "s/^DB_DATABASE=.*/DB_DATABASE=${DB_NAME}/g" "${SHARED_DIR}/.env"
sed -i "s/^DB_USERNAME=.*/DB_USERNAME=${DB_USER}/g" "${SHARED_DIR}/.env"
sed -i "s/^DB_PASSWORD=.*/DB_PASSWORD=${DB_PASSWORD}/g" "${SHARED_DIR}/.env"
sed -i "s/^APP_ENV=.*/APP_ENV=production/g" "${SHARED_DIR}/.env"
sed -i "s/^APP_DEBUG=.*/APP_DEBUG=false/g" "${SHARED_DIR}/.env"

rm -rf "${NEW_RELEASE}/storage"
sudo -u "$APP_USER" ln -s "${SHARED_DIR}/storage" "${NEW_RELEASE}/storage"
rm -f "${NEW_RELEASE}/.env"
sudo -u "$APP_USER" ln -s "${SHARED_DIR}/.env" "${NEW_RELEASE}/.env"
