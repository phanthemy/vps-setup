#!/bin/bash
# ============================================================
#  VPS AUTO SETUP SCRIPT
#  Tác giả: phanthemy@gmail.com
#  Dùng cho: Ubuntu 22.04 / 24.04 (Oracle Always Free)
#  Projects: wasypro | myspa-jinshang | nhatro
# ============================================================

set -e  # Dừng nếu có lỗi

# ---------- MÀU SẮC ----------
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m'

log()    { echo -e "${GREEN}[✓]${NC} $1"; }
warn()   { echo -e "${YELLOW}[!]${NC} $1"; }
error()  { echo -e "${RED}[✗]${NC} $1"; exit 1; }
header() { echo -e "\n${BLUE}═══════════════════════════════════${NC}"; echo -e "${BLUE}  $1${NC}"; echo -e "${BLUE}═══════════════════════════════════${NC}"; }

# ============================================================
# BƯỚC 0: KIỂM TRA QUYỀN ROOT
# ============================================================
if [ "$EUID" -ne 0 ]; then
  error "Chạy script bằng sudo: sudo bash install_vps.sh"
fi

header "VPS SETUP - BẮT ĐẦU"
echo "Thời gian: $(date)"
echo "User: $(whoami)"
echo "OS: $(lsb_release -d | cut -f2)"
echo ""

# ============================================================
# BƯỚC 1: CẬP NHẬT HỆ THỐNG
# ============================================================
header "BƯỚC 1: Cập nhật hệ thống"
apt update -y && apt upgrade -y
apt install -y curl wget git unzip zip build-essential software-properties-common \
               ca-certificates gnupg lsb-release ufw fail2ban dnsutils
log "Cập nhật hệ thống xong"

# ============================================================
# BƯỚC 2: CÀI NODE.JS 20 LTS
# ============================================================
header "BƯỚC 2: Cài Node.js 20 LTS"
if ! command -v node &>/dev/null; then
  curl -fsSL https://deb.nodesource.com/setup_20.x | bash -
  apt install -y nodejs
  log "Node.js $(node -v) đã cài"
else
  warn "Node.js đã có: $(node -v)"
fi

# ============================================================
# BƯỚC 3: CÀI PM2
# ============================================================
header "BƯỚC 3: Cài PM2"
if ! command -v pm2 &>/dev/null; then
  npm install -g pm2
  pm2 startup systemd -u ubuntu --hp /home/ubuntu | tail -1 | bash || true
  log "PM2 $(pm2 -v) đã cài"
else
  warn "PM2 đã có: $(pm2 -v)"
fi

# ============================================================
# BƯỚC 4: CÀI POSTGRESQL
# ============================================================
header "BƯỚC 4: Cài PostgreSQL"
if ! command -v psql &>/dev/null; then
  apt install -y postgresql postgresql-contrib
  systemctl enable postgresql
  systemctl start postgresql
  log "PostgreSQL đã cài và khởi động"
else
  warn "PostgreSQL đã có: $(psql --version)"
fi

# Tạo database và user
DB_NAME="crm_dev"
DB_USER="erp"
DB_PASS="erp@2024"

sudo -u postgres psql -c "CREATE USER ${DB_USER} WITH PASSWORD '${DB_PASS}';" 2>/dev/null || warn "User ${DB_USER} đã tồn tại"
sudo -u postgres psql -c "CREATE DATABASE ${DB_NAME} OWNER ${DB_USER};" 2>/dev/null || warn "Database ${DB_NAME} đã tồn tại"
sudo -u postgres psql -c "GRANT ALL PRIVILEGES ON DATABASE ${DB_NAME} TO ${DB_USER};" 2>/dev/null || true
log "Database '${DB_NAME}' với user '${DB_USER}' đã sẵn sàng"

# ============================================================
# BƯỚC 5: CÀI NGINX
# ============================================================
header "BƯỚC 5: Cài Nginx"
if ! command -v nginx &>/dev/null; then
  apt install -y nginx
  systemctl enable nginx
  systemctl start nginx
  log "Nginx $(nginx -v 2>&1 | cut -d/ -f2) đã cài"
else
  warn "Nginx đã có"
fi

# ============================================================
# BƯỚC 6: CÀI CERTBOT (SSL Let's Encrypt)
# ============================================================
header "BƯỚC 6: Cài Certbot SSL"
if ! command -v certbot &>/dev/null; then
  apt install -y certbot python3-certbot-nginx
  log "Certbot đã cài"
else
  warn "Certbot đã có"
fi

