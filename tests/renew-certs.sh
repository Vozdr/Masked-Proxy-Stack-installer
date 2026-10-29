#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
TEST_DIR="$(mktemp -d)"
trap 'rm -rf -- "$TEST_DIR"' EXIT

docker() {
  printf '%s\n' "$*" >> "$CALLS"
  case "$*" in
    run\ *) [ "$SCENARIO" != partial ] ;;
    'exec masked-panel-gate nginx -t') [ "$SCENARIO" != invalid ] ;;
    'exec masked-panel-gate nginx -s reload') [ "$SCENARIO" != reload_fail ] ;;
    *) return 0 ;;
  esac
}
export -f docker
export DATA_DIR='/custom data'

for SCENARIO in success partial invalid reload_fail; do
  export SCENARIO CALLS="$TEST_DIR/$SCENARIO.calls"
  result=0
  bash "$SCRIPT_DIR/renew-certs.sh" > "$TEST_DIR/$SCENARIO.log" 2>&1 || result=$?
  expected=1
  [ "$SCENARIO" != success ] || expected=0
  [ "$result" -eq "$expected" ]
  grep -Fq -- '-v /custom data/certs:/etc/letsencrypt' "$CALLS"
  grep -Fxq 'exec masked-fake-gate nginx -s reload' "$CALLS"
  if [ "$SCENARIO" = invalid ]; then
    ! grep -Fxq 'exec masked-panel-gate nginx -s reload' "$CALLS"
  else
    grep -Fxq 'exec masked-panel-gate nginx -s reload' "$CALLS"
  fi
  ! grep -q '^restart ' "$CALLS"
  if [ "$result" -ne 0 ]; then
    grep -q 'ERROR:' "$TEST_DIR/$SCENARIO.log"
  fi
  printf 'PASS: %s\n' "$SCENARIO"
done
