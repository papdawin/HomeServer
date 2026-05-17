#!/usr/bin/env bash
set -euo pipefail

base_url="http://127.0.0.1:6767"
api_url="$base_url/api"
bazarr_config_yaml="/appdata/bazarr/config/config.yaml"

log() { printf '[bazarr-bootstrap-user] %s\n' "$*" >&2; }

read_bazarr_api_key() {
  local file="$1"
  sed -n '/^auth:/,/^[^[:space:]]/p' "$file" \
    | sed -n 's/^[[:space:]]*apikey:[[:space:]]*//p' \
    | head -n1 \
    | tr -d "\"'"
}

wait_for_api_key() {
  local file="$1" value=""
  local i=0
  while [ "$i" -lt 180 ]; do
    if [ -f "$file" ]; then
      value="$(read_bazarr_api_key "$file" || true)"
      if [ -n "$value" ]; then
        printf '%s' "$value"
        return 0
      fi
    fi
    i="$((i + 1))"
    sleep 2
  done
  return 1
}

wait_api_ready() {
  local i=0
  while [ "$i" -lt 180 ]; do
    if curl -fsS "$api_url/system/ping" >/dev/null 2>&1; then
      return 0
    fi
    i="$((i + 1))"
    sleep 2
  done
  return 1
}

api_get_settings() {
  curl -fsS -H "X-API-KEY: $bazarr_api_key" "$api_url/system/settings"
}

api_update_auth_settings() {
  curl -fsS -o /dev/null \
    -H "X-API-KEY: $bazarr_api_key" \
    -X POST "$api_url/system/settings" \
    --data-urlencode "settings-auth-type=form" \
    --data-urlencode "settings-auth-username=$username" \
    --data-urlencode "settings-auth-password=$password"
}

login_works() {
  local code
  code="$(
    curl -sS -o /dev/null -w '%{http_code}' \
      -X POST "$api_url/system/account" \
      -H "Content-Type: application/x-www-form-urlencoded" \
      --data-urlencode "action=login" \
      --data-urlencode "username=$username" \
      --data-urlencode "password=$password" || true
  )"
  [ "$code" = "204" ]
}

systemctl start bazarr-credentials.service
. /run/bazarr-bootstrap.env

username="${BAZARR_BOOTSTRAP_USERNAME:-}"
password="${BAZARR_BOOTSTRAP_PASSWORD:-}"
[ -n "$username" ] && [ -n "$password" ] || { log "Missing bootstrap credentials"; exit 1; }

wait_api_ready || { log "Bazarr API did not become ready in time"; exit 1; }
bazarr_api_key="$(wait_for_api_key "$bazarr_config_yaml" || true)"
[ -n "$bazarr_api_key" ] || { log "Bazarr API key not found in $bazarr_config_yaml"; exit 1; }

settings_json="$(api_get_settings)"
auth_type="$(printf '%s' "$settings_json" | jq -r '.auth.type // ""' | tr '[:upper:]' '[:lower:]')"
current_username="$(printf '%s' "$settings_json" | jq -r '.auth.username // ""')"

if [ "$auth_type" = "form" ] && [ "$current_username" = "$username" ] && login_works; then
  log "Bootstrap user already configured; nothing to do"
  exit 0
fi

api_update_auth_settings

wait_api_ready || { log "Bazarr API did not become ready after auth update"; exit 1; }
login_works || { log "Bootstrap user login still fails after update"; exit 1; }
log "Bootstrap user configured"
