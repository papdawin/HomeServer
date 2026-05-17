#!/usr/bin/env bash
set -euo pipefail

# Jellyseerr integrates with Jellyfin + Radarr/Sonarr.
# Prowlarr is wired to Radarr/Sonarr (not directly to Jellyseerr).

base_url="http://127.0.0.1:5055/api/v1"
radarr_host="192.168.68.29"
sonarr_host="192.168.68.30"
radarr_active_directory="/media/downloads/radarr"
sonarr_active_directory="/media/downloads/sonarr"
cookie_file=""

log() { printf '[jellyseerr-bootstrap] %s\n' "$*" >&2; }

cleanup() {
  if [ -n "${cookie_file:-}" ] && [ -f "$cookie_file" ]; then
    rm -f "$cookie_file"
  fi
}
trap cleanup EXIT

is_ipv4() {
  case "${1:-}" in
    *[!0-9.]*|"") return 1 ;;
  esac

  local old_ifs="$IFS" octet
  IFS='.'
  # shellcheck disable=SC2086
  set -- $1
  IFS="$old_ifs"
  [ "$#" -eq 4 ] || return 1

  for octet in "$@"; do
    [ -n "$octet" ] || return 1
    [ "$octet" -ge 0 ] 2>/dev/null || return 1
    [ "$octet" -le 255 ] 2>/dev/null || return 1
  done
}

jellyfin_base_url() {
  local host port alias
  host="${JELLYSEERR_JELLYFIN_HOST:-}"
  port="${JELLYSEERR_JELLYFIN_PORT:-8096}"

  if is_ipv4 "$host"; then
    alias="jellyfin.home.arpa"
    if [ -w /etc/hosts ] && ! grep -Eq "[[:space:]]${alias}([[:space:]]|$)" /etc/hosts; then
      printf '%s %s\n' "$host" "$alias" >> /etc/hosts
      log "Added /etc/hosts alias for Jellyfin auth: $alias -> $host"
    fi
    host="$alias"
  fi

  printf 'http://%s:%s' "$host" "$port"
}

normalize_host_port() {
  local input="$1" default_port="$2" hostport host port

  hostport="${input#http://}"
  hostport="${hostport#https://}"
  hostport="${hostport%%/*}"
  [ -n "$hostport" ] || return 1

  host="$hostport"
  port="$default_port"
  if [ "${hostport#*:}" != "$hostport" ]; then
    host="${hostport%%:*}"
    port="${hostport##*:}"
  fi

  [ -n "$host" ] || return 1
  [ -n "$port" ] || return 1
  [ "$port" -ge 1 ] 2>/dev/null || return 1
  [ "$port" -le 65535 ] 2>/dev/null || return 1

  printf '%s %s' "$host" "$port"
}

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
  if [ -n "${cookie_file:-}" ] && [ -f "$cookie_file" ]; then
    args+=( -b "$cookie_file" -c "$cookie_file" )
  fi
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
    --arg activeDirectory "$radarr_active_directory" \
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
    --arg activeDirectory "$sonarr_active_directory" \
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

