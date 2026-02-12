#!/bin/bash
# ============================================
# BOT PANEL INSTALLER - FIXED VERSION
# Perbaikan oleh: Auto-Fix Script
# ============================================
# PERBAIKAN:
# 1. Cek dependensi (domain, xray, SSL) sebelum install
# 2. var.txt di-overwrite bukan append (mencegah duplikat)
# 3. chmod hanya untuk file bot, bukan seluruh /usr/bin
# 4. Validasi input user (token & ID)
# 5. Cek apakah bot sudah terinstall sebelumnya
# 6. Sinkronisasi token dengan notifikasi system
# ============================================

# Warna
grenbo="\e[92;1m"
red="\e[1;31m"
NC='\e[0m'
BLUE="\033[36m"
YELLOW="\033[33m"

# ============================================
# FUNGSI: Cek apakah file/dependensi tersedia
# ============================================
check_dependencies() {
    local has_error=0

    echo -e "\033[1;36m━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\033[0m"
    echo -e " \e[1;97;101m     CEK DEPENDENSI BOT PANEL     \e[0m"
    echo -e "\033[1;36m━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\033[0m"

    # Cek domain
    if [[ ! -f /etc/xray/domain ]] || [[ -z $(cat /etc/xray/domain 2>/dev/null) ]]; then
        echo -e "${red}[ERROR]${NC} Domain belum dikonfigurasi di /etc/xray/domain"
        echo -e "${YELLOW}[INFO]${NC}  Jalankan instalasi utama (main.sh) terlebih dahulu"
        has_error=1
    else
        echo -e "${grenbo}[OK]${NC} Domain: $(cat /etc/xray/domain)"
    fi

    # Cek SSL
    if [[ ! -f /etc/xray/xray.crt ]] || [[ ! -f /etc/xray/xray.key ]]; then
        echo -e "${red}[ERROR]${NC} SSL Certificate belum terpasang"
        echo -e "${YELLOW}[INFO]${NC}  Pastikan SSL sudah diinstall via main.sh"
        has_error=1
    else
        echo -e "${grenbo}[OK]${NC} SSL Certificate ditemukan"
    fi

    # Cek Xray
    if ! command -v xray &>/dev/null && [[ ! -f /usr/local/bin/xray ]]; then
        echo -e "${YELLOW}[WARN]${NC} Xray belum terinstall - bot mungkin tidak bisa kelola akun"
    else
        echo -e "${grenbo}[OK]${NC} Xray ditemukan"
    fi

    # Cek SlowDNS (opsional)
    if [[ -f /etc/slowdns/server.pub ]]; then
        echo -e "${grenbo}[OK]${NC} SlowDNS Public Key ditemukan"
    else
        echo -e "${YELLOW}[WARN]${NC} SlowDNS tidak ditemukan (opsional)"
    fi

    # Cek DNS
    if [[ -f /etc/xray/dns ]]; then
        echo -e "${grenbo}[OK]${NC} DNS Nameserver ditemukan"
    else
        echo -e "${YELLOW}[WARN]${NC} DNS Nameserver tidak ditemukan (opsional)"
    fi

    echo ""

    if [[ $has_error -eq 1 ]]; then
        echo -e "${red}[GAGAL]${NC} Dependensi utama belum terpenuhi!"
        echo -e "${YELLOW}[INFO]${NC}  Install VPS dengan main.sh terlebih dahulu"
        echo ""
        read -p "Lanjutkan instalasi bot? (y/n): " lanjut
        if [[ "$lanjut" != "y" && "$lanjut" != "Y" ]]; then
            echo "Instalasi dibatalkan."
            exit 1
        fi
    fi
}

# ============================================
# FUNGSI: Cek apakah bot sudah terinstall
# ============================================
check_existing_bot() {
    if systemctl is-active --quiet kyt 2>/dev/null; then
        echo ""
        echo -e "${YELLOW}[WARN]${NC} Bot panel sudah berjalan!"
        echo -e "${YELLOW}[INFO]${NC} Menginstall ulang akan menimpa konfigurasi lama"
        echo ""
        read -p "Lanjutkan? (y/n): " overwrite
        if [[ "$overwrite" != "y" && "$overwrite" != "Y" ]]; then
            echo "Instalasi dibatalkan."
            exit 0
        fi
        echo -e "${BLUE}[INFO]${NC} Menghentikan bot lama..."
        systemctl stop kyt 2>/dev/null
        systemctl disable kyt 2>/dev/null
    fi
}

