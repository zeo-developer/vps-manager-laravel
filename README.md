# 🚀 VPS Manager CLI - Giải Pháp Quản Trị Hệ Thống Chuyên Nghiệp

> **Công cụ dòng lệnh (CLI) tinh gọn, bảo mật và mạnh mẽ dành cho việc quản trị các ứng dụng Laravel hiện đại trên hệ điều hành Ubuntu.**

---

## 📖 1. Tổng Quan Dự Án (Project Overview)

**VPS Manager CLI** là một bộ công cụ tự động hóa quy trình quản trị máy chủ, được thiết kế để chuẩn hoá một VPS Ubuntu nguyên bản thành môi trường vận hành (production environment) đáp ứng tiêu chuẩn DevOps.

Dự án tập trung vào 3 tiêu chí cốt lõi: **Hiệu năng (Performance)**, **Bảo mật (Security)** và **Tính tiêu chuẩn hoá (Standardization)**. Đặc biệt, bộ công cụ hỗ trợ cấu hình tự động cho các công nghệ hiện đại như Inertia SSR, JWT Auth và xử lý Background Jobs.

---

## 🔥 2. Tính Năng Nổi Bật (Key Features)

### 🏗️ Quản Trị Đa Dự Án (Multi-Site & Isolation)
*   **SSH Isolation**: Định danh độc lập phân tách SSH Key cho từng website. Cơ chế này đảm bảo máy chủ kết nối an toàn với nhiều Repository lưu trữ khác nhau mà không phát sinh xung đột định danh.
*   **PHP Versioning**: Hỗ trợ chỉ định và chuyển đổi phiên bản PHP (8.1, 8.2, 8.3, 8.4) phân lập cho từng tên miền (domain) cụ thể thông qua cấu hình Nginx Handler nội bộ.
*   **Node.js Versioning**: Mỗi website có `NODE_VERSION` riêng được liên kết với các wrapper toàn cục `node${version}`, `npm${version}`, `npx${version}` tại `/usr/local/bin/`. Supervisor SSR sẽ nạp trực tiếp PATH trỏ tới thư mục bin thực tế tương ứng của `n`, đảm bảo build Vite/Inertia SSR chạy đúng runtime cô lập theo site và loại bỏ rác wrapper cục bộ.
*   **Database Isolation**: Định tuyến cơ sở dữ liệu và người dùng riêng biệt trên hệ sinh thái MariaDB cho mỗi dự án, tuân thủ nguyên tắc an toàn dữ liệu và quyền truy cập.

### 🌐 Domain Identity & Routing
*   **Domain Alias**: Định danh đa tên miền (Parked Domains), cho phép trỏ đồng thời hệ thống mạng lưới tên miền phụ hoặc server name cấp vùng (.vn, .net) vào chung một mã nguồn `public` mà không cần thiết lập lại cấu trúc lưu trữ độc lập.
*   **Rename Domain**: Tự động hóa quá trình di chuyển cấu trúc hệ thống sang tên miền mới hoàn toàn (bao gồm thư mục Root, liên kết vật lý cơ sở dữ liệu, và khai báo lại cấu hình Virtual Host Nginx).

### 🚀 Quy Trình Triển Khai Phương Thức Kỹ Thuật (Modern Deployment)
*   **Zero-Downtime Deployment**: Chế độ triển khai tự động duy trì tính sẵn sàng cao, sử dụng cơ chế liên kết động (Symlink Mapping) để hoán đổi thư mục chứa bản phát hành (release), đảm bảo dịch vụ không bị gián đoạn.
*   **Quick Deploy**: Tùy chọn CI/CD tối giản, cho phép đồng bộ hóa dữ liệu trực tiếp (Git Pull) vào thư mục dang chạy phục vụ chu trình kiểm thử và vá lỗi nóng (Hotfix).
*   **Inertia SSR Management**: Tự động quản lý vòng đời tiến trình Node.js Server-Side Rendering thông qua dịch vụ Supervisor daemon và tự động cấp phát luồng cổng giao diện nội bộ.
*   **Instant Rollback**: Giảm thiểu thiệt hại thời gian khi có sự cố ứng dụng sau triển khai, bằng cơ chế khôi phục liên kết thư mục lập tức về bộ tệp tin ổn định liền kề trong chuỗi lưu trữ hệ thống.

