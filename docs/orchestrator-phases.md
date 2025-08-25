# NixMox Orchestrator: Phase Order and Responsibilities

This document defines the canonical deployment order and responsibilities of the NixMox orchestrator. The orchestrator is the single control plane that reads a user-provided manifest, generates a deployment plan, and executes Terraform and NixOS phases idempotently.

## Phase Order (authoritative)

1) tf:infra
- Purpose: Provision core infrastructure primitives required for hosts and networks.
- Typical resources: Proxmox LXCs/VMs, networks/VLANs, base DNS zones/records, storage volumes, base secrets/state buckets.
- Tooling: Terraform (optionally generated via Terranix).

2) nix:core
- Purpose: Configure core NixOS services on provisioned hosts.
- Core services (always required): dns, postgresql, caddy, authentik (runtime).
- Outcomes: Services installed/enabled, CA/trust configured, reverse proxy baseline online.

3) tf:auth-core
- Purpose: Provision Authentik resources that depend on a running Authentik (apps, providers, outposts), and any other identity resources.
- Typical resources: authentik_application, authentik_provider (OIDC), outpost tokens/bindings.
- Outputs: Client IDs/secrets, redirect URIs, outpost tokens (fed to Nix via SOPS or TF outputs).

4) Per-service loop (for each service S in dependency order)
   4a) tf:service-infra
   - Purpose: Provision service-scoped primitives independent of Nix config.
   - Examples: DB instances/roles/schemas (if TF-managed), buckets, queues, DNS records, Authentik app/provider for S.
   
   4b) nix:service-config
   - Purpose: Configure service host(s) and runtime with data from TF outputs.
   - Examples: System units/containers, reverse proxy rules, truststores, DB connectivity, OIDC client wiring.
   
   4c) tf:service-config
   - Purpose: Apply TF that requires the service to be running/configured.
   - Examples: Authentik outpost bindings that require reachable upstreams, runtime-generated callbacks, dynamic DNS updates.
   
   4d) verify
   - Health checks: startup/liveness/readiness.
   - End-to-end checks: OIDC redirect URLs, DB connectivity, reverse proxy headers, TLS.

Notes:
- Terranix may be used to generate Terraform HCL from Nix if we want fully declarative TF plans.
- Each TF phase should plan first; if no changes, skip apply. Use separate workspaces/state when helpful.
- Secrets from TF should be surfaced via outputs → SOPS or environment-injection only; never committed.

## Manifest Additions (interfaces)

services.<name>.interface.terraform
- modules: [ paths ]  # directories or files containing TF for this phase
- variables: { ... }  # values wired from manifest (domains, IPs, callback URIs, etc.)
- targets: [ strings ]  # logical targets for reporting/apply order
- apply_order: [ strings ]  # fine-grained sub-apply sequencing

services.<name>.interface.auth
- oidc: { client_id?, redirect_uris, scopes, username_claim, groups_claim }
- provider: "authentik"

services.<name>.interface.db
- mode: "terraform" | "native-migration"
- database: name
- role: name
- migrations: [ paths ]

services.<name>.interface.proxy
- domain, path, headers, upstream, tls, authz

services.<name>.interface.health
- startup, liveness, readiness (commands or URLs)

## Orchestrator Execution Model

- Build the graph from manifest (core + optional services), sort by dependencies.
- Execute phases strictly in the order above.
- Between subphases: wait on health checks as defined by service.interface.health and default patterns.
- Rollbacks: on failure, attempt service-level rollback; if core phase fails, halt and report.

## Terraform Integration

- Runner must support:
  - init/plan/apply/destroy with idempotence
  - -refresh-only to quickly detect no-op updates
  - per-phase workspaces (e.g., infra, auth-core, <svc>-infra, <svc>-config)
  - outputs exposed to Nix (environment or SOPS-injected)
- Terranix (optional): generate TF HCL from Nix if we prefer single-language manifests.

## Health and Verification

- Core health gates (dns, postgresql, caddy, authentik) are mandatory before proceeding.
- Service verify step should be explicit and include OIDC callback success where applicable.

This phase order and interface surface are the contract the orchestrator will implement.