# 🚀 VPS Manager CLI - Giải Pháp Quản Trị Laravel Chuyên Nghiệp

> **Công cụ dòng lệnh (CLI) tinh gọn, bảo mật và mạnh mẽ dành cho việc quản lý các ứng dụng Laravel hiện đại trên hệ điều hành Ubuntu.**

---

## 📖 1. Tổng Quan Dự Án (Project Overview)

**VPS Manager CLI** là một bộ công cụ tự động hóa quy trình quản trị máy chủ, được thiết kế để biến một VPS Ubuntu mới thành một môi trường chạy Laravel chuẩn DevOps. 

Công cụ tập trung vào 3 yếu tố cốt lõi: **Tốc độ (Speed)**, **Bảo mật (Security)** và **Tính tiêu chuẩn (Standardization)**. Đặc biệt, dự án hỗ trợ tối ưu cho các công nghệ mới nhất như Inertia SSR, JWT và WebSockets.

---

## 🔥 2. Tính Năng Nổi Bật (Key Features)

### 🏗️ Quản Trị Đa Dự Án (Multi-Site & Multi-Git)
*   **SSH Isolation**: Tự động sinh mã SSH Key độc lập cho từng website. Điều này cho phép triển khai mã nguồn từ nhiều tài khoản GitHub/GitLab khác nhau trên cùng một máy chủ mà không gây xung đột.
*   **PHP Versioning**: Hỗ trợ chuyển đổi linh hoạt giữa các phiên bản PHP 8.1, 8.2, 8.3 và 8.4 cho từng domain riêng biệt.
*   **Database Isolation**: Mỗi website sở hữu cơ sở dữ liệu và người dùng riêng, đảm bảo tính cách ly và an toàn dữ liệu cao nhất.

### 🚀 Quy Trình Triển Khai Hiện Đại (Modern Deployment)
*   **Zero-Downtime Deployment**: Sử dụng cơ chế hoán đổi Symlink giữa các folder Release, giúp website luôn hoạt động ổn định và không bị gián đoạn trong quá trình cập nhật mã nguồn.
*   **Inertia SSR (Server-Side Rendering)**: Tự động quản lý tiến trình Node.js SSR thông qua Supervisor, bao gồm việc cấp phát cổng (Port) tự động và không trùng lặp.
*   **JWT Secret Automation**: Tự động khởi tạo khóa JWT khi triển khai dự án mới, đảm bảo hệ thống xác thực luôn sẵn sàng.
*   **Rollback Tức Thì**: Cho phép khôi phục về phiên bản ổn định gần nhất chỉ trong vài giây nếu bản cập nhật mới gặp sự cố.

### 🛡️ Bảo Mật & Tối Ưu Hệ Thống (Security & Hardening)
*   **MariaDB Secure Wrapper**: Thực thi các lệnh cơ sở dữ liệu thông qua cấu hình tạm thời, giúp ẩn mật khẩu khỏi danh sách tiến trình hệ thống (`ps aux`).
*   **Harden Permissions**: Tự động thiết lập quyền truy cập `600` cho các tệp tin cấu hình nhạy cảm (`.env`) ngay khi khởi tạo.
*   **Fail2ban & Brute-force Shield**: Tích hợp sẵn các bộ lọc bảo vệ cổng SSH (22) và Database (3306), tự động chặn các địa chỉ IP có hành vi tấn công.
*   **Nginx Security Optimization**: Cấu hình Nginx được tinh chỉnh sẵn với Gzip, Cache và các thông số bảo mật chuẩn A+.

---

## 📂 3. Cấu Trúc Mã Nguồn (System Architecture)

```text
/vps-manager
├── vps.sh                  # Tệp tin điều hướng chính (Looping Menu)
├── install.sh              # Trình cài đặt lõi hệ thống (Run once)
├── .env.global.example     # Mẫu cấu hình chung (Telegram, DB Root)
├── .env.site.example       # Mẫu cấu hình cho từng website cụ thể
├── modules/                # Chứa logic các tính năng độc lập
│   ├── site.sh             # Khởi tạo Site/DB/SSH Key/Supervisor
│   ├── deploy.sh           # Quy trình Zero-Downtime & Rollback
│   ├── utils.sh            # Hàm tiện ích & Bảo mật (MySQL Wrapper)
│   ├── manage-db.sh        # Quản lý Database: Remote Access, Grants
│   ├── ssl.sh              # Tự động hóa Let's Encrypt SSL
│   └── info.sh             # Dashboard thông tin chi tiết Website
├── configs/                # Các tệp tin mẫu (Templates)
│   ├── nginx-template.conf # Cấu hình Nginx tối ưu hóa Laravel
│   ├── supervisor-queue.conf # Cấu hình Queue Worker
│   └── supervisor-ssr.conf # Cấu hình Inertia SSR
└── sites/                  # Lưu trữ file cấu hình của từng website
```

---

## 🛠️ 4. Hướng Dẫn Cài Đặt (Installation Guide)

### 4.1. Điều kiện tiên quyết (Prerequisites)
*   **Hệ điều hành**: Ubuntu 22.04 LTS hoặc mới hơn (Khuyên dùng bản mới nhất).
*   **Quyền hạn**: Tài khoản có quyền `sudo` hoặc truy cập trực tiếp bằng `root`.
*   **Trạng thái**: Một VPS "trắng" hoàn toàn để tránh xung đột cấu hình cũ.

