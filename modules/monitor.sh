#!/usr/bin/env bash
# modules/monitor.sh
# System Resources & App Health Monitor with Telegram Alert

send_telegram() {
    local message="$1"
    if [ ! -z "$TELEGRAM_BOT_TOKEN" ] && [ ! -z "$TELEGRAM_CHAT_ID" ]; then
        curl -s -X POST "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendMessage" \
             -d chat_id="${TELEGRAM_CHAT_ID}" \
             -d text="🔔 <b>VPS ${APP_DOMAIN} Alert:</b> %0A${message}" \
             -d parse_mode="HTML" > /dev/null
    else
        warn "Telegram Token hoặc Chat_ID chưa cấu hình. Bỏ qua gửi report."
    fi
}

check_cpu() {
    # Tính toán CPU Usage % bằng chuỗi top
    local cpu_usage=$(top -bn1 | grep "Cpu(s)" | sed "s/.*, *\([0-9.]*\)%* id.*/\1/" | awk '{print 100 - $1}' | awk '{printf "%.0f\n", $1}')
    if [ "$cpu_usage" -ge "$ALERT_CPU_THRESHOLD" ]; then
        send_telegram "⚠️ Tải CPU đang vượt ngưỡng: ${cpu_usage}%"
    fi
    info "CPU Usage: ${cpu_usage}%"
}

check_ram() {
    local total_ram=$(free -m | awk '/Mem:/ { print $2 }')
    local used_ram=$(free -m | awk '/Mem:/ { print $3 }')
    local ram_usage=$(( (used_ram * 100) / total_ram ))
    
    if [ "$ram_usage" -ge "$ALERT_RAM_THRESHOLD" ]; then
        send_telegram "⚠️ Tải RAM (Bộ nhớ) đang vượt ngưỡng: ${ram_usage}% ($used_ram MB)"
    fi
    info "RAM Usage: ${ram_usage}%"
}

check_disk() {
    # Giám sát phân vùng root "/"
    local disk_usage=$(df -h / | tail -1 | awk '{print $5}' | sed 's/%//')
    if [ "$disk_usage" -ge "$ALERT_DISK_THRESHOLD" ]; then
         send_telegram "🚨 Full ổ đĩa nguy cấp: ${disk_usage}% (Phân vùng / )"
    fi
    info "Disk Usage (Root): ${disk_usage}%"
}

check_all_sites() {
    info "Tiến hành dò tìm sức khoẻ vòng lặp (Health Check) Đa Website..."
    
    # Quét tất cả file .env của từng website
    for env_file in $SCRIPT_DIR/sites/.env.*; do
        # Nếu thư mục rỗng trả về chuỗi "*", bỏ qua
        [ -f "$env_file" ] || continue
        
        local chk_domain=$(grep -oP "(?<=^APP_DOMAIN=\")[^\"]+" "$env_file" || echo "")
        
        if [ ! -z "$chk_domain" ]; then
            local check_url=$( (source "$env_file" >/dev/null 2>&1; eval echo \$HEALTH_CHECK_URL) )
            if [ -z "$check_url" ] || [ "$check_url" = 'https:///up' ]; then
                check_url="https://${chk_domain}/up"
            fi
            # Ping cực nhanh kiểm tra HTTP Status CODE
            local status_code=$(curl --max-time 10 -s -o /dev/null -w "%{http_code}" "$check_url" || echo "000")
            
            # Cho phép mã 200 (OK), 301/302 (Redirect bình thường)
            if [ "$status_code" -ne 200 ] && [ "$status_code" -ne 301 ] && [ "$status_code" -ne 302 ]; then
                 send_telegram "❌ <b>BÁO ĐỘNG SẬP TRANG WEB:</b> %0ATên miền: <a href=\"${check_url}\">${chk_domain}</a> %0AHTTP Lỗi Trả Về: <b>$status_code</b> %0AXin sếp vui lòng kiểm tra ngay!"
                 warn "Phát hiện lỗi HTTP $status_code tại $chk_domain"
            else
                 info "App Ping [ $chk_domain ]: Đang Sống Bình Thường ($status_code)"
            fi
        fi
    done
}