### 🛡️ Bảo Mật & Tinh Chỉnh Hệ Thống (Security & Hardening)
*   **Dynamic SWAP Allocation**: Cấp phát tức thời bộ nhớ ảo (SWAP) làm tài nguyên giải nén lưu lớn, phòng tránh hiện tượng sập hệ thống (OOM) trong tiến trình Compile Asset Front-End (Vite/Node) hay Composer Installer.
*   **MariaDB Secure Wrapper**: Thực thi thao tác SQL thông qua cấu hình ẩn tạm thời (my.cnf bypass), loại trừ việc phơi nhiễm chuỗi cấu trúc mật khẩu lên lưới phân tích System Processes (`ps aux`).
*   **Fail2ban System & Hardening Policies**: Tổ hợp bộ lọc lớp phòng thủ chuyên dụng (Fail2ban SSH/Port 3306 IP Ban) và thắt chặt quyền hạn tệp tin định dạng cấu hình `.env` mặc định dưới tham số `600` bảo mật.

---

## 📂 3. Cấu Trúc Ngôn Ngữ Bảng (System Architecture)

```text
/vps-manager
├── vps.sh                  # Công cụ dòng lệnh tương tác gốc (CLI Root Menu)
├── install.sh              # Trình khởi tạo thiết lập tài nguyên Hệ thống OS
├── .env.global.example     # Tổ hợp cấu hình vận hành nội bộ (Telegram/DB Root)
├── .env.site.example       # Mẫu thiết lập tham số cho từng cấu hình Domain
├── modules/                # Tập hợp thư viện Core Bash Scripts điều khiển riêng
│   ├── db/                 # Thư mục con chứa các file quản lý Database
│   │   ├── db.sh           # Loader điều phối quản lý CSDL (password, remote access)
│   │   ├── password.sh     # Đổi mật khẩu database của website
│   │   └── remote.sh       # Quản lý quyền truy cập MySQL từ xa qua IP
│   ├── deploy/             # Thư mục con chứa các file Deploy & Rollback
│   │   ├── deploy.sh       # Loader điều phối triển khai và khôi phục website
│   │   ├── main.sh         # Thuật toán CI/CD Zero-Downtime Deploy
│   │   └── rollback.sh     # Thuật toán Rollback phiên bản cũ
│   ├── domain/             # Thư mục con chứa các file quản lý Domain
│   │   ├── domain.sh       # Menu phụ điều phối Quản lý Website
│   │   ├── add.sh          # Tạo mới website (Nginx, DB, SSL, SSH Key)
│   │   ├── alias.sh        # Quản lý ánh xạ tên miền phụ (Domain Alias)
│   │   ├── delete.sh       # Xóa website và giải phóng tài nguyên
│   │   ├── info.sh         # Xem thông tin chi tiết trạng thái Website
│   │   └── rename.sh       # Thay đổi tên miền của website
│   ├── install/            # Thư mục con chứa các phase cài đặt của install.sh
│   │   ├── db.sh           # Thiết lập MariaDB Server, backup, logrotate
│   │   ├── env.sh          # Cài đặt Web Stack runtime (Nginx, PHP, Node.js...)
│   │   ├── finalize.sh     # Tạo symlink vps toàn cục để gọi qua CLI
│   │   ├── init.sh         # Khởi tạo môi trường, kiểm tra root, sinh pass MariaDB
│   │   ├── menu.sh         # Hiển thị menu giới thiệu tiến trình cài đặt
│   │   └── system.sh       # Cấu hình OS, SSH, Firewall, Fail2Ban
│   ├── laravel/            # Thư mục con chứa các file quản lý Laravel
│   │   ├── laravel.sh      # Loader điều phối quản lý dự án Laravel
│   │   ├── artisan.sh      # Thực thi lệnh Artisan (migrate, rollback, key, jwt, link)
│   │   ├── build.sh        # Biên dịch asset front-end (npm run build/build:ssr)
│   │   ├── cache.sh        # Dọn dẹp cache và lưu cấu hình tối ưu hiệu năng
│   │   ├── queue.sh        # Cấu hình Custom Queue Worker cho Laravel
│   │   ├── scheduler.sh    # Bật/tắt Laravel Scheduler
│   │   └── ssr.sh          # Bật/tắt và quản lý Supervisor Inertia SSR
│   ├── logs/               # Thư mục con chứa các file quản lý Log
│   │   ├── logs.sh         # Loader quản lý Giám sát Log hệ thống
│   │   └── watch.sh        # Trình theo dõi realtime các luồng log
│   ├── runtime/            # Thư mục con chứa các file quản lý Runtime
│   │   ├── runtime.sh      # Loader quản lý runtime PHP và Node.js
│   │   ├── node.sh         # Quản lý Node.js và wrapper toàn cục
│   │   └── php.sh          # Quản lý PHP-FPM socket và php wrapper
│   ├── ssl/                # Thư mục con chứa các file quản lý SSL
│   │   ├── ssl.sh          # Loader quản lý Chứng chỉ SSL Let's Encrypt
│   │   ├── install.sh      # Cài đặt SSL Let's Encrypt
│   │   └── renew.sh        # Gia hạn tự động chứng chỉ SSL
│   ├── swap/               # Thư mục con chứa các file quản lý SWAP
│   │   ├── swap.sh         # Loader quản lý bộ nhớ ảo SWAP
│   │   ├── create.sh       # Tạo mới file SWAP
│   │   ├── delete.sh       # Xóa bỏ file SWAP hiện tại
│   │   ├── status.sh       # Kiểm tra trạng thái bộ nhớ ảo SWAP
│   │   └── swappiness.sh   # Cấu hình chỉ số Swappiness hệ thống
│   ├── update/             # Thư mục con chứa các file cập nhật hệ thống
│   │   ├── update.sh       # Loader quản lý Cập nhật hệ thống
│   │   └── run.sh          # Cập nhật hệ thống OS & dọn dẹp RAM Cache
│   └── utils.sh            # Các hàm helper kiểm tra, xuất dữ liệu và MariaDB Auth
├── configs/                # Thành phần nguyên mẫu (Templates Configurations Structure)
│   ├── nginx-template.conf # Khối Nginx Server Block chuẩn cấu hình hiệu năng cao Framework Route
│   ├── supervisor-queue.conf # Thiết lập Template cho Backend Queue Manager
│   └── supervisor-ssr.conf # Thiết lập Template hỗ trợ InertiaJs Request Engine Side
└── sites/                  # Không trung lưu trữ bộ thiết lập Status State sau biên dịch
```

