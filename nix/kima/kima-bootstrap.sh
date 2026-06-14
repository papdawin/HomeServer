#!/usr/bin/env bash
set -euo pipefail

log() { printf '[kima-bootstrap] %s\n' "$*" >&2; }

kima_container="${KIMA_CONTAINER:-kima}"
kima_base_url="${KIMA_BASE_URL:-http://127.0.0.1:3030}"
kima_callback_url="${KIMA_CALLBACK_URL:-http://192.168.68.41:3030}"
lidarr_url="${LIDARR_URL:-http://192.168.68.40:8686}"
music_path="${MUSIC_PATH:-/music}"
download_source="${KIMA_DOWNLOAD_SOURCE:-lidarr}"

wait_for_kima() {
  local i=0
  while [ "$i" -lt 180 ]; do
    if docker inspect -f '{{.State.Running}}' "$kima_container" 2>/dev/null | grep -qx true &&
      curl -fsS "$kima_base_url/api/health" >/dev/null 2>&1; then
      return 0
    fi
    i="$((i + 1))"
    sleep 2
  done
  return 1
}

encrypt_for_kima() {
  local plaintext="$1"
  docker exec -i -e KIMA_BOOTSTRAP_SECRET="$plaintext" "$kima_container" node <<'NODE'
const crypto = require("crypto");
const fs = require("fs");

const keyText = fs.readFileSync("/data/secrets/encryption_key", "utf8").trim();
const key = crypto.createHash("sha256").update(keyText).digest();
const iv = crypto.randomBytes(16);
const cipher = crypto.createCipheriv("aes-256-cbc", key, iv);
const encrypted = Buffer.concat([
  cipher.update(process.env.KIMA_BOOTSTRAP_SECRET || ""),
  cipher.final(),
]);

process.stdout.write(`${iv.toString("hex")}:${encrypted.toString("hex")}`);
NODE
}

sql_quote() {
  local value="$1"
  printf "'%s'" "$(printf '%s' "$value" | sed "s/'/''/g")"
}

wait_for_lidarr() {
  local i=0
  while [ "$i" -lt 120 ]; do
    if curl -fsS -H "X-Api-Key: $lidarr_api_key" "$lidarr_url/api/v1/system/status" >/dev/null 2>&1; then
      return 0
    fi
    i="$((i + 1))"
    sleep 2
  done
  return 1
}

ensure_kima_settings() {
  local encrypted_lidarr_api_key="$1"

  docker exec -i "$kima_container" env PGPASSWORD=kima psql -h localhost -U kima -d kima >/dev/null <<SQL
INSERT INTO "SystemSettings" (
  "id",
  "lidarrEnabled",
  "lidarrUrl",
  "lidarrApiKey",
  "musicPath",
  "downloadSource",
  "primaryFailureFallback",
  "autoSync",
  "autoEnrichMetadata",
  "maxConcurrentDownloads",
  "downloadRetryAttempts",
  "transcodeCacheMaxGb",
  "createdAt",
  "updatedAt"
) VALUES (
  'default',
  true,
  $(sql_quote "$lidarr_url"),
  $(sql_quote "$encrypted_lidarr_api_key"),
  $(sql_quote "$music_path"),
  $(sql_quote "$download_source"),
  'none',
  true,
  true,
  3,
  3,
  10,
  now(),
  now()
)
ON CONFLICT ("id") DO UPDATE SET
  "lidarrEnabled" = EXCLUDED."lidarrEnabled",
  "lidarrUrl" = EXCLUDED."lidarrUrl",
  "lidarrApiKey" = EXCLUDED."lidarrApiKey",
  "musicPath" = EXCLUDED."musicPath",
  "downloadSource" = EXCLUDED."downloadSource",
  "updatedAt" = now();
SQL
}

api_call_lidarr() {
  local method="$1" endpoint="$2" data="${3:-}"
  local -a args=(
    -fsS
    -X "$method"
    -H "X-Api-Key: $lidarr_api_key"
  )
  if [ -n "$data" ]; then
    args+=( -H "Content-Type: application/json" --data "$data" )
  fi
  curl "${args[@]}" "$lidarr_url/api/v1/$endpoint"
}

ensure_lidarr_webhook() {
  local webhook_url notifications existing_id payload
  webhook_url="${kima_callback_url%/}/api/webhooks/lidarr"
  notifications="$(api_call_lidarr GET "notification")"
  existing_id="$(
    printf '%s' "$notifications" | jq -r '
      [
        .[] | select(
          .implementation == "Webhook"
          and (
            .name == "Kima"
            or any((.fields // []); .name == "url" and ((.value // "") | test("webhooks/lidarr|lidify")))
          )
        )
      ][0].id // empty
    '
  )"

  payload="$(
    jq -cn --arg webhook_url "$webhook_url" '{
      onGrab: true,
      onReleaseImport: true,
      onAlbumDownload: true,
      onDownloadFailure: true,
      onImportFailure: true,
      onAlbumDelete: true,
      onRename: true,
      onHealthIssue: false,
      onApplicationUpdate: false,
      supportsOnGrab: true,
      supportsOnReleaseImport: true,
      supportsOnAlbumDownload: true,
      supportsOnDownloadFailure: true,
      supportsOnImportFailure: true,
      supportsOnAlbumDelete: true,
      supportsOnRename: true,
      supportsOnHealthIssue: true,
      supportsOnApplicationUpdate: true,
      includeHealthWarnings: false,
      name: "Kima",
      implementation: "Webhook",
      implementationName: "Webhook",
      configContract: "WebhookSettings",
      infoLink: "https://wiki.servarr.com/lidarr/supported#webhook",
      tags: [],
      fields: [
        { name: "url", value: $webhook_url },
        { name: "method", value: 1 },
        { name: "username", value: "" },
        { name: "password", value: "" }
      ]
    }'
  )"

  if [ -n "$existing_id" ]; then
    api_call_lidarr PUT "notification/$existing_id?forceSave=true" "$payload" >/dev/null
    log "Updated Lidarr webhook: $webhook_url"
    return 0
  fi

  api_call_lidarr POST "notification?forceSave=true" "$payload" >/dev/null
  log "Created Lidarr webhook: $webhook_url"
}

systemctl start kima-credentials.service
# shellcheck disable=SC1091
. /run/kima-lidarr.env

lidarr_api_key="${LIDARR_API_KEY:-}"
[ -n "$lidarr_api_key" ] || { log "Missing LIDARR_API_KEY"; exit 1; }

wait_for_kima || { log "Kima did not become ready in time"; exit 1; }
encrypted_lidarr_api_key="$(encrypt_for_kima "$lidarr_api_key")"
[ -n "$encrypted_lidarr_api_key" ] || { log "Failed to encrypt Lidarr API key for Kima"; exit 1; }

ensure_kima_settings "$encrypted_lidarr_api_key"
log "Configured Kima SystemSettings for Lidarr provider"

wait_for_lidarr || { log "Lidarr did not become ready in time"; exit 1; }
ensure_lidarr_webhook

log "Bootstrap completed"
