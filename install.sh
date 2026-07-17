#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DATA_DIR="${DATA_DIR:-/data}"
COMPOSE_DIR="$DATA_DIR/compose"
DOCS_DIR="$DATA_DIR/docs"
SCRIPTS_DIR="$DATA_DIR/scripts"

ADMIN_USER=""
ADMIN_PASS=""
BASE_DOMAIN=""
XUI_SUBDOMAIN=""
TELEMT_SUBDOMAIN=""
XUI_DOMAIN=""
TELEMT_DOMAIN=""
LE_EMAIL=""
SECRET_PATH=""
FAKE_SITE_IMAGE=""
FAKE_SITE_PORT="8080"
SESSION_SECRET=""
TZ_VALUE="UTC"
COMPOSE_CMD=""
SILENT="no"
PORTAINER="no"
XUI_DOMAIN_INPUT=""
TELEMT_DOMAIN_INPUT=""

die() {
  printf 'ERROR: %s\n' "$*" >&2
  exit 1
}

log() {
  printf '\n== %s ==\n' "$*"
}

set_data_dirs() {
  DATA_DIR="${DATA_DIR%/}"
  [ -n "$DATA_DIR" ] || DATA_DIR="/data"
  COMPOSE_DIR="$DATA_DIR/compose"
  DOCS_DIR="$DATA_DIR/docs"
  SCRIPTS_DIR="$DATA_DIR/scripts"
}

need_root() {
  if [ "$(id -u)" -ne 0 ]; then
    die "Run as root or with sudo."
  fi
}

prompt() {
  local var_name="$1"
  local label="$2"
  local default="${3:-}"
  local value
  if [ "$SILENT" = "yes" ]; then
    printf -v "$var_name" '%s' "$default"
    return
  fi
  if [ -n "$default" ]; then
    read -r -p "$label [$default]: " value
    value="${value:-$default}"
  else
    read -r -p "$label: " value
  fi
  printf -v "$var_name" '%s' "$value"
}

prompt_secret() {
  local var_name="$1"
  local label="$2"
  local default="${3:-}"
  local value
  if [ "$SILENT" = "yes" ]; then
    printf -v "$var_name" '%s' "$default"
    return
  fi
  if [ -n "$default" ]; then
    read -r -s -p "$label [provided, Enter = keep]: " value
    value="${value:-$default}"
  else
    read -r -s -p "$label (empty = generate): " value
  fi
  printf '\n'
  printf -v "$var_name" '%s' "$value"
}

random_hex() {
  local bytes="${1:-16}"
  openssl rand -hex "$bytes"
}

random_token() {
  random_hex 12
}

normalize_domain() {
  printf '%s' "$1" | sed -E 's#^https?://##; s#/.*$##; s#:$##'
}

usage() {
  cat <<'EOF'
Usage:
  sudo ./install.sh [options]

Options:
  --silent                         Run non-interactively using defaults and provided options.
  --dir PATH                       Install directory. Default: /data
  --base-domain DOMAIN             Base fake-site domain, for example site.com. Required in --silent mode.
  --3x-domain DOMAIN_OR_SUBDOMAIN  3x-ui/VLESS domain or subdomain. Default: apiv1.<base-domain>
  --telemt-domain DOMAIN_OR_SUBDOMAIN
                                   TeleMT domain or subdomain. Default: apiv2.<base-domain>
  --le-email EMAIL                 Let's Encrypt email. Default: admin@<base-domain>
  --admin-login USER               Admin username. Default: generated admin_xxxxxxxx
  --admin-pass PASS                Admin password. Default: generated random password
  --secret-path PATH               Hidden control URL path. Default: generated random path
  --fake-site-image IMAGE          Custom fake-site Docker image. Default: built-in API stub
  --fake-site-port PORT            Internal HTTP port for custom fake-site image. Default: 8080
  --tz TIMEZONE                    IANA timezone, for example Europe/Moscow. Default: UTC
  --portainer                      Deploy the generated stack through Portainer CE.
  -h, --help                       Show this help.

When an option is provided without --silent, the installer still asks the
question, but uses the provided value as the default. Press Enter to accept it.
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
      --silent)
        SILENT="yes"
        shift
        ;;
      --dir)
        DATA_DIR="$(option_value "$1" "${2:-}")"
        shift 2
        ;;
      --base-domain)
        BASE_DOMAIN="$(option_value "$1" "${2:-}")"
        shift 2
        ;;
      --3x-domain)
        XUI_DOMAIN_INPUT="$(option_value "$1" "${2:-}")"
        shift 2
        ;;
      --telemt-domain)
        TELEMT_DOMAIN_INPUT="$(option_value "$1" "${2:-}")"
        shift 2
        ;;
      --le-email)
        LE_EMAIL="$(option_value "$1" "${2:-}")"
        shift 2
        ;;
      --admin-login)
        ADMIN_USER="$(option_value "$1" "${2:-}")"
        shift 2
        ;;
      --admin-pass)
        ADMIN_PASS="$(option_value "$1" "${2:-}")"
        shift 2
        ;;
      --secret-path)
        SECRET_PATH="$(option_value "$1" "${2:-}")"
        shift 2
        ;;
      --fake-site-image)
        FAKE_SITE_IMAGE="$(option_value "$1" "${2:-}")"
        shift 2
        ;;
      --fake-site-port)
        FAKE_SITE_PORT="$(option_value "$1" "${2:-}")"
        shift 2
        ;;
      --tz)
        TZ_VALUE="$(option_value "$1" "${2:-}")"
        shift 2
        ;;
      --portainer)
        PORTAINER="yes"
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

