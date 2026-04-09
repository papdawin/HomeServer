#!/usr/bin/env bash
set -euo pipefail

base_url="http://127.0.0.1:7878"
api_url="$base_url/api/v3"
config_xml="/media/appdata/radarr/config.xml"

log() { printf '[radarr-bootstrap] %s\n' "$*" >&2; }

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
    -H "X-Api-Key: $radarr_api_key"
  )
  if [ -n "$data" ]; then
    args+=( -H "Content-Type: application/json" --data "$data" )
  fi
  curl "${args[@]}" "$api_url/$endpoint"
}

wait_api_ready() {
  local i=0
  while [ "$i" -lt 180 ]; do
    if curl -fsS -H "X-Api-Key: $radarr_api_key" "$api_url/system/status" >/dev/null 2>&1; then
      return 0
    fi
    i="$((i + 1))"
    sleep 2
  done
  return 1
}

ensure_root_folder() {
  local folders
  folders="$(api_call GET "rootfolder")"
  if printf '%s' "$folders" | jq -e '.[] | (.path | rtrimstr("/")) == "/media/movies"' >/dev/null; then
    log "Root folder already configured: /media/movies"
    return 0
  fi

  api_call POST "rootfolder" '{"path":"/media/movies"}' >/dev/null
  log "Root folder configured: /media/movies"
}

build_qbit_fields() {
  local schema="$1"
  jq -c \
    --arg host "$qbt_host" \
    --argjson port "$qbt_port" \
    --arg username "$qbt_username" \
    --arg password "$qbt_password" \
    --arg category "radarr" \
    '
      (.fields // []) | map(
        if .name == "host" then .value = $host
        elif .name == "port" then .value = $port
        elif .name == "useSsl" then .value = false
        elif .name == "urlBase" then .value = ""
        elif .name == "username" then .value = $username
        elif .name == "password" then .value = $password
        elif .name == "category" or .name == "movieCategory" or .name == "tvCategory" then .value = $category
        else .
        end
      )
    ' <<<"$schema"
}

ensure_download_client() {
  local schemas qb_schema fields existing payload contract

  schemas="$(api_call GET "downloadclient/schema")"
  qb_schema="$(printf '%s' "$schemas" | jq -c '.[] | select((.implementation // "" | ascii_downcase) == "qbittorrent")' | head -n1)"
  [ -n "$qb_schema" ] || { log "qBittorrent schema not found in Radarr"; return 1; }

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

enable_completed_download_handling() {
  local cfg updated
  cfg="$(api_call GET "config/downloadClient" || true)"
  [ -n "$cfg" ] || return 0

  updated="$(printf '%s' "$cfg" | jq -c 'if has("enableCompletedDownloadHandling") then .enableCompletedDownloadHandling = true else . end')"
  api_call PUT "config/downloadClient" "$updated" >/dev/null || true
}

systemctl start radarr-credentials.service
# shellcheck disable=SC1091
. /run/radarr-bootstrap.env

qbt_host="${RADARR_QBITTORRENT_HOST:-192.168.68.26}"
qbt_port="${RADARR_QBITTORRENT_PORT:-8080}"
qbt_username="${RADARR_QBITTORRENT_USERNAME:-}"
qbt_password="${RADARR_QBITTORRENT_PASSWORD:-}"

[ -n "$qbt_username" ] && [ -n "$qbt_password" ] || { log "Missing qBittorrent credentials"; exit 1; }

radarr_api_key="$(wait_for_file_value "$config_xml" "ApiKey" || true)"
[ -n "$radarr_api_key" ] || { log "Radarr API key not found in $config_xml"; exit 1; }

wait_api_ready || { log "Radarr API did not become ready in time"; exit 1; }

ensure_root_folder
ensure_download_client
enable_completed_download_handling

log "Bootstrap completed"
