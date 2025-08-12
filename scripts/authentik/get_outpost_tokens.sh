#!/usr/bin/env bash
set -euo pipefail

# Usage: get_outpost_tokens.sh <ssh target, e.g. root@192.168.88.194>
HOST=${1:-}
if [[ -z "$HOST" ]]; then
  echo "Usage: $0 <ssh target, e.g. root@192.168.88.194>" >&2
  exit 1
fi

ssh "$HOST" 'cat > /tmp/get_outpost_tokens.py <<PY
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

print(json.dumps(mapping))
PY
ak shell -c "exec(open('/tmp/get_outpost_tokens.py').read())"'


