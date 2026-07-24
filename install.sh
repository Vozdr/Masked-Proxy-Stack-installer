#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DATA_DIR="${DATA_DIR:-/data}"
COMPOSE_DIR="$DATA_DIR/compose"
DOCS_DIR="$DATA_DIR/docs"
SCRIPTS_DIR="$DATA_DIR/scripts"
ANSWERS_FILE="$SCRIPT_DIR/.install-answers.env"

ADMIN_USER=""
ADMIN_PASS=""
BASE_DOMAIN=""
CONTROL_DOMAIN=""
CONTROL_PREFIX=""
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
BASE_TLS_UPSTREAM=""
CONTROL_DOMAIN_MAP=""
CONTROL_FALLBACK_BLOCK=""
REINSTALL="no"
BACKUP_BEFORE_REINSTALL="yes"

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
  if command -v openssl >/dev/null 2>&1; then
    openssl rand -hex "$bytes"
  else
    od -An -N "$bytes" -tx1 /dev/urandom | tr -d ' \n'
  fi
}

random_token() {
  random_hex 12
}

normalize_domain() {
  printf '%s' "$1" | sed -E 's#^https?://##; s#/.*$##; s#:$##'
}

normalize_host() {
  printf '%s' "$1" | sed -E 's#^https?://##; s#/.*$##; s#:$##; s#^/+##; s#/+$##'
}

normalize_secret_path() {
  local raw="$1"
  local host=""
  local path=""

  raw="$(printf '%s' "$raw" | sed -E 's#^https?://##; s#\\#/#g')"
  if printf '%s' "$raw" | grep -q '/'; then
    host="${raw%%/*}"
    path="${raw#*/}"
  else
    host="$raw"
    path="$raw"
  fi

  if printf '%s' "$host" | grep -q '\.'; then
    CONTROL_DOMAIN="$(normalize_host "$host")"
    if [ "$raw" = "$host" ]; then
      path=""
    fi
  else
    CONTROL_DOMAIN="$BASE_DOMAIN"
    path="$raw"
  fi

  path="$(printf '%s' "$path" | sed -E 's#^/+##; s#/+$##')"
  case "$path" in
    */3x-ui) path="${path%/3x-ui}" ;;
    */telemt) path="${path%/telemt}" ;;
    */portainer) path="${path%/portainer}" ;;
    3x-ui|telemt|portainer) path="" ;;
  esac
  path="$(printf '%s' "$path" | sed -E 's#^/+##; s#/+$##')"

  SECRET_PATH="$path"
  if [ -n "$SECRET_PATH" ]; then
    CONTROL_PREFIX="/$SECRET_PATH"
  else
    CONTROL_PREFIX=""
  fi
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
  --secret-path PATH               Hidden control path, or control host/path like sub.<base-domain>/path.
                                   Base-domain is optional and stripped when provided. Default: generated random path
  --fake-site-image IMAGE          Custom fake-site Docker image. Default: built-in API stub
  --fake-site-port PORT            Internal HTTP port for custom fake-site image. Default: 8080
  --tz TIMEZONE                    IANA timezone, for example Europe/Moscow. Default: UTC
  --portainer                      Deploy the generated stack through Portainer CE.
  --reinstall                      Allow reinstall when an existing stack is detected. Default: no
  --no-backup                      Do not create backup before reinstall. Default: backup enabled
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
      --reinstall)
        REINSTALL="yes"
        shift
        ;;
      --no-backup)
        BACKUP_BEFORE_REINSTALL="no"
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

shell_escape() {
  printf '%q' "$1"
}

load_saved_answers() {
  if [ -f "$ANSWERS_FILE" ]; then
    # shellcheck disable=SC1090
    . "$ANSWERS_FILE"
    set_data_dirs
  fi
}

write_answer_line() {
  local key="$1"
  local value="$2"
  printf '%s=%s\n' "$key" "$(shell_escape "$value")"
}

