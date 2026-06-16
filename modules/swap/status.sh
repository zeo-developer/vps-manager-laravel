#!/usr/bin/env bash
# modules/swap/status.sh
# Kiểm tra và hiển thị trạng thái hiện tại của bộ nhớ ảo SWAP.

#-----------------------------------------------------------------------------
# Function:     show_swap_status
# Description:  Displays the current active SWAP configuration, RAM usage,
#               and system swappiness value.
# Globals:      CYAN, NC, BLUE
# Arguments:    None
# Returns:      None
#-----------------------------------------------------------------------------
show_swap_status() {
    echo -e "${CYAN}------------------------------------------${NC}"
    echo -e " ${BLUE}Trạng thái SWAP hiện tại:${NC}"
    echo -e "${CYAN}------------------------------------------${NC}"
    if command -v swapon &> /dev/null; then
        swapon --show
    else
        echo "Lệnh swapon không tồn tại."
    fi
    echo ""
    free -h
    echo -e "${CYAN}------------------------------------------${NC}"
    echo -ne " ${BLUE}Chỉ số Swappiness hiện tại:${NC} "
    if [ -f /proc/sys/vm/swappiness ]; then
        cat /proc/sys/vm/swappiness
    else
        echo "N/A"
    fi
}