# ============================================================
# BƯỚC 7: CẤU HÌNH FIREWALL (UFW)
# ============================================================
header "BƯỚC 7: Cấu hình Firewall (UFW)"
# Lưu ý: CSF đã ngừng phát triển từ 8/2025 → dùng UFW + Fail2Ban thay thế
ufw --force reset
ufw default deny incoming
ufw default allow outgoing
ufw allow 22/tcp    comment 'SSH'
ufw allow 80/tcp    comment 'HTTP'
ufw allow 443/tcp   comment 'HTTPS'
ufw allow 10000/tcp comment 'Webmin'
# Port 3010,3011,5174,5175,3000 chỉ dùng internal qua nginx - KHÔNG mở public
ufw --force enable
log "Firewall UFW đã cấu hình (SSH + HTTP + HTTPS + Webmin)"
ufw status verbose

# ============================================================
# BƯỚC 8: CẤU HÌNH FAIL2BAN
# ============================================================
header "BƯỚC 8: Cấu hình Fail2Ban (thay thế CSF brute-force protection)"
cat > /etc/fail2ban/jail.local << 'EOF'
[DEFAULT]
bantime  = 3600
findtime = 600
maxretry = 5
ignoreip = 127.0.0.1/8 ::1

[sshd]
enabled  = true
port     = ssh
logpath  = %(sshd_log)s
backend  = %(sshd_backend)s
maxretry = 3

[nginx-http-auth]
enabled  = true

[nginx-limit-req]
enabled  = true
filter   = nginx-limit-req
action   = iptables-multiport[name=ReqLimit, port="http,https"]
logpath  = /var/log/nginx/error.log
findtime = 600
bantime  = 7200
maxretry = 10
EOF
systemctl enable fail2ban
systemctl restart fail2ban
log "Fail2Ban đã cấu hình"

# ============================================================
# BƯỚC 8B: CÀI WEBMIN (GUI quản lý tường lửa thay CSF)
# ============================================================
header "BƯỚC 8B: Cài Webmin (GUI firewall thay thế CSF)"
if ! command -v webmin &>/dev/null && [ ! -f /etc/webmin/miniserv.conf ]; then
  # Cài dependencies
  apt install -y perl libnet-ssleay-perl openssl libauthen-pam-perl \
                 libpam-runtime libio-pty-perl apt-show-versions python3 \
                 libwww-perl liblwp-protocol-https-perl 2>/dev/null || true

  # Thêm Webmin repo
  curl -fsSL https://download.webmin.com/jcameron-key.asc | gpg --dearmor -o /usr/share/keyrings/webmin.gpg 2>/dev/null
  echo "deb [signed-by=/usr/share/keyrings/webmin.gpg] https://download.webmin.com/download/repository sarge contrib" \
    > /etc/apt/sources.list.d/webmin.list
  apt update -y
  apt install -y webmin

  # Cấu hình Webmin
  systemctl enable webmin
  systemctl start webmin

  log "Webmin đã cài - truy cập: https://YOUR_VPS_IP:10000"
  warn "Đăng nhập Webmin bằng user 'root' hoặc 'ubuntu' của VPS"
  warn "Vào: Webmin → Networking → Linux Firewall để quản lý firewall bằng GUI"
else
  warn "Webmin đã có"
fi

# ============================================================
# BƯỚC 9: TẠO CẤU TRÚC THƯ MỤC
# ============================================================
header "BƯỚC 9: Tạo cấu trúc thư mục"
mkdir -p /var/www/wasypro
mkdir -p /var/www/myspa
mkdir -p /var/www/nhatro
chown -R ubuntu:ubuntu /var/www/wasypro
chown -R ubuntu:ubuntu /var/www/myspa
chown -R ubuntu:ubuntu /var/www/nhatro
log "Thư mục /var/www/wasypro, /var/www/myspa, /var/www/nhatro đã tạo"

# ============================================================
# BƯỚC 10: NGINX VIRTUAL HOSTS
# ============================================================
header "BƯỚC 10: Cấu hình Nginx Virtual Hosts"

