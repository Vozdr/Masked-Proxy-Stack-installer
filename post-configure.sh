#!/usr/bin/env bash
set -Eeuo pipefail

DATA_DIR="${DATA_DIR:-/data}"
MODE="compose"
BUILD="no"

die() {
  printf 'ERROR: %s\n' "$*" >&2
  exit 1
}

log() {
  printf '\n== %s ==\n' "$*"
}

usage() {
  cat <<'EOF'
Usage:
  sudo ./post-configure.sh [options]

Options:
  --dir PATH       Install directory. Default: /data
  --mode MODE      compose or portainer. Default: compose
  --build          Build local services when using compose mode.
  -h, --help       Show this help.
EOF
}

option_value() {
  local option="$1"
  local value="${2:-}"
  [ -n "$value" ] || die "Option $option requires a value."
  case "$value" in
    --*) die "Option $option requires a value." ;;
  esac
  printf '%s' "$value"
}

parse_args() {
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --dir)
        DATA_DIR="$(option_value "$1" "${2:-}")"
        shift 2
        ;;
      --mode)
        MODE="$(option_value "$1" "${2:-}")"
        shift 2
        ;;
      --build)
        BUILD="yes"
        shift
        ;;
      -h|--help)
        usage
        exit 0
        ;;
      *)
        die "Unknown option: $1"
        ;;
    esac
  done
}

need_root() {
  if [ "$(id -u)" -ne 0 ]; then
    die "Run as root or with sudo."
  fi
}

env_get() {
  local key="$1"
  sed -n "s/^${key}=//p" "$ENV_FILE" | tail -n 1
}

load_env() {
  DATA_DIR="${DATA_DIR%/}"
  COMPOSE_DIR="$DATA_DIR/compose"
  DOCS_DIR="$DATA_DIR/docs"
  ENV_FILE="$COMPOSE_DIR/.env"
  [ -f "$ENV_FILE" ] || die "Missing env file: $ENV_FILE"

  BASE_DOMAIN="$(env_get BASE_DOMAIN)"
  CONTROL_DOMAIN="$(env_get CONTROL_DOMAIN)"
  CONTROL_PREFIX="$(env_get CONTROL_PREFIX)"
  XUI_DOMAIN="$(env_get XUI_DOMAIN)"
  TELEMT_DOMAIN="$(env_get TELEMT_DOMAIN)"
  LE_EMAIL="$(env_get LE_EMAIL)"
  ADMIN_USER="$(env_get ADMIN_USER)"
  ADMIN_PASS="$(env_get ADMIN_PASS)"
  SECRET_PATH="$(env_get SECRET_PATH)"

  [ -n "$BASE_DOMAIN" ] || die "BASE_DOMAIN is empty in $ENV_FILE"
  CONTROL_DOMAIN="${CONTROL_DOMAIN:-$BASE_DOMAIN}"
  if [ -z "$CONTROL_PREFIX" ] && [ -n "$SECRET_PATH" ]; then
    CONTROL_PREFIX="/$SECRET_PATH"
  fi
  [ -n "$XUI_DOMAIN" ] || die "XUI_DOMAIN is empty in $ENV_FILE"
  [ -n "$TELEMT_DOMAIN" ] || die "TELEMT_DOMAIN is empty in $ENV_FILE"
  [ -n "$LE_EMAIL" ] || die "LE_EMAIL is empty in $ENV_FILE"
  [ -n "$ADMIN_USER" ] || die "ADMIN_USER is empty in $ENV_FILE"
  [ -n "$ADMIN_PASS" ] || die "ADMIN_PASS is empty in $ENV_FILE"
}

detect_compose() {
  if docker compose version >/dev/null 2>&1; then
    COMPOSE_CMD="docker compose"
    return
  fi
  if command -v docker-compose >/dev/null 2>&1; then
    COMPOSE_CMD="docker-compose"
    return
  fi
  die "Docker Compose is not available."
}

compose() {
  # shellcheck disable=SC2086
  $COMPOSE_CMD -f "$COMPOSE_DIR/docker-compose.yml" "$@"
}

wait_container_running() {
  local container="$1"
  local tries="${2:-60}"
  local i state
  for i in $(seq 1 "$tries"); do
    state="$(docker inspect -f '{{.State.Running}}' "$container" 2>/dev/null || true)"
    if [ "$state" = "true" ]; then
      return 0
    fi
    sleep 2
  done
  return 1
}

start_edge_for_acme() {
  if [ "$MODE" = "compose" ]; then
    log "Starting edge for ACME HTTP challenge"
    compose up -d edge
  else
    log "Waiting for Portainer stack edge container"
    wait_container_running masked-edge 90 || die "masked-edge did not start."
  fi
}

issue_cert() {
  local domain="$1"
  if [ -f "$DATA_DIR/certs/live/$domain/fullchain.pem" ]; then
    printf 'Certificate already exists for %s\n' "$domain"
    return
  fi
  log "Issuing certificate for $domain"
  docker run --rm \
    -v "$DATA_DIR/certs:/etc/letsencrypt" \
    -v "$DATA_DIR/certbot/www:/var/www/certbot" \
    certbot/certbot:latest certonly \
      --webroot \
      -w /var/www/certbot \
      --non-interactive \
      --agree-tos \
      --email "$LE_EMAIL" \
      -d "$domain"
}

