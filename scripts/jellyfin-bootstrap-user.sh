#!/usr/bin/env bash
set -euo pipefail

base_url="http://127.0.0.1:8096"
auth_header='X-Emby-Authorization: MediaBrowser Client="terraform-bootstrap", Device="terraform", DeviceId="terraform-bootstrap", Version="1.0.0"'
debug_enabled="${JELLYFIN_BOOTSTRAP_DEBUG:-0}"
log() { printf '[jellyfin-bootstrap] %s\n' "$*" >&2; }
debug() { [ "$debug_enabled" = "1" ] && log "DEBUG: $*"; }

systemctl start jellyfin-credentials.service
set -a
. /run/jellyfin-bootstrap.env
set +a

username="$JELLYFIN_BOOTSTRAP_USERNAME"
password="$JELLYFIN_BOOTSTRAP_PASSWORD"

if [ -z "$username" ] || [ -z "$password" ]; then
  echo "Missing Jellyfin bootstrap credentials"
  exit 1
fi

debug "Starting bootstrap for username=$username"

json_escape() { printf '%s' "$1" | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g'; }

post_status() {
  endpoint="$1"
  data="${2:-}"
  debug "POST $endpoint"
  body_file="$(mktemp)"
  header_file="$(mktemp)"
  if [ -n "$data" ]; then
    curl -sS -o "$body_file" -D "$header_file" -X POST -H "Content-Type: application/json" -H "$auth_header" --data "$data" "$base_url/$endpoint" >/dev/null 2>&1 || true
  else
    curl -sS -o "$body_file" -D "$header_file" -X POST -H "$auth_header" "$base_url/$endpoint" >/dev/null 2>&1 || true
  fi
  status="$(awk '/^HTTP/{code=$2} END{print code}' "$header_file")"
  [ -n "$status" ] || status="000"
  if [ "$status" -ge 400 ] 2>/dev/null; then
    body_snippet="$(tr -d '\r' <"$body_file" | head -c 500)"
    log "HTTP $status from $endpoint: $body_snippet"
  else
    debug "HTTP $status from $endpoint"
  fi
  rm -f "$body_file" "$header_file"
  printf '%s' "$status"
}

wait_ready() {
  i=0
  until curl -fsS "$base_url/System/Ping" >/dev/null 2>&1; do
    i="$((i + 1))"
    [ "$i" -ge 120 ] && return 1
    sleep 2
  done
}

auth_ok() {
  payload_auth="$(printf '{"Username":"%s","Pw":"%s"}' "$(json_escape "$username")" "$(json_escape "$password")")"
  status_auth="$(post_status "Users/AuthenticateByName" "$payload_auth")"
  debug "AuthenticateByName status=$status_auth"
  [ "$status_auth" = "200" ]
}

has_users() {
  users_public="$(curl -fsS "$base_url/Users/Public" || true)"
  users_compact="$(printf '%s' "$users_public" | tr -d '[:space:]')"
  [ -n "$users_compact" ] && [ "$users_compact" != "[]" ]
}

diagnose_failure() {
  log "---- failure diagnostics ----"
  curl -fsS "$base_url/System/Ping" >/dev/null 2>&1 && log "Ping: ok" || log "Ping: failed"
  users_public="$(curl -sS "$base_url/Users/Public" 2>/dev/null || true)"
  log "Users/Public: ${users_public:-<empty>}"
  for xml in /var/lib/jellyfin/config/system.xml /etc/jellyfin/system.xml; do
    [ -f "$xml" ] || continue
    wizard_state="$(grep -E 'IsStartupWizardCompleted|IsStartupWizardComplete' "$xml" || true)"
    log "$xml: ${wizard_state:-<no wizard flags found>}"
  done
  if command -v journalctl >/dev/null 2>&1; then
    log "Last jellyfin logs:"
    journalctl -u jellyfin -n 120 --no-pager 2>/dev/null \
      | while IFS= read -r line; do log "[jellyfin] $line"; done || true
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
  startup_user_json="$(curl -sS -H "$auth_header" "$base_url/Startup/User" 2>/dev/null || true)"
  debug "Startup/User(GET) body=${startup_user_json:-<empty>}"

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
auth_ok && { log "Credentials already work; nothing to do"; exit 0; }
has_users && { log "Jellyfin already has users; skipping bootstrap"; exit 0; }

recover_wizard
wait_ready || { log "Jellyfin did not become ready after recovery"; diagnose_failure; exit 1; }
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
