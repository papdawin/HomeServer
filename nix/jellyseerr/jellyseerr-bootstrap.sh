#!/usr/bin/env bash
set -euo pipefail

# Jellyseerr integrates with Jellyfin + Radarr/Sonarr.
# Prowlarr is wired to Radarr/Sonarr (not directly to Jellyseerr).

base_url="http://127.0.0.1:5055/api/v1"
radarr_config_xml="/media/appdata/radarr/config.xml"
sonarr_config_xml="/media/appdata/sonarr/config.xml"
radarr_host="192.168.68.29"
sonarr_host="192.168.68.30"

log() { printf '[jellyseerr-bootstrap] %s\n' "$*" >&2; }

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
    -H "Content-Type: application/json"
  )
  if [ -n "$data" ]; then
    args+=( --data "$data" )
  fi
  curl "${args[@]}" "$base_url/$endpoint"
}

wait_ready() {
  local i=0
  while [ "$i" -lt 180 ]; do
    if curl -fsS "http://127.0.0.1:5055/api/v1/status" >/dev/null 2>&1; then
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

is_initialized() {
  local public
  public="$(curl -fsS "$base_url/settings/public" || true)"
  [ "$(printf '%s' "$public" | jq -r '.initialized // false')" = "true" ]
}

pick_availability() {
  local test_json
  test_json="$1"
  if printf '%s' "$test_json" | jq -e '.minimumAvailabilityOptions? | type == "array" and (.minimumAvailabilityOptions | length > 0)' >/dev/null 2>&1; then
    printf '%s' "$test_json" | jq -r '.minimumAvailabilityOptions[0].id // .minimumAvailabilityOptions[0].name // "released"'
  else
    printf 'released'
  fi
}

upsert_radarr() {
  local test_json existing radarr_id profile_id profile_name min_avail payload

  test_json="$(api_call POST "settings/radarr/test" "{\"hostname\":\"$radarr_host\",\"port\":7878,\"apiKey\":\"$radarr_api_key\",\"useSsl\":false,\"baseUrl\":\"\"}")"
  profile_id="$(printf '%s' "$test_json" | jq -r '.profiles[0].id // empty')"
  profile_name="$(printf '%s' "$test_json" | jq -r '.profiles[0].name // empty')"
  [ -n "$profile_id" ] && [ -n "$profile_name" ] || { log "Unable to detect Radarr profile"; return 1; }

  min_avail="$(pick_availability "$test_json")"

  payload="$(jq -cn \
    --arg host "$radarr_host" \
    --arg apiKey "$radarr_api_key" \
    --arg profileName "$profile_name" \
    --arg activeDirectory "/media/movies" \
    --arg minimumAvailability "$min_avail" \
    --argjson activeProfileId "$profile_id" \
    '{
      name: "Radarr",
      hostname: $host,
      port: 7878,
      apiKey: $apiKey,
      useSsl: false,
      baseUrl: "",
      activeProfileId: $activeProfileId,
      activeProfileName: $profileName,
      activeDirectory: $activeDirectory,
      is4k: false,
      minimumAvailability: $minimumAvailability,
      isDefault: true,
      syncEnabled: true,
      preventSearch: false
    }')"

  existing="$(api_call GET "settings/radarr" | jq -c '.[] | select(.is4k == false) | .id' | head -n1)"
  if [ -z "$existing" ]; then
    api_call POST "settings/radarr" "$payload" >/dev/null
    log "Configured Radarr service in Jellyseerr"
    return 0
  fi

  radarr_id="$(printf '%s' "$existing" | tr -d '\n')"
  api_call PUT "settings/radarr/$radarr_id" "$payload" >/dev/null
  log "Updated Radarr service in Jellyseerr"
}