---

## 🛠️ 4. Yêu Cầu và Cài Đặt (Installation Details)

### 4.1. Điều kiện tiên quyết (Prerequisites)
*   **Hệ quy chiếu OS**: Sử dụng System Server Ubuntu 22.04 LTS (Hoặc phiên bản cập nhật LTS mới hơn).
*   **Quyền Hạn Tham Số**: Phiên đăng nhập thực hiện với cấu hình user `root` vật lý hoặc account có đặc quyền nhóm `sudo` mức cao nhất.
*   **Tính Cục Bộ**: Chỉ áp dụng với hệ điều hành chưa từng cài đặt các Stack dịch vụ máy chủ bên thứ ba cũ để loại bỏ rủi ro xung đột Configuration (Porting/Path).

### 4.2. Khởi tạo Căn Bản (3 Bước)

```bash
# 1. Đồng bộ mã dự án cài đặt từ Github Hub
git clone https://github.com/zeo-developer/vps-manager-laravel.git vps-manager
cd vps-manager

# 2. Xử lý cấp quyền truy cập thao tác bash logic (Execution Rights)
sudo chmod +x install.sh vps.sh

# 3. Kích hoạt biên dịch trình cài đặt System Libraries
sudo ./install.sh
```

---

## 🎮 5. Hướng Dẫn Vận Hành (Operational Guide)

### 5.1. Quy trình Triển khai Tiêu chuẩn (Go-Live Flow)
Để triển khai một dự án lưu trữ chuẩn mực, hệ thống yêu cầu tuân thủ trình tự vòng đời khép kín sau:

1.  **Khởi Tạo Hệ Thống (Menu 1 - Add Site)**: Khai báo định dạng Domain chuẩn và khai báo điều kiện vận hành tương thích (Chọn Version PHP-FPM Engine, kích hoạt khóa JWT, phân bổ Service NodeJs SSR).
2.  **Thông Quan Kho Lưu Trữ (Menu 6 - Site Info)**: Lấy khóa **SSH Public Key** riêng biệt tự động cấp phép và đính kèm trên quản trị **Deploy Keys** (Source Provider GitHub/GitLab). Động tác này xác thực kênh tải về minh bạch.
3.  **Thực thi Triển Khai (Menu 3 - Deploy)**: Kích hoạt Automated Pipeline. Trình tự bao gồm: System Clone Source Version, giải quyết các Software Dependencies (Bằng Composer/NPM), xây dựng Compile Asset Bundle tĩnh, chạy Routing config Caching và thi triển cập nhật Database Migrations lược đồ thực tiễn.
4.  **Khởi động Tầng Bảo Mật (Menu 2 - SSL Manager)**: Khi Records Local Name System Server được phân giải thành công (Lookup Match IP), kích hoạt quy trình Request mã thiết lập chứng chỉ tự động SSL Certbot/ZeroSSL. Đảm bảo cổng Port 443 truy cập hoạt động.
5.  **Tầm Cáo Khả Dụng Hệ Web (Menu 9 - View Logs)**: Rà soát quá trình tải trang bằng tiện ích Output Tail theo thời gian thực (Giữa Nginx Proxy Access, Base Log Errors, Service PHP FPM). Giám định tính ổn định cuối cùng của luồng hoạt động ứng dụng cung cấp.

