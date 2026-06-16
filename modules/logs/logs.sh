#!/usr/bin/env bash
# modules/logs.sh
# Bộ nạp và quản lý Giám sát Log hệ thống

# Nạp sub-module chuyên biệt
load_module "logs/watch.sh" || return 1

