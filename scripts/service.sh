#!/usr/bin/env bash
#
# ============================================================
# BoRIS — vless-client
# Версия: 2.0
#
# VLESS CLIENT CONFIG GENERATOR & PROFILE MANAGER
#
# Debian 13
# BoRIS: 192.168.1.200
#
# Назначение:
#   - генерация клиентского Xray VLESS + REALITY конфига
#   - интерактивная настройка параметров
#   - сохранение параметров в environment file
#   - безопасная повторная генерация
#   - JSON validation
#   - вывод готовых параметров подключения
#   - управление профилями (create/list/show/delete)
#   - генерация VLESS URI
#   - диагностика подключения
#   - backup/rollback
#
# НЕ делает:
#   - не меняет routing
#   - не меняет firewall
#   - не меняет Keenetic
#   - не запускает клиентский Xray
#   - не меняет серверный Xray
#
# ============================================================

set -Eeuo pipefail

VERSION="2.0"

# ============================================================
# BoRIS configuration (unified with previous scripts)
# ============================================================

BORI_ROOT="/opt/boris"
LAN_IP="192.168.1.200"

SERVICES_ROOT="${BORI_ROOT}/services"
BASE_DIR="${BORI_ROOT}/vless-client"

XRAY_SERVER_DIR="${SERVICES_ROOT}/xray"
PROFILE_DIR="${BASE_DIR}/profiles"
BACKUP_DIR="${BASE_DIR}/backups"

SECRETS_DIR="${XRAY_SERVER_DIR}/secrets"
ENV_FILE="${BASE_DIR}/client.env"

LOG="/var/log/boris-vless-client.log"

# ============================================================
# Xray configuration
# ============================================================

XRAY_IMAGE="ghcr.io/xtls/xray-core:latest"
XRAY_CONTAINER="boris-xray"
XRAY_SERVER_PORT="443"

# ============================================================
# Defaults
# ============================================================

DEFAULT_VLESS_PORT="443"
DEFAULT_VLESS_FLOW="xtls-rprx-vision"
DEFAULT_REALITY_SERVER_NAME="www.cloudflare.com"
DEFAULT_REALITY_FINGERPRINT="chrome"
DEFAULT_XHTTP_PATH="/xhttp"
DEFAULT_XHTTP_MODE="auto"
DEFAULT_PROFILE_NAME="boris-phone"

# ============================================================
# Runtime variables
# ============================================================

VLESS_PUBLIC_HOST=""
VLESS_PORT=""
VLESS_UUID=""
VLESS_FLOW=""
REALITY_PUBLIC_KEY=""
REALITY_SHORT_ID=""
REALITY_SERVER_NAME=""
REALITY_FINGERPRINT=""
XHTTP_PATH=""
XHTTP_MODE=""
XHTTP_HOST=""
PROFILE_NAME=""
TRANSPORT=""

# ============================================================
# Colors
# ============================================================

if [[ -t 1 ]]; then
    GREEN='\033[0;32m'
    YELLOW='\033[1;33m'
    RED='\033[0;31m'
    BLUE='\033[0;34m'
    CYAN='\033[0;36m'
    NC='\033[0m'
else
    GREEN=''
    YELLOW=''
    RED=''
    BLUE=''
    CYAN=''
    NC=''
fi

# ============================================================
# Logging
# ============================================================

mkdir -p "$(dirname "$LOG")"
touch "$LOG"
chmod 600 "$LOG"

log() {
    echo -e "${GREEN}[OK]${NC} $*" | tee -a "$LOG"
}

info() {
    echo -e "${BLUE}[INFO]${NC} $*" | tee -a "$LOG"
}

warn() {
    echo -e "${YELLOW}[WARN]${NC} $*" | tee -a "$LOG"
}

die() {
    echo -e "${RED}[ERROR]${NC} $*" | tee -a "$LOG" >&2
    exit 1
}

on_error() {
    local code=$?
    local line=$1
    echo | tee -a "$LOG"
    echo -e "${RED}[ERROR]${NC} Ошибка в строке ${line}, exit code=${code}." | tee -a "$LOG" >&2
    echo -e "${RED}[ERROR]${NC} Log: ${LOG}" | tee -a "$LOG" >&2
    exit "$code"
}

trap 'on_error "$LINENO"' ERR

# ============================================================
# Helpers
# ============================================================