is_radarr_configured() {
  local count
  count="$(api_call GET "settings/radarr" | jq -r --arg host "$radarr_host" --arg activeDirectory "$radarr_active_directory" '
    [
      .[]
      | select((.is4k // false) == false)
      | select((.hostname // "") == $host)
      | select((.port // 0) == 7878)
      | select((.activeDirectory // "" | rtrimstr("/")) == ($activeDirectory | rtrimstr("/")))
    ] | length
  ')"
  [ "$count" -ge 1 ] 2>/dev/null
}

is_sonarr_configured() {
  local count
  count="$(api_call GET "settings/sonarr" | jq -r --arg host "$sonarr_host" --arg activeDirectory "$sonarr_active_directory" '
    [
      .[]
      | select((.is4k // false) == false)
      | select((.hostname // "") == $host)
      | select((.port // 0) == 8989)
      | select((.activeDirectory // "" | rtrimstr("/")) == ($activeDirectory | rtrimstr("/")))
    ] | length
  ')"
  [ "$count" -ge 1 ] 2>/dev/null
}

ensure_arr_services() {
  local i=0
  while [ "$i" -lt 3 ]; do
    upsert_radarr
    upsert_sonarr

    if is_radarr_configured && is_sonarr_configured; then
      log "Verified Radarr and Sonarr services in Jellyseerr"
      return 0
    fi

    i="$((i + 1))"
    sleep 2
  done

  log "Radarr/Sonarr services not visible in Jellyseerr settings after retries"
  return 1
}

configure_jellyfin() {
  local payload libraries library_ids host

  host="$(jellyfin_base_url)"
  payload="$(jq -cn \
    --arg host "$host" \
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

auth_with_jellyfin() {
  local payload code body_file ok configured_host env_host email pair host port server_type

  cookie_file="$(mktemp)"
  body_file="$(mktemp)"
  ok=0
  env_host="$(jellyfin_base_url)"
  email="${JELLYSEERR_BOOTSTRAP_EMAIL:-${JELLYSEERR_BOOTSTRAP_USERNAME:-papdawin}@local.invalid}"

  # When Jellyfin is already configured in Jellyseerr, auth endpoint requires
  # username/password without hostname/port fields.
  payload="$(jq -cn \
    --arg username "$JELLYSEERR_JELLYFIN_USERNAME" \
    --arg password "$JELLYSEERR_JELLYFIN_PASSWORD" \
    '{ username: $username, password: $password }')"
  code="$(
    curl -sS -o "$body_file" -w '%{http_code}' \
      -c "$cookie_file" \
      -b "$cookie_file" \
      -X POST \
      -H "Content-Type: application/json" \
      --data "$payload" \
      "$base_url/auth/jellyfin" || true
  )"
  if [ "$code" = "200" ]; then
    ok=1
    log "Authenticated to Jellyseerr via auth/jellyfin (configured Jellyfin path)"
  fi

  [ "$ok" -eq 1 ] && { rm -f "$body_file"; return 0; }

  configured_host="$(api_call GET "settings/jellyfin" | jq -r '.hostname // empty' 2>/dev/null || true)"

  for pair in \
    "$(normalize_host_port "$configured_host" "${JELLYSEERR_JELLYFIN_PORT:-8096}" || true)" \
    "$(normalize_host_port "$env_host" "${JELLYSEERR_JELLYFIN_PORT:-8096}" || true)" \
    "$(normalize_host_port "${JELLYSEERR_JELLYFIN_HOST:-}" "${JELLYSEERR_JELLYFIN_PORT:-8096}" || true)"
  do
    [ -n "$pair" ] || continue
    host="${pair% *}"
    port="${pair##* }"
    for server_type in 2 3; do
      payload="$(jq -cn \
        --arg username "$JELLYSEERR_JELLYFIN_USERNAME" \
        --arg password "$JELLYSEERR_JELLYFIN_PASSWORD" \
        --arg hostname "$host" \
        --arg email "$email" \
        --arg urlBase "" \
        --argjson port "$port" \
        --argjson useSsl false \
        --argjson serverType "$server_type" \
        '{
          username: $username,
          password: $password,
          hostname: $hostname,
          port: $port,
          useSsl: $useSsl,
          urlBase: $urlBase,
          email: $email,
          serverType: $serverType
        }')"

      code="$(
        curl -sS -o "$body_file" -w '%{http_code}' \
          -c "$cookie_file" \
          -b "$cookie_file" \
          -X POST \
          -H "Content-Type: application/json" \
          --data "$payload" \
          "$base_url/auth/jellyfin" || true
      )"
      if [ "$code" = "200" ]; then
        ok=1
        log "Authenticated to Jellyseerr via auth/jellyfin (serverType=$server_type host=$host port=$port)"
        break 2
      fi
      if [ "$code" = "500" ] && jq -e '.message == "NO_ADMIN_USER"' "$body_file" >/dev/null 2>&1; then
        continue
      fi
    done
  done

  if [ "$ok" -ne 1 ]; then
    log "Jellyseerr Jellyfin auth failed: HTTP $code $(tr '\n' ' ' < "$body_file" | head -c 300)"
  fi
  rm -f "$body_file"

  [ "$ok" -eq 1 ] || { log "Unable to authenticate to Jellyseerr via Jellyfin endpoints"; return 1; }
}

ensure_local_login_enabled() {
  local main_settings payload

  main_settings="$(api_call GET "settings/main")"
  payload="$(printf '%s' "$main_settings" | jq -c 'del(.apiKey) | .localLogin = true')"
  api_call POST "settings/main" "$payload" >/dev/null

  log "Enabled local login in Jellyseerr"
}

ensure_bootstrap_user() {
  local username password email admin_permissions users_json existing_id payload created user_id user_json resolved_email

  username="${JELLYSEERR_BOOTSTRAP_USERNAME:-}"
  password="${JELLYSEERR_BOOTSTRAP_PASSWORD:-}"
  email="${JELLYSEERR_BOOTSTRAP_EMAIL:-${username}@local.invalid}"

  [ -n "$username" ] && [ -n "$password" ] || { log "Missing Jellyseerr bootstrap credentials"; return 1; }

  admin_permissions="$(api_call GET "auth/me" | jq -r '.permissions // 0')"
  if ! [ "$admin_permissions" -ge 0 ] 2>/dev/null; then
    admin_permissions=0
  fi

  users_json="$(api_call GET "user?take=100&skip=0")"
  existing_id="$(
    printf '%s' "$users_json" \
      | jq -r --arg username "$username" --arg email "$email" '
          .results[]?
          | select(
              ((.username // "") | ascii_downcase) == ($username | ascii_downcase)
              or ((.email // "") | ascii_downcase) == ($email | ascii_downcase)
            )
          | .id
        ' \
      | head -n1
  )"

  if [ -z "$existing_id" ]; then
    payload="$(jq -cn \
      --arg username "$username" \
      --arg email "$email" \
      --argjson permissions "$admin_permissions" \
      '{
        username: $username,
        email: $email,
        permissions: $permissions
      }')"
    created="$(api_call POST "user" "$payload")"
    user_id="$(printf '%s' "$created" | jq -r '.id // empty')"
    [ -n "$user_id" ] || { log "Failed to create Jellyseerr local user"; return 1; }
    log "Created Jellyseerr local user $username"
  else
    user_id="$existing_id"
    log "Jellyseerr local user $username already exists"
  fi

  payload="$(jq -cn --arg username "$username" --arg email "$email" '{ username: $username, email: $email }')"
  api_call POST "user/$user_id/settings/main" "$payload" >/dev/null || true

  user_json="$(api_call GET "user/$user_id" 2>/dev/null || true)"
  resolved_email="$(printf '%s' "$user_json" | jq -r '.email // empty' 2>/dev/null || true)"
  [ -n "$resolved_email" ] || resolved_email="$email"

  payload="$(jq -cn --arg newPassword "$password" '{ newPassword: $newPassword }')"
  api_call POST "user/$user_id/settings/password" "$payload" >/dev/null

  payload="$(jq -cn --arg email "$resolved_email" --arg password "$password" '{ email: $email, password: $password }')"
  if [ "$(
    curl -sS -o /tmp/jellyseerr-auth-local.out -w '%{http_code}' \
      -X POST \
      -H "Content-Type: application/json" \
      --data "$payload" \
      "$base_url/auth/local" || true
  )" = "200" ]; then
    log "Verified Jellyseerr local user login via email"
    return 0
  fi

  payload="$(jq -cn --arg email "$username" --arg password "$password" '{ email: $email, password: $password }')"
  if [ "$(
    curl -sS -o /tmp/jellyseerr-auth-local.out -w '%{http_code}' \
      -X POST \
      -H "Content-Type: application/json" \
      --data "$payload" \
      "$base_url/auth/local" || true
  )" = "200" ]; then
    log "Verified Jellyseerr local user login via username fallback"
    return 0
  fi

  log "Unable to verify Jellyseerr local login for $username (email tried: $resolved_email)"
  return 1
}

systemctl start jellyseerr-credentials.service
# shellcheck disable=SC1091
. /run/jellyseerr-bootstrap.env

wait_ready || { log "Jellyseerr did not become ready in time"; exit 1; }

radarr_api_key="${JELLYSEERR_RADARR_API_KEY:-}"
sonarr_api_key="${JELLYSEERR_SONARR_API_KEY:-}"
[ -n "$radarr_api_key" ] || { log "Radarr API key missing; set JELLYSEERR_RADARR_API_KEY"; exit 1; }
[ -n "$sonarr_api_key" ] || { log "Sonarr API key missing; set JELLYSEERR_SONARR_API_KEY"; exit 1; }

wait_arr "$radarr_host" 7878 "$radarr_api_key" || { log "Radarr did not become ready in time"; exit 1; }
wait_arr "$sonarr_host" 8989 "$sonarr_api_key" || { log "Sonarr did not become ready in time"; exit 1; }

auth_with_jellyfin

if ! is_initialized; then
  api_call POST "settings/initialize" '{}' >/dev/null
  log "Initialized Jellyseerr"
fi

is_initialized || { log "Jellyseerr initialize did not stick"; exit 1; }

ensure_local_login_enabled
ensure_bootstrap_user
configure_jellyfin
ensure_arr_services

log "Bootstrap completed"
