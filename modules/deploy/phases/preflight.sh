# modules/deploy/phases/preflight.sh

# -------------------------------------------------------------------------
# PHASE 1: CHUẨN BỊ MÔI TRƯỜNG (PRE-FLIGHT & SETUP)
# -------------------------------------------------------------------------
local SITE_ENV_FILE="$SCRIPT_DIR/sites/.env.${APP_DOMAIN}"
if [ ! -f "$SITE_ENV_FILE" ]; then
    error "Lỗi: Site '${APP_DOMAIN}' chưa được khởi tạo. Vui lòng chạy: vps add-site"
    return 1
fi

info "Bắt đầu Zero-Downtime Deploy: $APP_DOMAIN..."

load_module "runtime.sh" || return 1
ensure_site_node_version "$APP_DOMAIN" "${NODE_VERSION:-20}" || return 1

local BASE_DIR="/var/www/${APP_DOMAIN}"
local RELEASES_DIR="${BASE_DIR}/releases"
local SHARED_DIR="${BASE_DIR}/shared"
local CURRENT_DIR="${BASE_DIR}/current"

local TIMESTAMP=$(date +"%Y%m%d%H%M%S")
local NEW_RELEASE="${RELEASES_DIR}/${TIMESTAMP}"

cd "$BASE_DIR" || cd /tmp
MIGRATE_NEW=false

chown -R "$APP_USER":"$APP_USER" "$BASE_DIR"

if [ -z "$GIT_REPO" ] || [ "$GIT_REPO" = "git_repo_url" ]; then
    info "Yêu cầu: Cấu hình Git Repository cho site '${APP_DOMAIN}'."
    while true; do
        read -p "Nhập Git Repo URL (vd: git@github.com:user/repo.git): " input_repo
        input_repo=$(echo "$input_repo" | xargs)

        if [[ "$input_repo" =~ ^https://(github\.com|gitlab\.com|bitbucket\.org)/(.+) ]]; then
            local provider="${BASH_REMATCH[1]}"
            local path="${BASH_REMATCH[2]}"
            path="${path%.git}"
            
            local ssh_url="git@${provider}:${path}.git"
            warn "Cảnh báo: URL HTTPS không sử dụng được với SSH Key."
            read -p "Tự động chuyển đổi sang SSH URL: [ ${ssh_url} ]? (y/n): " convert_choice
            if [[ "$convert_choice" =~ ^[Yy]$ ]]; then
                input_repo="$ssh_url"
                info "Đã chuyển đổi sang giao thức SSH."
            fi
        fi

        if [[ "$input_repo" =~ ^git@ ]]; then
            GIT_REPO="$input_repo"
            if grep -q "^GIT_REPO=" "$SITE_ENV_FILE"; then
                sed -i "s|^GIT_REPO=.*|GIT_REPO=\"${GIT_REPO}\"|g" "$SITE_ENV_FILE"
            else
                echo "GIT_REPO=\"${GIT_REPO}\"" >> "$SITE_ENV_FILE"
            fi
            info "Đã lưu Git Repo: ${GIT_REPO}"
            break
        elif [[ "$input_repo" =~ ^https:// ]]; then
            warn "Lưu ý: HTTPS yêu cầu xác thực thủ công khi clone/pull."
            GIT_REPO="$input_repo"
            break
        else
            error "Lỗi: Định dạng URL không hợp lệ. Đề xuất sử dụng giao thức SSH (git@...)"
        fi
    done
fi

mkdir -p "${RELEASES_DIR}"
mkdir -p "${SHARED_DIR}/storage/logs"
mkdir -p "${SHARED_DIR}/storage/app/public"
mkdir -p "${SHARED_DIR}/storage/framework/cache"
mkdir -p "${SHARED_DIR}/storage/framework/sessions"
mkdir -p "${SHARED_DIR}/storage/framework/views"
chown -R "$APP_USER":"$APP_USER" "${RELEASES_DIR}" "${SHARED_DIR}"

local is_first_deploy=0
if [ ! -L "$CURRENT_DIR" ] && [ ! -d "$CURRENT_DIR" ]; then
    is_first_deploy=1
fi