# ----- app.wasypro.com -----
cat > /etc/nginx/sites-available/app.wasypro.com << 'NGINX'
server {
    listen 80;
    server_name app.wasypro.com www.app.wasypro.com;

    location /api/ {
        proxy_pass http://127.0.0.1:3011;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }

    location /.well-known/acme-challenge/ { root /var/www/html; }

    location / {
        proxy_pass http://127.0.0.1:5175;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection 'upgrade';
        proxy_set_header Host $host;
        proxy_cache_bypass $http_upgrade;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }
}
NGINX

# ----- jinshang.com.vn (myspa) -----
cat > /etc/nginx/sites-available/jinshang.com.vn << 'NGINX'
server {
    listen 80;
    server_name jinshang.com.vn www.jinshang.com.vn;

    location /api/ {
        proxy_pass http://127.0.0.1:3010;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }

    location /.well-known/acme-challenge/ { root /var/www/html; }

    location / {
        proxy_pass http://127.0.0.1:5174;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection 'upgrade';
        proxy_set_header Host $host;
        proxy_cache_bypass $http_upgrade;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }
}
NGINX

# ----- nhatro.storeviet.app -----
cat > /etc/nginx/sites-available/nhatro.storeviet.app << 'NGINX'
server {
    listen 80;
    server_name nhatro.storeviet.app www.nhatro.storeviet.app;

    location /.well-known/acme-challenge/ { root /var/www/html; }

    location / {
        proxy_pass http://127.0.0.1:3000;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection 'upgrade';
        proxy_set_header Host $host;
        proxy_cache_bypass $http_upgrade;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }
}
NGINX

# Enable sites
ln -sf /etc/nginx/sites-available/app.wasypro.com   /etc/nginx/sites-enabled/
ln -sf /etc/nginx/sites-available/jinshang.com.vn   /etc/nginx/sites-enabled/
ln -sf /etc/nginx/sites-available/nhatro.storeviet.app /etc/nginx/sites-enabled/
rm -f /etc/nginx/sites-enabled/default

# Test và reload nginx
nginx -t && systemctl reload nginx
log "Nginx virtual hosts đã cấu hình"

# ============================================================
# BƯỚC 11: TẠO SCRIPT CHẠY APPS
# ============================================================
header "BƯỚC 11: Tạo ecosystem PM2"

cat > /home/ubuntu/start_all.sh << 'BASH'
#!/bin/bash
# Script khởi động tất cả apps

# ===== WASYPRO =====
cd /var/www/wasypro
npm install --production 2>/dev/null || true
cd /var/www/wasypro/server
npm install --production 2>/dev/null || true
pm2 start ecosystem.config.cjs --only wasypro-backend,wasypro-frontend 2>/dev/null || \
  pm2 start server/index.js --name wasypro-backend -- --port 3011

# ===== MYSPA (JINSHANG) =====
cd /var/www/myspa
npm install --production 2>/dev/null || true
cd /var/www/myspa/server
npm install --production 2>/dev/null || true
pm2 start ecosystem.config.cjs --only myspa-backend,myspa-frontend 2>/dev/null || \
  pm2 start server/index.js --name myspa-backend -- --port 3010

# ===== NHATRO =====
cd /var/www/nhatro
npm install --production 2>/dev/null || true
npm run build 2>/dev/null || true
pm2 start ecosystem.config.js --only nhatro 2>/dev/null || \
  pm2 start "npm run start" --name nhatro

pm2 save
pm2 list
BASH

chmod +x /home/ubuntu/start_all.sh
chown ubuntu:ubuntu /home/ubuntu/start_all.sh
log "Script start_all.sh đã tạo tại /home/ubuntu/start_all.sh"

# ============================================================
# BƯỚC 12: TẠO SCRIPT RESTORE DATABASE
# ============================================================
header "BƯỚC 12: Tạo script restore database"

cat > /home/ubuntu/restore_db.sh << 'BASH'
#!/bin/bash
# Restore PostgreSQL database từ backup
# Dùng: bash restore_db.sh /path/to/database_backup.sql

BACKUP_FILE="${1:-database_backup.sql}"

if [ ! -f "$BACKUP_FILE" ]; then
  echo "File không tìm thấy: $BACKUP_FILE"
  echo "Dùng: bash restore_db.sh /path/to/database_backup.sql"
  exit 1
fi

DB_NAME="crm_dev"
DB_USER="erp"

echo "Đang restore database $DB_NAME từ $BACKUP_FILE..."
sudo -u postgres psql -c "DROP DATABASE IF EXISTS ${DB_NAME};"
sudo -u postgres psql -c "CREATE DATABASE ${DB_NAME} OWNER ${DB_USER};"
sudo -u postgres psql -d "${DB_NAME}" < "$BACKUP_FILE"
echo "✓ Restore xong!"
BASH

chmod +x /home/ubuntu/restore_db.sh
chown ubuntu:ubuntu /home/ubuntu/restore_db.sh
log "Script restore_db.sh đã tạo"

# ============================================================
# KẾT THÚC
# ============================================================
header "✅ CÀI ĐẶT HOÀN TẤT!"
echo ""
echo "  📁 Code để tại:    /var/www/{wasypro,myspa,nhatro}"
echo "  🚀 Chạy apps:      bash /home/ubuntu/start_all.sh"
echo "  🗄️  Restore DB:     bash /home/ubuntu/restore_db.sh <file.sql>"
echo "  🔒 Cấp SSL:        sudo certbot --nginx -d yourdomain.com"
echo ""
echo "  Port mapping:"
echo "    app.wasypro.com   → frontend :5175 | backend :3011"
echo "    jinshang.com.vn   → frontend :5174 | backend :3010"
echo "    nhatro.storeviet  → Next.js   :3000"
echo ""
echo -e "${GREEN}Xong! Giờ chỉ cần copy code vào /var/www/ và chạy start_all.sh${NC}"
