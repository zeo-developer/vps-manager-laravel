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
│   ├── site.sh             # Logic khởi tạo Root Web Folder, Database, SSH Key
│   ├── deploy.sh           # Thuật toán CI/CD: Release Build, Symlink và Rollback
│   ├── info.sh             # Report cấu trúc Status cho một dịch vụ Website
│   ├── ssl.sh              # Giao thức Certbot cấu trúc TLS/SSL bảo mật HTTPs
│   ├── php-version.sh      # Xử lý Engine cấu hình Handler PHP động trên khối Nginx
│   ├── manage-db.sh        # Phân quyền IAM (IP Permission) truy cập kết nối Remote Database
│   ├── logs.sh             # Output Stream Logging chuẩn Systemd & Laravel Laravel Logging
│   ├── queue.sh            # Cấu hình biên dịch Background Worker sử dụng Daemon Supervisor
│   ├── rename-domain.sh    # Đồng bộ hóa thay đổi Namespace ứng dụng Domain Base
│   ├── alias.sh            # Gắn kết cấu trúc bản sao tên miền trỏ về Domain Parent
│   ├── swap.sh             # Thiết đặt phân bổ hệ điều hành tạo ảo Volume SWAP
│   ├── monitor.sh          # Payload Alert Engine bắn thông cáo Event sang Telegram API
│   ├── remove-site.sh      # Thực thi quy trình hủy phân vùng độc lập để giải phóng tài nguyên
│   ├── update.sh           # Xác minh các Dependencies và nâng cấp gói Repository APT 
│   ├── db-setup.sh         # Module Script định nghĩa cấu hình và tạo MariaDB User Privilege
│   ├── env-setup.sh        # Quy trình Render ra các chuẩn Template File .env Environment
│   ├── system-setup.sh     # Dependency Check phục vụ module cài đặt Install base Ubuntu 
│   └── utils.sh            # Cấu trúc Functions Helper dùng lại các Validation Color & MariaDB Auth Wrapper
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

Bảng điều khiển (Menu) của hệ thống bao gồm **15 chức năng** giúp đơn giản hóa các thao tác quản trị phức tạp:

