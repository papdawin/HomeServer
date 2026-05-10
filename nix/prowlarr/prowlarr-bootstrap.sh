#!/usr/bin/env bash
set -euo pipefail

base_url="http://127.0.0.1:9696"
api_url="$base_url/api/v1"
prowlarr_config_xml="/appdata/prowlarr/config.xml"
radarr_config_xml="/appdata/radarr/config.xml"
sonarr_config_xml="/appdata/sonarr/config.xml"
radarr_legacy_config_xml="/media/appdata/radarr/config.xml"
sonarr_legacy_config_xml="/media/appdata/sonarr/config.xml"
prowlarr_url="http://192.168.68.31:9696"
radarr_host="192.168.68.29"
radarr_port="7878"
sonarr_host="192.168.68.30"
sonarr_port="8989"

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

wait_for_file_value_candidates() {
  local tag="$1" value="" file
  shift
  local i=0
  while [ "$i" -lt 180 ]; do
    for file in "$@"; do
      [ -f "$file" ] || continue
      value="$(xml_value "$file" "$tag" || true)"
      if [ -n "$value" ]; then
        printf '%s' "$value"
        return 0
      fi
    done
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

api_status_code() {
  local endpoint="$1"
  curl -sS -o /dev/null -w '%{http_code}' \
    -H "X-Api-Key: $prowlarr_api_key" \
    "$api_url/$endpoint" || true
}

resolve_application_collection_endpoint() {
  if [ "$(api_status_code "application/schema")" = "200" ]; then
    printf '%s' "application"
    return 0
  fi
  if [ "$(api_status_code "applications/schema")" = "200" ]; then
    printf '%s' "applications"
    return 0
  fi
  log "Neither /application/schema nor /applications/schema is available"
  return 1
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

radarr_api_call() {
  local method="$1" endpoint="$2" data="${3:-}"
  local -a args=(
    -fsS
    -X "$method"
    -H "X-Api-Key: $radarr_api_key"
  )
  if [ -n "$data" ]; then
    args+=( -H "Content-Type: application/json" --data "$data" )
  fi
  curl "${args[@]}" "http://${radarr_host}:${radarr_port}/api/v3/$endpoint"
}

radarr_has_ncore_indexer() {
  radarr_api_call GET "indexer" | jq -e '
    [
      .[] | select(
        ((.name // "" | ascii_downcase) | contains("ncore"))
      )
    ] | length > 0
  ' >/dev/null
}

wait_radarr_ncore_indexer() {
  local i=0
  while [ "$i" -lt 90 ]; do
    if radarr_has_ncore_indexer; then
      log "Verified nCore indexer synced to Radarr"
      return 0
    fi
    i="$((i + 1))"
    sleep 2
  done

  log "nCore indexer not visible in Radarr after waiting"
  radarr_api_call GET "indexer" | jq -r '.[] | .name // empty' | sed 's/^/[prowlarr-bootstrap] Radarr indexer: /' >&2 || true
  return 1
}

build_app_fields() {
  local schema="$1" host="$2" port="$3" api_key="$4"
  jq -c \
    --arg host "$host" \
    --argjson port "$port" \
    --arg baseUrl "http://${host}:${port}" \
    --arg apiKey "$api_key" \
    --arg prowlarrUrl "$prowlarr_url" \
    '
      (.fields // []) | map(
        if .name == "prowlarrUrl" then .value = $prowlarrUrl
        elif .name == "baseUrl" then .value = $baseUrl
        elif .name == "url" then .value = $baseUrl
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
  local schemas schema contract fields payload existing existing_id collection_endpoint

  collection_endpoint="${application_collection_endpoint:-}"
  [ -n "$collection_endpoint" ] || { log "Application collection endpoint is not resolved"; return 1; }

  schemas="$(api_call GET "$collection_endpoint/schema")"
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

  existing="$(api_call GET "$collection_endpoint" | jq -c --arg app_type "$app_type" '.[] | select((.implementation // "" | ascii_downcase) == ($app_type | ascii_downcase))' | head -n1)"

  if [ -z "$existing" ]; then
    api_call POST "$collection_endpoint" "$payload" >/dev/null
    log "Configured $app_type application"
    return 0
  fi

  existing_id="$(printf '%s' "$existing" | jq -r '.id')"
  payload="$(jq -c --argjson fields "$fields" --arg name "$app_type" '. | .enable = true | .name = $name | .syncLevel = "fullSync" | .fields = $fields' <<<"$existing")"
  api_call PUT "$collection_endpoint/$existing_id" "$payload" >/dev/null
  log "Updated $app_type application"
}

get_default_app_profile_id() {
  local app_profile_id
  app_profile_id="$(
    api_call GET "appprofile" | jq -r '
      [ .[] | .id // 0 | select(. > 0) ][0] // empty
    '
  )"
  [ -n "$app_profile_id" ] || { log "No valid app profile id returned by /appprofile"; return 1; }
  printf '%s' "$app_profile_id"
}

build_ncore_fields() {
  local schema="$1" username="$2" password="$3"
  local schema_definition_file
  schema_definition_file="$(
    printf '%s' "$schema" | jq -r '
      ((.fields // []) | map(select((.name // "" | ascii_downcase) == "definitionfile")) | .[0].value) // empty
    '
  )"

  jq -c \
    --arg username "$username" \
    --arg password "$password" \
    --arg schemaDefinitionFile "$schema_definition_file" \
    '
      (.fields // []) | map(
        if (.name // "" | ascii_downcase) == "username" then .value = $username
        elif (.name // "" | ascii_downcase) == "password" then .value = $password
        elif (.name // "" | ascii_downcase) == "definitionfile" then
          .value = (
            if ($schemaDefinitionFile | length) > 0 then $schemaDefinitionFile
            elif ((.value // "" | tostring | length) > 0) then (.value | tostring)
            else "ncore"
            end
          )
        else .
        end
      )
    ' <<<"$schema"
}

upsert_ncore_indexer() {
  local schemas schema fields existing existing_id implementation contract protocol payload app_profile_id

  if [ -z "${ncore_username:-}" ] || [ -z "${ncore_password:-}" ]; then
    log "Skipping nCore indexer bootstrap: missing PROWLARR_NCORE_USERNAME/PROWLARR_NCORE_PASSWORD"
    return 0
  fi

  app_profile_id="$(get_default_app_profile_id)" || return 1

  schemas="$(api_call GET "indexer/schema")"
  schema="$(
    printf '%s' "$schemas" | jq -c '
      .[] | select(
        ((.implementation // "" | ascii_downcase) == "ncore")
        or ((.name // "" | ascii_downcase) == "ncore")
        or ((.implementationName // "" | ascii_downcase) == "ncore")
        or (
          ((.fields // []) | map(
            select(
              (.name // "" | ascii_downcase) == "definitionfile"
              and ((.value // "" | tostring | ascii_downcase) | contains("ncore"))
            )
          ) | length) > 0
        )
      )
    ' | head -n1
  )"

  if [ -z "$schema" ]; then
    schema="$(
      printf '%s' "$schemas" | jq -c '
        .[] | select(
          (.implementation // "" | ascii_downcase) == "cardigann"
          and ((.fields // []) | map(select((.name // "" | ascii_downcase) == "definitionfile")) | length) > 0
        )
      ' | head -n1
    )"
  fi

  [ -n "$schema" ] || { log "Schema not found for nCore indexer"; return 1; }

  fields="$(build_ncore_fields "$schema" "$ncore_username" "$ncore_password")"
  implementation="$(printf '%s' "$schema" | jq -r '.implementation')"
  contract="$(printf '%s' "$schema" | jq -r '.configContract // empty')"
  protocol="$(printf '%s' "$schema" | jq -r '.protocol // "torrent"')"

  existing="$(
    api_call GET "indexer" | jq -c '
      .[] | select(
        ((.implementation // "" | ascii_downcase) == "ncore")
        or ((.name // "" | ascii_downcase) | contains("ncore"))
        or (
          ((.fields // []) | map(
            select(
              (.name // "" | ascii_downcase) == "definitionfile"
              and ((.value // "" | tostring | ascii_downcase) | contains("ncore"))
            )
          ) | length) > 0
        )
      )
    ' | head -n1
  )"

  if [ -z "$existing" ]; then
    payload="$(
      jq -cn \
        --arg name "nCore" \
        --arg implementation "$implementation" \
        --arg configContract "$contract" \
        --arg protocol "$protocol" \
        --argjson appProfileId "$app_profile_id" \
        --argjson fields "$fields" \
        '{
          name: $name,
          enable: true,
          priority: 25,
          appProfileId: $appProfileId,
          implementation: $implementation,
          fields: $fields,
          tags: []
        }
        + (if $configContract == "" then {} else { configContract: $configContract } end)
        + { protocol: $protocol }'
    )"
    api_call POST "indexer" "$payload" >/dev/null
    log "Configured nCore indexer"
    return 0
  fi

  existing_id="$(printf '%s' "$existing" | jq -r '.id')"
  payload="$(jq -c --argjson fields "$fields" --argjson appProfileId "$app_profile_id" '. | .enable = true | .name = "nCore" | .appProfileId = $appProfileId | .fields = $fields' <<<"$existing")"
  api_call PUT "indexer/$existing_id" "$payload" >/dev/null
  log "Updated nCore indexer"
}

verify_ncore_indexer_present() {
  if api_call GET "indexer" | jq -e '
    [
      .[] | select(
        ((.implementation // "" | ascii_downcase) == "ncore")
        or ((.name // "" | ascii_downcase) | contains("ncore"))
        or (
          ((.fields // []) | map(
            select(
              (.name // "" | ascii_downcase) == "definitionfile"
              and ((.value // "" | tostring | ascii_downcase) | contains("ncore"))
            )
          ) | length) > 0
        )
      )
    ] | length > 0
  ' >/dev/null; then
    log "Verified nCore indexer is present"
    return 0
  fi

  log "nCore indexer is still missing after bootstrap"
  return 1
}

if ! systemctl start prowlarr-credentials.service; then
  log "prowlarr-credentials.service start failed; using existing /run/prowlarr-bootstrap.env if present"
fi
[ -f /run/prowlarr-bootstrap.env ] && . /run/prowlarr-bootstrap.env

ncore_username="${PROWLARR_NCORE_USERNAME:-}"
ncore_password="${PROWLARR_NCORE_PASSWORD:-}"
prowlarr_url="${PROWLARR_URL:-$prowlarr_url}"
radarr_host="${PROWLARR_RADARR_HOST:-$radarr_host}"
radarr_port="${PROWLARR_RADARR_PORT:-$radarr_port}"
sonarr_host="${PROWLARR_SONARR_HOST:-$sonarr_host}"
sonarr_port="${PROWLARR_SONARR_PORT:-$sonarr_port}"

prowlarr_api_key="$(wait_for_file_value "$prowlarr_config_xml" "ApiKey" || true)"
[ -n "$prowlarr_api_key" ] || { log "Prowlarr API key not found in $prowlarr_config_xml"; exit 1; }

radarr_api_key="${PROWLARR_RADARR_API_KEY:-}"
sonarr_api_key="${PROWLARR_SONARR_API_KEY:-}"
[ -n "$radarr_api_key" ] || radarr_api_key="$(wait_for_file_value_candidates "ApiKey" "$radarr_config_xml" "$radarr_legacy_config_xml" || true)"
[ -n "$sonarr_api_key" ] || sonarr_api_key="$(wait_for_file_value_candidates "ApiKey" "$sonarr_config_xml" "$sonarr_legacy_config_xml" || true)"
[ -n "$radarr_api_key" ] || { log "Radarr API key missing; set PROWLARR_RADARR_API_KEY (fallback paths: $radarr_config_xml, $radarr_legacy_config_xml)"; exit 1; }
[ -n "$sonarr_api_key" ] || { log "Sonarr API key missing; set PROWLARR_SONARR_API_KEY (fallback paths: $sonarr_config_xml, $sonarr_legacy_config_xml)"; exit 1; }

wait_api_ready || { log "Prowlarr API did not become ready in time"; exit 1; }
application_collection_endpoint="$(resolve_application_collection_endpoint)" || { log "Failed to resolve Prowlarr application endpoint"; exit 1; }
wait_arr "$radarr_host" "$radarr_port" "$radarr_api_key" || { log "Radarr did not become ready in time"; exit 1; }
wait_arr "$sonarr_host" "$sonarr_port" "$sonarr_api_key" || { log "Sonarr did not become ready in time"; exit 1; }

upsert_application "Radarr" "$radarr_host" "$radarr_port" "$radarr_api_key"
upsert_application "Sonarr" "$sonarr_host" "$sonarr_port" "$sonarr_api_key"
upsert_ncore_indexer
verify_ncore_indexer_present
wait_radarr_ncore_indexer

log "Bootstrap completed"