### 5.2. Công Cụ Lệnh Quản Trị
Truy cập trực tiếp Giao diện Main Menu hệ sinh thái bằng phương thức command toàn cục (Global Alias) ở bất kì đâu:
```bash
sudo vps
```

---

## 🖥️ 6. Chi Tiết Tính Năng Cốt Lõi (CLI Menu Reference)

Bảng điều khiển (Menu Dashboard) của hệ thống bao gồm **9 nhóm chức năng chính** được thiết kế tinh gọn và dễ sử dụng:

1.  **Quản lý Website (Domain, Alias)**: Menu phụ tập hợp toàn bộ các tính năng tương tác với Website:
    *   **Thêm Website:** Tự động tạo thư mục, cấu hình Nginx/Supervisor, sinh SSH Deploy Keys và tạo Database riêng.
    *   **Xem thông tin Website:** Hiển thị chi tiết trạng thái SSL, PHP, Node.js, CSDL và lấy khóa SSH Public Key.
    *   **Thay đổi tên miền:** Đổi tên thư mục, CSDL và cấu hình Virtual Host Nginx sang tên miền mới.
    *   **Quản lý tên miền ánh xạ (Domain Alias):** Liên kết nhiều tên miền phụ hoặc tên miền song song trỏ vào chung một mã nguồn.
    *   **Xóa Website:** Giải phóng tài nguyên hệ thống bằng cách xóa sạch code, CSDL, cấu hình Nginx và Supervisor.
2.  **Quản lý SSL Let's Encrypt**: Cài đặt và tự động gia hạn chứng chỉ HTTPS miễn phí, đồng bộ thiết lập an toàn vào Nginx.
3.  **Triển khai & Khôi phục (Deploy/Rollback)**: Quản lý vòng đời dự án:
    *   **Deploy (Zero-Downtime):** Tải mã nguồn mới nhất từ Git, chạy Composer/NPM install, biên dịch Asset và hoán đổi symlink an toàn.
    *   **Rollback:** Khôi phục nhanh về bản phát hành ổn định trước đó (và tự động lùi cấu trúc CSDL nếu cần).
4.  **Quản lý phiên bản PHP & Node.js (Runtime)**: Cấu hình môi trường thực thi:
    *   **PHP Version:** Chuyển đổi linh hoạt giữa PHP 8.1 - 8.4 và chạy trực tiếp phiên bản tương ứng toàn cục.
    *   **Node.js Version:** Gán phiên bản Node.js (18 - 24) và tự động tạo các symlink/wrapper toàn cục (`node${version}`, `npm${version}`) để build asset cô lập.
5.  **Quản lý Cơ sở dữ liệu**: Đổi mật khẩu CSDL của website (tự động cập nhật file `.env` dự án) và cho phép/ngăn chặn kết nối MySQL từ xa bằng cách giới hạn quyền theo IP trên tường lửa UFW.
6.  **Quản lý Laravel (Artisan, SSR, Cache, Scheduler)**: Các công cụ dành riêng cho dự án Laravel:
    *   Chạy Database Migration & Rollback.
    *   Bật/Tắt & Khởi động lại dịch vụ Inertia Server-Side Rendering (SSR) quản lý bởi Supervisor daemon.
    *   Tạo Application Key (`key:generate`) & sinh khóa JWT secret.
    *   Tạo liên kết dữ liệu (`storage:link`).
    *   Dọn dẹp cache hệ thống & Lưu cache cấu hình tối ưu hiệu năng (`config:cache`, `route:cache`, `view:cache`).
    *   Biên dịch Asset front-end (`npm run build` / `npm run build:ssr`) thủ công.
    *   Bật/Tắt Laravel Scheduler (`artisan schedule:run`) tự động hàng phút cho website.
    *   Thêm Custom Queue Worker (Laravel) chạy ngầm qua Supervisor.
