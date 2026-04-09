#!/usr/bin/env bash
set -euo pipefail

base_url="http://127.0.0.1:8080"
api_url="$base_url/api/v2"
cookie_file="$(mktemp)"

log() { printf '[qbittorrent-bootstrap] %s\n' "$*" >&2; }
cleanup() { rm -f "$cookie_file"; }
trap cleanup EXIT

json_escape() { printf '%s' "$1" | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g'; }

wait_ready() {
  local i=0
  until curl -sS -o /dev/null "$base_url"; do
    i="$((i + 1))"
    [ "$i" -ge 120 ] && return 1
    sleep 2
  done
}

login() {
  local username="$1" password="$2" body
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

set_webui_credentials() {
  local username="$1" password="$2" payload
  payload="$(printf '{"web_ui_username":"%s","web_ui_password":"%s"}' "$(json_escape "$username")" "$(json_escape "$password")")"
  curl -sS \
    -H "Referer: $base_url" \
    --data-urlencode "json=$payload" \
    "$api_url/app/setPreferences" \
    -b "$cookie_file" >/dev/null
}

temp_admin_password() {
  journalctl -u qbittorrent.service -n 200 --no-pager 2>/dev/null \
    | grep "The WebUI administrator password was not set." \
    | awk '{ print $NF }' \
    | tail -n1 \
    | tr -d '\r\n'
}

fresh_cookie() {
  rm -f "$cookie_file"
  cookie_file="$(mktemp)"
}

systemctl start qbittorrent-credentials.service
. /run/qbittorrent-bootstrap.env

username="${QBITTORRENT_BOOTSTRAP_USERNAME:-}"
password="${QBITTORRENT_BOOTSTRAP_PASSWORD:-}"
[ -n "$username" ] && [ -n "$password" ] || { log "Missing bootstrap credentials"; exit 1; }

wait_ready || { log "qBittorrent did not become ready in time"; exit 1; }

if login "$username" "$password"; then
  log "Credentials already work; nothing to do"
  exit 0
fi

fresh_cookie
if login "admin" "adminadmin"; then
  log "Using default admin credentials for bootstrap"
else
  temp_password="$(temp_admin_password)"
  [ -n "$temp_password" ] || { log "Unable to find temporary admin password in qbittorrent logs"; exit 1; }
  fresh_cookie
  login "admin" "$temp_password" || { log "Failed to authenticate with temporary admin password"; exit 1; }
  log "Using temporary admin credentials for bootstrap"
fi

set_webui_credentials "$username" "$password"

fresh_cookie
if login "$username" "$password"; then
  log "Bootstrap user configured and validated"
  exit 0
fi

sleep 2
fresh_cookie
if login "$username" "$password"; then
  log "Bootstrap user configured and validated"
  exit 0
fi

log "Bootstrap user setup failed"
exit 1
