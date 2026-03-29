#!/usr/bin/env bash
set -euo pipefail

node_name="${1:?missing node name}"
template_volid="${2:?missing template volid (e.g. local:vztmpl/system-tarball)}"
template_url="${3:-}"

if [[ ! "$template_volid" =~ ^([^:]+):vztmpl/(.+)$ ]]; then
  echo "template volid must match '<storage>:vztmpl/<filename>', got: $template_volid" >&2
  exit 1
fi

storage="${BASH_REMATCH[1]}"
filename="${BASH_REMATCH[2]}"

api_url="${PM_API_URL:?set PM_API_URL}"
token_id="${PM_API_TOKEN_ID:?set PM_API_TOKEN_ID}"
token_secret="${PM_API_TOKEN_SECRET:?set PM_API_TOKEN_SECRET}"

curl_args=( -sS )
if [[ "${PM_TLS_INSECURE:-true}" == "true" ]]; then
  curl_args+=( -k )
fi

auth_header="Authorization: PVEAPIToken=${token_id}=${token_secret}"
api_url="${api_url%/}"

echo "Checking template ${template_volid} on node ${node_name}..."
content_json="$(curl "${curl_args[@]}" -H "$auth_header" "${api_url}/nodes/${node_name}/storage/${storage}/content?content=vztmpl")"
if echo "$content_json" | grep -Fq "\"volid\":\"${template_volid}\""; then
  echo "Template already exists: ${template_volid}"
  exit 0
fi

if [[ -z "$template_url" ]]; then
  echo "missing template download url (3rd argument) because template is not present yet" >&2
  exit 1
fi

echo "Template missing. Starting download from: ${template_url}"
create_response="$(curl "${curl_args[@]}" -X POST -H "$auth_header" \
  --data-urlencode "content=vztmpl" \
  --data-urlencode "filename=${filename}" \
  --data-urlencode "url=${template_url}" \
  -w $'\n%{http_code}' \
  "${api_url}/nodes/${node_name}/storage/${storage}/download-url")"

http_code="${create_response##*$'\n'}"
create_json="${create_response%$'\n'*}"
if [[ "${http_code}" -ge 400 ]]; then
  echo "Proxmox download-url API failed with HTTP ${http_code}" >&2
  echo "$create_json" >&2
  exit 1
fi

upid="$(printf '%s' "$create_json" | sed -n 's/.*"data":"\([^"]*\)".*/\1/p')"
if [[ -z "$upid" ]]; then
  echo "Unable to parse task ID from response:" >&2
  echo "$create_json" >&2
  exit 1
fi

upid_enc="${upid//:/%3A}"
echo "Waiting for download task: ${upid}"

for _ in $(seq 1 300); do
  task_json="$(curl "${curl_args[@]}" -H "$auth_header" "${api_url}/nodes/${node_name}/tasks/${upid_enc}/status")"
  if echo "$task_json" | grep -q '"status":"stopped"'; then
    if echo "$task_json" | grep -q '"exitstatus":"OK"'; then
      echo "Template downloaded: ${template_volid}"
      exit 0
    fi

    echo "Template download failed:" >&2
    echo "$task_json" >&2
    exit 1
  fi
  sleep 2
done

echo "Timed out waiting for template download task to finish" >&2
exit 1
