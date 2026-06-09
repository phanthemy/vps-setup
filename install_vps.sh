#!/bin/bash
# ============================================================
#  VPS AUTO SETUP SCRIPT
#  TÃ¡c giáº£: phanthemy@gmail.com
#  DÃ¹ng cho: Ubuntu 22.04 / 24.04 (Oracle Always Free)
#  Projects: wasypro | myspa-jinshang | nhatro
# ============================================================

set -e  # Dá»«ng náº¿u cÃ³ lá»—i

# ---------- MÃ€U Sáº®C ----------
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m'

log()    { echo -e "${GREEN}[âœ“]${NC} $1"; }
warn()   { echo -e "${YELLOW}[!]${NC} $1"; }
error()  { echo -e "${RED}[âœ—]${NC} $1"; exit 1; }
header() { echo -e "\n${BLUE}â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•${NC}"; echo -e "${BLUE}  $1${NC}"; echo -e "${BLUE}â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•${NC}"; }

# ============================================================
# BÆ¯á»šC 0: KIá»‚M TRA QUYá»€N ROOT
# ============================================================
if [ "$EUID" -ne 0 ]; then
  error "Cháº¡y script báº±ng sudo: sudo bash install_vps.sh"
fi

header "VPS SETUP - Báº®T Äáº¦U"
echo "Thá»i gian: $(date)"
echo "User: $(whoami)"
echo "OS: $(lsb_release -d | cut -f2)"
echo ""

# ============================================================
# BÆ¯á»šC 1: Cáº¬P NHáº¬T Há»† THá»NG
# ============================================================
header "BÆ¯á»šC 1: Cáº­p nháº­t há»‡ thá»‘ng"
apt update -y && apt upgrade -y
apt install -y curl wget git unzip zip build-essential software-properties-common \
               ca-certificates gnupg lsb-release ufw fail2ban dnsutils
log "Cáº­p nháº­t há»‡ thá»‘ng xong"

# ============================================================
# BÆ¯á»šC 2: CÃ€I NODE.JS 20 LTS
# ============================================================
header "BÆ¯á»šC 2: CÃ i Node.js 20 LTS"
if ! command -v node &>/dev/null; then
  curl -fsSL https://deb.nodesource.com/setup_20.x | bash -
  apt install -y nodejs
  log "Node.js $(node -v) Ä‘Ã£ cÃ i"
else
  warn "Node.js Ä‘Ã£ cÃ³: $(node -v)"
fi

# ============================================================
# BÆ¯á»šC 3: CÃ€I PM2
# ============================================================
header "BÆ¯á»šC 3: CÃ i PM2"
if ! command -v pm2 &>/dev/null; then
  npm install -g pm2
  pm2 startup systemd -u ubuntu --hp /home/ubuntu | tail -1 | bash || true
  log "PM2 $(pm2 -v) Ä‘Ã£ cÃ i"
else
  warn "PM2 Ä‘Ã£ cÃ³: $(pm2 -v)"
fi

# ============================================================
# BÆ¯á»šC 4: CÃ€I POSTGRESQL
# ============================================================
header "BÆ¯á»šC 4: CÃ i PostgreSQL"
if ! command -v psql &>/dev/null; then
  apt install -y postgresql postgresql-contrib
  systemctl enable postgresql
  systemctl start postgresql
  log "PostgreSQL Ä‘Ã£ cÃ i vÃ  khá»Ÿi Ä‘á»™ng"
else
  warn "PostgreSQL Ä‘Ã£ cÃ³: $(psql --version)"
fi

# Táº¡o database vÃ  user
DB_NAME="crm_dev"
DB_USER="erp"
DB_PASS="erp@2024"

sudo -u postgres psql -c "CREATE USER ${DB_USER} WITH PASSWORD '${DB_PASS}';" 2>/dev/null || warn "User ${DB_USER} Ä‘Ã£ tá»“n táº¡i"
sudo -u postgres psql -c "CREATE DATABASE ${DB_NAME} OWNER ${DB_USER};" 2>/dev/null || warn "Database ${DB_NAME} Ä‘Ã£ tá»“n táº¡i"
sudo -u postgres psql -c "GRANT ALL PRIVILEGES ON DATABASE ${DB_NAME} TO ${DB_USER};" 2>/dev/null || true
log "Database '${DB_NAME}' vá»›i user '${DB_USER}' Ä‘Ã£ sáºµn sÃ ng"

# ============================================================
# BÆ¯á»šC 5: CÃ€I NGINX
# ============================================================
header "BÆ¯á»šC 5: CÃ i Nginx"
if ! command -v nginx &>/dev/null; then
  apt install -y nginx
  systemctl enable nginx
  systemctl start nginx
  log "Nginx $(nginx -v 2>&1 | cut -d/ -f2) Ä‘Ã£ cÃ i"
else
  warn "Nginx Ä‘Ã£ cÃ³"
fi

# ============================================================
# BÆ¯á»šC 6: CÃ€I CERTBOT (SSL Let's Encrypt)
# ============================================================
header "BÆ¯á»šC 6: CÃ i Certbot SSL"
if ! command -v certbot &>/dev/null; then
  apt install -y certbot python3-certbot-nginx
  log "Certbot Ä‘Ã£ cÃ i"
else
  warn "Certbot Ä‘Ã£ cÃ³"
fi

