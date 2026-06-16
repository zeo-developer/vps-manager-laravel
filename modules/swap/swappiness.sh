#!/usr/bin/env bash
# modules/swap/swappiness.sh
# Cấu hình chỉ số swappiness cho hệ thống để tối ưu hóa tần suất sử dụng SWAP.

#-----------------------------------------------------------------------------
# Function:     set_swappiness_value
# Description:  Helper function to modify vm.swappiness settings persistently.
# Globals:      None
# Arguments:    $1 - Value (0-100)
# Returns:      None
#-----------------------------------------------------------------------------
set_swappiness_value() {
    local val="${1:-10}"
    sysctl vm.swappiness="$val"
    
    if grep -q "vm.swappiness" /etc/sysctl.conf; then
        sed -i "s/^vm.swappiness=.*/vm.swappiness=$val/" /etc/sysctl.conf
    else
        echo "vm.swappiness=$val" >> /etc/sysctl.conf
    fi
}

#-----------------------------------------------------------------------------
# Function:     configure_swappiness
# Description:  Prompts user for a custom swappiness value and applies it.
# Globals:      None
# Arguments:    None
# Returns:      0 on success, 1 on failure
#-----------------------------------------------------------------------------
configure_swappiness() {
    local val
    read -p "Nhập chỉ số swappiness muốn thiết lập (0-100, khuyên dùng: 10): " val
    val=$(sanitize_input "$val")
    
    if [[ ! "$val" =~ ^[0-9]+$ ]] || [ "$val" -lt 0 ] || [ "$val" -gt 100 ]; then
        error "Chỉ số không hợp lệ. Phải là số nguyên từ 0 đến 100."
        return 1
    fi

    info "Đang cấu hình chỉ số swappiness về $val..."
    set_swappiness_value "$val"
    info "Đã cập nhật swappiness thành công."
    return 0
}
