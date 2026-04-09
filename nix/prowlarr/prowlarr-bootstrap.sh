#!/usr/bin/env bash
set -euo pipefail

base_url="http://127.0.0.1:9696"
api_url="$base_url/api/v1"
prowlarr_config_xml="/media/appdata/prowlarr/config.xml"
radarr_config_xml="/media/appdata/radarr/config.xml"
sonarr_config_xml="/media/appdata/sonarr/config.xml"
prowlarr_url="http://192.168.68.31:9696"
radarr_host="192.168.68.29"
sonarr_host="192.168.68.30"

log() { printf '[prowlarr-bootstrap] %s\n' "$*" >&2; }

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
    -H "X-Api-Key: $prowlarr_api_key"
  )
  if [ -n "$data" ]; then
    args+=( -H "Content-Type: application/json" --data "$data" )
  fi
  curl "${args[@]}" "$api_url/$endpoint"
}

wait_api_ready() {
  local i=0
  while [ "$i" -lt 180 ]; do
    if curl -fsS -H "X-Api-Key: $prowlarr_api_key" "$api_url/system/status" >/dev/null 2>&1; then
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

build_app_fields() {
  local schema="$1" host="$2" port="$3" api_key="$4"
  jq -c \
    --arg host "$host" \
    --argjson port "$port" \
    --arg apiKey "$api_key" \
    --arg prowlarrUrl "$prowlarr_url" \
    '
      (.fields // []) | map(
        if .name == "prowlarrUrl" then .value = $prowlarrUrl
        elif .name == "baseUrl" then .value = ""
        elif .name == "host" then .value = $host
        elif .name == "port" then .value = $port
        elif .name == "apiKey" then .value = $apiKey
        elif .name == "syncLevel" then .value = "fullSync"
        else .
        end
      )
    ' <<<"$schema"
}

upsert_application() {
  local app_type="$1" host="$2" port="$3" api_key="$4"
  local schemas schema contract fields payload existing existing_id

  schemas="$(api_call GET "application/schema")"
  schema="$(printf '%s' "$schemas" | jq -c --arg app_type "$app_type" '.[] | select((.implementation // "" | ascii_downcase) == ($app_type | ascii_downcase))' | head -n1)"
  [ -n "$schema" ] || { log "Schema not found for $app_type"; return 1; }

  fields="$(build_app_fields "$schema" "$host" "$port" "$api_key")"
  contract="$(printf '%s' "$schema" | jq -r '.configContract // empty')"

  payload="$({
    jq -cn \
      --arg implementation "$(printf '%s' "$schema" | jq -r '.implementation')" \
      --arg configContract "$contract" \
      --argjson fields "$fields" \
      --arg name "$app_type" \
      '{
        name: $name,
        enable: true,
        syncLevel: "fullSync",
        implementation: $implementation,
        fields: $fields,
        tags: []
      } + (if $configContract == "" then {} else { configContract: $configContract } end)'
  })"

  existing="$(api_call GET "application" | jq -c --arg app_type "$app_type" '.[] | select((.implementation // "" | ascii_downcase) == ($app_type | ascii_downcase))' | head -n1)"

  if [ -z "$existing" ]; then
    api_call POST "application" "$payload" >/dev/null
    log "Configured $app_type application"
    return 0
  fi

  existing_id="$(printf '%s' "$existing" | jq -r '.id')"
  payload="$(jq -c --argjson fields "$fields" --arg name "$app_type" '. | .enable = true | .name = $name | .syncLevel = "fullSync" | .fields = $fields' <<<"$existing")"
  api_call PUT "application/$existing_id" "$payload" >/dev/null
  log "Updated $app_type application"
}

prowlarr_api_key="$(wait_for_file_value "$prowlarr_config_xml" "ApiKey" || true)"
[ -n "$prowlarr_api_key" ] || { log "Prowlarr API key not found in $prowlarr_config_xml"; exit 1; }

radarr_api_key="$(wait_for_file_value "$radarr_config_xml" "ApiKey" || true)"
sonarr_api_key="$(wait_for_file_value "$sonarr_config_xml" "ApiKey" || true)"
[ -n "$radarr_api_key" ] || { log "Radarr API key not found in $radarr_config_xml"; exit 1; }
[ -n "$sonarr_api_key" ] || { log "Sonarr API key not found in $sonarr_config_xml"; exit 1; }

wait_api_ready || { log "Prowlarr API did not become ready in time"; exit 1; }
wait_arr "$radarr_host" 7878 "$radarr_api_key" || { log "Radarr did not become ready in time"; exit 1; }
wait_arr "$sonarr_host" 8989 "$sonarr_api_key" || { log "Sonarr did not become ready in time"; exit 1; }

upsert_application "Radarr" "$radarr_host" 7878 "$radarr_api_key"
upsert_application "Sonarr" "$sonarr_host" 8989 "$sonarr_api_key"

log "Bootstrap completed"
