#!/bin/bash
# ============================================
# FUNGSI NOTIFIKASI TELEGRAM - FIXED VERSION
# ============================================
# PERBAIKAN:
# 1. Membaca token dari /etc/bot/.bot.db (sinkron dengan bot panel)
# 2. BUKAN hardcoded token lagi
# 3. Fallback ke token default jika belum setup bot panel
# 4. Fungsi reusable untuk kirim notifikasi
# ============================================

# ============================================
# FUNGSI: Baca konfigurasi bot
# ============================================
get_bot_config() {
    # Prioritas 1: Baca dari /etc/bot/.bot.db (disimpan oleh bot-fixed.sh)
    if [[ -f /etc/bot/.bot.db ]]; then
        BOT_TOKEN=$(sed -n '1p' /etc/bot/.bot.db)
        CHAT_ID=$(sed -n '2p' /etc/bot/.bot.db)
        if [[ -n "$BOT_TOKEN" && -n "$CHAT_ID" ]]; then
            return 0
        fi
    fi

    # Prioritas 2: Baca dari var.txt bot panel
    local VAR_FILE="/usr/local/share/kyt-bot/kyt/var.txt"
    if [[ -f "$VAR_FILE" ]]; then
        BOT_TOKEN=$(grep '^BOT_TOKEN=' "$VAR_FILE" | cut -d'"' -f2)
        CHAT_ID=$(grep '^ADMIN=' "$VAR_FILE" | cut -d'"' -f2)
        if [[ -n "$BOT_TOKEN" && -n "$CHAT_ID" ]]; then
            return 0
        fi
    fi

    # Prioritas 3: Baca dari var.txt lama (kompatibilitas)
    local OLD_VAR="/usr/bin/kyt/var.txt"
    if [[ -f "$OLD_VAR" ]]; then
        BOT_TOKEN=$(grep '^BOT_TOKEN=' "$OLD_VAR" | cut -d'"' -f2)
        CHAT_ID=$(grep '^ADMIN=' "$OLD_VAR" | cut -d'"' -f2)
        if [[ -n "$BOT_TOKEN" && -n "$CHAT_ID" ]]; then
            return 0
        fi
    fi

    # Tidak ada konfigurasi ditemukan
    BOT_TOKEN=""
    CHAT_ID=""
    return 1
}

# ============================================
# FUNGSI: Kirim notifikasi Telegram
# Parameter: $1 = pesan (HTML format)
# Parameter: $2 = inline keyboard JSON (opsional)
# ============================================
send_telegram() {
    local message="$1"
    local keyboard="$2"
    local TIMEOUT=10

    # Baca konfigurasi bot
    get_bot_config
    if [[ -z "$BOT_TOKEN" || -z "$CHAT_ID" ]]; then
        echo "[NOTIF] Bot belum dikonfigurasi - notifikasi dilewati"
        return 1
    fi

    local URL="https://api.telegram.org/bot${BOT_TOKEN}/sendMessage"

    if [[ -n "$keyboard" ]]; then
        curl -s --max-time $TIMEOUT \
            --data-urlencode "chat_id=$CHAT_ID" \
            --data-urlencode "disable_web_page_preview=1" \
            --data-urlencode "text=$message" \
            --data-urlencode "parse_mode=html" \
            --data-urlencode "reply_markup=$keyboard" \
            "$URL" >/dev/null 2>&1
    else
        curl -s --max-time $TIMEOUT \
            --data-urlencode "chat_id=$CHAT_ID" \
            --data-urlencode "disable_web_page_preview=1" \
            --data-urlencode "text=$message" \
            --data-urlencode "parse_mode=html" \
            "$URL" >/dev/null 2>&1
    fi

    return $?
}

# ============================================
# FUNGSI: Notifikasi saat install script selesai
# (Pengganti kode hardcoded di main.sh)
# ============================================
send_install_notification() {
    # Kumpulkan info system
    local IP=$(curl -sS ipv4.icanhazip.com 2>/dev/null)
    local domain=$(cat /etc/xray/domain 2>/dev/null || echo "belum diset")
    local ISP=$(cat /root/.isp 2>/dev/null || echo "unknown")
    local CITY=$(cat /root/.city 2>/dev/null || echo "unknown")
    local OS_Name=$(cat /etc/os-release | grep -w PRETTY_NAME | head -n1 | sed 's/PRETTY_NAME=//g' | sed 's/"//g')
    local Ram_Total=$(free -m | awk '/Mem:/ {print $2}')
    local DATE=$(date +'%Y-%m-%d')
    local TIME=$(date +'%H:%M:%S')
    local username=$(cat /usr/bin/user 2>/dev/null || echo "unknown")
    local exp=$(cat /usr/bin/e 2>/dev/null || echo "unknown")

    local TEXT="
<code>------------------------------------</code>
<b>NOTIFIKASI INSTALL SCRIPT</b>
<code>------------------------------------</code>
<code>User     : ${username}</code>
<code>IP       : ${IP}</code>
<code>Domain   : ${domain}</code>
<code>ISP      : ${ISP}</code>
<code>OS       : ${OS_Name}</code>
<code>RAM      : ${Ram_Total} MB</code>
<code>City     : ${CITY}</code>
<code>Tanggal  : ${DATE}</code>
<code>Waktu    : ${TIME}</code>
<code>Exp Sc.  : ${exp}</code>
<code>------------------------------------</code>
<b>ZERO STORE VVIP SCRIPT</b>
<code>------------------------------------</code>"

    local KEYBOARD='{"inline_keyboard":[[{"text":"Menu Bot","url":"t.me/'$(get_bot_username)'"}]]}'

    send_telegram "$TEXT" "$KEYBOARD"
}