require_root() {
    [[ "$EUID" -eq 0 ]] ||
        die "Скрипт необходимо запускать через sudo/root."
}

require_command() {
    local cmd="$1"
    command -v "$cmd" >/dev/null 2>&1 ||
        die "Не найдено обязательное приложение: ${cmd}"
}

valid_ipv4_or_hostname() {
    local value="$1"
    [[ "$value" =~ ^[A-Za-z0-9._:-]+$ ]]
}

valid_port() {
    local port="$1"
    [[ "$port" =~ ^[0-9]+$ ]] && (( port >= 1 && port <= 65535 ))
}

valid_uuid() {
    local uuid="$1"
    [[ "$uuid" =~ ^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[1-5][0-9a-fA-F]{3}-[89abAB][0-9a-fA-F]{3}-[0-9a-fA-F]{12}$ ]]
}

valid_short_id() {
    local id="$1"
    [[ "$id" =~ ^[0-9a-fA-F]+$ ]] && (( ${#id} >= 2 )) && (( ${#id} <= 16 )) && (( ${#id} % 2 == 0 ))
}

generate_uuid() {
    if command -v uuidgen >/dev/null 2>&1; then
        uuidgen
    elif [[ -r /proc/sys/kernel/random/uuid ]]; then
        cat /proc/sys/kernel/random/uuid
    else
        die "Не удалось получить UUID."
    fi
}

# ============================================================
# Directory initialization
# ============================================================

init_dirs() {
    mkdir -p \
        "$BASE_DIR" \
        "$PROFILE_DIR" \
        "$BACKUP_DIR"

    chmod 700 "$BASE_DIR"
    chmod 700 "$PROFILE_DIR"
    chmod 700 "$BACKUP_DIR"

    if [[ ! -f "$ENV_FILE" ]]; then
        touch "$ENV_FILE"
        chmod 600 "$ENV_FILE"
    fi
}

# ============================================================
# Read server secrets
# ============================================================

read_server_values() {
    [[ -f "${SECRETS_DIR}/uuid" ]] ||
        die "Не найден Xray UUID: ${SECRETS_DIR}/uuid"

    [[ -f "${SECRETS_DIR}/public.key" ]] ||
        die "Не найден REALITY public key: ${SECRETS_DIR}/public.key"

    [[ -f "${SECRETS_DIR}/short-id" ]] ||
        die "Не найден REALITY shortId: ${SECRETS_DIR}/short-id"

    VLESS_UUID="$(tr -d '\r\n' < "${SECRETS_DIR}/uuid")"
    REALITY_PUBLIC_KEY="$(tr -d '\r\n' < "${SECRETS_DIR}/public.key")"
    REALITY_SHORT_ID="$(tr -d '\r\n' < "${SECRETS_DIR}/short-id")"

    [[ -n "$VLESS_UUID" ]] || die "VLESS UUID пуст."
    [[ -n "$REALITY_PUBLIC_KEY" ]] || die "REALITY public key пуст."
    [[ -n "$REALITY_SHORT_ID" ]] || die "REALITY shortId пуст."

    valid_uuid "$VLESS_UUID" || die "Некорректный VLESS UUID: ${VLESS_UUID}"
    valid_short_id "$REALITY_SHORT_ID" || die "Некорректный REALITY shortId: ${REALITY_SHORT_ID}"

    log "Xray server secrets прочитаны."
}

# ============================================================
# Load/Save environment
# ============================================================

load_environment() {
    if [[ -f "$ENV_FILE" ]]; then
        # shellcheck disable=SC1090
        source "$ENV_FILE"
        return 0
    fi
    return 1
}

save_environment() {
    local tmp
    tmp="$(mktemp)"

    cat > "$tmp" <<EOF
# BoRIS VLESS client environment
# Generated by 07-vless-client.sh v${VERSION}

VLESS_PUBLIC_HOST='${VLESS_PUBLIC_HOST}'
VLESS_PORT='${VLESS_PORT}'
VLESS_UUID='${VLESS_UUID}'
VLESS_FLOW='${VLESS_FLOW}'
REALITY_PUBLIC_KEY='${REALITY_PUBLIC_KEY}'
REALITY_SHORT_ID='${REALITY_SHORT_ID}'
REALITY_SERVER_NAME='${REALITY_SERVER_NAME}'
REALITY_FINGERPRINT='${REALITY_FINGERPRINT}'
XHTTP_PATH='${XHTTP_PATH}'
XHTTP_MODE='${XHTTP_MODE}'
XHTTP_HOST='${XHTTP_HOST}'
EOF

    chmod 600 "$tmp"
    mv -f "$tmp" "$ENV_FILE"
    log "Environment сохранён: $ENV_FILE"
}

backup_file() {
    local file="$1"
    [[ -f "$file" ]] || return 0

    local timestamp
    timestamp="$(date '+%Y%m%d-%H%M%S')"
    local name
    name="$(basename "$file")"

    cp -a "$file" "${BACKUP_DIR}/${name}.${timestamp}.bak"
    chmod 600 "${BACKUP_DIR}/${name}.${timestamp}.bak"
    log "Backup создан: ${name}.${timestamp}.bak"
}

# ============================================================
# Interactive configuration
# ============================================================

configure_interactive() {
    echo
    echo "============================================================"
    echo "             VLESS CLIENT CONFIGURATION"
    echo "============================================================"
    echo

    # Public host
    if [[ -n "${VLESS_PUBLIC_HOST:-}" ]]; then
        info "Текущий VLESS_PUBLIC_HOST: ${VLESS_PUBLIC_HOST}"
        read -r -p "Внешний host/IP [${VLESS_PUBLIC_HOST}]: " input
        VLESS_PUBLIC_HOST="${input:-$VLESS_PUBLIC_HOST}"
    else
        while true; do
            read -r -p "Внешний IP/домен BoRIS: " input
            VLESS_PUBLIC_HOST="$input"
            if valid_ipv4_or_hostname "$VLESS_PUBLIC_HOST"; then
                break
            fi
            warn "Некорректный host/IP."
        done
    fi

    # Port
    VLESS_PORT="${VLESS_PORT:-$DEFAULT_VLESS_PORT}"
    while true; do
        read -r -p "Внешний порт VLESS [${VLESS_PORT}]: " input
        VLESS_PORT="${input:-$VLESS_PORT}"
        if valid_port "$VLESS_PORT"; then
            break
        fi
        warn "Некорректный TCP порт."
    done

    # Flow
    VLESS_FLOW="${VLESS_FLOW:-$DEFAULT_VLESS_FLOW}"
    echo
    echo "VLESS flow:"
    echo "  1) xtls-rprx-vision"
    echo "  2) none"
    read -r -p "Flow [${VLESS_FLOW}]: " input

    if [[ -n "$input" ]]; then
        case "$input" in
            1|xtls-rprx-vision) VLESS_FLOW="xtls-rprx-vision" ;;
            2|none) VLESS_FLOW="" ;;
            *) warn "Неизвестное значение. Оставляем ${VLESS_FLOW}." ;;
        esac
    fi

    # REALITY serverName
    REALITY_SERVER_NAME="${REALITY_SERVER_NAME:-$DEFAULT_REALITY_SERVER_NAME}"
    read -r -p "REALITY serverName [${REALITY_SERVER_NAME}]: " input
    REALITY_SERVER_NAME="${input:-$REALITY_SERVER_NAME}"

    # Fingerprint
    REALITY_FINGERPRINT="${REALITY_FINGERPRINT:-$DEFAULT_REALITY_FINGERPRINT}"
    read -r -p "REALITY fingerprint [${REALITY_FINGERPRINT}]: " input
    REALITY_FINGERPRINT="${input:-$REALITY_FINGERPRINT}"

    # Summary
    echo
    echo "============================================================"
    echo "                 CONFIGURATION SUMMARY"
    echo "============================================================"
    echo
    echo "Public host       : ${VLESS_PUBLIC_HOST}"
    echo "Public port       : ${VLESS_PORT}"
    echo "VLESS UUID        : ${VLESS_UUID}"
    echo "VLESS flow        : ${VLESS_FLOW:-none}"
    echo "REALITY server    : ${REALITY_SERVER_NAME}"
    echo "REALITY fingerprint: ${REALITY_FINGERPRINT}"
    echo "REALITY shortId   : ${REALITY_SHORT_ID}"
    echo "REALITY publicKey : ${REALITY_PUBLIC_KEY}"
    echo
}