1.  **Thêm Website (Add Site)**: Tự động khởi tạo toàn bộ không gian cho website mới: Tạo thư mục chứa code, cài đặt Database phân quyền riêng, tạo thư mục mã hóa SSH Key, và chuẩn bị cấu hình Nginx/Supervisor.
2.  **Quản Lý SSL (SSL Manager)**: Cài đặt và tự động gia hạn chứng chỉ bảo mật HTTPS (Let's Encrypt) chuẩn hóa vào cấu hình Nginx.
3.  **Triển Khai Mã Nguồn (Deploy)**: Tự động tải code mới nhất từ Git và cài đặt ứng dụng. Hỗ trợ 2 chế độ:
    *   **Zero-Downtime:** Tải code vào một thư mục tạm, cài đặt đầy đủ quy trình rồi mới chuyển liên kết vào website đang thực chạy. Đảm bảo website không bao giờ bị lỗi (sập) trong lúc cập nhật.
    *   **Quick Deploy:** Kéo thả code đè trực tiếp lên phiên bản hiện tại, tốc độ nhanh (phù hợp cho các dự án cần fix lỗi nóng cục bộ).
4.  **Khôi Phục Phiên Bản (Rollback)**: Cứu hộ khẩn cấp. Khôi phục trạng thái bộ code ngay lập tức (và tự động lùi cấu trúc Database) về lại phiên bản chạy ổn định trước đó nếu lỗi mã nguồn khi Deploy.
5.  **Xóa Website (Remove Site)**: Dọn dẹp sạch sẽ thư mục code dự án, Database, User MySQL và Nginx Config của website không còn sử dụng để tiết kiệm tài nguyên.
6.  **Xem Thông Tin Website (Site Info)**: Hiển thị bảng tóm tắt thông số dự án (IP Máy chủ, Phiên bản PHP đang dùng, Port Node.js) và xuất chuỗi *SSH Public Key* để khai báo lên tính năng Deploy Keys của GitHub/GitLab.
7.  **Đổi Phiên Bản PHP (Change PHP Version)**: Chuyển đổi linh hoạt hệ thống Website qua lại giữa các phiên bản PHP (8.1 -> 8.4) thao tác riêng rẽ, không làm chập chờn các site khác.
8.  **Quản Lý Database (Manage DB)**: Mở quyền kết nối Remote Database an toàn thông qua cấu hình chặn IP. Cho phép bạn hoặc nhân sự dùng DataGrip/Navicat để kết nối trích xuất CSDL an toàn nhất.
9.  **Giám Sát Log (View Logs)**: Tính năng soi lỗi hệ thống theo thời gian thực (Real-time tracking). Hiển thị song song Log yêu cầu bị lỗi từ Nginx hoặc Log thông báo cấu trúc trong thư mục Laravel.
10. **Thêm Hàng Đợi (Add Queue Worker)**: Thiết lập các tiến trình chạy ngầm qua cấu hình Supervisor (Gửi Email, Export file...) để vận hành Job của Laravel trơn tru mà không lo Script bị kill giữa chừng.
11. **Cập Nhật OS (OS Update)**: Script tự động truy vấn cấu trúc Ubuntu và cài đặt các bản vá lỗi bảo mật Base Dependencies an toàn cho Server.
12. **Cấu Hình Giám Sát (Monitor Setup)**: Kết nối Token Telegram Bot. Giúp nhóm của bạn nhận thông báo trực tiếp qua Chat tự động về quy trình trạng thái khi dự án của bạn Build/Deploy hoàn tất.
13. **Đổi Tên Miền (Rename Domain)**: Giúp dự án "thay tên đổi họ" cấp tốc mà vẫn an toàn. Tool sẽ tự động xử lý đổi tên Thư mục, CSDL, cấu trúc Symlink User cho tên miền hoàn toàn mới.
14. **Quản Lý Domain Ánh Xạ (Domain Alias)**: Cho phép kết nối nhiều cụm tên miền mở rộng (.vn, .net) vào hoạt động chung một Core Source gốc `.com` bằng Nginx Server name ảo. Và bạn có quyền Thêm hoặc Gỡ alias dễ dàng.
15. **Quản Lý Bộ Nhớ Ảo (SWAP Memory)**: Tính năng cứu nguy khi VPS có dung lượng cấu hình thụ động thấp. Nó cho phép bạn trích tạo thêm ổ cứng chuyển thành lượng Cache SWAP giả lập RAM, giải quyết triệt để lỗi giật "Out Of Memory" khi đang chạy lệnh cài đặt NPM (Node / Vite / Npm install) nặng.

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

*   **Bộ Định Tuyến Dịch Vụ Data Từ Xa (Remote Setup Scheme)**: Hệ thống Firewall không thiết lập All-Access Default đối với Data (Tránh lỗi 3306 Phishing Attack). Để công cụ trực quan (DataGrip / DBeaver) làm việc từ Local Computer, bắt buộc yêu cầu Căn cước định dạng cấu hình tại Menu 8 cung cấp Static IP từ Host làm việc.
*   **Tràn Vùng Nhớ Đệm Vật Lý (Build RAM Crisis Handling)**: Quy Trình Dependency Composer Hoặc Build Asset Compilation (NPM packages Install) khi chạy tạo cực lượng IO Resource tải Cache RAM. Khuyến nghị chủ động Setup SWAP (Menu số 16) phân hiệu lớn chuẩn trước thời điểm làm quy trình triển khai phiên bản quy cho Server nhỏ <= 2GB Memory.

---

## 🚨 9. Nguyên Tắc Thao Tác Cơ Sở (Standard Operating Best Practices)

1.  Quy luật thiết kế Code Logic đòi hỏi truy nhập đặc quyền cấu hình thư mục Root Services Linux, File Permission Ownership và Systemctl Services. Lệnh vận hành Tool không thể và nghiêm cấm uỷ quyền (Alias) không dùng prefix `sudo` Root Level.
2.  Ưu tiên vận dụng Tương tác Logic xử lý luồng thao tác thông qua Bảng giao diện cấu hình chính thức (CLI Menu), hạn chế can thiệp thủ công File Template Edit bằng phương thức Vim/Nano Tools trong phân vùng lưu `sites/` tránh việc sai Format System Parsing Script.
3.  Tuân thủ chuẩn bảo mật cấu trúc Repository Access Deploy cấp độ cao nhất. Khuyến nghị: Phân bổ 1 Server Project cấp 1 cặp SSH Data Key Base RSA (Hệ thống đã Auto gen phục vụ bạn) thay phiên giải pháp dùng Profile Token Credentials chung Github Developer (Personal Level Access). Giải pháp này nhằm cắt đứt quyền truy xuất hệ sinh thái Repo Server khác khi 1 Root Server bị phơi nhiễm.

---

**Cộng Đồng VPS DevOps Engineer - Nền Kiến Trúc Chuẩn Sinh Tính Sẵn Sàng Lưu Trữ Cơ Sở Cao Bậc! 🛡️**
