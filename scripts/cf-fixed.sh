#!/bin/bash
# ============================================
# CLOUDFLARE DNS AUTO-SETUP - FIXED VERSION
# ============================================
# PERBAIKAN:
# 1. Kredensial TIDAK di-hardcode - dibaca dari file konfigurasi
# 2. Validasi input sebelum proses
# 3. Error handling yang lebih baik
# 4. Sinkronisasi domain ke semua lokasi yang dibutuhkan
# ============================================

# Warna
grenbo="\e[92;1m"
red="\e[1;31m"
NC='\e[0m'
BLUE="\033[36m"
YELLOW="\033[33m"

# File konfigurasi Cloudflare
CF_CONFIG="/etc/xray/.cf-config"

# ============================================
# FUNGSI: Setup kredensial Cloudflare
# ============================================
setup_cf_credentials() {
    echo -e "\033[1;36m━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\033[0m"
    echo -e " \e[1;97;101m   SETUP CLOUDFLARE CREDENTIALS   \e[0m"
    echo -e "\033[1;36m━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\033[0m"
    echo ""

    read -e -p "[*] Cloudflare Email : " cf_email
    read -e -p "[*] Cloudflare API Key (Global) : " cf_key
    read -e -p "[*] Domain Utama (contoh: example.com) : " cf_domain

    if [[ -z "$cf_email" || -z "$cf_key" || -z "$cf_domain" ]]; then
        echo -e "${red}[ERROR]${NC} Semua field harus diisi!"
        exit 1
    fi

    # Simpan ke file dengan permission ketat
    cat > "$CF_CONFIG" << EOF
CF_EMAIL=$cf_email
CF_KEY=$cf_key
CF_DOMAIN=$cf_domain
EOF
    chmod 600 "$CF_CONFIG"
    echo -e "${grenbo}[OK]${NC} Kredensial tersimpan di $CF_CONFIG (permission: 600)"
}

# ============================================
# FUNGSI: Baca kredensial dari file
# ============================================
load_cf_credentials() {
    if [[ ! -f "$CF_CONFIG" ]]; then
        echo -e "${YELLOW}[INFO]${NC} Cloudflare belum dikonfigurasi"
        setup_cf_credentials
    fi

    # PERBAIKAN: Parsing aman tanpa source (mencegah code injection)
    CF_EMAIL=""
    CF_KEY=""
    CF_DOMAIN=""
    while IFS='=' read -r key value; do
        # Hapus spasi dan karakter berbahaya
        key=$(echo "$key" | tr -d '[:space:]')
        value=$(echo "$value" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//' | tr -d "'\"\`\$;|&")
        case "$key" in
            CF_EMAIL)  CF_EMAIL="$value" ;;
            CF_KEY)    CF_KEY="$value" ;;
            CF_DOMAIN) CF_DOMAIN="$value" ;;
        esac
    done < "$CF_CONFIG"

    if [[ -z "$CF_EMAIL" || -z "$CF_KEY" || -z "$CF_DOMAIN" ]]; then
        echo -e "${red}[ERROR]${NC} File konfigurasi tidak lengkap"
        setup_cf_credentials
        # Parse ulang
        while IFS='=' read -r key value; do
            key=$(echo "$key" | tr -d '[:space:]')
            value=$(echo "$value" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//' | tr -d "'\"\`\$;|&")
            case "$key" in
                CF_EMAIL)  CF_EMAIL="$value" ;;
                CF_KEY)    CF_KEY="$value" ;;
                CF_DOMAIN) CF_DOMAIN="$value" ;;
            esac
        done < "$CF_CONFIG"
    fi
}

