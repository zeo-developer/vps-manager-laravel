# modules/deploy/phases/cleanup.sh

# -------------------------------------------------------------------------
# PHASE 6: DỌN DẸP (CLEANUP)
# -------------------------------------------------------------------------
info "Dọn dẹp các bản release cũ..."
cd "$RELEASES_DIR"
ls -1t | tail -n +4 | xargs -r rm -rf

info "================================================================="
info " THÀNH CÔNG: Triển khai Zero-Downtime hoàn tất."
info " Bản phát hành: $TIMESTAMP"
info "================================================================="