setup_telegram_if_needed() {
    # Bỏ qua tương tác nếu chạy qua crontab
    if [ ! -t 0 ]; then
        if [ -z "$TELEGRAM_BOT_TOKEN" ] || [ -z "$TELEGRAM_CHAT_ID" ]; then
            return 1
        fi

        return
    fi

    local needs_setup=false
    if [ -z "$TELEGRAM_BOT_TOKEN" ] || [ -z "$TELEGRAM_CHAT_ID" ]; then
        needs_setup=true
        info "Bạn chưa cấu hình Bot Telegram. BẮT BUỘC phải cài đặt để sử dụng tính năng Giám sát."
    else
        read -p "Bạn đã cài Telegram rồi, bạn có muốn cấu hình lại Token không? (y/N): " reconf
        if [[ "$reconf" =~ ^[Yy]$ ]]; then
            needs_setup=true
        fi
    fi

    if [ "$needs_setup" = true ]; then
        info "Đang cấu hình Bot Telegram Giám sát Cho Toàn Bộ Máy Chủ..."
        echo "Lấy Token bằng cách chat với @BotFather trên Telegram."
        read -p "Nhập TELEGRAM_BOT_TOKEN (Ví dụ: 123456:ABC-DEF1234): " input_token
        if [ -z "$input_token" ]; then
            error "Token không được để trống. Bắt buộc phải có Bot Telegram mới cho chạy chức năng Giám sát."
        fi

        echo "Lấy Chat ID từ con Bot hoặc chat t.me/userinfobot."
        read -p "Nhập TELEGRAM_CHAT_ID (Ví dụ: -10012345678): " input_chat_id
        if [ -z "$input_chat_id" ]; then
            error "Chat ID không được để trống. Bắt buộc phải có Bot Telegram mới cho chạy chức năng Giám sát."
        fi

        local env_file="$SCRIPT_DIR/.env"
        info "Đang tiến hành lưu cấu hình tĩnh vào $env_file ..."

        if grep -q "^TELEGRAM_BOT_TOKEN=" "$env_file"; then
            sed -i "s|^TELEGRAM_BOT_TOKEN=.*|TELEGRAM_BOT_TOKEN=\"${input_token}\"|g" "$env_file"
        else
            echo "TELEGRAM_BOT_TOKEN=\"${input_token}\"" >> "$env_file"
        fi

        if grep -q "^TELEGRAM_CHAT_ID=" "$env_file"; then
            sed -i "s|^TELEGRAM_CHAT_ID=.*|TELEGRAM_CHAT_ID=\"${input_chat_id}\"|g" "$env_file"
        else
            echo "TELEGRAM_CHAT_ID=\"${input_chat_id}\"" >> "$env_file"
        fi

        export TELEGRAM_BOT_TOKEN="$input_token"
        export TELEGRAM_CHAT_ID="$input_chat_id"

        info "Đang đẩy một Tin nhắn Thử nghiệm lên Group Telegram của bạn..."
        local ip_address=$(hostname -I | awk '{print $1}')
        local test_msg="✅ Chào sếp! Máy chủ VPS <b>($ip_address)</b> đã kết nối thành công. Con Bot Giám sát này sẽ túc trực 24/24 báo cáo Tăng Tải Máy Chủ và Sập Web."
        
        local response_code=$(curl -s -o /dev/null -w "%{http_code}" -X POST "https://api.telegram.org/bot${input_token}/sendMessage" \
             -d chat_id="${input_chat_id}" \
             -d text="${test_msg}" \
             -d parse_mode="HTML")

        if [ "$response_code" -eq 200 ]; then
            info "================================================================="
            info "🔔 THIẾT LẬP THÀNH CÔNG! BẠN VỪA NHẬN ĐƯỢC TIN NHẮN TRÊN ĐIỆN THOẠI"
            info "================================================================="
        else
            error "Hệ thống Báo Lỗi! Không thể gửi Tin nhắn Test (HTTP Lỗi $response_code). Vui lòng check lại Token hoặc Thêm Bot vào Nhóm trước tiên."
        fi
    fi
}

run_monitor() {
    setup_telegram_if_needed
    
    info "Khởi động kịch bản quét Monitor..."
    check_cpu
    check_ram
    check_disk
    check_all_sites
    
    # Thiết lập chạy định kỳ cron 5 phút/lần gọi biến update
    local CRON_CMD="/usr/local/bin/vps monitor"
    if ! crontab -l 2>/dev/null | grep -q "vps monitor"; then
        (crontab -l 2>/dev/null; echo "*/5 * * * * bash $CRON_CMD >/dev/null 2>&1") | crontab -
        info "Đã kích hoạt ngầm hệ thống Cron tự động giám sát 5 Phút 1 Vòng."
    fi
    info "🚀 HOÀN TẤT LƯỢT QUÉT GIÁM SÁT MÁY CHỦ."
}
