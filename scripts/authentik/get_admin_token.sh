#!/usr/bin/env bash
set -euo pipefail

# Usage: get_admin_token.sh <ssh target, e.g. root@192.168.88.194>
# Prints (to stdout) an admin API token suitable for API calls.

HOST=${1:-}
if [[ -z "$HOST" ]]; then
  echo "Usage: $0 <ssh target>" >&2
  exit 1
fi

ssh "$HOST" 'ak shell -c "from authentik.core.models import Token, User; u=User.objects.get(username=\"akadmin\"); t,_=Token.objects.get_or_create(identifier=\"automation\", user=u, intent=\"app_password\", defaults={\"description\":\"automation\"}); print(t.key)"'