7.  **Xem Logs (Realtime)**: Theo dõi trực quan lỗi hệ thống theo thời gian thực (Laravel logs, Nginx access/error logs, hoặc xem kết hợp).
8.  **Cập nhật máy chủ (OS Update)**: Quét và cập nhật các bản vá lỗi bảo mật, đồng thời giải phóng RAM PageCache và dọn dẹp journald log dung lượng lớn để giải phóng đĩa cứng.
9.  **Quản lý SWAP Memory**: Cứu nguy cho VPS cấu hình thấp bằng cách cấp phát tức thời ổ cứng ảo làm bộ nhớ đệm RAM ảo (SWAP), ngăn chặn lỗi Out of Memory (OOM) khi compile asset.

---

## ⚙️ 7. Quản Trị Khung Cấu Hình Tham Số Bối Cảnh (Configuration States)

### 7.1. Cấu hình Tham Số Trung Ương Server Context (`.env` root directory)
Bộ trạng thái môi trường cốt lõi quản trị định danh mức cao nhất `DB_ROOT` password bảo hộ kết nối Local và Token Credentials tích hợp hệ thống Monitor `TELEGRAM_BOT_TOKEN`. Định hình Global Variables.

### 7.2. Cấu hình Tham Số Cục Bộ Domain State Zone (`sites/.env.[Domain]`)
Được tạo ngầm và Maintain lưu thông do CLI. Cung cấp tham chiếu định tuyến phân nhánh Application Setting Logic:
*   `USE_SSR=true/false` - Boolean thiết đặt quyết định Server Runtime biên dịch PM2 Node tiến trình View.
*   `USE_JWT=true/false` - Kích hoạt Automated Hook để tiêm vào Generate Token String JWT API Guard Security.
*   `PHP_VERSION` - Định chuẩn Variable PHP Container Service Link Engine sử dụng chạy khối FPM.
*   `SSH_KEY_PATH` - Đường truyền liên kết tới Authentication Private Module RSA Key Identifiers giúp Pipeline Agent Fetch Remote Repo an toàn.

---

## 💡 8. Phụ Lục Vận Hành Kỹ Thuật (Operational Glossary Checklists)

*   **Bộ Định Tuyến Dịch Vụ Data Từ Xa (Remote Setup Scheme)**: Hệ thống Firewall không thiết lập All-Access Default đối với Data (Tránh lỗi 3306 Phishing Attack). Để công cụ trực quan (DataGrip / DBeaver) làm việc từ Local Computer, bắt buộc yêu cầu cấu hình tại Menu 5 cung cấp Static IP từ Host làm việc.
*   **Tràn Vùng Nhớ Đệm Vật Lý (Build RAM Crisis Handling)**: Quy Trình Dependency Composer Hoặc Build Asset Compilation (NPM packages Install) khi chạy tạo cực lượng IO Resource tải Cache RAM. Khuyến nghị chủ động Setup SWAP (Menu số 9) phân hiệu lớn chuẩn trước thời điểm làm quy trình triển khai phiên bản quy cho Server nhỏ <= 2GB Memory.

---

## 🚨 9. Nguyên Tắc Thao Tác Cơ Sở (Standard Operating Best Practices)

1.  Quy luật thiết kế Code Logic đòi hỏi truy nhập đặc quyền cấu hình thư mục Root Services Linux, File Permission Ownership và Systemctl Services. Lệnh vận hành Tool không thể và nghiêm cấm uỷ quyền (Alias) không dùng prefix `sudo` Root Level.
2.  Ưu tiên vận dụng Tương tác Logic xử lý luồng thao tác thông qua Bảng giao diện cấu hình chính thức (CLI Menu), hạn chế can thiệp thủ công File Template Edit bằng phương thức Vim/Nano Tools trong phân vùng lưu `sites/` tránh việc sai Format System Parsing Script.
3.  Tuân thủ chuẩn bảo mật cấu trúc Repository Access Deploy cấp độ cao nhất. Khuyến nghị: Phân bổ 1 Server Project cấp 1 cặp SSH Data Key Base RSA (Hệ thống đã Auto gen phục vụ bạn) thay phiên giải pháp dùng Profile Token Credentials chung Github Developer (Personal Level Access). Giải pháp này nhằm cắt đứt quyền truy xuất hệ sinh thái Repo Server khác khi 1 Root Server bị phơi nhiễm.

---

**Cộng Đồng VPS DevOps Engineer - Nền Kiến Trúc Chuẩn Sinh Tính Sẵn Sàng Lưu Trữ Cơ Sở Cao Bậc! 🛡️**