save_answers() {
  local tmp
  tmp="$(mktemp)"
  {
    printf '# Saved answers for masked proxy stack installer.\n'
    printf '# This file is reused as defaults on the next install.sh run.\n'
    write_answer_line DATA_DIR "$DATA_DIR"
    write_answer_line BASE_DOMAIN "$BASE_DOMAIN"
    write_answer_line CONTROL_DOMAIN "$CONTROL_DOMAIN"
    write_answer_line CONTROL_PREFIX "$CONTROL_PREFIX"
    write_answer_line XUI_DOMAIN_INPUT "$XUI_DOMAIN_INPUT"
    write_answer_line TELEMT_DOMAIN_INPUT "$TELEMT_DOMAIN_INPUT"
    write_answer_line XUI_DOMAIN "$XUI_DOMAIN"
    write_answer_line TELEMT_DOMAIN "$TELEMT_DOMAIN"
    write_answer_line LE_EMAIL "$LE_EMAIL"
    write_answer_line ADMIN_USER "$ADMIN_USER"
    write_answer_line ADMIN_PASS "$ADMIN_PASS"
    write_answer_line SECRET_PATH "$SECRET_PATH"
    write_answer_line FAKE_SITE_IMAGE "$FAKE_SITE_IMAGE"
    write_answer_line FAKE_SITE_PORT "$FAKE_SITE_PORT"
    write_answer_line TZ_VALUE "$TZ_VALUE"
    write_answer_line PORTAINER "$PORTAINER"
    write_answer_line REINSTALL "$REINSTALL"
    write_answer_line BACKUP_BEFORE_REINSTALL "$BACKUP_BEFORE_REINSTALL"
  } > "$tmp"
  chmod 600 "$tmp"
  mv "$tmp" "$ANSWERS_FILE"
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
  CONTROL_DOMAIN="$CONTROL_DOMAIN" \
  CONTROL_PREFIX="$CONTROL_PREFIX" \
  BASE_TLS_UPSTREAM="$BASE_TLS_UPSTREAM" \
  CONTROL_DOMAIN_MAP="$CONTROL_DOMAIN_MAP" \
  CONTROL_FALLBACK_BLOCK="$CONTROL_FALLBACK_BLOCK" \
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
    "__CONTROL_DOMAIN__": os.environ["CONTROL_DOMAIN"],
    "__CONTROL_PREFIX__": os.environ["CONTROL_PREFIX"],
    "__BASE_TLS_UPSTREAM__": os.environ["BASE_TLS_UPSTREAM"],
    "__CONTROL_DOMAIN_MAP__": os.environ["CONTROL_DOMAIN_MAP"],
    "__CONTROL_FALLBACK_BLOCK__": os.environ["CONTROL_FALLBACK_BLOCK"],
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
  add_package_if_command_missing tar tar packages
  add_package_if_command_missing getent libc-bin packages
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
  case "$DATA_DIR" in
    /|/bin|/boot|/dev|/etc|/home|/lib|/lib64|/proc|/root|/run|/sbin|/sys|/tmp|/usr|/var)
      die "Install directory is too broad or unsafe: $DATA_DIR"
      ;;
  esac
}

prompt_yes_no() {
  local var_name="$1"
  local label="$2"
  local default="${3:-no}"
  local answer
  if [ "$SILENT" = "yes" ]; then
    printf -v "$var_name" '%s' "$default"
    return
  fi
  if [ "$default" = "yes" ]; then
    read -r -p "$label [Y/n]: " answer
    answer="${answer:-yes}"
  else
    read -r -p "$label [y/N]: " answer
    answer="${answer:-no}"
  fi
  case "$answer" in
    y|Y|yes|YES) printf -v "$var_name" 'yes' ;;
    *) printf -v "$var_name" 'no' ;;
  esac
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
    die "Cannot detect public IPv4 address, cannot verify DNS before requesting certificates."
  fi

  local domain resolved
  local failed="no"
  local checked=""
  for domain in "$BASE_DOMAIN" "$CONTROL_DOMAIN" "$XUI_DOMAIN" "$TELEMT_DOMAIN"; do
    case " $checked " in
      *" $domain "*) continue ;;
    esac
    checked="$checked $domain"
    resolved="$(getent ahostsv4 "$domain" 2>/dev/null | awk '{print $1; exit}' || true)"
    if [ -z "$resolved" ]; then
      printf 'ERROR: %s does not resolve from this server.\n' "$domain" >&2
      failed="yes"
    elif [ "$resolved" != "$ip" ]; then
      printf 'ERROR: %s resolves to %s, this server public IPv4 is %s.\n' "$domain" "$resolved" "$ip" >&2
      failed="yes"
    else
      printf 'OK: %s -> %s\n' "$domain" "$resolved"
    fi
  done
  if [ "$failed" = "yes" ]; then
    die "Fix DNS records and run install.sh again. Your answers were saved in $ANSWERS_FILE."
  fi
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

  prompt SECRET_PATH "Hidden control path or control host/path, empty = generate" "$SECRET_PATH"
  if [ -z "$SECRET_PATH" ]; then
    SECRET_PATH="$(random_hex 8)"
  fi
  normalize_secret_path "$SECRET_PATH"
  [ -n "$CONTROL_DOMAIN" ] || CONTROL_DOMAIN="$BASE_DOMAIN"

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