domain_from_input() {
  local value="$1"
  local default_subdomain="$2"
  value="$(normalize_domain "${value:-}")"
  if [ -z "$value" ]; then
    printf '%s.%s' "$default_subdomain" "$BASE_DOMAIN"
  elif printf '%s' "$value" | grep -q '\.'; then
    printf '%s' "$value"
  else
    printf '%s.%s' "$value" "$BASE_DOMAIN"
  fi
}

subdomain_from_domain() {
  local domain="$1"
  local fallback="$2"
  local suffix=".$BASE_DOMAIN"
  if [ "$domain" = "$BASE_DOMAIN" ]; then
    printf '%s' "$fallback"
  elif [ "${domain%"$suffix"}" != "$domain" ]; then
    printf '%s' "${domain%"$suffix"}"
  else
    printf '%s' "$domain"
  fi
}

render_template() {
  local src="$1"
  local dst="$2"
  BASE_DOMAIN="$BASE_DOMAIN" \
  DATA_DIR="$DATA_DIR" \
  XUI_SUBDOMAIN="$XUI_SUBDOMAIN" \
  TELEMT_SUBDOMAIN="$TELEMT_SUBDOMAIN" \
  XUI_DOMAIN="$XUI_DOMAIN" \
  TELEMT_DOMAIN="$TELEMT_DOMAIN" \
  ADMIN_USER="$ADMIN_USER" \
  ADMIN_PASS="$ADMIN_PASS" \
  SECRET_PATH="$SECRET_PATH" \
  SESSION_SECRET="$SESSION_SECRET" \
  FAKE_SITE_PORT="$FAKE_SITE_PORT" \
  FAKE_SITE_IMAGE="${FAKE_SITE_IMAGE:-built-in-api-stub}" \
  TZ_VALUE="$TZ_VALUE" \
  GENERATED_AT="$(date -Is)" \
  COMPOSE_CMD="$COMPOSE_CMD" \
  python3 - "$src" "$dst" <<'PY'
import os
import sys

src, dst = sys.argv[1], sys.argv[2]
values = {
    "__BASE_DOMAIN__": os.environ["BASE_DOMAIN"],
    "__DATA_DIR__": os.environ["DATA_DIR"],
    "__XUI_SUBDOMAIN__": os.environ["XUI_SUBDOMAIN"],
    "__TELEMT_SUBDOMAIN__": os.environ["TELEMT_SUBDOMAIN"],
    "__XUI_DOMAIN__": os.environ["XUI_DOMAIN"],
    "__TELEMT_DOMAIN__": os.environ["TELEMT_DOMAIN"],
    "__ADMIN_USER__": os.environ["ADMIN_USER"],
    "__ADMIN_PASS__": os.environ["ADMIN_PASS"],
    "__SECRET_PATH__": os.environ["SECRET_PATH"],
    "__SESSION_SECRET__": os.environ["SESSION_SECRET"],
    "__FAKE_SITE_PORT__": os.environ["FAKE_SITE_PORT"],
    "__FAKE_SITE_IMAGE__": os.environ["FAKE_SITE_IMAGE"],
    "__TZ__": os.environ["TZ_VALUE"],
    "__GENERATED_AT__": os.environ["GENERATED_AT"],
    "__COMPOSE_CMD__": os.environ["COMPOSE_CMD"],
}
text = open(src, encoding="utf-8").read()
for key, value in values.items():
    text = text.replace(key, value)
open(dst, "w", encoding="utf-8").write(text)
PY
}

require_command() {
  command -v "$1" >/dev/null 2>&1 || die "Missing required command: $1"
}

