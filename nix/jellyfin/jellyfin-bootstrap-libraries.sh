#!/usr/bin/env bash
set -euo pipefail

base_url="http://127.0.0.1:8096"
auth_header_base='X-Emby-Authorization: MediaBrowser Client="terraform-library-bootstrap", Device="terraform", DeviceId="terraform-library-bootstrap", Version="1.0.0"'

log() { printf '[jellyfin-libraries] %s\n' "$*" >&2; }

wait_ready() {
  local i=0
  while [ "$i" -lt 120 ]; do
    if curl -fsS "$base_url/System/Ping" >/dev/null 2>&1; then
      return 0
    fi
    i="$((i + 1))"
    sleep 2
  done
  return 1
}

authenticate() {
  local payload response
  payload="$(jq -cn --arg username "$username" --arg password "$password" '{ Username: $username, Pw: $password }')"
  response="$(curl -fsS -X POST \
    -H "$auth_header_base" \
    -H "Content-Type: application/json" \
    --data "$payload" \
    "$base_url/Users/AuthenticateByName")"

  access_token="$(printf '%s' "$response" | jq -r '.AccessToken // empty')"
  [ -n "$access_token" ] || return 1
}

api_get() {
  local endpoint="$1"
  curl -fsS \
    -H "$auth_header_base" \
    -H "X-Emby-Token: $access_token" \
    "$base_url/$endpoint"
}

api_post_query() {
  local endpoint="$1"
  shift

  curl -fsS -X POST \
    -H "$auth_header_base" \
    -H "X-Emby-Token: $access_token" \
    --get \
    "$@" \
    "$base_url/$endpoint"
}

api_post_json() {
  local endpoint="$1" payload="$2"
  curl -fsS -X POST \
    -H "$auth_header_base" \
    -H "X-Emby-Token: $access_token" \
    -H "Content-Type: application/json" \
    --data "$payload" \
    "$base_url/$endpoint"
}

library_name_by_path() {
  local path="$1"
  api_get "Library/VirtualFolders" | jq -r \
    --arg path "$path" \
    '
      [
        .[]
        | select((((.Locations // .Paths // []) | index($path)) != null))
        | (.Name // empty)
      ][0] // empty
    '
}

rename_library() {
  local current_name="$1" target_name="$2"
  [ "$current_name" != "$target_name" ] || return 0

  if api_post_query "Library/VirtualFolders/Name" \
      --data-urlencode "name=$current_name" \
      --data-urlencode "newName=$target_name" >/dev/null 2>&1; then
    log "Renamed library: $current_name -> $target_name"
    return 0
  fi

  log "Failed to rename library: $current_name -> $target_name"
  return 1
}

ensure_media_dir() {
  local path="$1"
  if [ -e "$path" ] && [ ! -d "$path" ]; then
    log "Path exists but is not a directory: $path"
    return 1
  fi
  install -d -m 2775 "$path"
  if getent group media >/dev/null 2>&1; then
    chgrp media "$path"
  fi
}

ensure_media_folders() {
  ensure_media_dir "/media"
  ensure_media_dir "/media/movies"
  ensure_media_dir "/media/shows"
}

library_path_exists() {
  local path="$1"
  api_get "Library/VirtualFolders" | jq -e \
    --arg path "$path" \
    '
      .[] | select(
        (((.Locations // .Paths // []) | index($path)) != null)
      )
    ' >/dev/null
}

ensure_library() {
  local name="$1" path="$2" collection_type="$3"
  local payload current_name

  if library_path_exists "$path"; then
    current_name="$(library_name_by_path "$path")"
    if [ -n "$current_name" ] && [ "$current_name" != "$name" ]; then
      rename_library "$current_name" "$name" || return 1
    else
      log "Library path already configured: $path"
    fi
    return 0
  fi

  if api_post_query "Library/VirtualFolders" \
      --data-urlencode "name=$name" \
      --data-urlencode "collectionType=$collection_type" \
      --data-urlencode "paths=$path" >/dev/null 2>&1; then
    log "Created library: $name -> $path (query mode)"
    return 0
  fi

  payload="$(jq -cn --arg name "$name" --arg path "$path" --arg collectionType "$collection_type" '{ Name: $name, CollectionType: $collectionType, Paths: [ $path ] }')"
  api_post_json "Library/VirtualFolders" "$payload" >/dev/null
  log "Created library: $name -> $path (json mode)"
}

verify_libraries() {
  api_get "Library/VirtualFolders" | jq -e '
    ([ .[] | select((.Name // "") == "Movies" and (((.Locations // .Paths // []) | index("/media/movies")) != null)) ] | length) > 0
    and
    ([ .[] | select((.Name // "") == "Shows" and (((.Locations // .Paths // []) | index("/media/shows")) != null)) ] | length) > 0
  ' >/dev/null
}

if ! systemctl start jellyfin-credentials.service; then
  log "jellyfin-credentials.service start failed; using existing /run/jellyfin-bootstrap.env if present"
fi

[ -s /run/jellyfin-bootstrap.env ] || { log "Missing /run/jellyfin-bootstrap.env"; exit 1; }
# shellcheck disable=SC1091
. /run/jellyfin-bootstrap.env

username="${JELLYFIN_BOOTSTRAP_USERNAME:-}"
password="${JELLYFIN_BOOTSTRAP_PASSWORD:-}"
[ -n "$username" ] && [ -n "$password" ] || { log "Missing Jellyfin bootstrap credentials"; exit 1; }

wait_ready || { log "Jellyfin did not become ready in time"; exit 1; }

auth_ok=0
for _ in $(seq 1 30); do
  if authenticate; then
    auth_ok=1
    break
  fi
  sleep 2
done
[ "$auth_ok" -eq 1 ] || { log "Unable to authenticate to Jellyfin API"; exit 1; }

ensure_media_folders
ensure_library "Movies" "/media/movies" "movies"
ensure_library "Shows" "/media/shows" "tvshows"
verify_libraries || { log "Library verification failed"; exit 1; }

log "Libraries configured: Movies=/media/movies, Shows=/media/shows"