known_container_names() {
  cat <<'EOF'
masked-edge
masked-fake-gate
masked-fake-site
masked-panel-gate
3xui_app
telemt
masked-telemt-admin
masked-cert-renewer
portainer
EOF
}

has_existing_install_files() {
  local path
  for path in \
    "$COMPOSE_DIR/docker-compose.yml" \
    "$COMPOSE_DIR/.env" \
    "$DATA_DIR/edge" \
    "$DATA_DIR/fake-gate" \
    "$DATA_DIR/panel-gate" \
    "$DATA_DIR/3x-ui" \
    "$DATA_DIR/telemt" \
    "$DATA_DIR/telemt-admin" \
    "$DATA_DIR/certs" \
    "$DATA_DIR/certbot"; do
    [ -e "$path" ] && return 0
  done
  return 1
}

has_existing_install_containers() {
  command -v docker >/dev/null 2>&1 || return 1
  local name
  while IFS= read -r name; do
    [ -n "$name" ] || continue
    if docker container inspect "$name" >/dev/null 2>&1; then
      return 0
    fi
  done <<EOF
$(known_container_names)
EOF
  return 1
}

existing_install_detected() {
  has_existing_install_files || has_existing_install_containers
}

show_existing_install_summary() {
  printf 'Existing install data was found for %s.\n' "$DATA_DIR"
  printf '\nFiles/directories:\n'
  local path any="no"
  for path in \
    "$COMPOSE_DIR/docker-compose.yml" \
    "$COMPOSE_DIR/.env" \
    "$DATA_DIR/edge" \
    "$DATA_DIR/fake-gate" \
    "$DATA_DIR/panel-gate" \
    "$DATA_DIR/3x-ui" \
    "$DATA_DIR/telemt" \
    "$DATA_DIR/telemt-admin" \
    "$DATA_DIR/certs" \
    "$DATA_DIR/certbot"; do
    if [ -e "$path" ]; then
      printf '  %s\n' "$path"
      any="yes"
    fi
  done
  [ "$any" = "yes" ] || printf '  none\n'

  printf '\nContainers:\n'
  any="no"
  if command -v docker >/dev/null 2>&1; then
    local name
    while IFS= read -r name; do
      [ -n "$name" ] || continue
      if docker container inspect "$name" >/dev/null 2>&1; then
        printf '  %s\n' "$name"
        any="yes"
      fi
    done <<EOF
$(known_container_names)
EOF
  fi
  [ "$any" = "yes" ] || printf '  none\n'
}

ask_reinstall_if_needed() {
  if existing_install_detected; then
    log "Existing installation check"
    show_existing_install_summary
    if [ "$SILENT" = "yes" ]; then
      [ "$REINSTALL" = "yes" ] || die "Existing install detected. Use --reinstall to allow reinstall in --silent mode."
      return 0
    fi
    prompt_yes_no REINSTALL "Reinstall and remove existing stack data?" "$REINSTALL"
    [ "$REINSTALL" = "yes" ] || die "Stopped by user."
    prompt_yes_no BACKUP_BEFORE_REINSTALL "Create backup before cleanup?" "$BACKUP_BEFORE_REINSTALL"
  fi
}

backup_existing_install() {
  [ "$BACKUP_BEFORE_REINSTALL" = "yes" ] || return 0
  [ -d "$DATA_DIR" ] || return 0
  local backup_dir backup_file
  backup_dir="$DATA_DIR/backups"
  mkdir -p "$backup_dir"
  backup_file="$backup_dir/reinstall-$(date +%Y%m%d-%H%M%S).tar.gz"
  log "Creating backup: $backup_file"
  tar \
    --exclude="$backup_dir" \
    --exclude="$backup_file" \
    -czf "$backup_file" \
    -C "$DATA_DIR" .
}

cleanup_existing_install() {
  [ "$REINSTALL" = "yes" ] || return 0
  log "Removing existing stack containers and files"
  local name
  if command -v docker >/dev/null 2>&1; then
    while IFS= read -r name; do
      [ -n "$name" ] || continue
      if docker container inspect "$name" >/dev/null 2>&1; then
        docker rm -f "$name" >/dev/null 2>&1 || true
      fi
    done <<EOF
$(known_container_names)
EOF
  fi

  rm -rf \
    "$COMPOSE_DIR" \
    "$DOCS_DIR" \
    "$SCRIPTS_DIR" \
    "$DATA_DIR/edge" \
    "$DATA_DIR/fake-gate" \
    "$DATA_DIR/fake-site" \
    "$DATA_DIR/panel-gate" \
    "$DATA_DIR/3x-ui" \
    "$DATA_DIR/telemt" \
    "$DATA_DIR/telemt-admin" \
    "$DATA_DIR/certs" \
    "$DATA_DIR/certbot"
}