# ============================================
# FUNGSI: Validasi Token Bot Telegram
# ============================================
validate_token() {
    local token="$1"
    # Format token: 123456789:ABCdefGHIjklMNOpqrSTUvwxYZ
    if [[ ! "$token" =~ ^[0-9]+:[-_a-zA-Z0-9]+$ ]]; then
        echo -e "${red}[ERROR]${NC} Format token tidak valid!"
        echo -e "${YELLOW}[INFO]${NC}  Format yang benar: 123456789:ABCdefGHIjklmno"
        return 1
    fi

    # Validasi token dengan memanggil API Telegram
    local response
    response=$(curl -s "https://api.telegram.org/bot${token}/getMe" 2>/dev/null)
    if echo "$response" | grep -q '"ok":true'; then
        local bot_name
        bot_name=$(echo "$response" | jq -r '.result.username' 2>/dev/null)
        echo -e "${grenbo}[OK]${NC} Token valid - Bot: @${bot_name}"
        return 0
    else
        echo -e "${red}[ERROR]${NC} Token tidak valid atau bot tidak ditemukan!"
        return 1
    fi
}

# ============================================
# FUNGSI: Validasi Chat ID Telegram
# ============================================
validate_chatid() {
    local chatid="$1"
    if [[ ! "$chatid" =~ ^-?[0-9]+$ ]]; then
        echo -e "${red}[ERROR]${NC} Chat ID harus berupa angka!"
        return 1
    fi
    return 0
}

# ============================================
# MULAI INSTALASI
# ============================================

# Harus root
if [[ "${EUID}" -ne 0 ]]; then
    echo "Script harus dijalankan sebagai root"
    exit 1
fi

# Cek dependensi
check_dependencies

# Cek bot lama
check_existing_bot

# Install dependencies
echo ""
echo -e "${BLUE}[INFO]${NC} Menginstall dependencies..."
apt update -y >/dev/null 2>&1
apt install -y python3 python3-pip jq curl >/dev/null 2>&1

# Ambil data dari system
domain=$(cat /etc/xray/domain 2>/dev/null || echo "belum_dikonfigurasi")
NS=$(cat /etc/xray/dns 2>/dev/null || echo "")
PUB=$(cat /etc/slowdns/server.pub 2>/dev/null || echo "")

# Download bot files
echo -e "${BLUE}[INFO]${NC} Mengunduh file bot..."
REPO="https://raw.githubusercontent.com/dit1304/VVIP/main"

# Buat direktori khusus bot (BUKAN langsung di /usr/bin)
BOT_DIR="/usr/local/share/kyt-bot"
mkdir -p "$BOT_DIR"

cd /tmp
rm -rf bot.zip kyt.zip bot/ kyt/ 2>/dev/null

wget -q "${REPO}/bot/bot.zip" -O bot.zip
if [[ $? -ne 0 ]]; then
    echo -e "${red}[ERROR]${NC} Gagal mengunduh bot.zip"
    exit 1
fi

wget -q "${REPO}/bot/kyt.zip" -O kyt.zip
if [[ $? -ne 0 ]]; then
    echo -e "${red}[ERROR]${NC} Gagal mengunduh kyt.zip"
    exit 1
fi

