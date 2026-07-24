#!/usr/bin/env bash
set -Eeuo pipefail

DATA_DIR="${DATA_DIR:-/data}"
STACK_NAME="${STACK_NAME:-masked-proxy}"
PORTAINER_IMAGE="${PORTAINER_IMAGE:-portainer/portainer-ce:latest}"
PORTAINER_CONTAINER="${PORTAINER_CONTAINER:-portainer}"
PORTAINER_URL="${PORTAINER_URL:-https://127.0.0.1:9443}"
PORTAINER_SETUP_TOKEN=""

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
  sudo ./deploy-portainer.sh [options]

Options:
  --dir PATH              Install directory. Default: /data
  --stack-name NAME       Portainer stack name. Default: masked-proxy
  --portainer-image IMG   Portainer image. Default: portainer/portainer-ce:latest
  -h, --help              Show this help.
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
      --stack-name)
        STACK_NAME="$(option_value "$1" "${2:-}")"
        shift 2
        ;;
      --portainer-image)
        PORTAINER_IMAGE="$(option_value "$1" "${2:-}")"
        shift 2
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
  SCRIPTS_DIR="$DATA_DIR/scripts"
  ENV_FILE="$COMPOSE_DIR/.env"
  COMPOSE_FILE="$COMPOSE_DIR/docker-compose.yml"
  [ -f "$ENV_FILE" ] || die "Missing env file: $ENV_FILE"
  [ -f "$COMPOSE_FILE" ] || die "Missing compose file: $COMPOSE_FILE"

  ADMIN_USER="$(env_get ADMIN_USER)"
  ADMIN_PASS="$(env_get ADMIN_PASS)"
  BASE_DOMAIN="$(env_get BASE_DOMAIN)"
  CONTROL_DOMAIN="$(env_get CONTROL_DOMAIN)"
  CONTROL_PREFIX="$(env_get CONTROL_PREFIX)"
  SECRET_PATH="$(env_get SECRET_PATH)"
  TZ_VALUE="$(env_get TZ)"

  [ -n "$ADMIN_USER" ] || die "ADMIN_USER is empty in $ENV_FILE"
  [ -n "$ADMIN_PASS" ] || die "ADMIN_PASS is empty in $ENV_FILE"
  [ -n "$BASE_DOMAIN" ] || die "BASE_DOMAIN is empty in $ENV_FILE"
  CONTROL_DOMAIN="${CONTROL_DOMAIN:-$BASE_DOMAIN}"
  if [ -z "$CONTROL_PREFIX" ] && [ -n "$SECRET_PATH" ]; then
    CONTROL_PREFIX="/$SECRET_PATH"
  fi
  TZ_VALUE="${TZ_VALUE:-UTC}"
  PORTAINER_API_URL="$PORTAINER_URL"
}

start_portainer() {
  log "Starting Portainer CE"
  mkdir -p "$DATA_DIR/portainer"

  if docker inspect "$PORTAINER_CONTAINER" >/dev/null 2>&1; then
    docker start "$PORTAINER_CONTAINER" >/dev/null
    return
  fi

  docker run -d \
    --name "$PORTAINER_CONTAINER" \
    --restart unless-stopped \
    -p 127.0.0.1:9443:9443 \
    -e TZ="$TZ_VALUE" \
    -v /var/run/docker.sock:/var/run/docker.sock \
    -v "$DATA_DIR/portainer:/data" \
    "$PORTAINER_IMAGE" \
    --base-url "$CONTROL_PREFIX/portainer" \
    --trusted-origins "$CONTROL_DOMAIN" >/dev/null
}

wait_portainer_api() {
  log "Waiting for Portainer API"
  local i
  for i in $(seq 1 90); do
    if curl -kfsS "$PORTAINER_API_URL/api/status" >/dev/null 2>&1; then
      return
    fi
    sleep 2
  done
  docker ps -a --filter "name=^/${PORTAINER_CONTAINER}$" >&2 || true
  docker logs --tail 80 "$PORTAINER_CONTAINER" >&2 || true
  die "Portainer API did not become ready."
}

read_portainer_setup_token() {
  log "Reading Portainer setup token"
  PORTAINER_SETUP_TOKEN="$(
    docker exec "$PORTAINER_CONTAINER" cat /data/portainer.init 2>/dev/null \
      | sed -nE 's/.*"setup_token"[[:space:]]*:[[:space:]]*"([^"]+)".*/\1/p' \
      | tail -n 1
  )"
  if [ -z "$PORTAINER_SETUP_TOKEN" ]; then
    PORTAINER_SETUP_TOKEN="$(
      docker logs --tail 200 "$PORTAINER_CONTAINER" 2>&1 \
        | sed -nE 's/.*[Ss]etup token:[[:space:]]*([A-Za-z0-9._-]+).*/\1/p' \
        | tail -n 1
    )"
  fi
  if [ -n "$PORTAINER_SETUP_TOKEN" ]; then
    printf 'Portainer setup token found.\n'
  else
    printf 'Portainer setup token was not found; continuing without it.\n'
  fi
}

