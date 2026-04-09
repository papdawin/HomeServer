#!/usr/bin/env bash
set -euo pipefail

base_url="http://127.0.0.1:8096"
auth_header='X-Emby-Authorization: MediaBrowser Client="terraform-library-bootstrap", Device="terraform", DeviceId="terraform-library-bootstrap", Version="1.0.0"'
log() { printf '[jellyfin-libraries] %s\n' "$*" >&2; }
wait_ready() {
  local i=0
  until curl -fsS "$base_url/System/Ping" >/dev/null 2>&1; do
    i="$((i + 1))"
    [ "$i" -ge 120 ] && return 1
    sleep 2
  done
}

fetch_libraries() {
  curl -fsS -H "$auth_header" -H "X-Emby-Token: $token" "$base_url/Library/VirtualFolders" | tr -d '[:space:]'
}

ensure_library() {
  local name="$1" collection_type="$2" media_path="$3" status
  if printf '%s' "$libraries" | grep -F "\"$media_path\"" >/dev/null 2>&1; then
    log "Library already configured for $media_path"
    return 0
  fi

  status="$(
    curl -sS \
      -o /dev/null \
      -w '%{http_code}' \
      -X POST \
      -H "$auth_header" \
      -H "X-Emby-Token: $token" \
      --get \
      --data-urlencode "name=$name" \
      --data-urlencode "collectionType=$collection_type" \
      --data-urlencode "paths=$media_path" \
      "$base_url/Library/VirtualFolders" || printf '000'
  )"
  case "$status" in 200|204|400) ;; *) log "Failed to create '$name' ($status)"; return 1 ;; esac
  libraries="$(fetch_libraries)"
  printf '%s' "$libraries" | grep -F "\"$media_path\"" >/dev/null 2>&1 || { log "Library missing after create: $media_path"; return 1; }
  log "Library configured: $name -> $media_path"
}

systemctl start jellyfin-credentials.service
. /run/jellyfin-bootstrap.env
username="${JELLYFIN_BOOTSTRAP_USERNAME:-}"
password="${JELLYFIN_BOOTSTRAP_PASSWORD:-}"
[ -n "$username" ] && [ -n "$password" ] || { log "Missing bootstrap credentials"; exit 1; }
wait_ready || { log "Jellyfin did not become ready in time"; exit 1; }
auth_payload="$(printf '{"Username":"%s","Pw":"%s"}' "$(printf '%s' "$username" | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g')" "$(printf '%s' "$password" | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g')")"
auth_response="$(curl -fsS -X POST -H "$auth_header" -H "Content-Type: application/json" --data "$auth_payload" "$base_url/Users/AuthenticateByName")"
token="$(printf '%s' "$auth_response" | sed -n 's/.*"AccessToken":"\([^"]*\)".*/\1/p' | head -n1)"
[ -n "$token" ] || { log "Authentication succeeded but no access token was returned"; exit 1; }
libraries="$(fetch_libraries)"
ensure_library "Movies" "movies" "/media/movies"
ensure_library "Shows" "tvshows" "/media/shows"

log "Library bootstrap completed"