issue_certs() {
  issue_cert "$BASE_DOMAIN"
  if [ "$CONTROL_DOMAIN" != "$BASE_DOMAIN" ]; then
    issue_cert "$CONTROL_DOMAIN"
  fi
  issue_cert "$XUI_DOMAIN"
  issue_cert "$TELEMT_DOMAIN"
}

start_or_restart_stack() {
  if [ "$MODE" = "compose" ]; then
    log "Starting full stack"
    if [ "$BUILD" = "yes" ]; then
      compose up -d --build
    else
      compose up -d
    fi
  else
    log "Restarting containers that need certificates"
    docker restart masked-panel-gate >/dev/null 2>&1 || true
    docker restart masked-fake-gate >/dev/null 2>&1 || true
    docker restart 3xui_app >/dev/null 2>&1 || true
    docker restart telemt >/dev/null 2>&1 || true
  fi
}

set_3xui_credentials() {
  log "Setting 3x-ui credentials"
  wait_container_running 3xui_app 90 || die "3xui_app did not start."
  docker exec 3xui_app /app/x-ui setting -username "$ADMIN_USER" -password "$ADMIN_PASS" -webBasePath "$CONTROL_PREFIX/3x-ui/" >/dev/null 2>&1 || true
  docker restart 3xui_app >/dev/null
}

create_3xui_inbound() {
  log "Creating 3x-ui VLESS inbound without clients"
  sleep 8
  python3 - "$ADMIN_USER" "$ADMIN_PASS" "$CONTROL_PREFIX" "$XUI_DOMAIN" <<'PY'
import json
import sys
import time
import urllib.parse
import urllib.request

user, password, control_prefix, domain = sys.argv[1:5]
panel_base_path = control_prefix.rstrip("/") + "/3x-ui"
base = "http://127.0.0.1:2053"
opener = urllib.request.build_opener(urllib.request.HTTPCookieProcessor())

def request(path, data=None):
    body = None
    headers = {}
    if data is not None:
        body = urllib.parse.urlencode(data).encode()
        headers["Content-Type"] = "application/x-www-form-urlencoded"
    req = urllib.request.Request(base + path, data=body, headers=headers)
    return opener.open(req, timeout=10).read()

for _ in range(30):
    try:
        request(panel_base_path + "/")
        break
    except Exception:
        time.sleep(2)

request(panel_base_path + "/login", {"username": user, "password": password})

payload = {
    "remark": "apiv1-vless-443",
    "enable": True,
    "listen": "0.0.0.0",
    "port": 443,
    "protocol": "vless",
    "settings": json.dumps({
        "clients": [],
        "decryption": "none",
        "encryption": "none",
        "fallbacks": [{"dest": "panel-gate:8081"}]
    }, separators=(",", ":")),
    "streamSettings": json.dumps({
        "network": "tcp",
        "security": "tls",
        "tcpSettings": {"acceptProxyProtocol": False, "header": {"type": "none"}},
        "tlsSettings": {
            "serverName": domain,
            "minVersion": "1.2",
            "maxVersion": "1.3",
            "cipherSuites": "",
            "rejectUnknownSni": False,
            "certificates": [{
                "certificateFile": f"/root/cert/live/{domain}/fullchain.pem",
                "keyFile": f"/root/cert/live/{domain}/privkey.pem",
                "ocspStapling": 3600
            }],
            "alpn": ["http/1.1"]
        }
    }, separators=(",", ":")),
    "sniffing": json.dumps({"enabled": True, "destOverride": ["http", "tls", "quic"], "metadataOnly": False, "routeOnly": False}, separators=(",", ":")),
    "tag": "in-443-tcp",
    "shareAddrStrategy": "custom",
    "shareAddr": domain,
}

try:
    req = urllib.request.Request(
        base + panel_base_path + "/panel/api/inbounds/add",
        data=json.dumps(payload).encode(),
        headers={"Content-Type": "application/json"},
    )
    print(opener.open(req, timeout=20).read().decode())
except Exception as exc:
    print(f"WARNING: failed to create inbound via 3x-ui API: {exc}", file=sys.stderr)
    sys.exit(0)
PY
}

finish_readme() {
  chmod 600 "$DOCS_DIR/README.txt" 2>/dev/null || true
}

main() {
  parse_args "$@"
  need_root
  case "$MODE" in
    compose|portainer) ;;
    *) die "--mode must be compose or portainer." ;;
  esac
  load_env
  command -v docker >/dev/null 2>&1 || die "Docker is not available."
  command -v curl >/dev/null 2>&1 || die "curl is not available."
  command -v python3 >/dev/null 2>&1 || die "python3 is not available."
  if [ "$MODE" = "compose" ]; then
    detect_compose
  fi

  start_edge_for_acme
  issue_certs
  start_or_restart_stack
  set_3xui_credentials
  create_3xui_inbound
  if [ "$MODE" = "compose" ]; then
    compose up -d
  fi
  finish_readme

  log "Post-configuration done"
  printf 'Generated documentation: %s\n' "$DOCS_DIR/README.txt"
  printf '3x-ui panel: https://%s%s/3x-ui/\n' "$CONTROL_DOMAIN" "$CONTROL_PREFIX"
  printf 'TeleMT Admin: https://%s%s/telemt/\n' "$CONTROL_DOMAIN" "$CONTROL_PREFIX"
}

main "$@"