# ============================================
# FUNGSI: Validasi API Key Cloudflare
# ============================================
validate_cf_api() {
    echo -e "${BLUE}[INFO]${NC} Memvalidasi API Cloudflare..."

    local response
    response=$(curl -sLX GET "https://api.cloudflare.com/client/v4/user/tokens/verify" \
        -H "X-Auth-Email: ${CF_EMAIL}" \
        -H "X-Auth-Key: ${CF_KEY}" \
        -H "Content-Type: application/json" 2>/dev/null)

    # Cek alternatif: langsung cek zone
    local zone_check
    zone_check=$(curl -sLX GET "https://api.cloudflare.com/client/v4/zones?name=${CF_DOMAIN}&status=active" \
        -H "X-Auth-Email: ${CF_EMAIL}" \
        -H "X-Auth-Key: ${CF_KEY}" \
        -H "Content-Type: application/json" 2>/dev/null)

    local zone_id
    zone_id=$(echo "$zone_check" | jq -r '.result[0].id' 2>/dev/null)

    if [[ -z "$zone_id" || "$zone_id" == "null" ]]; then
        echo -e "${red}[ERROR]${NC} Gagal mengakses domain ${CF_DOMAIN}"
        echo -e "${YELLOW}[INFO]${NC}  Cek email, API key, dan pastikan domain aktif di Cloudflare"
        exit 1
    fi

    echo -e "${grenbo}[OK]${NC} API valid - Zone ID: ${zone_id:0:8}..."
    ZONE_ID="$zone_id"
}

# ============================================
# FUNGSI: Buat subdomain random
# ============================================
generate_subdomain() {
    local sub
    sub=$(cat /dev/urandom | tr -dc 'a-z0-9' | head -c5)
    echo "${sub}.${CF_DOMAIN}"
}

# ============================================
# FUNGSI: Setup DNS record
# ============================================
setup_dns() {
    local subdomain="$1"
    local ip="$2"

    echo -e "${BLUE}[INFO]${NC} Setting up DNS: ${subdomain} -> ${ip}"

    # Cek apakah record sudah ada
    local existing
    existing=$(curl -sLX GET "https://api.cloudflare.com/client/v4/zones/${ZONE_ID}/dns_records?name=${subdomain}" \
        -H "X-Auth-Email: ${CF_EMAIL}" \
        -H "X-Auth-Key: ${CF_KEY}" \
        -H "Content-Type: application/json" 2>/dev/null)

    local record_id
    record_id=$(echo "$existing" | jq -r '.result[0].id' 2>/dev/null)

    if [[ -n "$record_id" && "$record_id" != "null" && "${#record_id}" -gt 10 ]]; then
        # Update record yang sudah ada
        echo -e "${BLUE}[INFO]${NC} Record sudah ada, mengupdate..."
        local result
        result=$(curl -sLX PUT "https://api.cloudflare.com/client/v4/zones/${ZONE_ID}/dns_records/${record_id}" \
            -H "X-Auth-Email: ${CF_EMAIL}" \
            -H "X-Auth-Key: ${CF_KEY}" \
            -H "Content-Type: application/json" \
            --data "{\"type\":\"A\",\"name\":\"${subdomain}\",\"content\":\"${ip}\",\"ttl\":120,\"proxied\":false}" 2>/dev/null)

        if echo "$result" | jq -r '.success' 2>/dev/null | grep -q "true"; then
            echo -e "${grenbo}[OK]${NC} DNS record diupdate"
        else
            echo -e "${red}[ERROR]${NC} Gagal update DNS"
            echo "$result" | jq '.errors' 2>/dev/null
            exit 1
        fi
    else
        # Buat record baru
        echo -e "${BLUE}[INFO]${NC} Membuat record baru..."
        local result
        result=$(curl -sLX POST "https://api.cloudflare.com/client/v4/zones/${ZONE_ID}/dns_records" \
            -H "X-Auth-Email: ${CF_EMAIL}" \
            -H "X-Auth-Key: ${CF_KEY}" \
            -H "Content-Type: application/json" \
            --data "{\"type\":\"A\",\"name\":\"${subdomain}\",\"content\":\"${ip}\",\"ttl\":120,\"proxied\":false}" 2>/dev/null)

        if echo "$result" | jq -r '.success' 2>/dev/null | grep -q "true"; then
            echo -e "${grenbo}[OK]${NC} DNS record dibuat"
        else
            echo -e "${red}[ERROR]${NC} Gagal buat DNS record"
            echo "$result" | jq '.errors' 2>/dev/null
            exit 1
        fi
    fi
}

