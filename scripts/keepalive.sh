#!/bin/bash
# ============================================================
#  ORACLE FREE VPS KEEP-ALIVE SCRIPT (TĂNG CƯỜNG)
#  Tạo đủ hoạt động để Oracle Metrics nhận thấy
# ============================================================

LOG="/var/log/keepalive.log"
MAX_LOG_SIZE=2097152  # 2MB

if [ -f "$LOG" ] && [ $(stat -c%s "$LOG") -gt $MAX_LOG_SIZE ]; then
    tail -n 300 "$LOG" > "${LOG}.tmp" && mv "${LOG}.tmp" "$LOG"
fi

log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" >> "$LOG"; }

log "=== Keep-alive bắt đầu ==="

# ---- 1. NETWORK - Download file lớn hơn ----
URLS=(
    "https://speed.cloudflare.com/__down?bytes=5000000"   # 5MB từ Cloudflare
    "https://www.google.com"
    "https://github.com"
    "https://api.ipify.org"
    "https://www.oracle.com"
    "https://cloudflare.com/cdn-cgi/trace"
)
RANDOM_URLS=($(shuf -e "${URLS[@]}" | head -$((RANDOM % 2 + 2))))
for url in "${RANDOM_URLS[@]}"; do
    result=$(curl -s -o /dev/null -w "%{http_code} %{size_download}B %{speed_download}B/s" \
             --max-time 30 --connect-timeout 5 "$url" 2>/dev/null)
    log "  Network: $url → $result"
    sleep $((RANDOM % 3 + 1))
done

# ---- 2. CPU - Tăng thời gian tính toán ----
CPU_SECONDS=$((RANDOM % 20 + 15))  # 15-35 giây
log "  CPU: Chạy ${CPU_SECONDS}s..."
END_TIME=$(($(date +%s) + CPU_SECONDS))
while [ $(date +%s) -lt $END_TIME ]; do
    # Tính toán nặng hơn
    echo "scale=1000; 4*a(1)" | bc -l > /dev/null 2>&1 &
    echo "scale=800; e(1)" | bc -l > /dev/null 2>&1 &
    wait
done
log "  CPU: Xong"

# ---- 3. MEMORY - Dùng RAM tạm thời ----
MEM_MB=$((RANDOM % 200 + 100))  # 100-300MB
log "  Memory: Dùng ${MEM_MB}MB RAM tạm..."
python3 -c "
import time, random
size = ${MEM_MB} * 1024 * 1024
data = bytearray(random.getrandbits(8) for _ in range(size))
time.sleep(3)
del data
" 2>/dev/null || true
log "  Memory: Xong"

# ---- 4. DISK - Ghi nhiều hơn ----
TMP_FILE="/tmp/keepalive_$(date +%s).tmp"
DISK_MB=$((RANDOM % 100 + 50))  # 50-150MB
log "  Disk: Ghi ${DISK_MB}MB..."
dd if=/dev/urandom of="$TMP_FILE" bs=1M count=$DISK_MB 2>/dev/null
sleep 2
rm -f "$TMP_FILE"
log "  Disk: Xong"

# ---- 5. KIỂM TRA SERVICE ----
for service in nginx postgresql; do
    if ! systemctl is-active --quiet "$service"; then
        log "  WARNING: $service tắt → đang restart..."
        systemctl restart "$service" 2>/dev/null
    fi
done

# ---- 6. MEMORY FLUSH ----
sync
echo 1 > /proc/sys/vm/drop_caches 2>/dev/null || true

log "=== Keep-alive hoàn tất ==="
log ""