add_package_if_command_missing() {
  local command_name="$1"
  local package_name="$2"
  local packages_var="$3"
  if ! command -v "$command_name" >/dev/null 2>&1; then
    eval "$packages_var=\"\${$packages_var} $package_name\""
  fi
}

apt_package_exists() {
  apt-cache show "$1" >/dev/null 2>&1
}

install_missing_prerequisites() {
  log "Checking required packages"
  local packages=""
  local compose_missing="no"

  add_package_if_command_missing curl curl packages
  add_package_if_command_missing openssl openssl packages
  add_package_if_command_missing python3 python3 packages
  add_package_if_command_missing sed sed packages
  add_package_if_command_missing ss iproute2 packages
  add_package_if_command_missing docker docker.io packages

  if ! docker compose version >/dev/null 2>&1 && ! command -v docker-compose >/dev/null 2>&1; then
    compose_missing="yes"
  fi

  if [ -z "$(printf '%s' "$packages" | xargs)" ] && [ "$compose_missing" = "no" ]; then
    printf 'All required packages look present.\n'
    return
  fi

  command -v apt-get >/dev/null 2>&1 || die "Missing packages and apt-get is not available."

  apt-get update

  if [ "$compose_missing" = "yes" ]; then
    if apt_package_exists docker-compose-plugin; then
      packages="$packages docker-compose-plugin"
    elif apt_package_exists docker-compose; then
      packages="$packages docker-compose"
    else
      printf 'WARNING: no docker-compose-plugin/docker-compose package found in apt repositories.\n'
    fi
  fi

  packages="$(printf '%s\n' $packages | awk '!seen[$0]++' | xargs)"
  if [ -n "$packages" ]; then
    # shellcheck disable=SC2086
    apt-get install -y $packages
  fi

  if command -v systemctl >/dev/null 2>&1; then
    systemctl enable --now docker >/dev/null 2>&1 || true
  fi
}

install_docker_if_needed() {
  if command -v docker >/dev/null 2>&1; then
    if command -v systemctl >/dev/null 2>&1; then
      systemctl enable --now docker >/dev/null 2>&1 || true
    fi
    return
  fi
  die "Docker is still not installed after prerequisite installation."
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

collect_install_dir() {
  prompt DATA_DIR "Install directory" "$DATA_DIR"
  DATA_DIR="${DATA_DIR:-/data}"
  set_data_dirs
}

check_ports() {
  log "Checking public ports"
  if ss -ltn '( sport = :80 or sport = :443 )' 2>/dev/null | grep -q LISTEN; then
    printf 'WARNING: Something is already listening on port 80 or 443.\n'
    printf 'Stop the conflicting service before continuing if this is not the current stack.\n'
    if [ "$SILENT" = "yes" ]; then
      die "Ports 80/443 are busy and --silent mode cannot ask for confirmation."
    fi
    read -r -p "Continue anyway? [y/N]: " answer
    case "$answer" in
      y|Y|yes|YES) ;;
      *) die "Stopped by user." ;;
    esac
  fi
}

check_dns() {
  log "Checking DNS records"
  local ip
  ip="$(curl -4fsS https://api.ipify.org 2>/dev/null || true)"
  if [ -z "$ip" ]; then
    printf 'WARNING: Cannot detect public IPv4 address, skipping DNS comparison.\n'
    return
  fi

  local domain resolved
  for domain in "$BASE_DOMAIN" "$XUI_DOMAIN" "$TELEMT_DOMAIN"; do
    resolved="$(getent ahostsv4 "$domain" 2>/dev/null | awk '{print $1; exit}' || true)"
    if [ -z "$resolved" ]; then
      printf 'WARNING: %s does not resolve from this server.\n' "$domain"
    elif [ "$resolved" != "$ip" ]; then
      printf 'WARNING: %s resolves to %s, this server public IPv4 is %s.\n' "$domain" "$resolved" "$ip"
    else
      printf 'OK: %s -> %s\n' "$domain" "$resolved"
    fi
  done
}

