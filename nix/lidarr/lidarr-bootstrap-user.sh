#!/usr/bin/env bash
set -euo pipefail

base_url="http://127.0.0.1:8686"
api_url="$base_url/api/v1"
lidarr_config_xml="/appdata/lidarr/config.xml"

log() { printf '[lidarr-bootstrap-user] %s\n' "$*" >&2; }

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

systemctl start lidarr-credentials.service
. /run/lidarr-bootstrap.env

username="${LIDARR_BOOTSTRAP_USERNAME:-}"
password="${LIDARR_BOOTSTRAP_PASSWORD:-}"
[ -n "$username" ] && [ -n "$password" ] || { log "Missing bootstrap credentials"; exit 1; }

lidarr_api_key="$(wait_for_file_value "$lidarr_config_xml" "ApiKey" || true)"
[ -n "$lidarr_api_key" ] || { log "Lidarr API key not found in $lidarr_config_xml"; exit 1; }

wait_api_ready || { log "Lidarr API did not become ready in time"; exit 1; }

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

put_config "config/host" "$host_cfg" "$payload" >/dev/null
systemctl restart lidarr.service

wait_api_ready || { log "Lidarr API did not become ready after restart"; exit 1; }
login_works || { log "Bootstrap user login still fails after update"; exit 1; }
log "Bootstrap user configured"