upsert_sonarr() {
  local test_json existing sonarr_id profile_id profile_name language_profile_id payload

  test_json="$(api_call POST "settings/sonarr/test" "{\"hostname\":\"$sonarr_host\",\"port\":8989,\"apiKey\":\"$sonarr_api_key\",\"useSsl\":false,\"baseUrl\":\"\"}")"
  profile_id="$(printf '%s' "$test_json" | jq -r '.profiles[0].id // empty')"
  profile_name="$(printf '%s' "$test_json" | jq -r '.profiles[0].name // empty')"
  language_profile_id="$(printf '%s' "$test_json" | jq -r '.languageProfiles[0].id // 1')"
  [ -n "$profile_id" ] && [ -n "$profile_name" ] || { log "Unable to detect Sonarr profile"; return 1; }

  payload="$(jq -cn \
    --arg host "$sonarr_host" \
    --arg apiKey "$sonarr_api_key" \
    --arg profileName "$profile_name" \
    --arg activeDirectory "/media/shows" \
    --argjson activeProfileId "$profile_id" \
    --argjson activeLanguageProfileId "$language_profile_id" \
    '{
      name: "Sonarr",
      hostname: $host,
      port: 8989,
      apiKey: $apiKey,
      useSsl: false,
      baseUrl: "",
      activeProfileId: $activeProfileId,
      activeProfileName: $profileName,
      activeDirectory: $activeDirectory,
      activeLanguageProfileId: $activeLanguageProfileId,
      is4k: false,
      enableSeasonFolders: true,
      isDefault: true,
      syncEnabled: true,
      preventSearch: false
    }')"

  existing="$(api_call GET "settings/sonarr" | jq -c '.[] | select(.is4k == false) | .id' | head -n1)"
  if [ -z "$existing" ]; then
    api_call POST "settings/sonarr" "$payload" >/dev/null
    log "Configured Sonarr service in Jellyseerr"
    return 0
  fi

  sonarr_id="$(printf '%s' "$existing" | tr -d '\n')"
  api_call PUT "settings/sonarr/$sonarr_id" "$payload" >/dev/null
  log "Updated Sonarr service in Jellyseerr"
}

configure_jellyfin() {
  local payload libraries library_ids

  payload="$(jq -cn \
    --arg host "http://${JELLYSEERR_JELLYFIN_HOST}:${JELLYSEERR_JELLYFIN_PORT}" \
    --arg user "$JELLYSEERR_JELLYFIN_USERNAME" \
    --arg pass "$JELLYSEERR_JELLYFIN_PASSWORD" \
    '{
      hostname: $host,
      externalHostname: $host,
      adminUser: $user,
      adminPass: $pass
    }')"

  api_call POST "settings/jellyfin" "$payload" >/dev/null

  libraries="$(api_call GET "settings/jellyfin/library?sync=true" || true)"
  library_ids="$(printf '%s' "$libraries" | jq -r '.[].id' 2>/dev/null | paste -sd, -)"
  if [ -n "$library_ids" ]; then
    api_call GET "settings/jellyfin/library?enable=$library_ids" >/dev/null || true
  fi

  log "Configured Jellyfin service in Jellyseerr"
}

systemctl start jellyseerr-credentials.service
# shellcheck disable=SC1091
. /run/jellyseerr-bootstrap.env

wait_ready || { log "Jellyseerr did not become ready in time"; exit 1; }

if is_initialized; then
  log "Jellyseerr already initialized; skipping bootstrap"
  exit 0
fi

radarr_api_key="$(wait_for_file_value "$radarr_config_xml" "ApiKey" || true)"
sonarr_api_key="$(wait_for_file_value "$sonarr_config_xml" "ApiKey" || true)"

[ -n "$radarr_api_key" ] || { log "Radarr API key not found in $radarr_config_xml"; exit 1; }
[ -n "$sonarr_api_key" ] || { log "Sonarr API key not found in $sonarr_config_xml"; exit 1; }

wait_arr "$radarr_host" 7878 "$radarr_api_key" || { log "Radarr did not become ready in time"; exit 1; }
wait_arr "$sonarr_host" 8989 "$sonarr_api_key" || { log "Sonarr did not become ready in time"; exit 1; }

configure_jellyfin
upsert_radarr
upsert_sonarr
api_call POST "settings/initialize" '{}' >/dev/null || true

log "Bootstrap completed"