collect_inputs() {
  log "Installer questions"
  prompt BASE_DOMAIN "Base fake-site domain, for example site.com" "$BASE_DOMAIN"
  BASE_DOMAIN="$(normalize_domain "$BASE_DOMAIN")"
  [ -n "$BASE_DOMAIN" ] || die "Base domain is required."

  prompt XUI_DOMAIN_INPUT "3x-ui domain or subdomain" "${XUI_DOMAIN_INPUT:-apiv1}"
  prompt TELEMT_DOMAIN_INPUT "TeleMT domain or subdomain" "${TELEMT_DOMAIN_INPUT:-apiv2}"
  XUI_DOMAIN="$(domain_from_input "$XUI_DOMAIN_INPUT" "apiv1")"
  TELEMT_DOMAIN="$(domain_from_input "$TELEMT_DOMAIN_INPUT" "apiv2")"
  XUI_SUBDOMAIN="$(subdomain_from_domain "$XUI_DOMAIN" "apiv1")"
  TELEMT_SUBDOMAIN="$(subdomain_from_domain "$TELEMT_DOMAIN" "apiv2")"

  prompt LE_EMAIL "Let's Encrypt email" "${LE_EMAIL:-admin@$BASE_DOMAIN}"
  LE_EMAIL="${LE_EMAIL:-admin@$BASE_DOMAIN}"

  prompt ADMIN_USER "Admin username, empty = generate" "$ADMIN_USER"
  if [ -z "$ADMIN_USER" ]; then
    ADMIN_USER="admin_$(random_hex 4)"
  fi
  prompt_secret ADMIN_PASS "Admin password" "$ADMIN_PASS"
  if [ -z "$ADMIN_PASS" ]; then
    ADMIN_PASS="$(random_hex 12)"
  fi

  prompt SECRET_PATH "Hidden URL path, empty = generate" "$SECRET_PATH"
  if [ -z "$SECRET_PATH" ]; then
    SECRET_PATH="$(random_hex 8)"
  fi
  SECRET_PATH="$(printf '%s' "$SECRET_PATH" | sed -E 's#^/+##; s#/+$##')"

  prompt FAKE_SITE_IMAGE "Custom fake-site Docker image, empty = built-in API stub" "$FAKE_SITE_IMAGE"
  if [ -n "$FAKE_SITE_IMAGE" ]; then
    prompt FAKE_SITE_PORT "Internal HTTP port of custom fake-site container" "${FAKE_SITE_PORT:-8080}"
  else
    FAKE_SITE_PORT="8080"
  fi

  prompt TZ_VALUE "IANA timezone, for example Europe/Moscow" "${TZ_VALUE:-UTC}"
  SESSION_SECRET="$(random_hex 24)"

  if [ "$PORTAINER" = "yes" ]; then
    printf 'Portainer mode enabled. The stack will be deployed through Portainer CE.\n'
  fi
}

write_env() {
  cat > "$COMPOSE_DIR/.env" <<EOF
DATA_DIR=$DATA_DIR
BASE_DOMAIN=$BASE_DOMAIN
XUI_SUBDOMAIN=$XUI_SUBDOMAIN
TELEMT_SUBDOMAIN=$TELEMT_SUBDOMAIN
XUI_DOMAIN=$XUI_DOMAIN
TELEMT_DOMAIN=$TELEMT_DOMAIN
LE_EMAIL=$LE_EMAIL
ADMIN_USER=$ADMIN_USER
ADMIN_PASS=$ADMIN_PASS
SECRET_PATH=$SECRET_PATH
FAKE_SITE_IMAGE=${FAKE_SITE_IMAGE:-}
FAKE_SITE_PORT=$FAKE_SITE_PORT
TZ=$TZ_VALUE
COMPOSE_CMD=$COMPOSE_CMD
EOF
  chmod 600 "$COMPOSE_DIR/.env"
}

make_dirs() {
  log "Creating install layout at $DATA_DIR"
  mkdir -p \
    "$COMPOSE_DIR" \
    "$DOCS_DIR" \
    "$DATA_DIR/edge" \
    "$SCRIPTS_DIR" \
    "$DATA_DIR/fake-gate" \
    "$DATA_DIR/fake-site/default" \
    "$DATA_DIR/panel-gate" \
    "$DATA_DIR/3x-ui/db" \
    "$DATA_DIR/telemt/config" \
    "$DATA_DIR/telemt/runtime" \
    "$DATA_DIR/telemt-admin/backups" \
    "$DATA_DIR/certs" \
    "$DATA_DIR/certbot/www"
}

copy_default_fake_site() {
  cp "$SCRIPT_DIR/fake-site/default/Dockerfile" "$DATA_DIR/fake-site/default/Dockerfile"
  cp "$SCRIPT_DIR/fake-site/default/server.py" "$DATA_DIR/fake-site/default/server.py"
}

copy_helper_scripts() {
  cp "$SCRIPT_DIR/post-configure.sh" "$SCRIPTS_DIR/post-configure.sh"
  cp "$SCRIPT_DIR/deploy-portainer.sh" "$SCRIPTS_DIR/deploy-portainer.sh"
  chmod 750 "$SCRIPTS_DIR/post-configure.sh" "$SCRIPTS_DIR/deploy-portainer.sh"
}

