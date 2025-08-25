# Orchestrator Overview

This document summarizes the orchestrator’s responsibilities, the manifest-driven plan, and multi-phase Terraform + Nix execution, aligned with `docs/orchestrator-phases.md`.

- Single control plane reading the manifest.
- Generates plan: tf:infra → nix:core → tf:auth-core → (tf:service-infra → nix:service-config → tf:service-config → verify)xN.
- Produces execution scripts for each phase with health/rollback gates.
- Integrates Terraform (optionally via Terranix) and surfaces outputs to Nix.
- Validates: dependency graph, IP/hostname conflicts, missing interfaces.

See `docs/orchestrator-phases.md` for authoritative phase details and interfaces.