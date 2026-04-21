#!/usr/bin/env bash
# modules/system.sh
# System Initialization & Security Module

run_system_setup() {
    info "Bắt đầu khởi tạo hệ thống cơ bản và bảo mật..."

    # 1. Update OS
    info "Cập nhật các gói phần mềm (apt update & upgrade)..."
    export NEEDRESTART_MODE=a
    export DEBIAN_FRONTEND=noninteractive
    apt-get update -y -q
    apt-get upgrade -y -q -o Dpkg::Options::="--force-confdef" -o Dpkg::Options::="--force-confold"


    if ! id -u "$APP_USER" >/dev/null 2>&1; then
        info "Đang tạo user ứng dụng: $APP_USER"
        useradd -m -s /bin/bash "$APP_USER"
        
        # Cấp quyền sudo không cần mật khẩu
        echo "$APP_USER ALL=(ALL) NOPASSWD:ALL" > "/etc/sudoers.d/$APP_USER"
        chmod 0440 "/etc/sudoers.d/$APP_USER"
    fi


    sed -i -e 's/#PasswordAuthentication yes/PasswordAuthentication no/g' \
           -e 's/PasswordAuthentication yes/PasswordAuthentication no/g' \
           -e 's/#PermitRootLogin prohibit-password/PermitRootLogin no/g' \
           -e 's/PermitRootLogin yes/PermitRootLogin no/g' \
           /etc/ssh/sshd_config || true
           
    # Cố gắng restart cả ssh (Ubuntu chính) và sshd (bí danh/khác)
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
    
    # Tự động dò tìm thư mục Home của APP_USER (Dùng cho cả user thường và www-data)
    local USER_HOME=$(getent passwd "$APP_USER" | cut -d: -f6)
    USER_HOME="${USER_HOME:-/home/$APP_USER}"
    
    # Đảm bảo thư mục gốc (vd: /var/www) tồn tại
    if [ ! -d "$USER_HOME" ]; then
        info "Khởi tạo thư mục Home [ $USER_HOME ]..."
        mkdir -p "$USER_HOME"
        chown "$APP_USER":"$APP_USER" "$USER_HOME"
    fi

    # Tạo .ssh và sinh Key bằng quyền Root (An toàn nhất)
    mkdir -p "${USER_HOME}/.ssh"
    chmod 700 "${USER_HOME}/.ssh"
    
    if [ ! -f "${USER_HOME}/.ssh/id_ed25519" ]; then
        info "Đang tạo SSH Key mới tại ${USER_HOME}/.ssh/id_ed25519 ..."
        ssh-keygen -t ed25519 -C "deploy_vps_manager" -N "" -f "${USER_HOME}/.ssh/id_ed25519" -q
    fi
    
    # Bypass StrictHostKeyChecking cho các provider phổ biến
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

    # Bàn giao toàn bộ quyền cho APP_USER
    chown -R "$APP_USER":"$APP_USER" "${USER_HOME}/.ssh"
    chmod 600 "${USER_HOME}/.ssh/id_ed25519"
    chmod 644 "${USER_HOME}/.ssh/id_ed25519.pub"
    chmod 600 "${USER_HOME}/.ssh/config"


    info "================================================================="
    info "THÀNH CÔNG: KHỞI TẠO HỆ THỐNG HOÀN TẤT."
    info "VUI LÒNG COPY PUBLIC KEY DƯỚI ĐÂY LÊN GITHUB/GITLAB (DEPLOY KEYS):"
    echo -e "${YELLOW}"
    cat "${USER_HOME}/.ssh/id_ed25519.pub"
    echo -e "${NC}"
    info "================================================================="
}

