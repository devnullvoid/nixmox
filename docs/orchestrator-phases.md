# NixMox Orchestrator: Phase Order and Responsibilities

This document defines the canonical deployment order and responsibilities of the NixMox orchestrator. The orchestrator is the single control plane that reads a user-provided manifest, generates a deployment plan, and executes Terraform and NixOS phases idempotently.

## Phase Order (authoritative)

1a) tf:infra
- Purpose: Provision ALL infrastructure primitives (core + applications) in a single phase.
- Typical resources: Proxmox LXCs/VMs for ALL services, networks/VLANs, base DNS zones/records, storage volumes, base secrets/state buckets.
- Tooling: Terraform (manifest-driven).
- **Key benefit**: All containers created upfront, enabling better resource optimization and dependency management.

1b) nix:core
- Purpose: Configure core NixOS services on provisioned infrastructure containers.
- Core services (always required): dns, postgresql, caddy, authentik (runtime).
- Outcomes: Services installed/enabled, CA/trust configured, reverse proxy baseline online.
- **Dependency**: Requires Phase 1a (tf:infra) to complete successfully.

2) tf:auth-core
- Purpose: Provision Authentik resources that depend on a running Authentik instance.
- Typical resources: authentik_application, authentik_provider (OIDC), outpost tokens/bindings.
- Outputs: Client IDs/secrets, redirect URIs, outpost tokens (fed to Nix via SOPS or TF outputs).
- **Dependency**: Requires Phase 1b (nix:core) to complete and Authentik to be healthy.

3) nix:applications
- Purpose: Configure application services on provisioned application containers.
- Examples: Vaultwarden, Guacamole, Nextcloud, Media, Monitoring, Mail.
- **Dependency**: Requires Phase 2 (tf:auth-core) to complete for OIDC configuration.
- **Data flow**: Uses OIDC client IDs, secrets, and configuration from Phase 2.

Notes:
- Phase 1a creates ALL containers upfront, enabling better resource planning and placement.
- Phase 1b deploys NixOS to core services, establishing the foundation.
- Phase 2 creates Authentik resources using the running Authentik instance.
- Phase 3 deploys applications with full OIDC configuration available.
- Each phase includes health checks and verification before proceeding.

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