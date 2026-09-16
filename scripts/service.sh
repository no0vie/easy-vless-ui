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

BORI_ROOT="${BORIS_ROOT:-${BORI_ROOT:-/opt/boris}}"
LAN_IP="192.168.1.200"

SERVICES_ROOT="${BORI_ROOT}/services"
BASE_DIR="${BASE_DIR:-${BORI_ROOT}/vless-client}"

XRAY_SERVER_DIR="${SERVICES_ROOT}/xray"
PROFILE_DIR="${PROFILE_DIR:-${BASE_DIR}/profiles}"
BACKUP_DIR="${BACKUP_DIR:-${BASE_DIR}/backups}"

SECRETS_DIR="${SECRETS_DIR:-${XRAY_SERVER_DIR}/secrets}"
ENV_FILE="${ENV_FILE:-${BASE_DIR}/client.env}"

LOG="${LOG:-/var/log/boris-vless-client.log}"

# Noninteractive API (Bash + Python 3 standard library; no root/Docker/jq):
#   service.sh --list-clients --format json
#   service.sh --create-client --name phone --transport raw
#   service.sh --get-client --name phone
#   service.sh --update-client --name phone --new-name tablet --expiry 30
#   service.sh --copy-client --name tablet --new-name laptop
#   service.sh --delete-client --name laptop
#   service.sh --status
# JSON is the default/only API format. No arguments retains the interactive UI.
# --transport: raw or xhttp (REALITY); --flow: none, '', or xtls-rprx-vision.
# 'none' normalizes to empty flow in config, metadata responses and URI output.
# XHTTP defaults to empty flow and rejects explicitly supplied Vision flow.
# --expiry: nonnegative integer DAYS; 0 clears, positive days become now + DAYS
# in UTC ISO format (24 hours/day). ISO dates/timezone-qualified datetimes remain
# accepted for compatibility; ''/null also clears. Expiry is metadata only.
# Identity is the filename stem, never the shared VLESS UUID. Rename changes it.
# Copies retain credentials/config/expiry, but receive a new creation timestamp.
# Existing files without _profile metadata expose null created/expiry. Metadata
# lives under _profile in the existing JSON file, omitted from returned config.
# JSON mode manages connection profiles, NOT server accounts. Expiry is metadata
# only: no revocation, enforcement, server reload, or traffic monitoring occurs.
# All activity/server status is unknown; unavailable telemetry/version is null.
#
# Paths: BORIS_ROOT (legacy BORI_ROOT fallback), BASE_DIR, PROFILE_DIR,
# SECRETS_DIR, ENV_FILE, BACKUP_DIR, LOG override the defaults below/above.
# API uses PROFILE_DIR (including .api.lock); BACKUP_DIR/LOG are interactive-only.
# Creation reads literal assignments from ENV_FILE, overridden by process env:
# VLESS_PUBLIC_HOST (required), VLESS_PORT (443), VLESS_UUID, VLESS_FLOW (Vision),
# REALITY_PUBLIC_KEY, REALITY_SHORT_ID, REALITY_SERVER_NAME (www.cloudflare.com),
# REALITY_FINGERPRINT (chrome), XHTTP_PATH (/xhttp), XHTTP_MODE (auto), XHTTP_HOST.
# Missing UUID/key/short ID fall back to SECRETS_DIR/{uuid,public.key,short-id}.
# Get/update/copy/delete need only existing profiles, not env or server secrets.
# List/status read ENV_FILE for server address/port, falling back to profiles.
# ENV_FILE accepts literal KEY=value (optionally export/quoted), not shell code.
# API writes are private (0600), atomically replaced and serialized on .api.lock;
# the interactive UI does not participate in that lock. No API backups are made.
# Keep this before interactive logging, root checks and runtime variable resets.
if (( $# )); then
    if ! command -v python3 >/dev/null 2>&1; then
        printf '%s\n' '{"error":"python3 is required","code":"SCRIPT_ERROR"}'
        exit 1
    fi
    export BASE_DIR PROFILE_DIR BACKUP_DIR SECRETS_DIR ENV_FILE
    exec python3 - "$@" <<'PYAPI'
import copy
import datetime as dt
import fcntl
import json
import os
from pathlib import Path
import re
import shlex
import sys
import tempfile
import urllib.parse
import uuid


class APIError(Exception):
    def __init__(self, message, code="VALIDATION_ERROR"):
        super().__init__(message)
        self.code = code


def fail(message, code="VALIDATION_ERROR"):
    raise APIError(message, code)


NAME = re.compile(r"[A-Za-z0-9][A-Za-z0-9_-]{0,63}", re.ASCII)
ACTIONS = {"--" + v + "-client" for v in ("create", "get", "update", "copy", "delete")}
ACTIONS |= {"--list-clients", "--status"}
OPTIONS = {"--name", "--new-name", "--transport", "--flow", "--expiry", "--format"}
KEYS = set("VLESS_PUBLIC_HOST VLESS_PORT VLESS_UUID VLESS_FLOW REALITY_PUBLIC_KEY REALITY_SHORT_ID REALITY_SERVER_NAME REALITY_FINGERPRINT XHTTP_PATH XHTTP_MODE XHTTP_HOST".split())
profiles = Path(os.environ["PROFILE_DIR"])


def arguments():
    args, opts, action = iter(sys.argv[1:]), {}, None
    for arg in args:
        if arg in ACTIONS:
            if action:
                fail("Exactly one action is required")
            action = arg
        elif arg in OPTIONS:
            if arg in opts:
                fail("Duplicate option: " + arg)
            value = next(args, None)
            if value is None or value.startswith("--"):
                fail("Missing value for " + arg)
            opts[arg] = value
        else:
            fail("Unknown argument: " + arg)
    if not action:
        fail("An action is required")
    if opts.get("--format", "json") != "json":
        fail("Only --format json is supported")
    allowed = {"--format"}
    if action not in {"--list-clients", "--status"}:
        allowed.add("--name")
        if "--name" not in opts:
            fail("--name is required")
    if action in {"--create-client", "--update-client", "--copy-client"}:
        allowed |= {"--transport", "--flow", "--expiry"}
    if action in {"--update-client", "--copy-client"}:
        allowed.add("--new-name")
    if action == "--copy-client" and "--new-name" not in opts:
        fail("--new-name is required for copy")
    if opts.keys() - allowed:
        fail("Options not applicable to action: " + ", ".join(sorted(opts.keys() - allowed)))
    for key in ("--name", "--new-name"):
        if key in opts and not NAME.fullmatch(opts[key]):
            fail(key + " must match ^[A-Za-z0-9][A-Za-z0-9_-]{0,63}$")
    if "--transport" in opts and opts["--transport"] not in {"raw", "xhttp"}:
        fail("Supported transports: raw, xhttp")
    if opts.get("--flow") == "none":
        opts["--flow"] = ""
    if "--flow" in opts and opts["--flow"] not in {"", "xtls-rprx-vision"}:
        fail("Flow must be none, empty or xtls-rprx-vision")
    if "--expiry" in opts:
        value = opts["--expiry"]
        if value in {"", "null"}:
            opts["--expiry"] = None
        elif re.fullmatch(r"[0-9]+", value):
            try:
                days = int(value)
                opts["--expiry"] = (
                    (dt.datetime.now(dt.timezone.utc) + dt.timedelta(days=days))
                    .isoformat().replace("+00:00", "Z") if days else None
                )
            except (ValueError, OverflowError):
                fail("Expiry days exceed the supported datetime range")
        else:
            try:
                if re.fullmatch(r"\d{4}-\d{2}-\d{2}", value):
                    dt.date.fromisoformat(value)
                else:
                    parsed = dt.datetime.fromisoformat(value.replace("Z", "+00:00"))
                    if parsed.tzinfo is None:
                        raise ValueError()
            except ValueError:
                fail("Expiry must be nonnegative integer days, an ISO date or timezone-qualified datetime, or null")
    return action, opts


def environment():
    # Literal assignments only; never source/eval user-writable shell content.
    values = {}
    path = Path(os.environ["ENV_FILE"])
    if path.exists():
        for number, line in enumerate(path.read_text().splitlines(), 1):
            if not line.strip() or line.lstrip().startswith("#"):
                continue
            match = re.fullmatch(r"\s*(?:export\s+)?([A-Z_]+)=(.*)", line)
            if not match or match[1] not in KEYS:
                fail("Unsupported environment assignment at line " + str(number))
            try:
                parts = shlex.split(match[2], comments=True)
            except ValueError:
                fail("Invalid environment quoting at line " + str(number))
            if len(parts) > 1:
                fail("Expected a literal environment value at line " + str(number))
            values[match[1]] = parts[0] if parts else ""
    values.update({k: os.environ[k] for k in KEYS if k in os.environ})
    return values


def path_for(name):
    path = profiles / (name + ".json")
    if path.is_symlink():
        fail("Symlink profiles are not supported", "SCRIPT_ERROR")
    return path


def load(name):
    path = path_for(name)
    if not path.exists():
        fail("Profile not found: " + name, "NOT_FOUND")
    with path.open() as stream:
        data = json.load(stream)
    client(name, data)  # Validate existing profiles before any mutation.
    return data


def client(name, data):
    s, u = data["streamSettings"], data["users"][0]
    r = s["realitySettings"]
    if s["network"] not in {"raw", "xhttp"} or s["security"] != "reality":
        fail("Unsupported stored profile: " + name, "SCRIPT_ERROR")
    params = {"encryption": u.get("encryption", "none"), "flow": u.get("flow", ""),
              "security": "reality", "sni": r["serverName"], "fp": r.get("fingerprint", "chrome"),
              "pbk": r["publicKey"], "sid": r["shortId"], "spx": r.get("spiderX", "/"),
              "type": s["network"]}
    if s["network"] == "xhttp":
        x = s.get("xhttpSettings", {})
        params.update(path=x.get("path", "/"), mode=x.get("mode", ""), host=x.get("host", ""))
    address = data["address"]
    authority = "[" + address + "]" if ":" in address and not address.startswith("[") else address
    uri = "vless://{}@{}:{}?{}#{}".format(u["id"], authority, data["port"],
        urllib.parse.urlencode({k: v for k, v in params.items() if v != ""}), urllib.parse.quote(name))
    metadata = data.get("_profile", {})
    config = {k: v for k, v in data.items() if k != "_profile"}
    return dict(id=name, name=name, transport=s["network"], flow=u.get("flow", ""),
                created=metadata.get("created"), expiry=metadata.get("expiry"), status="unknown",
                address=address, port=data["port"], config=config, connectionString=uri)


def new_profile(env):
    values = dict(env)
    for key, filename in (("VLESS_UUID", "uuid"), ("REALITY_PUBLIC_KEY", "public.key"), ("REALITY_SHORT_ID", "short-id")):
        if not values.get(key):
            path = Path(os.environ["SECRETS_DIR"]) / filename
            if path.is_file():
                values[key] = path.read_text().strip()
        if not values.get(key):
            fail("Missing " + key + " (environment or server secrets)")
    host = values.get("VLESS_PUBLIC_HOST", "")
    if not re.fullmatch(r"[A-Za-z0-9._:-]+", host):
        fail("A valid VLESS_PUBLIC_HOST is required")
    try:
        port = int(values.get("VLESS_PORT", "443"))
        if not 1 <= port <= 65535:
            raise ValueError()
        uuid.UUID(values["VLESS_UUID"])
    except ValueError:
        fail("Invalid VLESS_PORT or VLESS_UUID")
    sid = values["REALITY_SHORT_ID"]
    if not re.fullmatch(r"(?:[a-fA-F0-9]{2}){1,8}", sid):
        fail("Invalid REALITY_SHORT_ID")
    return {"address": host, "port": port,
            "users": [{"id": values["VLESS_UUID"], "encryption": "none", "flow": values.get("VLESS_FLOW", "xtls-rprx-vision")}],
            "streamSettings": {"network": "raw", "security": "reality", "realitySettings": {
                "fingerprint": values.get("REALITY_FINGERPRINT", "chrome"),
                "serverName": values.get("REALITY_SERVER_NAME", "www.cloudflare.com"),
                "publicKey": values["REALITY_PUBLIC_KEY"], "shortId": sid, "spiderX": "/"}}}


def persist(path, data):
    fd, tmp = tempfile.mkstemp(prefix=".profile-", dir=str(profiles))
    try:
        with os.fdopen(fd, "w") as stream:
            json.dump(data, stream, indent=2)
            stream.write("\n")
            stream.flush()
            os.fsync(stream.fileno())
        os.replace(tmp, path)
    finally:
        if os.path.exists(tmp):
            os.unlink(tmp)


def run(action, opts):
    if action in {"--list-clients", "--status"}:
        items = [client(p.stem, load(p.stem)) for p in sorted(profiles.glob("*.json")) if NAME.fullmatch(p.stem)]
        env = environment()
        address = env.get("VLESS_PUBLIC_HOST") or (items[0]["address"] if items else None)
        port = int(env["VLESS_PORT"]) if env.get("VLESS_PORT") else (items[0]["port"] if items else None)
        if action == "--status":
            return {"server": {"status": "unknown", "address": address, "port": port, "uptime": None},
                    "clients": {"total": len(items), "active": None}, "traffic": {"today": None, "total": None}}
        summaries = [{k: v for k, v in item.items() if k not in {"config", "connectionString"}} for item in items]
        return {"clients": summaries, "total": len(items), "serverInfo": {"address": address, "port": port, "version": None}}
    name = opts["--name"]
    source = path_for(name)
    if action == "--create-client":
        if source.exists():
            fail("Profile already exists: " + name, "CONFLICT")
        env = environment()
        data = new_profile(env)
    else:
        data = load(name)
        if action == "--get-client":
            return client(name, data)
        if action == "--delete-client":
            source.unlink()
            return {"success": True}
        env = {}  # Updates/copies do not depend on current server secrets/env.
    target_name = opts.get("--new-name", name)
    target = path_for(target_name)
    if (target != source or action == "--copy-client") and target.exists():
        fail("Profile already exists: " + target_name, "CONFLICT")
    data = copy.deepcopy(data)
    s = data["streamSettings"]
    s["network"] = opts.get("--transport", s["network"])
    if s["network"] == "xhttp":
        s.setdefault("xhttpSettings", {"path": env.get("XHTTP_PATH", "/xhttp"), "mode": env.get("XHTTP_MODE", "auto")})
        if env.get("XHTTP_HOST"):
            s["xhttpSettings"]["host"] = env["XHTTP_HOST"]
    else:
        s.pop("xhttpSettings", None)
    user = data["users"][0]
    if "--flow" in opts:
        user["flow"] = opts["--flow"]
    elif s["network"] == "xhttp":
        user["flow"] = ""
    if user.get("flow", "") not in {"", "xtls-rprx-vision"}:
        fail("Flow must be empty or xtls-rprx-vision")
    if s["network"] == "xhttp" and user.get("flow"):
        fail("XHTTP requires empty flow")
    metadata = data.setdefault("_profile", {})
    if action in {"--create-client", "--copy-client"}:
        metadata["created"] = dt.datetime.now(dt.timezone.utc).isoformat().replace("+00:00", "Z")
    if "--expiry" in opts:
        metadata["expiry"] = opts["--expiry"]
    result = client(target_name, data)
    persist(target, data)
    if action == "--update-client" and target != source:
        source.unlink()
    return {"success": True, "client": result}


try:
    action, opts = arguments()
    os.umask(0o077)
    profiles.mkdir(parents=True, exist_ok=True, mode=0o700)
    # Serialize API writers/readers across processes; atomic replaces keep readers
    # of the original interactive format from seeing partially written JSON.
    lock_fd = os.open(str(profiles / ".api.lock"), os.O_CREAT | os.O_RDWR | os.O_NOFOLLOW, 0o600)
    with os.fdopen(lock_fd, "a") as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)
        result = run(action, opts)
    print(json.dumps(result))
except APIError as exc:
    print(json.dumps({"error": str(exc), "code": exc.code}))
    sys.exit(1)
except Exception as exc:
    print(json.dumps({"error": "Profile operation failed: " + str(exc), "code": "SCRIPT_ERROR"}))
    sys.exit(1)
PYAPI
fi

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
