#!/usr/bin/env bash
set -euo pipefail

base_url="http://127.0.0.1:8096"
auth_header='X-Emby-Authorization: MediaBrowser Client="terraform-bootstrap", Device="terraform", DeviceId="terraform-bootstrap", Version="1.0.0"'
debug_enabled="${JELLYFIN_BOOTSTRAP_DEBUG:-0}"
trace_enabled="${JELLYFIN_BOOTSTRAP_TRACE:-0}"
log() { printf '[jellyfin-bootstrap] %s %s\n' "$(date -Iseconds)" "$*" >&2; }
debug() {
  if [ "$debug_enabled" = "1" ]; then
    log "DEBUG: $*"
  fi
  return 0
}

if [ "$trace_enabled" = "1" ]; then
  set -x
fi

redact_sensitive() {
  sed -E \
    -e 's/("AccessToken"[[:space:]]*:[[:space:]]*")[^"]+/\1<redacted>/g' \
    -e 's/("Token"[[:space:]]*:[[:space:]]*")[^"]+/\1<redacted>/g' \
    -e 's/("Pw"[[:space:]]*:[[:space:]]*")[^"]+/\1<redacted>/g' \
    -e 's/("Password"[[:space:]]*:[[:space:]]*")[^"]+/\1<redacted>/g'
}

compact_snippet() {
  printf '%s' "$1" | redact_sensitive | tr -d '\r' | tr '\n' ' ' | head -c 500
}

dump_systemd_state() {
  command -v systemctl >/dev/null 2>&1 || return 0
  for unit in jellyfin.service jellyfin-credentials.service jellyfin-bootstrap.service; do
    active="$(systemctl is-active "$unit" 2>/dev/null || true)"
    substate="$(systemctl show "$unit" -p SubState --value 2>/dev/null || true)"
    result="$(systemctl show "$unit" -p Result --value 2>/dev/null || true)"
    log "$unit state: active=${active:-unknown} substate=${substate:-unknown} result=${result:-unknown}"
  done
}

dump_file_state() {
  for path in /run/jellyfin-bootstrap.env /var/lib/jellyfin/config/system.xml /etc/jellyfin/system.xml; do
    if [ -e "$path" ]; then
      perms="$(stat -c '%A %U:%G %s' "$path" 2>/dev/null || true)"
      log "$path present (${perms:-unknown})"
    else
      log "$path missing"
    fi
  done
}

on_error() {
  rc=$?
  log "ERROR rc=$rc line=${BASH_LINENO[0]:-unknown} cmd=${BASH_COMMAND:-unknown}"
  dump_systemd_state || true
  exit "$rc"
}
trap on_error ERR

log "Bootstrap start (debug=$debug_enabled trace=$trace_enabled)"
dump_systemd_state
dump_file_state

log "Starting jellyfin-credentials.service"
if ! systemctl start jellyfin-credentials.service; then
  log "jellyfin-credentials.service start failed; using existing /run/jellyfin-bootstrap.env if present"
fi

if [ ! -s /run/jellyfin-bootstrap.env ]; then
  log "Missing or empty /run/jellyfin-bootstrap.env"
  dump_systemd_state
  command -v journalctl >/dev/null 2>&1 && \
    journalctl -u jellyfin-credentials -n 120 --no-pager 2>/dev/null \
      | while IFS= read -r line; do log "[jellyfin-credentials] $line"; done || true
  exit 1
fi

set -a
. /run/jellyfin-bootstrap.env
set +a

username="${JELLYFIN_BOOTSTRAP_USERNAME:-}"
password="${JELLYFIN_BOOTSTRAP_PASSWORD:-}"
password_len="${#password}"
debug "Credentials loaded: username='${username:-<empty>}' password_len=$password_len"

if [ -z "$username" ] || [ -z "$password" ]; then
  log "Missing Jellyfin bootstrap credentials after loading /run/jellyfin-bootstrap.env"
  exit 1
fi

debug "Starting bootstrap for username=$username"

