#!/usr/bin/env bash
set -euo pipefail

# Usage: seed_outposts.sh <host>
HOST=${1:-}
if [[ -z "$HOST" ]]; then
  echo "Usage: $0 <ssh target, e.g. root@192.168.88.194>" >&2
  exit 1
fi

ssh "$HOST" 'cat > /tmp/seed_outposts.py <<PY
from authentik.core.models import Application
from authentik.flows.models import Flow
from authentik.providers.ldap.models import LDAPProvider
from authentik.providers.radius.models import RadiusProvider
from authentik.outposts.models import Outpost
import json

def ensure_ldap():
    flow = Flow.objects.get(slug="default-authentication-flow")
    app, _ = Application.objects.get_or_create(slug="ldap-directory", defaults={"name": "LDAP Directory"})
    prov, _ = LDAPProvider.objects.get_or_create(name="LDAP Provider", defaults={"base_dn": "dc=nixmox,dc=lan", "bind_mode": "direct", "search_mode": "direct", "mfa_support": True})
    if getattr(app, "provider", None) != prov:
        app.provider = prov
        app.save()
    if getattr(prov, "authorization_flow_id", None) != flow.id:
        prov.authorization_flow = flow
        prov.save()
    out, _ = Outpost.objects.get_or_create(name="LDAP Outpost", defaults={"type": "ldap"})
    out.providers.add(prov)
    return {"application": app.slug, "provider": prov.name, "outpost": out.name}

def ensure_radius():
    flow = Flow.objects.get(slug="default-authentication-flow")
    app, _ = Application.objects.get_or_create(slug="radius-access", defaults={"name": "RADIUS Access"})
    prov, _ = RadiusProvider.objects.get_or_create(name="RADIUS Provider", defaults={"shared_secret": "test-secret"})
    if getattr(app, "provider", None) != prov:
        app.provider = prov
        app.save()
    if getattr(prov, "authorization_flow_id", None) != flow.id:
        prov.authorization_flow = flow
        prov.save()
    out, _ = Outpost.objects.get_or_create(name="RADIUS Outpost", defaults={"type": "radius"})
    out.providers.add(prov)
    return {"application": app.slug, "provider": prov.name, "outpost": out.name}

if __name__ == "__main__":
    result = {"ldap": ensure_ldap(), "radius": ensure_radius()}
    print(json.dumps(result))
PY
ak shell -c "exec(open('/tmp/seed_outposts.py').read())"'