### 4.2. Các bước cài đặt (3 Bước)
Chạy các lệnh sau tại Terminal của Server:

```bash
# 1. Tải bộ mã nguồn từ Repository
git clone https://github.com/zeo-developer/vps-manager-laravel.git vps-manager
cd vps-manager

# 2. Cấp quyền thực thi cho các script cài đặt và vận hành
sudo chmod +x install.sh vps.sh

# 3. Chạy trình cài đặt lõi hệ thống
sudo ./install.sh
```

---

## 🎮 5. Hướng Dẫn Vận Hành (Operational Guide)

### 5.1. Quy trình 5 Bước để "Đưa Website lên kệ" (Go-Live Flow)
Đây là quy trình khuyên dùng để triển khai một dự án Laravel mới:

1.  **Thêm Website (Menu 1)**: Nhập domain, chọn phiên bản PHP, chọn cấu hình JWT/SSR.
2.  **Cấu hình Git (Menu 6)**: Vào `Site Info`, copy mã **SSH Public Key** và thêm vào **Deploy Keys** trên GitHub/GitLab của dự án.
3.  **Deploy Code (Menu 3)**: Chạy Deploy lần đầu. Hệ thống sẽ tự động Pull code, cài đặt Library và chạy Migration.
4.  **Cài đặt SSL (Menu 2)**: Sau khi domain đã trỏ IP về Server, chạy trình cài đặt SSL để bật HTTPS (Let's Encrypt).
5.  **Kiểm tra Logs (Menu 9)**: Xem livestream logs để đảm bảo ứng dụng không phát sinh lỗi khởi tạo.

### 5.2. Quản lý trạng thái thông qua CLI
Chỉ cần gõ lệnh sau để mở Menu tương tác:
```bash
sudo vps
```

---

## 🖥️ 6. Chi Tiết Menu Điều Khiển (CLI Menu Reference)

Hệ thống cung cấp menu 12 chức năng chuyên sâu:
1.  **Add Site**: Khởi tạo Web Folder, Database, User MySQL, SSH Key riêng và Supervisor Group.
2.  **SSL Manager**: Tự động hóa Let's Encrypt (Cài mới/Gia hạn).
3.  **Deploy**: Quy trình Zero-Downtime Releases (Giữ lại 3 bản gần nhất).
4.  **Rollback**: Quay xe về bản release ổn định cũ trong 1 giây.
5.  **Remove Site**: Xóa sạch dấu vết website để dọn dẹp tài nguyên VPS.
6.  **Site Info**: Bảng Dashboard kỹ thuật (PHP, Port SSR, SSH Keys).
7.  **Change PHP**: Chuyển đổi giữa 8.1, 8.2, 8.3, 8.4 chỉ bằng 1 nút nhấn.
8.  **Database Manager**: Cấp quyền Remote Access theo IP hoặc theo dải IP.
9.  **View Logs**: Xem logs thực tế (Tail -f) của Laravel và Nginx.
10. **Add Queue**: Tạo thêm các worker chạy ngầm tùy chỉnh.
11. **OS Updater**: Cập nhật hệ điều hành an toàn.
12. **Monitor**: Cấu hình thông báo Telegram cho hệ thống.

---

## ⚙️ 7. Cấu Hình & Tinh Chỉnh (Configuration)

### 7.1. File cấu hình chung (`.env`)
Chứa mật khẩu Database Root và các cấu hình Telegram dùng cho toàn server.

### 7.2. File cấu hình site (`sites/.env.domain`)
Mỗi domain có một file cấu hình riêng, cho phép anh thay đổi:
*   `USE_SSR="true/false"`: Bật/Tắt render phía server.
*   `USE_JWT="true/false"`: Bật/Tắt tự động sinh khóa JWT.
*   `SSH_KEY_PATH`: Đường dẫn chìa khóa private dành cho Git của domain đó.
*   `PHP_VERSION`: Phiên bản PHP đang dùng.

---

## 💡 8. Mẹo & Ghi Chú Vận Hành (Operational Tips)

*   **Quản lý SSH Key**: Người dùng có thể xem lại mã SSH Public Key bất cứ lúc nào thông qua chức năng số **6 (Site Info)**.

*   **Truy cập Database từ xa**: Chức năng số **8** cho phép giới hạn quyền truy cập MySQL từ xa theo địa chỉ IP cụ thể để đảm bảo an ninh.
*   **Giám sát Logs**: Chức năng số **9** cung cấp trình xem log thời gian thực từ Laravel hoặc Nginx giúp xử lý sự cố nhanh chóng.

---

## 🚨 9. Nguyên Tắc Bảo Mật (Security Policy)

1.  **Quyền thực thi**: Các thao tác hệ thống yêu cầu quyền Root để thay đổi cấu hình Nginx và dịch vụ hệ thống.
2.  **Quản lý cấu hình**: Khuyến khích sử dụng menu điều khiển để thay đổi cấu hình thay vì chỉnh sửa thủ công các tệp tin trong thư mục `sites/`.
3.  **Deploy Keys**: Luôn ưu tiên sử dụng Deploy Keys riêng cho từng dự án để tối đa hóa tính bảo mật và cách ly.

---

**Dự án được phát triển và duy trì bởi đội ngũ DevOps VPS Manager.**
**Hướng tới một cộng đồng phát triển Laravel bền vững và bảo mật! 🚀🛡️✨**