# Extract bot tools
unzip -qo bot.zip -d bot_extract/
if [[ -d bot_extract/bot ]]; then
    # PERBAIKAN: Hanya pindahkan file bot, BUKAN chmod seluruh /usr/bin
    cp -f bot_extract/bot/* "$BOT_DIR/" 2>/dev/null
    chmod +x "$BOT_DIR"/*
    # Buat symlink hanya untuk script yang diperlukan
    for f in "$BOT_DIR"/*; do
        fname=$(basename "$f")
        ln -sf "$f" "/usr/bin/$fname" 2>/dev/null
    done
fi

# Extract kyt bot panel
unzip -qo kyt.zip -d kyt_extract/
if [[ -d kyt_extract/kyt ]]; then
    rm -rf "$BOT_DIR/kyt"
    mv kyt_extract/kyt "$BOT_DIR/kyt"
fi

# Install Python requirements
if [[ -f "$BOT_DIR/kyt/requirements.txt" ]]; then
    echo -e "${BLUE}[INFO]${NC} Menginstall Python requirements..."
    pip3 install -r "$BOT_DIR/kyt/requirements.txt" >/dev/null 2>&1
fi

# Cleanup
rm -rf /tmp/bot.zip /tmp/kyt.zip /tmp/bot_extract /tmp/kyt_extract
cd /root

clear

# ============================================
# INPUT KONFIGURASI BOT
# ============================================
echo -e "\033[1;36m━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\033[0m"
echo -e " \e[1;97;101m       KONFIGURASI BOT PANEL       \e[0m"
echo -e "\033[1;36m━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\033[0m"
echo -e "${grenbo}Cara mendapatkan Token & ID:${NC}"
echo -e "${grenbo}[1] Buat Bot & Token : @BotFather di Telegram${NC}"
echo -e "${grenbo}[2] Cek ID Telegram  : @MissRose_bot , ketik /info${NC}"
echo -e "\033[1;36m━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\033[0m"
echo ""

# Input Token dengan validasi
while true; do
    read -e -p "[*] Masukkan Bot Token : " bottoken
    if [[ -z "$bottoken" ]]; then
        echo -e "${red}[ERROR]${NC} Token tidak boleh kosong!"
        continue
    fi
    if validate_token "$bottoken"; then
        break
    fi
    echo "Silakan coba lagi."
done

# Input Admin ID dengan validasi
while true; do
    read -e -p "[*] Masukkan ID Telegram : " admin
    if validate_chatid "$admin"; then
        echo -e "${grenbo}[OK]${NC} Chat ID: $admin"
        break
    fi
    echo "Silakan coba lagi."
done

# ============================================
# PERBAIKAN UTAMA: Overwrite var.txt (bukan append)
# ============================================
cat > "$BOT_DIR/kyt/var.txt" << EOF
BOT_TOKEN="$bottoken"
ADMIN="$admin"
DOMAIN="$domain"
PUB="$PUB"
HOST="$NS"
EOF

# ============================================
# PERBAIKAN: Simpan token juga untuk notifikasi system
# Ini yang membuat bot panel & notifikasi SINKRON
# ============================================
mkdir -p /etc/bot
cat > /etc/bot/.bot.db << EOF
$bottoken
$admin
EOF

echo -e "${grenbo}[OK]${NC} Token disimpan untuk notifikasi system (sinkron dengan bot panel)"

# ============================================
# Buat systemd service
# ============================================
cat > /etc/systemd/system/kyt.service << END
[Unit]
Description=KYT Bot Panel - Zero Store
After=network.target
Wants=network-online.target

[Service]
Type=simple
WorkingDirectory=$BOT_DIR
Environment=PYTHONPATH=$BOT_DIR
ExecStart=/usr/bin/python3 -m kyt
Restart=on-failure
RestartSec=10
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
END

# Pastikan kyt bisa ditemukan sebagai Python module
if [[ -d "$BOT_DIR/kyt" && ! -f "$BOT_DIR/kyt/__init__.py" ]]; then
    touch "$BOT_DIR/kyt/__init__.py"
fi
if [[ -d "$BOT_DIR/kyt" && ! -f "$BOT_DIR/kyt/__main__.py" ]]; then
    echo -e "${YELLOW}[WARN]${NC} kyt/__main__.py tidak ditemukan - bot mungkin tidak bisa start"
    echo -e "${YELLOW}[INFO]${NC} Cek isi $BOT_DIR/kyt/ untuk entry point yang benar"
fi

# Reload dan start service
systemctl daemon-reload
systemctl enable kyt
systemctl start kyt

# Cek status
sleep 2
if systemctl is-active --quiet kyt; then
    STATUS="${grenbo}RUNNING${NC}"
else
    STATUS="${red}GAGAL - cek: journalctl -u kyt -n 20${NC}"
fi

# ============================================
# TAMPILKAN HASIL
# ============================================
clear
echo -e "\033[1;36m━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\033[0m"
echo -e " \e[1;97;42m    BOT PANEL BERHASIL DIINSTALL    \e[0m"
echo -e "\033[1;36m━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\033[0m"
echo -e " Token Bot  : $bottoken"
echo -e " Admin ID   : $admin"
echo -e " Domain     : $domain"
echo -e " Pub Key    : ${PUB:-(tidak tersedia)}"
echo -e " NS Host    : ${NS:-(tidak tersedia)}"
echo -e " Status     : $STATUS"
echo -e " Config     : $BOT_DIR/kyt/var.txt"
echo -e "\033[1;36m━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\033[0m"
echo -e " Ketik ${grenbo}/menu${NC} di bot Telegram untuk mulai"
echo -e "\033[1;36m━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\033[0m"
echo ""