# ============================================================
# BÆ¯á»šC 7: Cáº¤U HÃŒNH FIREWALL (UFW)
# ============================================================
header "BÆ¯á»šC 7: Cáº¥u hÃ¬nh Firewall"
ufw --force reset
ufw default deny incoming
ufw default allow outgoing
ufw allow ssh
ufw allow 80/tcp
ufw allow 443/tcp
ufw allow 22/tcp
# Má»Ÿ cÃ¡c port ná»™i bá»™ cho apps (khÃ´ng cáº§n má»Ÿ public)
# Port 3010, 3011, 5174, 5175, 3000 chá»‰ dÃ¹ng internal qua nginx
ufw --force enable
log "Firewall Ä‘Ã£ cáº¥u hÃ¬nh (SSH + HTTP + HTTPS)"
ufw status

# ============================================================
# BÆ¯á»šC 8: Cáº¤U HÃŒNH FAIL2BAN
# ============================================================
header "BÆ¯á»šC 8: Cáº¥u hÃ¬nh Fail2Ban"
cat > /etc/fail2ban/jail.local << 'EOF'
[DEFAULT]
bantime  = 3600
findtime = 600
maxretry = 5

[sshd]
enabled = true
port    = ssh
logpath = %(sshd_log)s
backend = %(sshd_backend)s

[nginx-http-auth]
enabled = true

[nginx-limit-req]
enabled = true
EOF
systemctl enable fail2ban
systemctl restart fail2ban
log "Fail2Ban Ä‘Ã£ cáº¥u hÃ¬nh"

# ============================================================
# BÆ¯á»šC 9: Táº O Cáº¤U TRÃšC THÆ¯ Má»¤C
# ============================================================
header "BÆ¯á»šC 9: Táº¡o cáº¥u trÃºc thÆ° má»¥c"
mkdir -p /var/www/wasypro
mkdir -p /var/www/myspa
mkdir -p /var/www/nhatro
chown -R ubuntu:ubuntu /var/www/wasypro
chown -R ubuntu:ubuntu /var/www/myspa
chown -R ubuntu:ubuntu /var/www/nhatro
log "ThÆ° má»¥c /var/www/wasypro, /var/www/myspa, /var/www/nhatro Ä‘Ã£ táº¡o"

# ============================================================
# BÆ¯á»šC 10: NGINX VIRTUAL HOSTS
# ============================================================
header "BÆ¯á»šC 10: Cáº¥u hÃ¬nh Nginx Virtual Hosts"

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

# Test vÃ  reload nginx
nginx -t && systemctl reload nginx
log "Nginx virtual hosts Ä‘Ã£ cáº¥u hÃ¬nh"

# ============================================================
# BÆ¯á»šC 11: Táº O SCRIPT CHáº Y APPS
# ============================================================
header "BÆ¯á»šC 11: Táº¡o ecosystem PM2"

cat > /home/ubuntu/start_all.sh << 'BASH'
#!/bin/bash
# Script khá»Ÿi Ä‘á»™ng táº¥t cáº£ apps

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
log "Script start_all.sh Ä‘Ã£ táº¡o táº¡i /home/ubuntu/start_all.sh"

# ============================================================
# BÆ¯á»šC 12: Táº O SCRIPT RESTORE DATABASE
# ============================================================
header "BÆ¯á»šC 12: Táº¡o script restore database"

cat > /home/ubuntu/restore_db.sh << 'BASH'
#!/bin/bash
# Restore PostgreSQL database tá»« backup
# DÃ¹ng: bash restore_db.sh /path/to/database_backup.sql

BACKUP_FILE="${1:-database_backup.sql}"

if [ ! -f "$BACKUP_FILE" ]; then
  echo "File khÃ´ng tÃ¬m tháº¥y: $BACKUP_FILE"
  echo "DÃ¹ng: bash restore_db.sh /path/to/database_backup.sql"
  exit 1
fi

DB_NAME="crm_dev"
DB_USER="erp"

echo "Äang restore database $DB_NAME tá»« $BACKUP_FILE..."
sudo -u postgres psql -c "DROP DATABASE IF EXISTS ${DB_NAME};"
sudo -u postgres psql -c "CREATE DATABASE ${DB_NAME} OWNER ${DB_USER};"
sudo -u postgres psql -d "${DB_NAME}" < "$BACKUP_FILE"
echo "âœ“ Restore xong!"
BASH

chmod +x /home/ubuntu/restore_db.sh
chown ubuntu:ubuntu /home/ubuntu/restore_db.sh
log "Script restore_db.sh Ä‘Ã£ táº¡o"

# ============================================================
# Káº¾T THÃšC
# ============================================================
header "âœ… CÃ€I Äáº¶T HOÃ€N Táº¤T!"
echo ""
echo "  ðŸ“ Code Ä‘á»ƒ táº¡i:    /var/www/{wasypro,myspa,nhatro}"
echo "  ðŸš€ Cháº¡y apps:      bash /home/ubuntu/start_all.sh"
echo "  ðŸ—„ï¸  Restore DB:     bash /home/ubuntu/restore_db.sh <file.sql>"
echo "  ðŸ”’ Cáº¥p SSL:        sudo certbot --nginx -d yourdomain.com"
echo ""
echo "  Port mapping:"
echo "    app.wasypro.com   â†’ frontend :5175 | backend :3011"
echo "    jinshang.com.vn   â†’ frontend :5174 | backend :3010"
echo "    nhatro.storeviet  â†’ Next.js   :3000"
echo ""
echo -e "${GREEN}Xong! Giá» chá»‰ cáº§n copy code vÃ o /var/www/ vÃ  cháº¡y start_all.sh${NC}"
