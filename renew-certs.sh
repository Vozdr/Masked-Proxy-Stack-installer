#!/bin/sh
set -eu

DATA_DIR="${DATA_DIR:-/data}"
status=0

log() {
  printf '[%s] %s\n' "$(date -u '+%Y-%m-%dT%H:%M:%SZ')" "$*"
}

log "Checking certificate renewals"
if docker run --rm \
  -v "$DATA_DIR/certs:/etc/letsencrypt" \
  -v "$DATA_DIR/certbot/www:/var/www/certbot" \
  certbot/certbot:latest renew \
    --webroot \
    -w /var/www/certbot \
    --non-interactive; then
  log "Certificate renewal check completed"
else
  log "ERROR: Certbot failed; still attempting to apply certificates already on disk" >&2
  status=1
fi

# Retry on every cycle, including after partial renewal or an earlier reload failure.
for container in masked-panel-gate masked-fake-gate; do
  log "Checking nginx configuration in $container"
  if docker exec "$container" nginx -t; then
    if docker exec "$container" nginx -s reload; then
      log "Reload signal sent to $container"
    else
      log "ERROR: Could not send reload signal to $container" >&2
      status=1
    fi
  else
    log "ERROR: Configuration check failed in $container; reload skipped" >&2
    status=1
  fi
done

log "Certificate maintenance finished (status=$status)"
exit "$status"
