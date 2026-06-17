#!/bin/bash
# ============================================================
#  AUTO BACKUP TO GITHUB
#  Chạy hàng ngày lúc 2:00 AM qua cron
#  Backup: Code + Database → push lên GitHub
# ============================================================

LOG="/var/log/github_backup.log"
GITHUB_TOKEN="YOUR_GITHUB_TOKEN"
GITHUB_USER="phanthemy"
GITHUB_EMAIL="phanthemy@gmail.com"
DATE=$(date '+%Y-%m-%d %H:%M:%S')
DATE_TAG=$(date '+%Y%m%d_%H%M')

log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG"; }

# Xoay log nếu >2MB
if [ -f "$LOG" ] && [ $(stat -c%s "$LOG" 2>/dev/null || echo 0) -gt 2097152 ]; then
    tail -n 300 "$LOG" > "${LOG}.tmp" && mv "${LOG}.tmp" "$LOG"
fi

log "====== BẮT ĐẦU BACKUP ======"

# ---- CẤU HÌNH GIT GLOBAL ----
git config --global user.email "$GITHUB_EMAIL"
git config --global user.name "Phan The My"
git config --global --add safe.directory '*'

# ============================================================
# HÀM BACKUP TỪNG PROJECT
# ============================================================
backup_project() {
    local PROJECT_DIR="$1"
    local REPO_NAME="$2"
    local HAS_POSTGRES="$3"  # "yes" nếu cần backup PostgreSQL

    log "--- Backup: $REPO_NAME ---"

    if [ ! -d "$PROJECT_DIR" ]; then
        log "  SKIP: Thư mục $PROJECT_DIR không tồn tại"
        return
    fi

    cd "$PROJECT_DIR" || return

    # Backup PostgreSQL nếu cần
    if [ "$HAS_POSTGRES" = "yes" ]; then
        log "  Đang dump PostgreSQL crm_dev..."
        sudo -u postgres pg_dump crm_dev > database_backup.sql 2>/dev/null
        if [ $? -eq 0 ]; then
            log "  PostgreSQL dump OK ($(du -sh database_backup.sql | cut -f1))"
        else
            log "  WARNING: PostgreSQL dump thất bại"
        fi
    fi

    # Backup SQLite nếu có
    if [ -f "server/dev.db" ]; then
        cp server/dev.db "server/dev_backup_${DATE_TAG}.db" 2>/dev/null
        # Chỉ giữ 3 bản backup gần nhất
        ls -t server/dev_backup_*.db 2>/dev/null | tail -n +4 | xargs rm -f 2>/dev/null
        log "  SQLite backup OK"
    fi

    # Kiểm tra git repo
    if [ ! -d ".git" ]; then
        log "  Init git repo..."
        git init
        git remote add origin "https://${GITHUB_TOKEN}@github.com/${GITHUB_USER}/${REPO_NAME}.git"
    else
        # Cập nhật remote URL với token mới nhất
        git remote set-url origin "https://${GITHUB_TOKEN}@github.com/${GITHUB_USER}/${REPO_NAME}.git"
    fi

    # Stage và commit
    git add -A 2>/dev/null
    CHANGED=$(git diff --cached --stat | tail -1)

    if git diff --cached --quiet; then
        log "  Không có thay đổi, bỏ qua commit"
    else
        git commit -m "Auto backup: $DATE_TAG - $CHANGED" 2>/dev/null
        git push origin main --force 2>/dev/null || git push origin master --force 2>/dev/null
        if [ $? -eq 0 ]; then
            log "  Push GitHub OK ✓"
        else
            log "  ERROR: Push thất bại!"
        fi
    fi
}

# ============================================================
# CHẠY BACKUP
# ============================================================
backup_project "/var/www/wasypro"     "wasypro"         "yes"
backup_project "/var/www/myspa"       "myspa-jinshang"  "no"
backup_project "/var/www/nhatro"      "nhatro"          "no"

log "====== BACKUP HOÀN TẤT ======"
log ""
