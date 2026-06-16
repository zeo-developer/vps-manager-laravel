#!/usr/bin/env bash
# modules/install/system.sh
# Khởi tạo hệ thống cơ bản và cấu hình bảo mật (Phase 1)

#-----------------------------------------------------------------------------
# Hàm:          run_system_setup
# Mô tả:        Cập nhật gói OS, cấu hình SSH Keys, Firewall UFW và Fail2Ban.
# Biến toàn cục: APP_USER, UFW_ALLOW_PORTS, SCRIPT_DIR, YELLOW, NC
# Tham số:      Không có
# Trả về:       Không có
#-----------------------------------------------------------------------------
run_system_setup() {
    info "Bắt đầu khởi tạo hệ thống cơ bản và bảo mật..."

    # 1. Cập nhật hệ điều hành (Update OS)
    info "Cập nhật các gói phần mềm (apt update & upgrade)..."
    export NEEDRESTART_MODE=a
    export DEBIAN_FRONTEND=noninteractive
    apt-get update -y -q
    apt-get upgrade -y -q -o Dpkg::Options::="--force-confdef" -o Dpkg::Options::="--force-confold"

    # 2. Tạo User ứng dụng
    if ! id -u "$APP_USER" >/dev/null 2>&1; then
        info "Đang tạo user ứng dụng: $APP_USER"
        useradd -m -s /bin/bash "$APP_USER"
        
        # Cấp quyền sudo không cần mật khẩu
        echo "$APP_USER ALL=(ALL) NOPASSWD:ALL" > "/etc/sudoers.d/$APP_USER"
        chmod 0440 "/etc/sudoers.d/$APP_USER"
    fi

    # 3. Bảo mật dịch vụ SSH (Tắt đăng nhập mật khẩu & root)
    sed -i -e 's/#PasswordAuthentication yes/PasswordAuthentication no/g' \
           -e 's/PasswordAuthentication yes/PasswordAuthentication no/g' \
           -e 's/#PermitRootLogin prohibit-password/PermitRootLogin no/g' \
           -e 's/PermitRootLogin yes/PermitRootLogin no/g' \
           /etc/ssh/sshd_config || true
           
    # Khởi động lại dịch vụ SSH để áp dụng cấu hình
    if systemctl list-units --full -all | grep -Fq 'ssh.service'; then
        systemctl restart ssh
    elif systemctl list-units --full -all | grep -Fq 'sshd.service'; then
        systemctl restart sshd
    fi

    # 4. Định cấu hình UFW (Firewall)
    info "Thiết lập UFW Firewall (Mở cổng: $UFW_ALLOW_PORTS)..."
    apt-get install -y ufw
    ufw --force reset
    ufw default deny incoming
    ufw default allow outgoing
    for port in $UFW_ALLOW_PORTS; do
        ufw allow "$port"
    done
    ufw --force enable

    # 5. Cài đặt Fail2Ban chống Brute Force (SSH & MySQL)
    info "Cài đặt & Kích hoạt Fail2Ban..."
    apt-get install -y fail2ban
    
    # Cấu hình bộ lọc riêng cho việc đăng nhập MySQL/MariaDB
    if [ -f "$SCRIPT_DIR/configs/fail2ban-mysql-filter.conf" ]; then
        cp "$SCRIPT_DIR/configs/fail2ban-mysql-filter.conf" /etc/fail2ban/filter.d/vps-mysql-auth.conf
        cp "$SCRIPT_DIR/configs/fail2ban-mysql-jail.conf" /etc/fail2ban/jail.d/vps-mysql-auth.conf
        info "Đã cấu hình Fail2ban Jail cho MySQL (vps-mysql-auth)."
    fi

    systemctl enable fail2ban
    systemctl restart fail2ban

    # 6. Unattended Upgrades (Tự động cập nhật gói bảo mật định kỳ)
    info "Bật tính năng tự động cập nhật hệ điều hành..."
    apt-get install -y unattended-upgrades
    dpkg-reconfigure -plow unattended-upgrades -f noninteractive || true

    # 7. Tích hợp SSH Keys cho Git
    info "Sinh Deploy Key (Ed25519) dùng cho GitHub/GitLab Deployment..."
    
    # Tìm thư mục Home của APP_USER
    local USER_HOME=$(getent passwd "$APP_USER" | cut -d: -f6)
    USER_HOME="${USER_HOME:-/home/$APP_USER}"
    
    if [ ! -d "$USER_HOME" ]; then
        info "Khởi tạo thư mục Home [ $USER_HOME ]..."
        mkdir -p "$USER_HOME"
        chown "$APP_USER":"$APP_USER" "$USER_HOME"
    fi

    # Tạo thư mục .ssh và sinh SSH Keys
    mkdir -p "${USER_HOME}/.ssh"
    chmod 700 "${USER_HOME}/.ssh"
    
    if [ ! -f "${USER_HOME}/.ssh/id_ed25519" ]; then
        info "Đang tạo SSH Key mới tại ${USER_HOME}/.ssh/id_ed25519 ..."
        ssh-keygen -t ed25519 -C "deploy_vps_manager" -N "" -f "${USER_HOME}/.ssh/id_ed25519" -q
    fi
    
    # Thêm cấu hình tự động bỏ qua kiểm tra SSH host key cho GitHub, GitLab và BitBucket
    cat <<'EOF' > "${USER_HOME}/.ssh/config"
Host github.com
    StrictHostKeyChecking no
    User git

Host gitlab.com
    StrictHostKeyChecking no
    User git

Host bitbucket.org
    StrictHostKeyChecking no
    User git
EOF

    # Bàn giao toàn bộ quyền sở hữu cho APP_USER
    chown -R "$APP_USER":"$APP_USER" "${USER_HOME}/.ssh"
    chmod 600 "${USER_HOME}/.ssh/id_ed25519"
    chmod 644 "${USER_HOME}/.ssh/id_ed25519.pub"
    chmod 600 "${USER_HOME}/.ssh/config"

    info "================================================================="
    info "THÀNH CÔNG: KHỞI TẠO HỆ THỐNG HOÀT TẤT."
    info "VUI LÒNG COPY PUBLIC KEY DƯỚI ĐÂY LÊN GITHUB/GITLAB (DEPLOY KEYS):"
    echo -e "${YELLOW}"
    cat "${USER_HOME}/.ssh/id_ed25519.pub"
    echo -e "${NC}"
    info "================================================================="
}
