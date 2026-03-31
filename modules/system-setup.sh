#!/usr/bin/env bash
# modules/system.sh
# System Initialization & Security Module

run_system_setup() {
    info "Bắt đầu khởi tạo hệ thống cơ bản và bảo mật..."

    # 1. Update OS
    info "Cập nhật các gói phần mềm (apt update & upgrade)..."
    apt-get update -y && DEBIAN_FRONTEND=noninteractive apt-get upgrade -y -o Dpkg::Options::="--force-confdef" -o Dpkg::Options::="--force-confold"

    # 2. Tạo User & Phân quyền sudo
    if ! id -u "$APP_USER" >/dev/null 2>&1; then
        info "Đang tạo user ứng dụng: $APP_USER"
        useradd -m -s /bin/bash "$APP_USER"
        
        # Cấp quyền sudo không cần mật khẩu cho user ứng dụng (có thể bật/tắt tuỳ chính sách)
        echo "$APP_USER ALL=(ALL) NOPASSWD:ALL" > "/etc/sudoers.d/$APP_USER"
        chmod 0440 "/etc/sudoers.d/$APP_USER"
    else
        warn "User $APP_USER đã tồn tại, tiếp tục..."
    fi

    # 3. Bảo mật SSH (Disable Password Auth & Root Login)
    info "Cấu hình bảo mật SSH..."
    sed -i -e 's/#PasswordAuthentication yes/PasswordAuthentication no/g' \
           -e 's/PasswordAuthentication yes/PasswordAuthentication no/g' \
           -e 's/#PermitRootLogin prohibit-password/PermitRootLogin no/g' \
           -e 's/PermitRootLogin yes/PermitRootLogin no/g' \
           /etc/ssh/sshd_config || true
    systemctl restart sshd

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
    
    # Cấu hình lọc cho MySQL Auth
    if [ -f "$SCRIPT_DIR/configs/fail2ban-mysql-filter.conf" ]; then
        cp "$SCRIPT_DIR/configs/fail2ban-mysql-filter.conf" /etc/fail2ban/filter.d/vps-mysql-auth.conf
        cp "$SCRIPT_DIR/configs/fail2ban-mysql-jail.conf" /etc/fail2ban/jail.d/vps-mysql-auth.conf
        info "Đã cấu hình Fail2ban Jail cho MySQL (vps-mysql-auth)."
    fi

    systemctl enable fail2ban
    systemctl restart fail2ban

    # 6. Unattended Upgrades (Tự động cập nhật gói bảo mật)
    info "Bật tính năng tự động cập nhật hệ điều hành..."
    apt-get install -y unattended-upgrades
    dpkg-reconfigure -plow unattended-upgrades -f noninteractive || true

    # 7. Tích hợp SSH Keys cho Git
    info "Sinh Deploy Key (Ed25519) dùng cho GitHub/GitLab Deployment..."
    su - "$APP_USER" -c "if [ ! -f ~/.ssh/id_ed25519 ]; then ssh-keygen -t ed25519 -C \"deploy_${APP_DOMAIN}\" -N '' -f ~/.ssh/id_ed25519 -q; fi"
    
    # Bypass StrictHostKeyChecking cho các provider phổ biến
    su - "$APP_USER" -c 'mkdir -p ~/.ssh && chmod 700 ~/.ssh'
    cat <<EOF > "/home/$APP_USER/.ssh/config"
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
    chown "$APP_USER":"$APP_USER" "/home/$APP_USER/.ssh/config"
    chmod 600 "/home/$APP_USER/.ssh/config"

    info "================================================================="
    info "THÀNH CÔNG: KHỞI TẠO HỆ THỐNG HOÀN TẤT."
    info "VUI LÒNG COPY PUBLIC KEY DƯỚI ĐÂY LÊN GITHUB/GITLAB (DEPLOY KEYS):"
    echo -e "${YELLOW}"
    cat "/home/$APP_USER/.ssh/id_ed25519.pub"
    echo -e "${NC}"
    info "================================================================="
}