json_escape() { printf '%s' "$1" | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g'; }

post_status() {
  endpoint="$1"
  data="${2:-}"
  debug "POST $endpoint (payload_len=${#data})"
  body_file="$(mktemp)"
  header_file="$(mktemp)"
  curl_rc=0
  if [ -n "$data" ]; then
    curl -sS -o "$body_file" -D "$header_file" -X POST -H "Content-Type: application/json" -H "$auth_header" --data "$data" "$base_url/$endpoint" >/dev/null 2>&1 || curl_rc=$?
  else
    curl -sS -o "$body_file" -D "$header_file" -X POST -H "$auth_header" "$base_url/$endpoint" >/dev/null 2>&1 || curl_rc=$?
  fi
  status="$(awk '/^HTTP/{code=$2} END{print code}' "$header_file")"
  [ -n "$status" ] || status="000"
  debug "POST $endpoint -> curl_rc=$curl_rc http_status=$status"
  if [ "$status" -ge 400 ] 2>/dev/null; then
    body_snippet="$(compact_snippet "$(cat "$body_file" 2>/dev/null || true)")"
    log "HTTP $status from $endpoint: $body_snippet"
  else
    debug "HTTP $status from $endpoint"
  fi
  if [ "$debug_enabled" = "1" ]; then
    header_snippet="$(compact_snippet "$(cat "$header_file" 2>/dev/null || true)")"
    body_snippet="$(compact_snippet "$(cat "$body_file" 2>/dev/null || true)")"
    debug "POST $endpoint headers=$header_snippet"
    debug "POST $endpoint body=$body_snippet"
  fi
  rm -f "$body_file" "$header_file"
  printf '%s' "$status"
}

wait_ready() {
  i=0
  until curl -fsS "$base_url/System/Ping" >/dev/null 2>&1; do
    i="$((i + 1))"
    if [ "$debug_enabled" = "1" ] && [ $((i % 5)) -eq 0 ]; then
      ping_status="$(curl -sS -o /dev/null -w '%{http_code}' "$base_url/System/Ping" 2>/dev/null || true)"
      debug "Ping wait attempt=$i http_status=${ping_status:-000}"
    fi
    [ "$i" -ge 120 ] && return 1
    sleep 2
  done
  debug "Ping succeeded after $i retries"
}

wait_api_ready() {
  i=0
  while [ "$i" -lt 90 ]; do
    status="$(curl -sS -o /dev/null -w '%{http_code}' "$base_url/Users/Public" 2>/dev/null || true)"
    case "$status" in
      200|401|403)
        debug "Users/Public readiness status=$status after ${i}s"
        return 0
        ;;
      503|"")
        if [ "$debug_enabled" = "1" ] && [ $((i % 10)) -eq 0 ]; then
          debug "Users/Public still warming up (status=${status:-000}, elapsed=${i}s)"
        fi
        ;;
      *)
        debug "Users/Public readiness got status=$status, continuing to wait"
        ;;
    esac
    i="$((i + 2))"
    sleep 2
  done
  log "Users/Public did not become ready in time"
  return 1
}

auth_ok() {
  payload_auth="$(printf '{"Username":"%s","Pw":"%s"}' "$(json_escape "$username")" "$(json_escape "$password")")"
  status_auth="$(post_status "Users/AuthenticateByName" "$payload_auth")"
  debug "AuthenticateByName status=$status_auth"
  [ "$status_auth" = "200" ]
}

has_users() {
  users_public="$(curl -sS "$base_url/Users/Public" 2>/dev/null || true)"
  users_compact="$(printf '%s' "$users_public" | tr -d '[:space:]')"
  users_count="$(printf '%s' "$users_public" | grep -o '"Name"' | wc -l | tr -d ' ' || true)"
  debug "Users/Public count=${users_count:-0} body=$(compact_snippet "$users_public")"
  [ -n "$users_compact" ] && [ "$users_compact" != "[]" ]
}

diagnose_failure() {
  log "---- failure diagnostics ----"
  dump_systemd_state
  dump_file_state
  curl -fsS "$base_url/System/Ping" >/dev/null 2>&1 && log "Ping: ok" || log "Ping: failed"
  users_public="$(curl -sS "$base_url/Users/Public" 2>/dev/null || true)"
  log "Users/Public: $(compact_snippet "${users_public:-<empty>}")"
  for xml in /var/lib/jellyfin/config/system.xml /etc/jellyfin/system.xml; do
    [ -f "$xml" ] || continue
    wizard_state="$(grep -E 'IsStartupWizardCompleted|IsStartupWizardComplete' "$xml" || true)"
    log "$xml: ${wizard_state:-<no wizard flags found>}"
  done
  if command -v journalctl >/dev/null 2>&1; then
    log "Last jellyfin logs:"
    journalctl -u jellyfin -n 120 --no-pager 2>/dev/null \
      | while IFS= read -r line; do log "[jellyfin] $line"; done || true
    log "Last jellyfin-credentials logs:"
    journalctl -u jellyfin-credentials -n 120 --no-pager 2>/dev/null \
      | while IFS= read -r line; do log "[jellyfin-credentials] $line"; done || true
  fi
  log "---- end diagnostics ----"
}

