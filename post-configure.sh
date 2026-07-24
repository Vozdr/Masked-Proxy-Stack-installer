#!/usr/bin/env bash
set -Eeuo pipefail

DATA_DIR="${DATA_DIR:-/data}"
MODE="compose"
BUILD="no"
LE_STAGING="no"

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
  LE_STAGING="$(env_get LE_STAGING)"
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
  LE_STAGING="${LE_STAGING:-no}"
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
  local staging_args=()
  if [ -f "$DATA_DIR/certs/live/$domain/fullchain.pem" ]; then
    printf 'Certificate already exists for %s\n' "$domain"
    return
  fi
  if [ "$LE_STAGING" = "yes" ]; then
    staging_args=(--staging)
  fi
  log "Issuing certificate for $domain"
  docker run --rm \
    -v "$DATA_DIR/certs:/etc/letsencrypt" \
    -v "$DATA_DIR/certbot/www:/var/www/certbot" \
    certbot/certbot:latest certonly \
      "${staging_args[@]}" \
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
    log "Starting base stack services"
    if [ "$BUILD" = "yes" ]; then
      compose up -d --build fake-site telemt 3x-ui
    else
      compose up -d fake-site telemt 3x-ui
    fi
    wait_container_running telemt 90 || die "telemt did not start."
    wait_container_running 3xui_app 90 || die "3xui_app did not start."

    log "Starting TeleMT Admin after TeleMT is running"
    compose up -d telemt-admin
    wait_container_running masked-telemt-admin 90 || die "masked-telemt-admin did not start."

    log "Starting gateway and helper services"
    compose up -d fake-gate panel-gate cert-renewer edge
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
  wait_container_running 3xui_app 90 || die "3xui_app did not start."
  local keys private_key public_key
  keys="$(docker exec 3xui_app /app/bin/xray-linux-amd64 x25519)"
  private_key="$(printf '%s\n' "$keys" | awk -F': ' '/PrivateKey/ {print $2; exit}')"
  public_key="$(printf '%s\n' "$keys" | awk -F': ' '/Password \(PublicKey\)/ {print $2; exit}')"
  [ -n "$private_key" ] || die "Failed to generate Reality private key."
  [ -n "$public_key" ] || die "Failed to generate Reality public key."
  docker stop 3xui_app >/dev/null
  if ! python3 - "$DATA_DIR/3x-ui/db/x-ui.db" "$XUI_DOMAIN" "$private_key" "$public_key" "$DOCS_DIR/README.txt" <<'PY'
import json
import secrets
import sys
import time
import sqlite3

db_path, domain, private_key, public_key, readme_path = sys.argv[1:6]
now_ms = int(time.time() * 1000)
short_ids = [secrets.token_hex(n) for n in (1, 2, 3, 4, 6, 8)]
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
        "security": "reality",
        "tcpSettings": {"acceptProxyProtocol": False, "header": {"type": "none"}},
        "realitySettings": {
            "show": False,
            "xver": 0,
            "target": "www.nvidia.com:443",
            "serverNames": ["www.nvidia.com"],
            "privateKey": private_key,
            "shortIds": short_ids,
            "minClientVer": "",
            "maxClientVer": "",
            "maxTimediff": 0,
            "mldsa65Seed": "",
            "settings": {
                "publicKey": public_key,
                "fingerprint": "chrome",
                "serverName": "",
                "spiderX": "/",
                "mldsa65Verify": ""
            },
            "limitFallbackUpload": {"afterBytes": 0, "bytesPerSec": 0, "burstBytesPerSec": 0},
            "limitFallbackDownload": {"afterBytes": 0, "bytesPerSec": 0, "burstBytesPerSec": 0}
        }
    }, separators=(",", ":")),
    "sniffing": json.dumps({"enabled": True, "destOverride": ["http", "tls", "quic"], "metadataOnly": False, "routeOnly": False}, separators=(",", ":")),
    "tag": "in-443-tcp",
    "shareAddrStrategy": "custom",
    "shareAddr": domain,
}

con = sqlite3.connect(db_path)
cur = con.cursor()
columns = [row[1] for row in cur.execute("pragma table_info(inbounds)")]
if not columns:
    raise RuntimeError("3x-ui inbounds table not found")

user_row = cur.execute("select id from users order by id limit 1").fetchone()
user_id = user_row[0] if user_row else 1

values = {
    "user_id": user_id,
    "up": 0,
    "down": 0,
    "total": 0,
    "remark": payload["remark"],
    "sub_sort_index": 1,
    "enable": 1,
    "expiry_time": 0,
    "traffic_reset": "never",
    "last_traffic_reset_time": now_ms,
    "listen": payload["listen"],
    "port": payload["port"],
    "protocol": payload["protocol"],
    "settings": payload["settings"],
    "stream_settings": payload["streamSettings"],
    "tag": payload["tag"],
    "sniffing": payload["sniffing"],
    "node_id": None,
    "share_addr_strategy": payload["shareAddrStrategy"],
    "share_addr": payload["shareAddr"],
    "origin_node_guid": "",
}

existing = cur.execute("select id from inbounds where remark=?", (payload["remark"],)).fetchone()
if existing:
    inbound_id = existing[0]
    update_columns = [col for col in columns if col in values]
    assignments = ", ".join(f"{col}=?" for col in update_columns)
    cur.execute(
        f"update inbounds set {assignments} where id=?",
        [values[col] for col in update_columns] + [inbound_id],
    )
    print(f"Updated existing inbound id={inbound_id}")
else:
    insert_columns = [col for col in columns if col != "id" and col in values]
    placeholders = ", ".join("?" for _ in insert_columns)
    cur.execute(
        f"insert into inbounds ({', '.join(insert_columns)}) values ({placeholders})",
        [values[col] for col in insert_columns],
    )
    print(f"Created inbound id={cur.lastrowid}")

con.commit()
print("Reality target=www.nvidia.com:443")
print("Reality serverName=www.nvidia.com")
print(f"Reality publicKey={public_key}")
print("Reality shortIds=" + ",".join(short_ids))
with open(readme_path, "a", encoding="utf-8") as readme:
    readme.write("\n3x-ui VLESS Reality:\n")
    readme.write(f"  Address:      {domain}\n")
    readme.write("  Port:         443\n")
    readme.write("  Security:     reality\n")
    readme.write("  ServerName:   www.nvidia.com\n")
    readme.write("  Target:       www.nvidia.com:443\n")
    readme.write("  Fingerprint:  chrome\n")
    readme.write(f"  Public key:   {public_key}\n")
    readme.write(f"  Short IDs:    {', '.join(short_ids)}\n")
    readme.write("  Flow:         xtls-rprx-vision\n")
    readme.write("\n3x-ui VLESS Reality:\n")
    readme.write(f"  Адрес:        {domain}\n")
    readme.write("  Порт:         443\n")
    readme.write("  Security:     reality\n")
    readme.write("  ServerName:   www.nvidia.com\n")
    readme.write("  Цель:         www.nvidia.com:443\n")
    readme.write("  Fingerprint:  chrome\n")
    readme.write(f"  Public key:   {public_key}\n")
    readme.write(f"  Short IDs:    {', '.join(short_ids)}\n")
    readme.write("  Flow:         xtls-rprx-vision\n")
PY
  then
    docker start 3xui_app >/dev/null 2>&1 || true
    die "Failed to create 3x-ui inbound in sqlite database."
  fi
  docker start 3xui_app >/dev/null
  wait_container_running 3xui_app 90 || die "3xui_app did not restart after inbound creation."
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