# ============================================================
# Profile management
# ============================================================

profile_path() {
    printf '%s/%s.json' "$PROFILE_DIR" "$1"
}

validate_profile() {
    local file="$1"
    [[ -f "$file" ]] || die "Файл профиля отсутствует."

    if command -v python3 >/dev/null 2>&1; then
        python3 -m json.tool "$file" >/dev/null 2>&1 ||
            die "JSON профиля некорректен: $file"
    fi

    log "Profile validation OK: $(basename "$file")"
}

list_profiles() {
    echo
    echo "============================================================"
    echo "                    VLESS PROFILES"
    echo "============================================================"
    echo

    local found=0
    shopt -s nullglob
    for file in "${PROFILE_DIR}"/*.json; do
        found=1
        local name
        name="$(basename "$file" .json)"
        echo "  - $name"
    done
    shopt -u nullglob

    if [[ "$found" -eq 0 ]]; then
        echo "  Профилей пока нет."
    fi
    echo
}

show_profile() {
    local name="$1"
    local file
    file="$(profile_path "$name")"
    [[ -f "$file" ]] || die "Профиль не найден."

    echo
    echo "============================================================"
    echo "                  PROFILE: ${name}"
    echo "============================================================"
    echo

    if command -v python3 >/dev/null 2>&1; then
        python3 - "$file" <<'PY'
import json
import sys

with open(sys.argv[1], encoding="utf-8") as f:
    d=json.load(f)

s=d["streamSettings"]
r=s["realitySettings"]
u=d["users"][0]

print("Address       :", d["address"])
print("Port          :", d["port"])
print("UUID          :", u["id"])
print("Flow          :", u.get("flow", ""))
print("Transport     :", s["network"])
print("Security      :", s["security"])
print("SNI           :", r["serverName"])
print("Fingerprint   :", r.get("fingerprint", ""))
print("Short ID      :", r["shortId"])
print("Public Key    :", r["publicKey"])

if s["network"] == "xhttp":
    x=s.get("xhttpSettings", {})
    print("XHTTP path    :", x.get("path", ""))
    print("XHTTP mode    :", x.get("mode", ""))
    print("XHTTP host    :", x.get("host", ""))
PY
    fi

    echo
}

# ============================================================
# Create profile
# ============================================================

create_profile() {
    echo
    echo "============================================================"
    echo "                  CREATE VLESS PROFILE"
    echo "============================================================"
    echo

    read -r -p "Имя профиля [${DEFAULT_PROFILE_NAME}]: " input
    PROFILE_NAME="${input:-$DEFAULT_PROFILE_NAME}"
    PROFILE_NAME="${PROFILE_NAME// /-}"

    echo
    echo "Транспорт:"
    echo "  1) RAW"
    echo "  2) XHTTP"
    read -r -p "Выбор [1]: " choice
    choice="${choice:-1}"

    case "$choice" in
        1) TRANSPORT="raw" ;;
        2) TRANSPORT="xhttp" ;;
        *) die "Неверный выбор." ;;
    esac

    echo
    read -r -p "VLESS_PUBLIC_HOST [${VLESS_PUBLIC_HOST}]: " input
    VLESS_PUBLIC_HOST="${input:-$VLESS_PUBLIC_HOST}"

    read -r -p "VLESS UUID [${VLESS_UUID}]: " input
    VLESS_UUID="${input:-$VLESS_UUID}"

    read -r -p "REALITY public key [${REALITY_PUBLIC_KEY}]: " input
    REALITY_PUBLIC_KEY="${input:-$REALITY_PUBLIC_KEY}"

    read -r -p "REALITY shortId [${REALITY_SHORT_ID}]: " input
    REALITY_SHORT_ID="${input:-$REALITY_SHORT_ID}"

    read -r -p "REALITY serverName [${REALITY_SERVER_NAME}]: " input
    REALITY_SERVER_NAME="${input:-$REALITY_SERVER_NAME}"

    read -r -p "REALITY fingerprint [${REALITY_FINGERPRINT}]: " input
    REALITY_FINGERPRINT="${input:-$REALITY_FINGERPRINT}"

    read -r -p "VLESS flow [${VLESS_FLOW}]: " input
    VLESS_FLOW="${input:-$VLESS_FLOW}"

    if [[ "$TRANSPORT" == "xhttp" ]]; then
        echo
        read -r -p "XHTTP path [${DEFAULT_XHTTP_PATH}]: " input
        XHTTP_PATH="${input:-$DEFAULT_XHTTP_PATH}"

        read -r -p "XHTTP mode [${DEFAULT_XHTTP_MODE}]: " input
        XHTTP_MODE="${input:-$DEFAULT_XHTTP_MODE}"

        read -r -p "XHTTP host (можно оставить пустым): " input
        XHTTP_HOST="${input:-}"
    fi

    local file
    file="$(profile_path "$PROFILE_NAME")"

    if [[ -f "$file" ]]; then
        echo
        warn "Профиль уже существует: $file"
        read -r -p "Перезаписать? [y/N]: " answer
        [[ "$answer" =~ ^[Yy]$ ]] || return 0
        backup_file "$file"
    fi

    write_profile "$file"
    save_environment
    validate_profile "$file"

    log "Профиль создан: $PROFILE_NAME"
    show_profile "$PROFILE_NAME"
}

# ============================================================
# Write profile JSON
# ============================================================

write_profile() {
    local file="$1"
    local tmp
    tmp="$(mktemp)"

    if [[ "$TRANSPORT" == "raw" ]]; then
        cat > "$tmp" <<EOF
{
  "address": "${VLESS_PUBLIC_HOST}",
  "port": ${XRAY_SERVER_PORT},
  "users": [
    {
      "id": "${VLESS_UUID}",
      "encryption": "none",
      "flow": "${VLESS_FLOW}"
    }
  ],
  "streamSettings": {
    "network": "raw",
    "security": "reality",
    "realitySettings": {
      "fingerprint": "${REALITY_FINGERPRINT}",
      "serverName": "${REALITY_SERVER_NAME}",
      "publicKey": "${REALITY_PUBLIC_KEY}",
      "shortId": "${REALITY_SHORT_ID}",
      "spiderX": "/"
    }
  }
}
EOF
    else
        cat > "$tmp" <<EOF
{
  "address": "${VLESS_PUBLIC_HOST}",
  "port": ${XRAY_SERVER_PORT},
  "users": [
    {
      "id": "${VLESS_UUID}",
      "encryption": "none",
      "flow": "${VLESS_FLOW}"
    }
  ],
  "streamSettings": {
    "network": "xhttp",
    "security": "reality",
    "realitySettings": {
      "fingerprint": "${REALITY_FINGERPRINT}",
      "serverName": "${REALITY_SERVER_NAME}",
      "publicKey": "${REALITY_PUBLIC_KEY}",
      "shortId": "${REALITY_SHORT_ID}",
      "spiderX": "/"
    },
    "xhttpSettings": {
      "path": "${XHTTP_PATH}",
      "mode": "${XHTTP_MODE}"
EOF
        if [[ -n "$XHTTP_HOST" ]]; then
            echo "," >> "$tmp"
            echo "      \"host\": \"${XHTTP_HOST}\"" >> "$tmp"
        fi
        echo "    }" >> "$tmp"
        echo "  }" >> "$tmp"
        echo "}" >> "$tmp"
    fi

    chmod 600 "$tmp"
    mv -f "$tmp" "$file"
    chmod 600 "$file"
    log "Профиль сохранён: $file"
}

# ============================================================
# Generate VLESS URI
# ============================================================

generate_uri() {
    list_profiles
    read -r -p "Имя профиля: " PROFILE_NAME

    local file
    file="$(profile_path "$PROFILE_NAME")"
    [[ -f "$file" ]] || die "Профиль не найден."

    echo
    echo "============================================================"
    echo "                    VLESS URI"
    echo "============================================================"
    echo

    if command -v python3 >/dev/null 2>&1; then
        python3 - "$file" "$PROFILE_NAME" <<'PY'
import json
import sys
import urllib.parse

file=sys.argv[1]
name=sys.argv[2]

with open(file, encoding="utf-8") as f:
    d=json.load(f)

s=d["streamSettings"]
r=s["realitySettings"]
u=d["users"][0]

params={
    "encryption": u.get("encryption", "none"),
    "flow": u.get("flow", ""),
    "security": "reality",
    "sni": r["serverName"],
    "fp": r.get("fingerprint", "chrome"),
    "pbk": r["publicKey"],
    "sid": r["shortId"],
    "spx": r.get("spiderX", "/")
}

if s["network"] == "xhttp":
    params["type"]="xhttp"
    x=s.get("xhttpSettings", {})
    params["path"]=x.get("path", "/")
    if x.get("mode"):
        params["mode"]=x["mode"]
    if x.get("host"):
        params["host"]=x["host"]
else:
    params["type"]="raw"

query=urllib.parse.urlencode(
    {k:v for k,v in params.items() if v != ""}
)

uri=(
    f"vless://{u['id']}@"
    f"{d['address']}:{d['port']}"
    f"?{query}"
    f"#{urllib.parse.quote(name)}"
)

print(uri)
PY
    fi

    echo
}

# ============================================================
# Diagnostics
# ============================================================

diagnose_profile() {
    list_profiles
    read -r -p "Имя профиля: " PROFILE_NAME

    local file
    file="$(profile_path "$PROFILE_NAME")"
    [[ -f "$file" ]] || die "Профиль не найден."

    validate_profile "$file"

    local host
    host="$(
        python3 - "$file" <<'PY'
import json
import sys
with open(sys.argv[1], encoding="utf-8") as f:
    d=json.load(f)
print(d["address"])
PY
    )"

    echo
    echo "============================================================"
    echo "                    DIAGNOSTICS"
    echo "============================================================"
    echo

    echo "[ PROFILE ]"
    echo "Name      : $PROFILE_NAME"
    echo "Host      : $host"
    echo "Port      : 443"

    echo
    echo "[ DNS ]"
    if getent ahosts "$host" >/dev/null 2>&1; then
        getent ahosts "$host"
        log "DNS resolution OK."
    else
        warn "DNS resolution failed: $host"
    fi

    echo
    echo "[ TCP ]"
    if command -v nc >/dev/null 2>&1; then
        if nc -z -w 5 "$host" 443 >/dev/null 2>&1; then
            log "TCP ${host}:443 reachable."
        else
            warn "TCP ${host}:443 unreachable."
        fi
    else
        warn "nc отсутствует — TCP тест пропущен."
    fi

    echo
    echo "[ XRAY CONTAINER ]"
    if command -v docker >/dev/null 2>&1 && docker inspect "$XRAY_CONTAINER" >/dev/null 2>&1; then
        docker inspect "$XRAY_CONTAINER" --format 'Status: {{.State.Status}}'
    else
        echo "Container not found."
    fi
}

# ============================================================
# Delete profile
# ============================================================

delete_profile() {
    list_profiles
    read -r -p "Профиль для удаления: " PROFILE_NAME

    local file
    file="$(profile_path "$PROFILE_NAME")"
    [[ -f "$file" ]] || die "Профиль не найден."

    echo
    warn "Будет удалён профиль: $file"
    read -r -p "Удалить? [y/N]: " answer
    [[ "$answer" =~ ^[Yy]$ ]] || return 0

    backup_file "$file"
    rm -f "$file"
    log "Профиль удалён: $PROFILE_NAME"
}

# ============================================================
# Rollback
# ============================================================

rollback_profile() {
    echo
    shopt -s nullglob
    local backups=("${BACKUP_DIR}"/*.json.*.bak)
    shopt -u nullglob

    if [[ "${#backups[@]}" -eq 0 ]]; then
        warn "Backup профилей не найден."
        return 0
    fi

    echo "Доступные backup:"
    local i=1
    for file in "${backups[@]}"; do
        echo "  ${i}) $(basename "$file")"
        ((i++))
    done

    echo
    read -r -p "Выбор backup [1]: " choice
    choice="${choice:-1}"
    local selected="${backups[$((choice-1))]:-}"
    [[ -n "$selected" ]] || die "Неверный backup."

    local original
    original="$(basename "$selected" | sed -E 's/\.[0-9]{8}-[0-9]{6}\.bak$//')"

    cp -a "$selected" "${PROFILE_DIR}/${original}"
    chmod 600 "${PROFILE_DIR}/${original}"
    log "Профиль восстановлен: ${original}"
}

rollback_environment() {
    echo
    shopt -s nullglob
    local backups=("${BACKUP_DIR}"/client.env.*.bak)
    shopt -u nullglob

    if [[ "${#backups[@]}" -eq 0 ]]; then
        warn "Backup environment не найден."
        return 0
    fi

    echo "Доступные backup:"
    local i=1
    for file in "${backups[@]}"; do
        echo "  ${i}) $(basename "$file")"
        ((i++))
    done

    echo
    read -r -p "Выбор backup [1]: " choice
    choice="${choice:-1}"
    local selected="${backups[$((choice-1))]:-}"
    [[ -n "$selected" ]] || die "Неверный backup."

    cp -a "$selected" "$ENV_FILE"
    chmod 600 "$ENV_FILE"
    load_environment
    log "Environment восстановлен."
}

# ============================================================
# Main menu
# ============================================================

menu() {
    while true; do
        echo
        echo "============================================================"
        echo "                 BoRIS VLESS CLIENT"
        echo "                       v${VERSION}"
        echo "============================================================"
        echo
        echo " Host: ${VLESS_PUBLIC_HOST:-NOT SET}"
        echo
        echo " 1) Создать / изменить профиль"
        echo " 2) Список профилей"
        echo " 3) Просмотреть профиль"
        echo " 4) Сгенерировать VLESS URI"
        echo " 5) Диагностика профиля"
        echo " 6) Настройки VLESS_PUBLIC_HOST / REALITY"
        echo " 7) Удалить профиль"
        echo " 8) Rollback profile"
        echo " 9) Rollback environment"
        echo " 0) Выход"
        echo
        read -r -p "Выбор: " choice

        case "$choice" in
            1) create_profile ;;
            2) list_profiles ;;
            3)
                list_profiles
                read -r -p "Имя профиля: " PROFILE_NAME
                show_profile "$PROFILE_NAME"
                ;;
            4) generate_uri ;;
            5) diagnose_profile ;;
            6)
                read_server_values
                configure_interactive
                validate_values
                save_environment
                ;;
            7) delete_profile ;;
            8) rollback_profile ;;
            9) rollback_environment ;;
            0)
                echo
                log "Выход."
                exit 0
                ;;
            *) warn "Неизвестная команда." ;;
        esac
    done
}

# ============================================================
# Validate values
# ============================================================

validate_values() {
    valid_ipv4_or_hostname "$VLESS_PUBLIC_HOST" ||
        die "Некорректный VLESS_PUBLIC_HOST."

    valid_port "$VLESS_PORT" ||
        die "Некорректный VLESS_PORT."

    valid_uuid "$VLESS_UUID" ||
        die "Некорректный VLESS_UUID."

    valid_short_id "$REALITY_SHORT_ID" ||
        die "Некорректный REALITY_SHORT_ID."

    [[ -n "$REALITY_PUBLIC_KEY" ]] ||
        die "REALITY_PUBLIC_KEY пуст."

    [[ -n "$REALITY_SERVER_NAME" ]] ||
        die "REALITY_SERVER_NAME пуст."

    [[ "$REALITY_FINGERPRINT" =~ ^[A-Za-z0-9._-]+$ ]] ||
        die "Некорректный REALITY_FINGERPRINT."

    log "Параметры VLESS/REALITY валидны."
}

# ============================================================
# Main
# ============================================================

main() {
    require_root

    require_command docker
    require_command python3
    require_command mkdir
    require_command mktemp
    require_command mv

    init_dirs

    echo
    echo "============================================================"
    echo "                 BoRIS VLESS CLIENT"
    echo "                    version ${VERSION}"
    echo "============================================================"
    echo

    info "BoRIS IP : ${LAN_IP}"
    info "Base dir  : ${BASE_DIR}"
    echo

    # Read server secrets
    read_server_values

    # Load existing config or create new
    if load_environment; then
        info "Используем существующие параметры."
        read -r -p "Изменить параметры подключения? [y/N]: " change

        if [[ "$change" =~ ^[YyДд]$ ]]; then
            configure_interactive
            validate_values
            save_environment
        fi
    else
        configure_interactive
        validate_values
        save_environment
    fi

    # Generate URI and show result
    echo
    echo "============================================================"
    echo "                    CONNECTION INFO"
    echo "============================================================"
    echo
    echo "VLESS URI:"
    echo "  vless://${VLESS_UUID}@${VLESS_PUBLIC_HOST}:${VLESS_PORT}?security=reality&pbk=${REALITY_PUBLIC_KEY}&sni=${REALITY_SERVER_NAME}&sid=${REALITY_SHORT_ID}&fp=${REALITY_FINGERPRINT}&flow=${VLESS_FLOW}#BoRIS"
    echo
    echo "Или используйте меню для создания профилей."
    echo

    menu
}

main "$@"
