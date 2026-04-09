#!/usr/bin/env bash
set -euo pipefail

base_url="http://127.0.0.1:8096"
auth_header='X-Emby-Authorization: MediaBrowser Client="terraform-bootstrap", Device="terraform", DeviceId="terraform-bootstrap", Version="1.0.0"'
log() { printf '[jellyfin-bootstrap] %s\n' "$*" >&2; }

json_escape() { printf '%s' "$1" | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g'; }

post_status() {
  local endpoint="$1" data="${2:-}"
  local -a args=(
    -sS
    -o /dev/null
    -w '%{http_code}'
    -X POST
    -H "$auth_header"
  )
  [ -n "$data" ] && args+=(-H "Content-Type: application/json" --data "$data")
  curl "${args[@]}" "$base_url/$endpoint" || printf '000'
}

status_ok() {
  case "$1" in
    200|204|400) return 0 ;;
    *) return 1 ;;
  esac
}

wait_ready() {
  local i=0
  until curl -fsS "$base_url/System/Ping" >/dev/null 2>&1; do
    i="$((i + 1))"
    [ "$i" -ge 120 ] && return 1
    sleep 2
  done
}

auth_ok() {
  local payload
  payload="$(printf '{"Username":"%s","Pw":"%s"}' "$(json_escape "$username")" "$(json_escape "$password")")"
  [ "$(post_status "Users/AuthenticateByName" "$payload")" = "200" ]
}

has_users() {
  local users_public users_compact
  users_public="$(curl -fsS "$base_url/Users/Public" || true)"
  users_compact="$(printf '%s' "$users_public" | tr -d '[:space:]')"
  [ -n "$users_compact" ] && [ "$users_compact" != "[]" ]
}

systemctl start jellyfin-credentials.service
. /run/jellyfin-bootstrap.env

username="${JELLYFIN_BOOTSTRAP_USERNAME:-}"
password="${JELLYFIN_BOOTSTRAP_PASSWORD:-}"
[ -n "$username" ] && [ -n "$password" ] || { log "Missing bootstrap credentials"; exit 1; }

bootstrap_once() {
  local status payload_user
  status="$(post_status "Startup/Configuration" '{"UICulture":"en-US","MetadataCountryCode":"US","PreferredMetadataLanguage":"en"}')"
  case "$status" in
    200|204|400|404) ;;
    *) return 1 ;;
  esac

  curl -fsS -H "$auth_header" "$base_url/Startup/User" >/dev/null 2>&1 || true

  payload_user="$(printf '{"Username":"%s","Pw":"%s"}' "$(json_escape "$username")" "$(json_escape "$password")")"
  status="$(post_status "Startup/User" "$payload_user")"
  status_ok "$status" || return 1

  status="$(post_status "Startup/Complete")"
  status_ok "$status" || return 1

  auth_ok
}

wait_ready || { log "Jellyfin did not become ready in time"; exit 1; }
auth_ok && { log "Credentials already work; nothing to do"; exit 0; }
has_users && { log "Jellyfin already has users; skipping bootstrap"; exit 0; }

for ((i = 1; i <= 20; i++)); do
  if bootstrap_once && auth_ok; then
    log "Bootstrap user created and validated"
    exit 0
  fi
  sleep 2
done

log "Jellyfin bootstrap failed after retries"
exit 1
