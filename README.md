# ðŸš€ VPS Setup Guide â€” phanthemy Projects

> HÆ°á»›ng dáº«n cÃ i Ä‘áº·t VPS tá»« Aâ†’Z cho 3 dá»± Ã¡n:
> **app.wasypro.com** | **jinshang.com.vn** | **nhatro.storeviet.app**

---

## ðŸ“‹ YÃªu cáº§u

| Má»¥c | YÃªu cáº§u |
|-----|---------|
| OS | Ubuntu 22.04 hoáº·c 24.04 |
| RAM | Tá»‘i thiá»ƒu 6GB (khuyáº¿n nghá»‹ Oracle Always Free 24GB) |
| CPU | 1+ vCPU (khuyáº¿n nghá»‹ 4 OCPU ARM) |
| Domain | ÄÃ£ trá» DNS vá» IP cá»§a VPS |

---

## âš¡ CÃ i Ä‘áº·t nhanh (1 lá»‡nh)

```bash
# SSH vÃ o VPS
ssh -i your-key.pem ubuntu@YOUR_VPS_IP

# Táº£i script vÃ  cháº¡y
wget https://raw.githubusercontent.com/phanthemy/vps-setup/main/install_vps.sh
sudo bash install_vps.sh
```

Script sáº½ tá»± Ä‘á»™ng cÃ i:
- âœ… Node.js 20 LTS
- âœ… PM2 (process manager)
- âœ… PostgreSQL (database)
- âœ… Nginx (reverse proxy)
- âœ… Certbot (SSL Let's Encrypt)
- âœ… UFW Firewall
- âœ… Fail2Ban (báº£o máº­t)

---

## ðŸ“ BÆ°á»›c tiáº¿p theo sau khi cÃ i

### 1. Copy code lÃªn VPS

```bash
# Tá»« mÃ¡y local, copy tá»«ng project:
scp -r ./wasypro     ubuntu@YOUR_VPS_IP:/var/www/wasypro
scp -r ./myspa       ubuntu@YOUR_VPS_IP:/var/www/myspa
scp -r ./nhatro      ubuntu@YOUR_VPS_IP:/var/www/nhatro

# Hoáº·c clone tá»« GitHub:
cd /var/www/wasypro  && git clone https://github.com/phanthemy/wasypro.git .
cd /var/www/myspa    && git clone https://github.com/phanthemy/myspa-jinshang.git .
cd /var/www/nhatro   && git clone https://github.com/phanthemy/nhatro.git .
```

### 2. Restore database

```bash
# Restore tá»« file backup SQL (cÃ³ trong repo wasypro/myspa)
sudo bash /home/ubuntu/restore_db.sh /var/www/wasypro/database_backup.sql
```

### 3. Táº¡o file `.env` cho tá»«ng project

**wasypro** (`/var/www/wasypro/server/.env`):
```env
DATABASE_URL="postgresql://erp:erp@2024@localhost:5432/crm_dev"
PORT=3011
NODE_ENV=production
JWT_SECRET=your_jwt_secret_here
```

**myspa** (`/var/www/myspa/server/.env`):
```env
DATABASE_URL="postgresql://erp:erp@2024@localhost:5432/crm_dev"
PORT=3010
NODE_ENV=production
JWT_SECRET=your_jwt_secret_here
```

**nhatro** (`/var/www/nhatro/.env`):
```env
DATABASE_URL="file:./prisma/dev.db"
NEXTAUTH_SECRET=your_secret_here
NEXTAUTH_URL=https://nhatro.storeviet.app
```

### 4. Cháº¡y táº¥t cáº£ apps

```bash
bash /home/ubuntu/start_all.sh
```

### 5. Cáº¥p SSL

```bash
# Sau khi DNS Ä‘Ã£ trá» Ä‘Ãºng vá» VPS
sudo certbot --nginx -d app.wasypro.com -d www.app.wasypro.com
sudo certbot --nginx -d jinshang.com.vn -d www.jinshang.com.vn
sudo certbot --nginx -d nhatro.storeviet.app
```

---

## ðŸ—„ï¸ Cáº¥u trÃºc Database

| Database | Loáº¡i | DÃ¹ng cho |
|----------|------|----------|
| `crm_dev` | PostgreSQL | wasypro + myspa/jinshang |
| `prisma/dev.db` | SQLite | nhatro (local/dev) |

**ThÃ´ng tin káº¿t ná»‘i PostgreSQL:**
```
Host: localhost
Port: 5432
Database: crm_dev
User: erp
Password: erp@2024
```

---

## ðŸŒ Port Mapping

| Domain | Frontend | Backend |
|--------|----------|---------|
| app.wasypro.com | :5175 | :3011 |
| jinshang.com.vn | :5174 | :3010 |
| nhatro.storeviet.app | :3000 | â€” |

---

## ðŸ”§ Lá»‡nh quáº£n lÃ½ thÆ°á»ng dÃ¹ng

```bash
# Xem tráº¡ng thÃ¡i apps
pm2 list
pm2 logs <app-name>

# Restart app
pm2 restart <app-name>

# Reload nginx
sudo nginx -t && sudo systemctl reload nginx

# Kiá»ƒm tra firewall
sudo ufw status

# Xem log nginx
sudo tail -f /var/log/nginx/error.log

# Backup database
sudo -u postgres pg_dump crm_dev > backup_$(date +%Y%m%d).sql

# Xem status systemd service
sudo systemctl status nginx
sudo systemctl status postgresql
sudo systemctl status fail2ban
```

---

## ðŸ“Š PM2 Ecosystem (tham kháº£o)

Má»—i project cÃ³ file `ecosystem.config.cjs` (hoáº·c `.js`). Cáº¥u hÃ¬nh máº«u:

```js
module.exports = {
  apps: [
    {
      name: 'myspa-backend',
      script: 'server/index.js',
      cwd: '/var/www/myspa',
      env: { PORT: 3010, NODE_ENV: 'production' }
    },
    {
      name: 'myspa-frontend',
      script: 'node_modules/.bin/vite',
      args: 'preview --port 5174 --host',
      cwd: '/var/www/myspa',
      env: { NODE_ENV: 'production' }
    }
  ]
}
```

---

## âš ï¸ LÆ°u Ã½ quan trá»ng

> [!WARNING]
> - Äá»•i máº­t kháº©u database máº·c Ä‘á»‹nh `erp@2024` trÆ°á»›c khi production
> - KhÃ´ng commit file `.env` lÃªn GitHub
> - Backup database Ä‘á»‹nh ká»³ hÃ ng ngÃ y

---

## ðŸ“ž ThÃ´ng tin dá»± Ã¡n

| Project | Repo | Domain |
|---------|------|--------|
| WasyPro | [github.com/phanthemy/wasypro](https://github.com/phanthemy/wasypro) | app.wasypro.com |
| MySpa/Jinshang | [github.com/phanthemy/myspa-jinshang](https://github.com/phanthemy/myspa-jinshang) | jinshang.com.vn |
| NhÃ  Trá» | [github.com/phanthemy/nhatro](https://github.com/phanthemy/nhatro) | nhatro.storeviet.app |
| VPS Setup | [github.com/phanthemy/vps-setup](https://github.com/phanthemy/vps-setup) | â€” |
