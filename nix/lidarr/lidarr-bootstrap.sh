#!/usr/bin/env bash
set -euo pipefail

base_url="http://127.0.0.1:8686"
api_url="$base_url/api/v1"
config_xml="/appdata/lidarr/config.xml"

log() { printf '[lidarr-bootstrap] %s\n' "$*" >&2; }

xml_value() {
  local file="$1" tag="$2"
  sed -n "s:.*<$tag>\\(.*\\)</$tag>.*:\\1:p" "$file" | head -n1
}

wait_for_file_value() {
  local file="$1" tag="$2" value=""
  local i=0
  while [ "$i" -lt 180 ]; do
    if [ -f "$file" ]; then
      value="$(xml_value "$file" "$tag" || true)"
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

api_call() {
  local method="$1" endpoint="$2" data="${3:-}"
  local -a args=(
    -fsS
    -X "$method"
    -H "X-Api-Key: $lidarr_api_key"
  )
  if [ -n "$data" ]; then
    args+=( -H "Content-Type: application/json" --data "$data" )
  fi
  curl "${args[@]}" "$api_url/$endpoint"
}

put_config() {
  local endpoint="$1" cfg="$2" data="$3" id
  id="$(printf '%s' "$cfg" | jq -r '.id // empty')"
  if [ -n "$id" ]; then
    api_call PUT "$endpoint/$id" "$data"
    return
  fi
  api_call PUT "$endpoint" "$data"
}

wait_api_ready() {
  local i=0
  while [ "$i" -lt 180 ]; do
    if curl -fsS -H "X-Api-Key: $lidarr_api_key" "$api_url/system/status" >/dev/null 2>&1; then
      return 0
    fi
    i="$((i + 1))"
    sleep 2
  done
  return 1
}

wait_qbt_ready() {
  local i=0
  local qbt_base_url="http://${qbt_host}:${qbt_port}"
  while [ "$i" -lt 120 ]; do
    if curl -fsS -o /dev/null "$qbt_base_url"; then
      return 0
    fi
    i="$((i + 1))"
    sleep 2
  done
  return 1
}

qbt_login() {
  local qbt_api_url="http://${qbt_host}:${qbt_port}/api/v2"
  local body
  body="$(
    curl -fsS \
      -H "Referer: http://${qbt_host}:${qbt_port}" \
      --data-urlencode "username=$qbt_username" \
      --data-urlencode "password=$qbt_password" \
      "$qbt_api_url/auth/login" \
      -c "$qbt_cookie_file" || true
  )"
  [ "$(printf '%s' "$body" | tr -d '\r\n')" = "Ok." ]
}

ensure_qbit_category_path() {
  local category="$1" save_path="$2"
  local qbt_api_url="http://${qbt_host}:${qbt_port}/api/v2"
  curl -fsS -o /dev/null \
    -H "Referer: http://${qbt_host}:${qbt_port}" \
    -b "$qbt_cookie_file" \
    --data-urlencode "category=$category" \
    --data-urlencode "savePath=$save_path" \
    "$qbt_api_url/torrents/createCategory" || true
  curl -fsS -o /dev/null \
    -H "Referer: http://${qbt_host}:${qbt_port}" \
    -b "$qbt_cookie_file" \
    --data-urlencode "category=$category" \
    --data-urlencode "savePath=$save_path" \
    "$qbt_api_url/torrents/editCategory"
}

ensure_root_folder() {
  local folders
  folders="$(api_call GET "rootfolder")"
  if printf '%s' "$folders" | jq -e '.[] | (.path | rtrimstr("/")) == "/media/music"' >/dev/null; then
    log "Root folder already configured: /media/music"
    return 0
  fi

  api_call POST "rootfolder" '{"path":"/media/music"}' >/dev/null
  log "Root folder configured: /media/music"
}

build_qbit_fields() {
  local schema="$1"
  jq -c \
    --arg host "$qbt_host" \
    --argjson port "$qbt_port" \
    --arg username "$qbt_username" \
    --arg password "$qbt_password" \
    --arg category "lidarr" \
    '
      (.fields // []) | map(
        if .name == "host" then .value = $host
        elif .name == "port" then .value = $port
        elif .name == "useSsl" then .value = false
        elif .name == "urlBase" then .value = ""
        elif .name == "username" then .value = $username
        elif .name == "password" then .value = $password
        elif .name == "category" or .name == "movieCategory" or .name == "tvCategory" or .name == "musicCategory" then .value = $category
        else .
        end
      )
    ' <<<"$schema"
}