# ============================================
# FUNGSI: Notifikasi saat user dibuat
# ============================================
send_user_created_notification() {
    local proto="$1"    # vmess/vless/trojan/ssh
    local user="$2"
    local exp="$3"
    local ip_limit="$4"

    local domain=$(cat /etc/xray/domain 2>/dev/null || echo "-")
    local DATE=$(date +'%Y-%m-%d %H:%M:%S')

    local TEXT="
<code>------------------------------------</code>
<b>AKUN BARU DIBUAT</b>
<code>------------------------------------</code>
<code>Protokol : ${proto}</code>
<code>Username : ${user}</code>
<code>Domain   : ${domain}</code>
<code>Expired  : ${exp}</code>
<code>IP Limit : ${ip_limit}</code>
<code>Dibuat   : ${DATE}</code>
<code>------------------------------------</code>"

    send_telegram "$TEXT"
}

# ============================================
# FUNGSI: Notifikasi saat user expired/dihapus
# ============================================
send_user_expired_notification() {
    local proto="$1"
    local user="$2"

    local DATE=$(date +'%Y-%m-%d %H:%M:%S')

    local TEXT="
<code>------------------------------------</code>
<b>AKUN EXPIRED / DIHAPUS</b>
<code>------------------------------------</code>
<code>Protokol : ${proto}</code>
<code>Username : ${user}</code>
<code>Waktu    : ${DATE}</code>
<code>------------------------------------</code>"

    send_telegram "$TEXT"
}

# ============================================
# FUNGSI: Dapatkan username bot
# ============================================
get_bot_username() {
    get_bot_config
    if [[ -n "$BOT_TOKEN" ]]; then
        local response
        response=$(curl -s "https://api.telegram.org/bot${BOT_TOKEN}/getMe" 2>/dev/null)
        local result
        if command -v jq &>/dev/null; then
            result=$(echo "$response" | jq -r '.result.username' 2>/dev/null)
        else
            result=$(echo "$response" | grep -o '"username":"[^"]*"' | head -1 | cut -d'"' -f4)
        fi
        echo "${result:-bot}"
    else
        echo "bot"
    fi
}

# ============================================
# FUNGSI: Test koneksi bot
# ============================================
test_bot_connection() {
    get_bot_config
    if [[ -z "$BOT_TOKEN" ]]; then
        echo -e "\e[1;31m[ERROR]\e[0m Bot belum dikonfigurasi"
        echo "Jalankan bot-fixed.sh terlebih dahulu"
        return 1
    fi

    echo "Testing bot connection..."
    echo "Token: ${BOT_TOKEN:0:10}...${BOT_TOKEN: -5}"
    echo "Chat ID: $CHAT_ID"

    local response
    response=$(curl -s "https://api.telegram.org/bot${BOT_TOKEN}/getMe" 2>/dev/null)
    if echo "$response" | grep -q '"ok":true'; then
        local bot_name
        if command -v jq &>/dev/null; then
            bot_name=$(echo "$response" | jq -r '.result.username')
        else
            bot_name=$(echo "$response" | grep -o '"username":"[^"]*"' | head -1 | cut -d'"' -f4)
        fi
        echo -e "\e[92;1m[OK]\e[0m Bot aktif: @${bot_name}"

        # Kirim pesan test
        send_telegram "<b>Test Notifikasi</b>%0ABot terhubung dengan VPS."
        if [[ $? -eq 0 ]]; then
            echo -e "\e[92;1m[OK]\e[0m Pesan test terkirim ke Telegram"
        else
            echo -e "\e[1;31m[ERROR]\e[0m Gagal mengirim pesan test"
        fi
    else
        echo -e "\e[1;31m[ERROR]\e[0m Bot tidak merespon - cek token"
    fi
}

# ============================================
# Jika script dijalankan langsung (bukan di-source)
# ============================================
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    case "${1}" in
        test)
            test_bot_connection
            ;;
        install)
            send_install_notification
            ;;
        *)
            echo "Penggunaan:"
            echo "  source notif-fixed.sh          # Import fungsi ke script lain"
            echo "  ./notif-fixed.sh test           # Test koneksi bot"
            echo "  ./notif-fixed.sh install        # Kirim notifikasi install"
            echo ""
            echo "Fungsi yang tersedia setelah source:"
            echo "  send_telegram \"<b>pesan</b>\"  # Kirim pesan custom"
            echo "  send_install_notification        # Notif install"
            echo "  send_user_created_notification proto user exp limit"
            echo "  send_user_expired_notification proto user"
            ;;
    esac
fi
