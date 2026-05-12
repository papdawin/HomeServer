#!/usr/bin/env bash
set -euo pipefail

log() { printf '[nextcloud-bootstrap-user] %s\n' "$*" >&2; }

OCC_BIN="/run/current-system/sw/bin/nextcloud-occ"
if [ ! -x "$OCC_BIN" ]; then
  OCC_BIN="$(command -v nextcloud-occ || true)"
fi
[ -n "${OCC_BIN:-}" ] || { log "nextcloud-occ not found"; exit 1; }

wait_for_nextcloud() {
  local i=0 status_json=""
  while [ "$i" -lt 360 ]; do
    status_json="$("$OCC_BIN" status --output=json 2>/dev/null || true)"
    if printf '%s' "$status_json" | grep -q '"installed":[[:space:]]*true'; then
      return 0
    fi
    if systemctl is-failed nextcloud-setup.service >/dev/null 2>&1; then
      log "nextcloud-setup.service failed; cannot bootstrap user"
      return 1
    fi
    i="$((i + 1))"
    sleep 2
  done
  return 1
}

systemctl start nextcloud-credentials.service
. /run/nextcloud-bootstrap.env

username="${NEXTCLOUD_BOOTSTRAP_USERNAME:-}"
password="${NEXTCLOUD_BOOTSTRAP_PASSWORD:-}"
[ -n "$username" ] && [ -n "$password" ] || { log "Missing bootstrap credentials"; exit 1; }

if ! wait_for_nextcloud; then
  log "Nextcloud did not become ready in time; skipping bootstrap for this run"
  exit 0
fi

if "$OCC_BIN" user:info "$username" >/dev/null 2>&1; then
  OC_PASS="$password" "$OCC_BIN" user:resetpassword --password-from-env "$username" >/dev/null
  log "Bootstrap user already exists; password synced from secret"
else
  OC_PASS="$password" "$OCC_BIN" user:add --password-from-env --display-name="$username" "$username" >/dev/null
  "$OCC_BIN" group:adduser admin "$username" >/dev/null 2>&1 || true
  log "Bootstrap user created"
fi