ensure_download_client() {
  local schemas qb_schema fields existing payload contract

  schemas="$(api_call GET "downloadclient/schema")"
  qb_schema="$(printf '%s' "$schemas" | jq -c '.[] | select((.implementation // "" | ascii_downcase) == "qbittorrent")' | head -n1)"
  [ -n "$qb_schema" ] || { log "qBittorrent schema not found in Lidarr"; return 1; }

  fields="$(build_qbit_fields "$qb_schema")"
  contract="$(printf '%s' "$qb_schema" | jq -r '.configContract // empty')"

  payload="$({
    jq -cn \
      --arg implementation "$(printf '%s' "$qb_schema" | jq -r '.implementation')" \
      --arg configContract "$contract" \
      --argjson fields "$fields" \
      '{
        enable: true,
        name: "qBittorrent",
        implementation: $implementation,
        protocol: "torrent",
        priority: 1,
        removeCompletedDownloads: false,
        removeFailedDownloads: false,
        fields: $fields
      } + (if $configContract == "" then {} else { configContract: $configContract } end)'
  })"

  existing="$(api_call GET "downloadclient" | jq -c '.[] | select((.implementation // "" | ascii_downcase) == "qbittorrent")' | head -n1)"

  if [ -z "$existing" ]; then
    api_call POST "downloadclient" "$payload" >/dev/null
    log "Configured qBittorrent download client"
    return 0
  fi

  payload="$(jq -c \
    --argjson fields "$fields" \
    '.
      | .enable = true
      | .name = "qBittorrent"
      | .fields = $fields
    ' <<<"$existing")"
  api_call PUT "downloadclient/$(printf '%s' "$existing" | jq -r '.id')" "$payload" >/dev/null
  log "Updated qBittorrent download client"
}

verify_download_client() {
  if api_call GET "downloadclient" | jq -e '
    [
      .[] | select(
        ((.implementation // "" | ascii_downcase) == "qbittorrent")
        and (.enable == true)
      )
    ] | length > 0
  ' >/dev/null; then
    log "Verified qBittorrent download client in Lidarr"
    return 0
  fi

  log "qBittorrent download client not configured in Lidarr"
  return 1
}

enable_completed_download_handling() {
  local cfg updated
  cfg="$(api_call GET "config/downloadClient" || true)"
  [ -n "$cfg" ] || return 0

  updated="$(printf '%s' "$cfg" | jq -c 'if has("enableCompletedDownloadHandling") then .enableCompletedDownloadHandling = true else . end')"
  put_config "config/downloadClient" "$cfg" "$updated" >/dev/null || true
}

synchronize_api_key() {
  local desired_api_key escaped
  desired_api_key="${LIDARR_API_KEY:-}"
  [ -n "$desired_api_key" ] || return 0

  if [ "$lidarr_api_key" = "$desired_api_key" ]; then
    return 0
  fi

  escaped="$(printf '%s' "$desired_api_key" | sed 's/[&|]/\\&/g')"
  if ! grep -q "<ApiKey>" "$config_xml"; then
    log "Cannot synchronize Lidarr API key: <ApiKey> tag missing in $config_xml"
    return 1
  fi

  sed -i "s|<ApiKey>[^<]*</ApiKey>|<ApiKey>${escaped}</ApiKey>|g" "$config_xml"
  systemctl restart lidarr.service
  lidarr_api_key="$desired_api_key"
  wait_api_ready || { log "Lidarr API did not become ready after API key synchronization"; return 1; }
  log "Synchronized Lidarr API key with shared secret"
}

if ! systemctl start lidarr-credentials.service; then
  log "lidarr-credentials.service start failed; using existing /run/lidarr-bootstrap.env if present"
fi
# shellcheck disable=SC1091
. /run/lidarr-bootstrap.env

qbt_host="${LIDARR_QBITTORRENT_HOST:-192.168.68.26}"
qbt_port="${LIDARR_QBITTORRENT_PORT:-8080}"
qbt_username="${LIDARR_QBITTORRENT_USERNAME:-}"
qbt_password="${LIDARR_QBITTORRENT_PASSWORD:-}"
qbt_cookie_file="$(mktemp)"
trap 'rm -f "$qbt_cookie_file"' EXIT

[ -n "$qbt_username" ] && [ -n "$qbt_password" ] || { log "Missing qBittorrent credentials"; exit 1; }

lidarr_api_key="$(wait_for_file_value "$config_xml" "ApiKey" || true)"
[ -n "$lidarr_api_key" ] || { log "Lidarr API key not found in $config_xml"; exit 1; }

wait_api_ready || { log "Lidarr API did not become ready in time"; exit 1; }
synchronize_api_key
wait_qbt_ready || { log "qBittorrent did not become ready in time"; exit 1; }
qbt_login || { log "Failed to authenticate to qBittorrent"; exit 1; }
ensure_qbit_category_path "lidarr" "/media/downloads/lidarr" || log "Warning: could not set qBittorrent category path for lidarr; continuing"

ensure_root_folder
ensure_download_client
verify_download_client
enable_completed_download_handling

log "Bootstrap completed"
