#!/usr/bin/env bash
set -euo pipefail

# Usage: update_outpost_tokens_via_ssh.sh <ssh target, e.g. root@192.168.88.194> [secrets-file]
# Fetch outpost tokens directly via ak shell on the server and update local SOPS secrets.

HOST=${1:-}
SECRETS_FILE=${2:-nixmox/secrets/default.yaml}

if [[ -z "$HOST" ]]; then
  echo "Usage: $0 <ssh target> [secrets-file]" >&2
  exit 1
fi

# Create and run a script on the server that writes JSON to a file, then read that file back
JSON=$(ssh "$HOST" 'cat > /tmp/_get_outpost_tokens.py <<"PY"
from authentik.core.models import Token
from authentik.outposts.models import Outpost
import json

mapping = {}
for o in Outpost.objects.all():
    ident = f"ak-outpost-{o.pk}-api"
    try:
        t = Token.objects.get(identifier=ident)
        mapping[str(o.name)] = {"identifier": ident, "key": t.key}
    except Token.DoesNotExist:
        mapping[str(o.name)] = {"identifier": ident, "key": None}

with open("/tmp/_outpost_tokens.json", "w") as f:
    json.dump(mapping, f)
PY
ak shell -c "exec(open(\"/tmp/_get_outpost_tokens.py\").read())" >/dev/null 2>&1
cat /tmp/_outpost_tokens.json' )

echo "$JSON" | jq . >/dev/null # validate JSON

LDAP_TOKEN=$(echo "$JSON" | jq -r '."LDAP Outpost".key // empty')
RADIUS_TOKEN=$(echo "$JSON" | jq -r '."RADIUS Outpost".key // empty')

if [[ -n "$LDAP_TOKEN" ]]; then
  sops --set "[\"authentik-ldap\"][\"env\"]=\"AUTHENTIK_HOST=http://auth.nixmox.lan:9000\\nAUTHENTIK_INSECURE=true\\nAUTHENTIK_TOKEN=${LDAP_TOKEN}\"" "$SECRETS_FILE"
fi

if [[ -n "$RADIUS_TOKEN" ]]; then
  sops --set "[\"authentik-radius\"][\"env\"]=\"AUTHENTIK_HOST=http://auth.nixmox.lan:9000\\nAUTHENTIK_INSECURE=true\\nAUTHENTIK_TOKEN=${RADIUS_TOKEN}\"" "$SECRETS_FILE"
fi

echo "Updated: $SECRETS_FILE"


