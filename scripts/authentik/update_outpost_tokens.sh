#!/usr/bin/env bash
set -euo pipefail

# Fetch outpost API tokens via view_key and update SOPS secrets.
#
# Usage:
#   update_outpost_tokens.sh --base-url http://auth.nixmox.lan:9000 --admin-token <TOKEN>
#   Optional: --host-header auth.nixmox.lan --secrets-file nixmox/secrets/default.yaml

BASE_URL=""
ADMIN_TOKEN=""
HOST_HEADER=""
SECRETS_FILE="nixmox/secrets/default.yaml"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --base-url) BASE_URL="$2"; shift 2;;
    --admin-token) ADMIN_TOKEN="$2"; shift 2;;
    --host-header) HOST_HEADER="$2"; shift 2;;
    --secrets-file) SECRETS_FILE="$2"; shift 2;;
    *) echo "Unknown arg: $1" >&2; exit 2;;
  esac
done

if [[ -z "$BASE_URL" || -z "$ADMIN_TOKEN" ]]; then
  echo "Usage: $0 --base-url <URL> --admin-token <TOKEN> [--host-header <HOST>] [--secrets-file <PATH>]" >&2
  exit 1
fi

curl_auth=(-H "Authorization: Bearer ${ADMIN_TOKEN}")
if [[ -n "$HOST_HEADER" ]]; then
  curl_auth+=(-H "Host: ${HOST_HEADER}")
fi

outposts_json=$(curl -sS "${BASE_URL}/api/v3/outposts/instances/?page_size=100" "${curl_auth[@]}")

ldap_pk=$(jq -r '.results[] | select(.name=="LDAP Outpost") | .pk' <<<"$outposts_json" || true)
radius_pk=$(jq -r '.results[] | select(.name=="RADIUS Outpost") | .pk' <<<"$outposts_json" || true)

fetch_token() {
  local pk="$1"
  curl -sS "${BASE_URL}/api/v3/core/tokens/ak-outpost-${pk}-api/view_key" "${curl_auth[@]}" | jq -r .key
}

if [[ -n "$ldap_pk" && "$ldap_pk" != "null" ]]; then
  ldap_token=$(fetch_token "$ldap_pk")
  if [[ -n "$ldap_token" && "$ldap_token" != "null" ]]; then
    sops --set "[\"authentik-ldap\"][\"env\"]=\"AUTHENTIK_HOST=http://auth.nixmox.lan:9000\\nAUTHENTIK_INSECURE=true\\nAUTHENTIK_TOKEN=${ldap_token}\"" "$SECRETS_FILE"
  fi
else
  echo "LDAP Outpost not found; skipping" >&2
fi

if [[ -n "$radius_pk" && "$radius_pk" != "null" ]]; then
  radius_token=$(fetch_token "$radius_pk")
  if [[ -n "$radius_token" && "$radius_token" != "null" ]]; then
    sops --set "[\"authentik-radius\"][\"env\"]=\"AUTHENTIK_HOST=http://auth.nixmox.lan:9000\\nAUTHENTIK_INSECURE=true\\nAUTHENTIK_TOKEN=${radius_token}\"" "$SECRETS_FILE"
  fi
else
  echo "RADIUS Outpost not found; skipping" >&2
fi

echo "Updated tokens in $SECRETS_FILE"


