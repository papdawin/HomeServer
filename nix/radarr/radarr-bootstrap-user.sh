#!/usr/bin/env bash
set -euo pipefail

base_url="http://127.0.0.1:7878"
api_url="$base_url/api/v3"
radarr_config_xml="/appdata/radarr/config.xml"

log() { printf '[radarr-bootstrap-user] %s\n' "$*" >&2; }

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

login_works() {
  local cookie_file header_file code location
  cookie_file="$(mktemp)"
  header_file="$(mktemp)"

  code="$(
    curl -sS -o /dev/null -D "$header_file" -c "$cookie_file" -w '%{http_code}' \
      -X POST "$base_url/login" \
      -H "Content-Type: application/x-www-form-urlencoded" \
      --data-urlencode "username=$username" \
      --data-urlencode "password=$password" \
      --data "rememberMe=false" || true
  )"
  location="$(sed -n 's/^[Ll]ocation:[[:space:]]*//p' "$header_file" | tr -d '\r' | tail -n1)"

  rm -f "$cookie_file" "$header_file"

  if [ "$code" != "302" ]; then
    return 1
  fi
  case "$location" in
    *loginFailed=true*) return 1 ;;
    *) return 0 ;;
  esac
}

systemctl start radarr-credentials.service
. /run/radarr-bootstrap.env

username="${RADARR_BOOTSTRAP_USERNAME:-}"
password="${RADARR_BOOTSTRAP_PASSWORD:-}"
[ -n "$username" ] && [ -n "$password" ] || { log "Missing bootstrap credentials"; exit 1; }

radarr_api_key="$(wait_for_file_value "$radarr_config_xml" "ApiKey" || true)"
[ -n "$radarr_api_key" ] || { log "Radarr API key not found in $radarr_config_xml"; exit 1; }

wait_api_ready || { log "Radarr API did not become ready in time"; exit 1; }

host_cfg="$(api_call GET "config/host")"
auth_method="$(printf '%s' "$host_cfg" | jq -r '.authenticationMethod // ""' | tr '[:upper:]' '[:lower:]')"
auth_required="$(printf '%s' "$host_cfg" | jq -r '.authenticationRequired // ""' | tr '[:upper:]' '[:lower:]')"
current_username="$(printf '%s' "$host_cfg" | jq -r '.username // ""')"

if [ "$auth_method" = "forms" ] && [ "$auth_required" = "enabled" ] && [ "$current_username" = "$username" ] && login_works; then
  log "Bootstrap user already configured; nothing to do"
  exit 0
fi

payload="$(printf '%s' "$host_cfg" | jq -c \
  --arg username "$username" \
  --arg password "$password" \
  '
    .authenticationMethod = "forms"
    | .authenticationRequired = "enabled"
    | .username = $username
    | .password = $password
    | .passwordConfirmation = $password
  '
)"

api_call PUT "config/host" "$payload" >/dev/null
systemctl restart radarr.service

wait_api_ready || { log "Radarr API did not become ready after restart"; exit 1; }
login_works || { log "Bootstrap user login still fails after update"; exit 1; }
log "Bootstrap user configured"
