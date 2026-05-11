#!/usr/bin/env bash
set -euo pipefail

base_url="http://127.0.0.1:8080"
api_url="$base_url/api/v2"
cookie_file="$(mktemp)"

log() { printf '[qbittorrent-routing] %s\n' "$*" >&2; }
cleanup() { rm -f "$cookie_file"; }
trap cleanup EXIT

wait_ready() {
  local i=0
  until curl -sS -o /dev/null "$base_url"; do
    i="$((i + 1))"
    [ "$i" -ge 120 ] && return 1
    sleep 2
  done
}

login() {
  local body
  body="$(
    curl -sS \
      -H "Referer: $base_url" \
      --data-urlencode "username=$username" \
      --data-urlencode "password=$password" \
      "$api_url/auth/login" \
      -c "$cookie_file" || true
  )"
  [ "$(printf '%s' "$body" | tr -d '\r\n')" = "Ok." ]
}

setup_category() {
  local category="$1" save_path="$2"
  curl -sS -o /dev/null -H "Referer: $base_url" -b "$cookie_file" \
    --data-urlencode "category=$category" \
    --data-urlencode "savePath=$save_path" \
    "$api_url/torrents/createCategory" || true
  curl -sS -o /dev/null -H "Referer: $base_url" -b "$cookie_file" \
    --data-urlencode "category=$category" \
    --data-urlencode "savePath=$save_path" \
    "$api_url/torrents/editCategory"
}

set_storage_preferences() {
  local payload
  payload='{"save_path":"/media/downloads/other","temp_path_enabled":true,"temp_path":"/media/downloads/incomplete","auto_tmm_enabled":false,"use_category_paths_in_manual_mode":true}'
  curl -sS -o /dev/null -H "Referer: $base_url" -b "$cookie_file" \
    --data-urlencode "json=$payload" \
    "$api_url/app/setPreferences"
}

systemctl start qbittorrent-credentials.service
. /run/qbittorrent-bootstrap.env

username="${QBITTORRENT_BOOTSTRAP_USERNAME:-}"
password="${QBITTORRENT_BOOTSTRAP_PASSWORD:-}"
[ -n "$username" ] && [ -n "$password" ] || { log "Missing bootstrap credentials"; exit 1; }

wait_ready || { log "qBittorrent did not become ready in time"; exit 1; }
login || { log "Failed to authenticate with bootstrap credentials"; exit 1; }

mkdir -p \
  /media/downloads/incomplete \
  /media/downloads/radarr \
  /media/downloads/sonarr \
  /media/downloads/other

set_storage_preferences
setup_category "radarr" "/media/downloads/radarr"
setup_category "sonarr" "/media/downloads/sonarr"
setup_category "other" "/media/downloads/other"

curl -sS -o /dev/null -H "Referer: $base_url" -b "$cookie_file" \
  --data-urlencode "tags=show,movie,other" \
  "$api_url/torrents/createTags" || true

log "Storage preferences and routing categories configured"
log "Convenience tags configured: show,movie,other"
