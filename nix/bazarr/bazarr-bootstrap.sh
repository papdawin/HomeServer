#!/usr/bin/env bash
set -euo pipefail

base_url="http://127.0.0.1:6767"
api_url="$base_url/api"
bazarr_config_yaml="/appdata/config/config.yaml"
radarr_host="192.168.68.29"
radarr_port="7878"
sonarr_host="192.168.68.30"
sonarr_port="8989"

log() { printf '[bazarr-bootstrap] %s\n' "$*" >&2; }

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

wait_arr() {
  local host="$1" port="$2" api_key="$3" endpoint
  endpoint="http://${host}:${port}/api/v3/system/status"

  local i=0
  while [ "$i" -lt 180 ]; do
    if curl -fsS -H "X-Api-Key: $api_key" "$endpoint" >/dev/null 2>&1; then
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

api_update_arr_settings() {
  curl -fsS -o /dev/null \
    -H "X-API-KEY: $bazarr_api_key" \
    -X POST "$api_url/system/settings" \
    --data-urlencode "settings-general-use_sonarr=true" \
    --data-urlencode "settings-sonarr-ip=$sonarr_host" \
    --data-urlencode "settings-sonarr-port=$sonarr_port" \
    --data-urlencode "settings-sonarr-base_url=" \
    --data-urlencode "settings-sonarr-apikey=$sonarr_api_key" \
    --data-urlencode "settings-sonarr-ssl=false" \
    --data-urlencode "settings-sonarr-series_sync_on_live=true" \
    --data-urlencode "settings-general-use_radarr=true" \
    --data-urlencode "settings-radarr-ip=$radarr_host" \
    --data-urlencode "settings-radarr-port=$radarr_port" \
    --data-urlencode "settings-radarr-base_url=" \
    --data-urlencode "settings-radarr-apikey=$radarr_api_key" \
    --data-urlencode "settings-radarr-ssl=false" \
    --data-urlencode "settings-radarr-movies_sync_on_live=true"
}

arr_settings_match() {
  local settings_json
  settings_json="$(api_get_settings)"

  printf '%s' "$settings_json" | jq -e \
    --arg sonarr_host "$sonarr_host" \
    --arg sonarr_port "$sonarr_port" \
    --arg sonarr_api_key "$sonarr_api_key" \
    --arg radarr_host "$radarr_host" \
    --arg radarr_port "$radarr_port" \
    --arg radarr_api_key "$radarr_api_key" '
      (.general.use_sonarr // false) == true and
      (.general.use_radarr // false) == true and
      (.sonarr.ip // "") == $sonarr_host and
      ((.sonarr.port // "" | tostring) == $sonarr_port) and
      (.sonarr.apikey // "") == $sonarr_api_key and
      (.radarr.ip // "") == $radarr_host and
      ((.radarr.port // "" | tostring) == $radarr_port) and
      (.radarr.apikey // "") == $radarr_api_key
    ' >/dev/null
}

[ -f /run/bazarr-bootstrap.env ] || { log "Missing /run/bazarr-bootstrap.env"; exit 1; }
. /run/bazarr-bootstrap.env

radarr_host="${BAZARR_RADARR_HOST:-$radarr_host}"
radarr_port="${BAZARR_RADARR_PORT:-$radarr_port}"
radarr_api_key="${BAZARR_RADARR_API_KEY:-}"
sonarr_host="${BAZARR_SONARR_HOST:-$sonarr_host}"
sonarr_port="${BAZARR_SONARR_PORT:-$sonarr_port}"
sonarr_api_key="${BAZARR_SONARR_API_KEY:-}"

[ -n "$radarr_api_key" ] || { log "Radarr API key missing; set BAZARR_RADARR_API_KEY"; exit 1; }
[ -n "$sonarr_api_key" ] || { log "Sonarr API key missing; set BAZARR_SONARR_API_KEY"; exit 1; }

wait_api_ready || { log "Bazarr API did not become ready in time"; exit 1; }
bazarr_api_key="$(wait_for_api_key "$bazarr_config_yaml" || true)"
[ -n "$bazarr_api_key" ] || { log "Bazarr API key not found in $bazarr_config_yaml"; exit 1; }

wait_arr "$radarr_host" "$radarr_port" "$radarr_api_key" || { log "Radarr did not become ready in time"; exit 1; }
wait_arr "$sonarr_host" "$sonarr_port" "$sonarr_api_key" || { log "Sonarr did not become ready in time"; exit 1; }

if arr_settings_match; then
  log "Bazarr Arr integration already configured; nothing to do"
  exit 0
fi

api_update_arr_settings
wait_api_ready || { log "Bazarr API did not become ready after settings update"; exit 1; }
arr_settings_match || { log "Bazarr Arr integration verification failed"; exit 1; }

log "Configured Bazarr integration with Sonarr and Radarr"
