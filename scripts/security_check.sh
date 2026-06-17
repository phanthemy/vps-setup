#!/bin/bash

BOT_TOKEN="YOUR_TELEGRAM_BOT_TOKEN"
CHAT_ID="YOUR_TELEGRAM_CHAT_ID"
WARNING=""
ACTION_TAKEN=""

# 1. QUET CRONJOB
CRON_CONTENT=$(crontab -l 2>/dev/null | grep -v "^#" | grep -v "security_check.sh")
if [ -n "$CRON_CONTENT" ]; then
    WARNING+="[PHAT HIEN CRONJOB LA]%0A$CRON_CONTENT%0A%0A"
    chattr -i /var/spool/cron/crontabs/root 2>/dev/null
    sed -i '/perfcc/d' /var/spool/cron/crontabs/root
    grep "security_check.sh" /var/spool/cron/crontabs/root > /tmp/cron_clean.tmp
    cat /tmp/cron_clean.tmp > /var/spool/cron/crontabs/root
    rm -f /tmp/cron_clean.tmp
    chattr -R -i /root/.config/cron/ 2>/dev/null
    find /root/.config/cron/ -type f -delete 2>/dev/null
    chattr +i /var/spool/cron/crontabs/root 2>/dev/null
    ACTION_TAKEN+="✅ Da don sach Cronjob xam nhap bang sed.%0A"
fi

# 2. QUET MANG KET NOI CHUI
SUSPICIOUS_NET=$(ss -antpW 2>/dev/null | grep ESTAB | grep -v -E \
"127.0.0.1|::1|:443|:80|:22|:20201|:20202|:5174|:5175|:3010|:3011|:8080|:8443|:5432|:3306|:27017|:6379")
if [ -n "$SUSPICIOUS_NET" ]; then
    WARNING+="[MANG BAT THUONG]%0A$SUSPICIOUS_NET%0A%0A"
    PIDS=$(echo "$SUSPICIOUS_NET" | awk -F'pid=' '{print $2}' | awk -F',' '{print $1}' | sort -u | grep -v "^$")
    if [ -n "$PIDS" ]; then
        for pid in $PIDS; do kill -9 $pid 2>/dev/null; done
        ACTION_TAKEN+="✅ Da bop co tien trinh len ket noi (PID: $PIDS).%0A"
    fi
    BAD_IPS=$(echo "$SUSPICIOUS_NET" | awk '{print $5}' | cut -d: -f1 | sort -u | grep -E "^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+")
    if [ -n "$BAD_IPS" ]; then
        for bad_ip in $BAD_IPS; do
            iptables -A OUTPUT -d $bad_ip -j DROP
            ACTION_TAKEN+="🧱 TUONG LUA: Da cam van IP: $bad_ip.%0A"
        done
    fi
fi

# 3. QUET CPU VA RAM — WHITELIST DAY DU
SAFE_APPS="\
apt|apt-get|apt-config|dpkg|unattended-upgrades|packagekit|\
node|npm|vite|serve|pm2|\
nginx|mysql|mysqld|\
snapd|snap|\
google_osconfig|google_guest|google_cloud|google-cloud|otelopscol|\
fluent-bit|fluent_bit|opentelemetry|\
fail2ban|\
systemd|kworker|rcu|ksoftirqd|kthreadd|migration|watchdog|\
kswapd|kcompactd|khugepaged|kdevtmpfs|kauditd|khungtaskd|oom_reaper|ksmd|\
jbd2|ecryptfs|scsi_eh|irq|pool_workqueue|idle_inject|cpuhp|hwrng|\
multipathd|polkitd|rsyslogd|chronyd|cron|dbus|agetty|\
networkd-dispatcher|packagekitd|\
sshd|bash|sh|ps|top|grep|awk|ss|curl|sed|cat|find|rm|chmod|\
redis|redis-server|mongod|\
python3|lsof|fuser|security_check"

PM2_PIDS=$(sudo -u ubuntu pm2 jlist 2>/dev/null | grep -o '"pid":[0-9]*' | grep -o '[0-9]*' | tr '\n' '|' | sed 's/|$//')
HIGH_RES_RAW=$(ps -eo pid,user,%cpu,%mem,cmd --sort=-%cpu | awk 'NR>1 && ($3 > 75.0 || $4 > 75.0) {print $0}')
if [ -n "$HIGH_RES_RAW" ]; then
    HIGH_RES_FILTERED=$(echo "$HIGH_RES_RAW" | grep -viwE "$SAFE_APPS" | grep -v "^$")
    if [ -n "$PM2_PIDS" ] && [ -n "$HIGH_RES_FILTERED" ]; then
        HIGH_RES_FILTERED=$(echo "$HIGH_RES_FILTERED" | grep -vE "^[[:space:]]*($PM2_PIDS)[[:space:]]")
    fi
    if [ -n "$HIGH_RES_FILTERED" ]; then
        PROCESS_INFO=$(echo "$HIGH_RES_FILTERED" | awk '{print "PID:"$1" CPU:"$3"% MEM:"$4"% CMD:"$5}')
        WARNING+="[PHAT HIEN TIEN TRINH LA HUT MAU VPS TREN 75%%]%0A$PROCESS_INFO%0A%0A"
        STRANGER_PIDS=$(echo "$HIGH_RES_FILTERED" | awk '{print $1}')
        for pid in $STRANGER_PIDS; do
            PROC_NAME=$(ps -p $pid -o comm= 2>/dev/null)
            kill -9 $pid 2>/dev/null
            ACTION_TAKEN+="✅ Da kill: $PROC_NAME (PID: $pid)%0A"
        done
    fi
fi

# 4. KIEM TRA DICH VU PM2
WATCH_SERVICES="myspa-frontend myspa-backend happylife-frontend happylife-backend nhatro"
for service in $WATCH_SERVICES; do
    STATUS=$(sudo -u ubuntu pm2 jlist 2>/dev/null | python3 -c "
import json,sys
data=json.load(sys.stdin)
s=[p for p in data if p['name']=='$service']
print(s[0]['pm2_env']['status'] if s else 'not_found')
" 2>/dev/null)
    if [ "$STATUS" != "online" ]; then
        WARNING+="🔴 DICH VU BI STOP: $service (trang thai: $STATUS)%0A%0A"
        sudo -u ubuntu pm2 restart $service 2>/dev/null
        sleep 2
        NEW_STATUS=$(sudo -u ubuntu pm2 jlist 2>/dev/null | python3 -c "
import json,sys
data=json.load(sys.stdin)
s=[p for p in data if p['name']=='$service']
print(s[0]['pm2_env']['status'] if s else 'not_found')
" 2>/dev/null)
        if [ "$NEW_STATUS" = "online" ]; then
            ACTION_TAKEN+="✅ Da tu dong RESTART $service thanh cong!%0A"
        else
            ACTION_TAKEN+="❌ RESTART $service THAT BAI — can kiem tra thu cong!%0A"
        fi
    fi
done

# 5. GUI TONG KET TELEGRAM
if [ -n "$WARNING" ]; then
    MESSAGE="🔥 [BAO DONG ORACLE VPS] 🔥%0A%0A⚠️ VAN DE:%0A$WARNING%0A🛡️ DA XU LY:%0A$ACTION_TAKEN"
    curl -s -X POST "https://api.telegram.org/bot$BOT_TOKEN/sendMessage" -d "chat_id=$CHAT_ID" -d "text=$MESSAGE" > /dev/null
fi