deploy_stack() {
  log "Creating or updating Portainer stack"
  read_portainer_setup_token
  python3 - "$PORTAINER_API_URL" "$ADMIN_USER" "$ADMIN_PASS" "$STACK_NAME" "$COMPOSE_FILE" "$PORTAINER_SETUP_TOKEN" <<'PY'
import json
import ssl
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
import uuid

base_url, username, password, stack_name, compose_file, setup_token = sys.argv[1:7]
ctx = ssl._create_unverified_context()

def progress(message):
    print(f"Portainer: {message}", flush=True)

def request(method, path, token=None, data=None, extra_headers=None):
    body = None
    headers = {}
    if data is not None:
        body = json.dumps(data).encode()
        headers["Content-Type"] = "application/json"
    if token:
        headers["Authorization"] = "Bearer " + token
    if extra_headers:
        headers.update(extra_headers)
    req = urllib.request.Request(base_url + path, data=body, headers=headers, method=method)
    try:
        raw = urllib.request.urlopen(req, timeout=300, context=ctx).read()
        return json.loads(raw.decode() or "{}")
    except urllib.error.HTTPError as exc:
        detail = exc.read().decode(errors="replace")
        raise RuntimeError(f"{method} {path} failed: HTTP {exc.code}: {detail}") from exc

def try_request(method, path, token=None, data=None, extra_headers=None):
    try:
        return request(method, path, token, data, extra_headers), None
    except Exception as exc:
        return None, exc

def request_multipart(method, path, token, fields):
    boundary = "----masked-edge-" + uuid.uuid4().hex
    chunks = []
    for name, value in fields.items():
        chunks.append(f"--{boundary}\r\n".encode())
        chunks.append(f'Content-Disposition: form-data; name="{name}"\r\n\r\n'.encode())
        chunks.append(str(value).encode())
        chunks.append(b"\r\n")
    chunks.append(f"--{boundary}--\r\n".encode())
    body = b"".join(chunks)
    headers = {
        "Content-Type": f"multipart/form-data; boundary={boundary}",
        "Authorization": "Bearer " + token,
    }
    req = urllib.request.Request(base_url + path, data=body, headers=headers, method=method)
    try:
        raw = urllib.request.urlopen(req, timeout=300, context=ctx).read()
        return json.loads(raw.decode() or "{}")
    except urllib.error.HTTPError as exc:
        detail = exc.read().decode(errors="replace")
        raise RuntimeError(f"{method} {path} failed: HTTP {exc.code}: {detail}") from exc

progress("initializing admin account")
init_headers = {}
if setup_token:
    init_headers["X-Setup-Token"] = setup_token
_, init_error = try_request("POST", "/api/users/admin/init", data={
    "Username": username,
    "Password": password,
}, extra_headers=init_headers)
if init_error:
    text = str(init_error).lower()
    if "already" not in text and "initialized" not in text and "409" not in text:
        print(f"WARNING: Portainer admin init returned: {init_error}", file=sys.stderr)

progress("authenticating")
try:
    auth = request("POST", "/api/auth", data={"Username": username, "Password": password})
except Exception as exc:
    raise RuntimeError(
        "Portainer authentication failed. If this Portainer data directory was "
        "initialized by an earlier run with different credentials, reinstall "
        "the stack or remove the Portainer data directory before retrying. "
        f"Original error: {exc}"
    ) from exc
token = auth.get("jwt")
if not token:
    raise RuntimeError("Portainer auth did not return JWT")

progress("checking Docker environment")
endpoints = request("GET", "/api/endpoints", token)
if not endpoints:
    progress("creating local Docker environment")
    request_multipart("POST", "/api/endpoints", token, {
        "Name": "local",
        "EndpointCreationType": 1,
    })
    endpoints = request("GET", "/api/endpoints", token)
if not endpoints:
    raise RuntimeError("Portainer has no local endpoint after creation. Check Docker socket mount.")
endpoint_id = endpoints[0]["Id"]

progress("checking existing stacks")
stacks = request("GET", "/api/stacks", token)
existing = next((s for s in stacks if s.get("Name") == stack_name), None)
compose_text = open(compose_file, encoding="utf-8").read()
env = []

if existing:
    progress(f"updating stack {stack_name}; this can take a while while images are pulled")
    stack_id = existing["Id"]
    path = f"/api/stacks/{stack_id}?endpointId={endpoint_id}"
    request("PUT", path, token, {
        "StackFileContent": compose_text,
        "Env": env,
        "Prune": False,
        "PullImage": True,
    })
    print(f"Updated Portainer stack {stack_name} on endpoint {endpoint_id}", flush=True)
else:
    progress(f"creating stack {stack_name}; this can take a while while images are pulled")
    query = urllib.parse.urlencode({"type": 2, "method": "string", "endpointId": endpoint_id})
    request("POST", f"/api/stacks/create/standalone/string?{query}", token, {
        "Name": stack_name,
        "StackFileContent": compose_text,
        "Env": env,
        "FromAppTemplate": False,
    })
    print(f"Created Portainer stack {stack_name} on endpoint {endpoint_id}", flush=True)

time.sleep(2)
PY
}

connect_portainer_network() {
  log "Connecting Portainer to stack network"
  for _ in $(seq 1 30); do
    if docker network inspect masked_net >/dev/null 2>&1; then
      docker network connect masked_net "$PORTAINER_CONTAINER" >/dev/null 2>&1 || true
      return
    fi
    sleep 2
  done
  die "masked_net network was not created by the Portainer stack."
}

run_post_configure() {
  log "Running post-configuration through shared script"
  "$SCRIPTS_DIR/post-configure.sh" --dir "$DATA_DIR" --mode portainer
}

main() {
  parse_args "$@"
  need_root
  load_env
  command -v docker >/dev/null 2>&1 || die "Docker is not available."
  command -v curl >/dev/null 2>&1 || die "curl is not available."
  command -v python3 >/dev/null 2>&1 || die "python3 is not available."

  start_portainer
  wait_portainer_api
  deploy_stack
  connect_portainer_network
  run_post_configure

  log "Portainer deployment done"
  printf 'Portainer: https://%s%s/portainer/\n' "$CONTROL_DOMAIN" "$CONTROL_PREFIX"
  printf 'Stack: %s\n' "$STACK_NAME"
}

main "$@"