recover_wizard() {
  debug "Recovering startup wizard flags"
  systemctl stop jellyfin
  for xml in /var/lib/jellyfin/config/system.xml /etc/jellyfin/system.xml; do
    [ -f "$xml" ] || continue
    sed -i \
      -e 's#<IsStartupWizardCompleted>true</IsStartupWizardCompleted>#<IsStartupWizardCompleted>false</IsStartupWizardCompleted>#g' \
      -e 's#<IsStartupWizardComplete>true</IsStartupWizardComplete>#<IsStartupWizardComplete>false</IsStartupWizardComplete>#g' \
      "$xml"
  done
  systemctl start jellyfin
}

bootstrap_once() {
  payload_cfg='{"UICulture":"en-US","MetadataCountryCode":"US","PreferredMetadataLanguage":"en"}'
  status_cfg="$(post_status "Startup/Configuration" "$payload_cfg")"
  debug "Startup/Configuration status=$status_cfg"
  case "$status_cfg" in
    200|204|400|404) ;;
    401) return 2 ;;
    *) log "Startup/Configuration failed with HTTP $status_cfg"; return 1 ;;
  esac

  # On current Jellyfin builds, Startup/User can 500 unless the startup user
  # is fetched first.
  startup_user_body_file="$(mktemp)"
  startup_user_status="$(curl -sS -o "$startup_user_body_file" -w '%{http_code}' -H "$auth_header" "$base_url/Startup/User" 2>/dev/null || true)"
  startup_user_json="$(cat "$startup_user_body_file" 2>/dev/null || true)"
  rm -f "$startup_user_body_file"
  debug "Startup/User(GET) status=${startup_user_status:-000} body=$(compact_snippet "${startup_user_json:-<empty>}")"

  payload_user_name="$(printf '{"Name":"%s","Password":"%s"}' "$(json_escape "$username")" "$(json_escape "$password")")"
  payload_user_username="$(printf '{"Username":"%s","Password":"%s"}' "$(json_escape "$username")" "$(json_escape "$password")")"
  payload_user_pw="$(printf '{"Username":"%s","Pw":"%s"}' "$(json_escape "$username")" "$(json_escape "$password")")"

  status_user="$(post_status "Startup/User" "$payload_user_name")"
  debug "Startup/User(Name/Password) status=$status_user"
  case "$status_user" in
    200|204|400) ;;
    401) return 2 ;;
    *)
      status_user="$(post_status "Startup/User" "$payload_user_username")"
      debug "Startup/User(Username/Password) status=$status_user"
      case "$status_user" in
        200|204|400) ;;
        401) return 2 ;;
        *)
          status_user="$(post_status "Startup/User" "$payload_user_pw")"
          debug "Startup/User(Username/Pw) status=$status_user"
          case "$status_user" in
            200|204|400) ;;
            401) return 2 ;;
            *) log "Startup/User failed with HTTP $status_user"; return 1 ;;
          esac
          ;;
      esac
      ;;
  esac

  status_complete="$(post_status "Startup/Complete")"
  debug "Startup/Complete status=$status_complete"
  case "$status_complete" in
    200|204|400) ;;
    401) return 2 ;;
    *) echo "Startup/Complete failed with HTTP $status_complete"; return 1 ;;
  esac

  auth_ok
}

wait_ready || { log "Jellyfin did not become ready in time"; exit 1; }
wait_api_ready || { diagnose_failure; exit 1; }
auth_ok && { log "Credentials already work; nothing to do"; exit 0; }
has_users && { log "Jellyfin already has users; skipping bootstrap"; exit 0; }

recover_wizard
wait_ready || { log "Jellyfin did not become ready after recovery"; diagnose_failure; exit 1; }
wait_api_ready || { diagnose_failure; exit 1; }
has_users && { log "Jellyfin already has users after recovery; skipping bootstrap"; exit 0; }

i=0
while [ "$i" -lt 20 ]; do
  debug "Bootstrap attempt $((i + 1))/20"
  if bootstrap_once && auth_ok; then
    log "Bootstrap user created and validated"
    exit 0
  fi
  i="$((i + 1))"
  sleep 2
done

log "Jellyfin bootstrap failed after retries"
diagnose_failure
exit 1
