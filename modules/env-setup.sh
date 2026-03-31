#!/usr/bin/env bash
# modules/environment.sh
# Môi trường Runtime: PHP, Nginx, Node, Certbot, Redis

run_env_setup() {
    info "Bắt đầu cài đặt môi trường Runtime..."

    # Cài đặt software common
    apt-get install -y software-properties-common curl ca-certificates gnupg zip unzip git

    # 1. Cài đặt PHP
    info "Thêm PPA ondrej/php và cài đặt PHP $PHP_VERSION..."
    add-apt-repository -y ppa:ondrej/php
    apt-get update -y
    
    local php_packages=(
        "php${PHP_VERSION}-cli"
        "php${PHP_VERSION}-fpm"
        "php${PHP_VERSION}-mysql"
        "php${PHP_VERSION}-mbstring"
        "php${PHP_VERSION}-xml"
        "php${PHP_VERSION}-zip"
        "php${PHP_VERSION}-bcmath"
        "php${PHP_VERSION}-curl"
        "php${PHP_VERSION}-intl"
        "php${PHP_VERSION}-gd"
        "php${PHP_VERSION}-redis"
    )
    
    info "Đang cài đặt các packages php: ${php_packages[*]}"
    apt-get install -y "${php_packages[@]}"

    # Chỉnh cấu hình fpm pool chạy dưới quyền user ứng dụng chứ không phải www-data mặc định nếu nó khác www-data
    if [ "$APP_USER" != "www-data" ]; then
        info "Cấu hình PHP-FPM chạy dưới quyền $APP_USER..."
        sed -i "s/user = www-data/user = $APP_USER/g" /etc/php/${PHP_VERSION}/fpm/pool.d/www.conf
        sed -i "s/group = www-data/group = $APP_USER/g" /etc/php/${PHP_VERSION}/fpm/pool.d/www.conf
        sed -i "s/listen.owner = www-data/listen.owner = $APP_USER/g" /etc/php/${PHP_VERSION}/fpm/pool.d/www.conf
        sed -i "s/listen.group = www-data/listen.group = $APP_USER/g" /etc/php/${PHP_VERSION}/fpm/pool.d/www.conf
    fi
    systemctl restart "php${PHP_VERSION}-fpm"
    systemctl enable "php${PHP_VERSION}-fpm"

    # 2. Cài Nginx
    info "Cài đặt Nginx..."
    apt-get install -y nginx
    # Cấu hình tối ưu Nginx cơ bản (ẩn thông tin phiên bản)
    sed -i 's/# server_tokens off;/server_tokens off;/' /etc/nginx/nginx.conf
    systemctl restart nginx
    systemctl enable nginx

    # (Tuỳ chọn: Thư mục www tổng thể)
    mkdir -p /var/www

    # 3. Cài Redis
    info "Cài đặt Redis Server (dùng làm Cache & Queue cho Laravel)..."
    apt-get install -y redis-server
    systemctl enable redis-server
    systemctl start redis-server

    # 4. Cài đặt Composer
    if ! command -v composer &> /dev/null; then
        info "Cài đặt Composer..."
        curl -sS https://getcomposer.org/installer | php
        mv composer.phar /usr/local/bin/composer
    else
        info "Composer đã cài đặt từ trước."
        composer self-update || true
    fi

    # 5. Cài đặt Node.js & NPM (Dùng Node.js 20 LTS NodeSource)
    if ! command -v node &> /dev/null; then
        info "Cài đặt Node.js 20.x..."
        curl -fsSL https://deb.nodesource.com/setup_20.x | bash -
        apt-get install -y nodejs
    else
        info "Node.js đã được cài đặt: $(node -v)"
    fi

    # 6. Cài đặt Certbot (Let's Encrypt)
    info "Cài đặt Certbot..."
    apt-get install -y certbot python3-certbot-nginx
    
    # 7. Cài đặt Supervisor cho Laravel Queue / Reverb
    info "Cài đặt Supervisor..."
    apt-get install -y supervisor
    systemctl enable supervisor
    systemctl start supervisor

    info "================================================================="
    info "THÀNH CÔNG: MÔI TRƯỜNG RUNTIME ĐƯỢC SETUP."
    info "Phiên bản PHP: $(php -v | head -n 1)"
    info "Phiên bản Node.js: $(node -v), NPM: $(npm -v)"
    info "Phiên bản Composer: $(composer --version | head -n 1)"
    info "================================================================="
}