write_env() {
  cat > "$COMPOSE_DIR/.env" <<EOF
DATA_DIR=$DATA_DIR
BASE_DOMAIN=$BASE_DOMAIN
CONTROL_DOMAIN=$CONTROL_DOMAIN
CONTROL_PREFIX=$CONTROL_PREFIX
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

portainer_location_block() {
  if [ "$PORTAINER" = "yes" ]; then
    cat <<EOF
        location = $CONTROL_PREFIX/portainer {
            return 301 $CONTROL_PREFIX/portainer/;
        }

        location $CONTROL_PREFIX/portainer/ {
            proxy_http_version 1.1;
            proxy_ssl_verify off;
            proxy_set_header Host \$host;
            proxy_set_header X-Real-IP \$remote_addr;
            proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
            proxy_set_header X-Forwarded-Proto https;
            proxy_set_header X-Forwarded-Host \$host;
            proxy_set_header Upgrade \$http_upgrade;
            proxy_set_header Connection \$connection_upgrade;
            rewrite ^$CONTROL_PREFIX/portainer/?(.*)\$ /\$1 break;
            proxy_pass https://portainer:9443/;
        }
EOF
  fi
}

base_tls_upstream() {
  if [ "$CONTROL_DOMAIN" = "$BASE_DOMAIN" ]; then
    printf 'panel-gate:443'
  else
    printf 'fake-gate:443'
  fi
}

control_domain_map_block() {
  if [ "$CONTROL_DOMAIN" != "$BASE_DOMAIN" ]; then
    printf '        %s panel-gate:443;' "$CONTROL_DOMAIN"
  fi
}

control_fallback_block() {
  if [ "$CONTROL_DOMAIN" = "$BASE_DOMAIN" ]; then
    cat <<'EOF'
            proxy_http_version 1.1;
            proxy_set_header Host $host;
            proxy_set_header X-Real-IP $remote_addr;
            proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
            proxy_set_header X-Forwarded-Proto https;
            proxy_pass http://fake_site_backend;
EOF
  else
    cat <<EOF
            return 301 https://$BASE_DOMAIN;
EOF
  fi
}

render_files() {
  log "Rendering config files"
  BASE_TLS_UPSTREAM="$(base_tls_upstream)"
  CONTROL_DOMAIN_MAP="$(control_domain_map_block)"
  CONTROL_FALLBACK_BLOCK="$(control_fallback_block)"
  render_template "$SCRIPT_DIR/templates/edge-nginx.conf.tpl" "$DATA_DIR/edge/nginx.conf"
  render_template "$SCRIPT_DIR/templates/fake-gate-nginx.conf.tpl" "$DATA_DIR/fake-gate/nginx.conf"
  render_template "$SCRIPT_DIR/templates/telemt-config.toml.tpl" "$DATA_DIR/telemt/config/config.toml"

  local panel_tmp
  panel_tmp="$(mktemp)"
  render_template "$SCRIPT_DIR/templates/panel-gate-nginx.conf.tpl" "$panel_tmp"
  sed "/__PORTAINER_LOCATION__/r /dev/stdin" "$panel_tmp" < <(portainer_location_block) | sed '/__PORTAINER_LOCATION__/d' > "$DATA_DIR/panel-gate/nginx.conf"
  rm -f "$panel_tmp"

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
docker restart masked-panel-gate >/dev/null 2>&1 || true
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
  load_saved_answers
  parse_args "$@"
  need_root
  collect_install_dir
  collect_inputs
  save_answers
  ask_reinstall_if_needed
  install_missing_prerequisites
  require_command sed
  require_command openssl
  require_command curl
  require_command python3
  require_command tar
  require_command getent
  install_docker_if_needed
  detect_compose
  check_dns
  backup_existing_install
  cleanup_existing_install
  check_ports
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
  printf '\nAdmin credentials:\n'
  printf '  Login:    %s\n' "$ADMIN_USER"
  printf '  Password: %s\n' "$ADMIN_PASS"
  printf '\nControl URLs:\n'
  printf '  3x-ui:        https://%s%s/3x-ui/\n' "$CONTROL_DOMAIN" "$CONTROL_PREFIX"
  printf '  TeleMT Admin: https://%s%s/telemt/\n' "$CONTROL_DOMAIN" "$CONTROL_PREFIX"
  if [ "$PORTAINER" = "yes" ]; then
    printf '  Portainer:    https://%s%s/portainer/\n' "$CONTROL_DOMAIN" "$CONTROL_PREFIX"
  fi
  printf '\nAll details were written to: %s\n' "$DOCS_DIR/README.txt"
}

main "$@"