fake_site_service_block() {
  if [ -n "$FAKE_SITE_IMAGE" ]; then
    cat <<EOF
  fake-site:
    image: $FAKE_SITE_IMAGE
    container_name: masked-fake-site
    restart: unless-stopped
    environment:
      TZ: "$TZ_VALUE"
    expose:
      - "$FAKE_SITE_PORT"
    networks:
      - masked_net
EOF
  else
    cat <<EOF
  fake-site:
    build:
      context: $DATA_DIR/fake-site/default
    container_name: masked-fake-site
    restart: unless-stopped
    environment:
      TZ: "$TZ_VALUE"
    expose:
      - "8080"
    networks:
      - masked_net
EOF
  fi
}

render_files() {
  log "Rendering config files"
  render_template "$SCRIPT_DIR/templates/edge-nginx.conf.tpl" "$DATA_DIR/edge/nginx.conf"
  render_template "$SCRIPT_DIR/templates/fake-gate-nginx.conf.tpl" "$DATA_DIR/fake-gate/nginx.conf"
  render_template "$SCRIPT_DIR/templates/panel-gate-nginx.conf.tpl" "$DATA_DIR/panel-gate/nginx.conf"
  render_template "$SCRIPT_DIR/templates/telemt-config.toml.tpl" "$DATA_DIR/telemt/config/config.toml"

  local compose_tmp
  compose_tmp="$(mktemp)"
  render_template "$SCRIPT_DIR/templates/docker-compose.yml.tpl" "$compose_tmp"
  sed "/__FAKE_SITE_SERVICE__/r /dev/stdin" "$compose_tmp" < <(fake_site_service_block) | sed '/__FAKE_SITE_SERVICE__/d' > "$COMPOSE_DIR/docker-compose.yml"
  rm -f "$compose_tmp"

  render_template "$SCRIPT_DIR/templates/README.generated.txt.tpl" "$DOCS_DIR/README.txt"
}

write_htpasswd() {
  log "Writing panel-gate Basic Auth"
  require_command openssl
  local hash
  hash="$(openssl passwd -apr1 "$ADMIN_PASS")"
  printf '%s:%s\n' "$ADMIN_USER" "$hash" > "$DATA_DIR/panel-gate/htpasswd"
  chmod 644 "$DATA_DIR/panel-gate/htpasswd"
}

write_renew_script() {
  log "Writing certificate renewal script"
  cat > "$SCRIPTS_DIR/renew-certs.sh" <<EOF
#!/bin/sh
set -eu

DATA_DIR="\${DATA_DIR:-$DATA_DIR}"

docker run --rm \
  -v "\$DATA_DIR/certs:/etc/letsencrypt" \
  -v "\$DATA_DIR/certbot/www:/var/www/certbot" \
  certbot/certbot:latest renew \
    --webroot \
    -w /var/www/certbot \
    --quiet

# These containers read certificate files directly. Restarting them is the
# simplest reliable way to make renewed certificates active.
docker restart masked-fake-gate >/dev/null 2>&1 || true
docker restart 3xui_app >/dev/null 2>&1 || true
docker restart telemt >/dev/null 2>&1 || true
EOF
  chmod 750 "$SCRIPTS_DIR/renew-certs.sh"
}

run_post_configure() {
  "$SCRIPTS_DIR/post-configure.sh" --dir "$DATA_DIR" --mode compose --build
}

run_portainer_deploy() {
  "$SCRIPTS_DIR/deploy-portainer.sh" --dir "$DATA_DIR" --stack-name masked-proxy
}

main() {
  parse_args "$@"
  need_root
  collect_install_dir
  install_missing_prerequisites
  collect_inputs
  require_command sed
  require_command openssl
  require_command curl
  require_command python3
  install_docker_if_needed
  detect_compose
  check_ports
  check_dns
  make_dirs
  copy_default_fake_site
  copy_helper_scripts
  write_env
  render_files
  write_htpasswd
  write_renew_script

  if [ "$PORTAINER" = "yes" ]; then
    run_portainer_deploy
  else
    run_post_configure
  fi

  log "Done"
  printf 'Generated documentation: %s\n' "$DOCS_DIR/README.txt"
  printf '3x-ui panel: https://%s/%s/\n' "$XUI_DOMAIN" "$SECRET_PATH"
  printf 'TeleMT Admin: https://%s/%s/telemt/\n' "$XUI_DOMAIN" "$SECRET_PATH"
}

main "$@"