# ============================================
# FUNGSI: Simpan domain ke semua lokasi
# PERBAIKAN: Sinkronisasi ke SEMUA file yang membutuhkan
# ============================================
save_domain_everywhere() {
    local domain="$1"

    echo -e "${BLUE}[INFO]${NC} Menyimpan domain ke semua lokasi..."

    # Lokasi utama
    echo "$domain" > /root/domain
    echo "$domain" > /root/scdomain
    echo "$domain" > /etc/xray/domain

    # Lokasi tambahan (jika direktori ada)
    [[ -d /etc/v2ray ]] && echo "$domain" > /etc/v2ray/domain
    echo "$domain" > /etc/xray/scdomain 2>/dev/null

    # Untuk kyt bot
    mkdir -p /var/lib/kyt
    echo "IP=$domain" > /var/lib/kyt/ipvps.conf

    # Update var.txt bot jika sudah terinstall
    local VAR_FILE="/usr/local/share/kyt-bot/kyt/var.txt"
    if [[ -f "$VAR_FILE" ]]; then
        # Update hanya baris DOMAIN tanpa menghapus config lain
        if grep -q '^DOMAIN=' "$VAR_FILE"; then
            sed -i "s|^DOMAIN=.*|DOMAIN=\"$domain\"|" "$VAR_FILE"
        else
            echo "DOMAIN=\"$domain\"" >> "$VAR_FILE"
        fi
        echo -e "${grenbo}[OK]${NC} Domain di bot panel juga diupdate"

        # Restart bot agar baca domain baru
        if systemctl is-active --quiet kyt 2>/dev/null; then
            systemctl restart kyt
            echo -e "${grenbo}[OK]${NC} Bot panel di-restart"
        fi
    fi

    echo -e "${grenbo}[OK]${NC} Domain tersimpan di semua lokasi"
}

# ============================================
# MULAI PROSES
# ============================================
if [[ "${EUID}" -ne 0 ]]; then
    echo "Script harus dijalankan sebagai root"
    exit 1
fi

# Install dependensi
apt install -y jq curl >/dev/null 2>&1

# Deteksi IP
MYIP=$(curl -sS ipv4.icanhazip.com 2>/dev/null)
if [[ -z "$MYIP" ]]; then
    echo -e "${red}[ERROR]${NC} Gagal mendeteksi IP address"
    exit 1
fi
echo -e "${grenbo}[OK]${NC} IP Address: $MYIP"

# Load/setup kredensial
load_cf_credentials

# Validasi API
validate_cf_api

# Generate subdomain
dns=$(generate_subdomain)
echo -e "${BLUE}[INFO]${NC} Subdomain yang dibuat: $dns"

# Setup DNS
setup_dns "$dns" "$MYIP"

# Simpan domain ke semua lokasi (SINKRONISASI)
save_domain_everywhere "$dns"

# Tampilkan hasil
echo ""
echo -e "\033[1;36m━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\033[0m"
echo -e " \e[1;97;42m     DOMAIN BERHASIL DIKONFIGURASI     \e[0m"
echo -e "\033[1;36m━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\033[0m"
echo -e " Domain  : $dns"
echo -e " IP      : $MYIP"
echo -e " Proxied : OFF (direct)"
echo -e " TTL     : 120 detik"
echo -e "\033[1;36m━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\033[0m"
echo ""
echo -e "${YELLOW}[INFO]${NC} Pengaturan Cloudflare yang disarankan:"
echo -e "  SSL/TLS            : FULL"
echo -e "  SSL Recommender    : OFF"
echo -e "  gRPC               : ON"
echo -e "  WebSocket          : ON"
echo -e "  Always Use HTTPS   : OFF"
echo -e "  Under Attack Mode  : OFF"
echo ""
