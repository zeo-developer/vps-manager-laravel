#!/usr/bin/env bash
# modules/install/finalize.sh
# Giai đoạn kết thúc cài đặt và cấu hình hoàn tất (Phase Final)

#-----------------------------------------------------------------------------
# Hàm:          run_install_finalize
# Mô tả:        Cấp quyền chạy cho vps.sh, tạo symlinks toàn cục 'vps' và in thông báo hoàn tất.
# Biến toàn cục: SCRIPT_DIR, GREEN, CYAN, NC
# Tham số:      Không có
# Trả về:       Không có
#-----------------------------------------------------------------------------
run_install_finalize() {
    # Cấp quyền thực thi và tạo liên kết tượng trưng (symlink) toàn cục để gõ lệnh 'vps' bất kỳ đâu
    chmod +x "$SCRIPT_DIR/vps.sh"
    ln -nfs "$SCRIPT_DIR/vps.sh" "/usr/local/bin/vps"
    ln -nfs "$SCRIPT_DIR/vps.sh" "/usr/bin/vps"

    echo -e "${GREEN}======================================================================${NC}"
    echo -e "${GREEN}                 HỆ THỐNG ĐÃ CÀI ĐẶT HOÀN TẤT THÀNH CÔNG!             ${NC}"
    echo -e "${GREEN}======================================================================${NC}"
    echo -e ""
    echo -e "Gõ lệnh: ${CYAN}vps${NC} trên Terminal để bắt đầu quản lý VPS của bạn."
    echo -e ""
}
