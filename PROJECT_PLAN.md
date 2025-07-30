# Project Plan: NixMox – NixOS LXC Orchestration on Proxmox

## Overview and Objectives

**NixMox** is a project to automate deployment of self-hosted services using **NixOS** containers on a **Proxmox** VE cluster. The goal is to create a highly modular, reproducible, and secure platform where each major service runs in its own NixOS LXC container, all orchestrated by a central management application. Key objectives include:

* **Isolation of Services:** Each application (media servers, web apps, etc.) runs on a separate NixOS container to isolate resources and configuration.
* **Declarative Configuration:** Use NixOS and Nix Flakes for declarative, version-controlled configuration of all services and system settings.
* **Central Management Plane:** Develop a **Go-based backend** with an embedded **React** UI to deploy and manage containers, handle service discovery, and provide a “single pane of glass” for operations.
* **Single Sign-On (SSO):** Integrate **Authentik** for unified authentication/SSO across all services (via LDAP, OAuth2/OIDC, or forward-auth headers).
* **High Automation & Customization:** Automate as much as possible (container provisioning, DNS, TLS, monitoring, backups) while allowing users to customize configurations for their needs.
* **Dev/Prod Parity:** Support at least two environments (development and production) with consistent tooling, to test changes before production rollout.
* **Security and Reliability:** Follow best practices for secret management (e.g. SOPS), network security, logging, monitoring, and backup to ensure a robust system.

By achieving these goals, NixMox will simplify self-hosting a large suite of applications with minimal manual intervention, using the power of NixOS for consistency and Proxmox for efficient containerization.

## Reference Inspirations and Prior Work

We have surveyed existing NixOS deployment projects to guide our design. Notably, we looked at **VGHS-lucaruby’s NixOS-Server Dots** and similar configurations:

* *Monolithic vs. Micro:* The referenced projects typically configure **many services on a single NixOS machine**, using NixOS modules for each service. For example, lucaruby’s setup enabled Authentik, Grafana, Jellyfin, Mailserver, etc., all on one NixOS VM. In contrast, **NixMox** will split services into separate containers. This micro-service approach improves isolation and scalability, at the cost of more network integration work.
* *Multi-Node Configuration:* Lucaruby’s flake defines multiple **nodes** (hosts) in one config, effectively one per service (e.g. separate hosts for Authentik, Grafana, Jellyfin, etc.). We will adopt a similar multi-node flake structure, treating each container as a “node” with its own NixOS config. This allows reuse of common configurations and easy instantiation of new service containers.
* *Secrets Management:* Projects like lucaruby’s use **SOPS-Nix** for secrets. Each host/node has an encrypted secrets file, decrypted at build or boot using that host’s key. We will follow this best practice: maintain a separate **private Git repo** for secrets, use SOPS with age or GPG encryption, and ensure secrets (passwords, API keys, etc.) never appear in plaintext in the Nix store. Each container will only have access to its own secrets file, decrypted via its host-specific key.
* *Backup Strategy:* The reference projects credit **Restic + Backblaze B2** for backups. This indicates an automated, off-site backup approach. We plan to integrate Restic for periodic backups of critical data (to cloud storage like B2 or S3, or to a local NAS) as detailed later.
* *Community Modules:* We can borrow NixOS module configurations from the community. For example, lucaruby’s config uses **Simple NixOS Mailserver** for email and `authentik-nix` for Authentik. Reusing such modules accelerates development by leveraging well-tested setups. We will review these projects’ Nix code (e.g., service options, networking tweaks) and incorporate relevant parts into our configuration where possible.

By learning from these existing setups, we avoid “reinventing the wheel” and ensure our design aligns with proven practices in the NixOS community.

## System Architecture Design

### Infrastructure: Proxmox and NixOS LXC Containers

**Proxmox VE** will serve as the base infrastructure, hosting multiple LXC containers each running NixOS (Linux Container images of NixOS). Key points of this setup:

* **NixOS LXC Image:** We will utilize the NixOS-provided container template for Proxmox. NixOS publishes a `nixos.proxmoxLXC` tarball that can be downloaded from Hydra and added to Proxmox’s template cache. This ensures we start containers with a minimal NixOS system.
* **Container Creation:** Because the Proxmox web GUI doesn’t fully support NixOS containers, we will use the Proxmox CLI or API to create them. *“You must use the CLI to successfully create a NixOS CT… the GUI does not give you a fully functioning CT.”*. Our management app will automate this step (via `pct` commands or API calls). We will create containers with:

  * **Unprivileged or Privileged?** The plan is to prefer **unprivileged containers with nesting enabled**, for security. According to community advice, an LXC should be unprivileged and have `nesting=1` to allow NixOS’s operations inside. This requires some configuration tweaks (discussed below). In cases where a specific service needs hardware access (e.g. GPU for Jellyfin transcoding), we may enable *privileged* mode or add device passthrough config for that container as needed.
  * **Container Options:** Typical options include a fixed CT ID, hostname, CPU/mem resources, and network settings. We’ll set `--features nesting=1` and console mode to `/dev/console` (to fix console access). Each container will likely get a **static IP** on a Proxmox bridge (for consistent service discovery), specified at creation (e.g. `--net0 name=eth0,bridge=vmbr0,ip=192.168.50.X/24,gw=192.168.50.1`).
  * **Initial Config:** Immediately after creation, the container will be provisioned with a basic NixOS config. The NixOS LXC template doesn’t contain a populated `/etc/nixos/configuration.nix` by default, so we will inject our NixOS config (either by mounting the flake or using `pct exec` to write the file). The config will include special settings for LXC:

    * Import the Proxmox LXC module: `imports = [ <nixpkgs/nixos/modules/virtualisation/proxmox-lxc.nix> ];` which applies necessary fixes (this handles things like no systemd mount for cgroups, etc.).
    * Set `boot.isContainer = true` and suppress certain systemd units that don’t work in containers (e.g. dev-mqueue, debug mounts).
    * Possibly disable Nix sandboxing (`nix.settings.sandbox = false`) for container builds, which the wiki suggests if using privileged mode.
    * Configure basic access: enable SSH, create an initial user (or use root with no password temporarily) so that our automation can connect. For example, set `services.openssh.enable = true` and allow passwordless root login just for bootstrapping (root password will be removed or set later via our secrets).
  * **Post-Create Initialization:** Once the container starts, we’ll perform an initial `nixos-rebuild switch` inside it to apply the full configuration. (The wiki notes that after adding the config, running `nixos-rebuild switch --upgrade` finalizes the setup.) We might need a reboot after the first switch in unprivileged containers due to known systemd issues (e.g. errors about `/boot` on first switch). After that, the container should be fully functional with NixOS.
* **Automating with Nix Flakes:** Instead of manual steps, we’ll integrate this into our flake and tooling:

  * We can leverage **nixos-generators** to build LXC container images directly from our flake. In fact, we plan to generate pre-configured images for each service container using `nixos-generators` in a CI pipeline or on-demand. For example, Mario Sangiorgio’s blog demonstrates: `nix run nixos-generators -f proxmox-lxc -c ./configuration.nix` produces a `nixos-system-x86_64-linux.tar.xz` ready for Proxmox. We can do similar, packaging each container’s config into an image file. Our management app could then automatically upload that to Proxmox and create the container from it.
  * Alternatively, we use a **template base image** (a minimal NixOS) and then apply config after creation (which might be slower per container). A hybrid approach: maintain a base template for NixOS LXC (updated periodically), and use NixOS remote builds for service specifics.
* **Proxmox API Integration:** We will write Go code to interface with Proxmox’s REST API or CLI for container operations. The app should be able to create, start/stop, destroy containers, and possibly snapshot or backup them if needed. We might use an existing Go library for Proxmox or simply shell out to `pct` commands via SSH, depending on reliability. This is crucial for the automation aspect: one-click deployment of a new service container from the web UI.

In summary, the infrastructure layer will treat Proxmox as a pool of resources (multiple nodes in a cluster, potentially) and manage NixOS containers on it in an automated fashion. We’ll implement the low-level provisioning carefully to account for the quirks of NixOS on LXC (as documented by NixOS Wiki and community posts).

### NixOS Configuration Management (Flakes & Modules)

At the heart of NixMox is a **Nix flake** that defines configurations for all service containers. This flake will serve as the single source of truth for system state. Key plans for configuration management:

* **Flake Structure:** We will use a multi-system flake model, similar to lucaruby’s approach, where we have a list of container hostnames and generate an output for each. For each container:

  * There will be a base module (common settings for all containers, e.g. networking defaults, NTP, maybe a standard user account if needed).
  * There will be a service-specific module enabling the necessary NixOS services/packages for that application (e.g. a module for Jellyfin, one for Nextcloud, etc.).
  * The flake’s `outputs.nixosConfigurations` will include each container, mapping the hostname to its combined config. This allows building or deploying with commands like `nixos-rebuild switch --flake .#jellyfin-container` for instance.

* **Container Naming and DNS:** Each container (host) will have a unique hostname (and likely a matching DNS name). We might adopt a naming scheme like `<service>.<env>.nixmox` (e.g. `jellyfin.prod.nixmox` or just `jellyfin` if on a separate DNS zone). The flake can pass a `primaryDomain` or similar parameter to each node config to help generate service URLs. For example, lucaruby’s config passes `primaryDomain = "datumine.co.uk"` into every node config, which can be used to form FQDNs. In our case, for a homelab scenario, we might use an internal domain (like `nixmox.lan`) or the user’s own domain for public-facing services. This will be configured centrally so all services follow the same domain pattern.

* **Service Modules:** We will incorporate community NixOS modules whenever possible:

  * **Authentik:** Using `nix-community/authentik-nix` flake which provides a NixOS module for Authentik. By adding it as a flake input, we can enable `services.authentik.enable = true` with minimal fuss. The module by default sets up Authentik’s core, a Redis, and a PostgreSQL (either embedded or pointed to external). We will configure Authentik’s settings via the Nix module (e.g., disable telemetry, set email SMTP config, etc. as shown in example). **Secret keys** for Authentik (like the Django secret key and admin password) will be provided via an environment file that is populated by SOPS at activation time. *Best practice:* use `services.authentik.environmentFile = "/run/secrets/authentik/authentik-env";` and let sops-nix provision that file with the sensitive variables.
  * **Mail Server:** We intend to integrate the *Simple NixOS Mailserver* module (from the upstream project on GitLab). This provides a full mail stack (Postfix, Dovecot, Spam filter, etc.) via NixOS module options. We’ll run it in its own container (`mail` container), and feed in required settings (domains, relay, accounts) through Nix config (with secrets like SMTP credentials or DKIM keys managed by SOPS).
  * **Media Servers:** **Jellyfin** is available in NixOS (`services.jellyfin` module exists). We will set that up in a media container with any hardware acceleration options if needed (e.g. VAAPI config). The **“Arr” stack** (Sonarr, Radarr, etc.) may not all have official NixOS modules, but we can install them via Nix packages or Docker images. Possible approach: run these .NET applications in the media container with systemd services, or use Docker-compose inside a container. Since one goal is high automation, we might prefer native Nix packaging to avoid manual container-in-container management. We will research Nix packages for Sonarr/Radarr/Lidarr; if not feasible, our flake can still use `dockerTools` to run them in Docker containers managed by NixOS (with Nix fetching the images).
  * **Nextcloud:** NixOS has a `services.nextcloud` module for Nextcloud which simplifies setup (database, php, etc.). We’ll use that in a separate container, possibly with an external database service if needed for performance (Nextcloud can use the common Postgres or MySQL container, but likely we’ll give it its own MariaDB in the same container or rely on our “infrastructure DB”).
  * **Databases:** Some services require databases (PostgreSQL/MariaDB). We can either run one **database container** serving multiple apps (as lucaruby did with a Postgres host), or run lightweight databases alongside each app. A middle-ground approach: one container for Postgres and one for MySQL to be shared, to avoid running too many DB instances. Authentik by default can run its own Postgres; for simplicity we might allow that to avoid cross-container dependencies. This is a design decision to make: *monolithic DB vs per-app*. Leaning towards per-app DB to keep containers independent (at cost of resource duplication).
  * **Vaultwarden:** This is an alternative to Bitwarden. There’s a NixOS module (`services.vaultwarden`) to set it up easily with an SQLite or MySQL backend and admin token. We will use that in a vaultwarden container. Again, secrets (admin token, SMTP creds) via SOPS.
  * **Guacamole:** Apache Guacamole (remote desktop gateway) might not have an official Nix module, but there is a package and it needs Tomcat and an SQL database. We might consider using Docker for Guacamole or try to package it via Nix. We’ll investigate existing Nix configs or use the official Docker image in a container if needed. Guacamole will also be integrated with Authentik (likely via LDAP or RDP file SSO).
  * **Kasm Workspaces:** Kasm is a proprietary-ish containerized desktop solution, usually deployed via Docker. Packaging it in NixOS could be complex. Our strategy might be to have a “kasm” container that simply runs the official Kasm Docker Compose. NixOS can run Docker, so we declare a systemd service to start Kasm’s docker stack. This keeps Kasm somewhat isolated from our other logic (since it’s heavy). We’ll mark this as optional (maybe not enabled by default).
  * **Monitoring Stack:** We will dedicate a container for monitoring. Likely use **Prometheus** for metrics collection and **Grafana** for dashboards. NixOS has modules for both. We’ll run node exporters on all containers (the `services.prometheus.nodeExporter.enable = true` on each) and have Prometheus scrap them. Grafana will connect to Prometheus and perhaps other data sources (e.g. Loki if logging). Lucaruby’s config mentions rolling out Prometheus exporters gradually, so we’ll take a similar incremental approach: ensure basic system metrics are collected, then add specific exporters (e.g. for Postgres, for Nextcloud, etc.) as needed.
  * **Logging:** For centralized logging, we plan to introduce a **Grafana Loki** or ELK stack in the future. Initially, journald on each container can suffice for local logs. But a central log aggregator is desirable. We could run a Loki container with Promtail agents on each container (or use a systemd journal forwarder) to ship logs to Loki, then view in Grafana. This will be part of the observability module. If time permits, we’ll integrate this early; otherwise it’s a future enhancement.
  * **Other Services:** There are many more potential services (“if it’s self-hostable, it can be integrated”). We will ensure the design is **modular**: adding a new service means defining a new NixOS module (and possibly a new container) without breaking others. Some additional services likely in scope: **Minio** (S3-compatible storage) – NixOS has a module for Minio, easy to add; **Restic** – not a service per se, but we will set up backup jobs (see Backup section); perhaps a **Git server** (Gitea) down the line, etc. We prioritize core services first and keep the framework extensible.

* **Secret Management via SOPS:** As mentioned, we will use **Mic92/sops-nix** for atomic secret provisioning. Concretely, we’ll do the following:

  * Maintain a **private repository** (or a directory encrypted with SOPS in the main repo) that contains YAML files for each container (e.g. `secrets/authentik.yaml`, `secrets/nextcloud.yaml`, etc., or one per node name like lucaruby’s structure). These YAML files hold keys, passwords, certificates, etc., encrypted with age or GPG.
  * In our flake, include the secrets repo as an input (if using a separate repo, as lucaruby does) or as local files. Pass the path to secrets into each NixOS configuration (e.g. via specialArgs like `nodeSecretsDir = ".../Nodes"`). Then the NixOS config for each container will specify `sops.defaultSopsFile = "${nodeSecretsDir}/${nodeHostName}.yaml";` so that at activation, the system can decrypt that file and load the values into the appropriate places (environment files or unit secrets).
  * Each container will have its own **age key** (or GPG key) for decryption. We can follow the method of deriving an age key from the container’s SSH host key. On first boot, we generate an age key (with `ssh-to-age`) and add it to the `.sops.yaml` policy for that host. This way, even if all containers use the same private repo, one container cannot decrypt another’s secrets – a good security isolation.
  * Ensuring that no secret leaks to the nix store: We’ll be careful to only use options that support external secrets (e.g. Authentik’s `environmentFile`, not hardcoding secrets in Nix code). Sops-nix will place decrypted files under `/run` (tmpfs) or other secure location, so they are not world-readable.

* **Dev vs Prod Config:** We will likely maintain two flake configurations (or profiles) for development and production. The differences might include:

  * Using smaller resource allocations or fewer replicas in dev.
  * Perhaps enabling debugging or using self-signed certs in dev vs Let’s Encrypt in prod.
  * The management plane could have a toggle to deploy to a “dev” Proxmox instance vs the “prod” cluster.
  * To implement this, we can use Nix flake profiles or simply branches. Another idea is to use a common flake but with an `environment` parameter that can conditionally set options. For example, our flake’s specialArgs might include `deploymentEnvironment = "prod"` or `"dev"`, which modules can check to adjust certain values.
  * In practice, for now we will set up a single environment (likely our lab cluster as prod) and later formalize the dev environment (which could even be a local single-node Proxmox or using containers inside a VM for testing).
  * We will document configuration differences and ensure that moving from dev to prod is just a matter of changing that environment flag, without drifting configurations.

Overall, our Nix-based configuration approach ensures that every aspect of the containers and services is captured in code. This means rapid redeployment, easy updates (just bump a version in flake, rebuild), and consistency across the board. New services are added by writing a new Nix module and adding an entry in a list – the automation will handle the rest (creating container, wiring it up).

### Central Management Plane (Go Backend & React UI)

A core component of NixMox is the **management application** that orchestrates everything. This will be a custom-built tool (in Go for backend, with a React/TypeScript frontend) that interacts with Proxmox and Git/Nix under the hood. Here’s how we plan this component:

* **Features of the Management Plane:**

  * **Service Catalog:** The UI will present a catalog of available self-hostable services (e.g. Nextcloud, Jellyfin, etc.). The user can select which ones to deploy. This catalog can be extensible (perhaps loaded from a config file or an online index).
  * **Deployment Orchestration:** When a user chooses to deploy a service, the backend will:

    1. Allocate a container name and IP (if not already).
    2. Add the service’s configuration to the Nix flake (or enable a flag for that service on a container).
    3. Trigger the build/deploy: this might involve using Nix to build a container image or pushing config to the container and running `nixos-rebuild`.
    4. Create the LXC in Proxmox via API with the appropriate template or base image.
    5. If using the “build image first” approach, upload the NixOS tarball to Proxmox and use `pct restore` or `pct create` with that tarball. Otherwise, create a minimal container and then remotely build it.
    6. Monitor the process, and report status to the UI (e.g. “Provisioning… configuring…”).
    7. Update DNS entries for the new service (so it’s reachable at the intended domain).
  * **Configuration Management:** The UI might allow some customization of each service before deployment – for example, setting volume sizes, choosing a version, or toggling certain options (like enabling a plugin). These would translate to NixOS module options. For instance, enabling Nextcloud’s OnlyOffice integration or specifying Jellyfin’s data path. We need to balance complexity; initially we can expose simple options (like “choose storage location”).
  * **Status and Health Monitoring:** The dashboard will show running containers, their resource usage (possibly via Prometheus metrics), and health (maybe ping an endpoint or check systemd status). It can highlight if a container is down or a service failed.
  * **Logs and Console:** It would be useful to have quick access to logs of a service from the UI (which could pull from a central logging system or run `journalctl -u service` via SSH). Also, possibly an embedded Web Console (maybe using the noVNC or by integrating Proxmox’s console for LXC) to troubleshoot containers directly from the UI.
  * **Multi-Node Awareness:** If the Proxmox cluster has multiple physical nodes, the management app could have the logic to pick which host to place a new container on (maybe based on resource availability or grouping). To keep scope manageable, initially we might assume a single Proxmox host or manual choice of host.
  * **User Management:** Because Authentik will handle end-user auth for the services, the management UI itself might also integrate with Authentik (for admin login). We might protect it with Authentik or at least a basic auth to ensure only the admin can orchestrate services.
  * **DevOps Integrations:** Using this in a larger context, perhaps the management plane can connect to GitHub (for our repo) to fetch updates or push changes. But more likely, we treat the flake as embedded and let the app manage it directly.
* **Interaction with Nix Flake:** We have two possible approaches to apply NixOS config changes:

  1. **Out-of-Band Builds:** The Go backend can programmatically update the flake Nix files (or generate them from templates) and then run `nix build` to produce a container image. Or run `nixos-rebuild` against a remote container using something like `nixos-rebuild switch --target-host`.

     * We could use tools like Colmena or morph as libraries, but since we are writing a custom tool, we might directly invoke `nixos-rebuild` over SSH for simplicity (essentially what those tools do). For example, after creating a container, use the container’s IP to run a rebuild with the flake’s config for that host.
     * Alternatively, use the Proxmox host to build images (via nixos-generators) then just start the container already configured. Lucaruby’s approach was to build a disk image (`.vma`) per node and restore it. For LXC, our analog is building the tar.xz template. We can automate that in Go by calling `nix` commands or using the Nix JSON APIs.
  2. **In-Place API:** Perhaps more advanced, but we could have an agent or use Nix’s remote build API to directly deploy config. A lightweight way is simply SSHing in and running `nix-channel --update && nixos-rebuild switch` (pointing at our flake in a Git repo or using `--flake github:devnullvoid/nixmox`). That requires the container to have internet or access to our repo. Since each container is NixOS, they can pull from a Git source if given access (like lucaruby does with deploy keys). This is an option for applying updates (e.g. automated upgrades).

  * We’ll likely start with the simpler **out-of-band build** approach for initial provisioning, then use in-place updates for day-2 changes. This means:

    * The management app maintains the desired state (in the flake) and pushes out changes by rebuilding containers.
    * Containers themselves can later do `nixos-rebuild` to apply updates (perhaps initiated via an SSH command from the manager).
    * Having the flake (or a portion of it) accessible to containers (like via a private Git repo) allows them to update themselves on command, which is a nice GitOps style. We may implement an automatic update mechanism for each container using this (like a systemd timer that checks for config changes and pulls).
* **Service Discovery & DNS:** The management plane will manage a registry of services and their addresses. We plan to use **DNS** as the primary service discovery mechanism, which the management app will update:

  * We’ll run an internal DNS server (see next section on networking) and when a new container is created, the app will add an A record like `jellyfin.nixmox.lan -> 192.168.50.10`. This can be done by editing the DNS service’s config (e.g. Unbound zone file or host entries) and reloading it, or by an API if available. Unbound on NixOS can be configured with local zones for our domain. We might generate a config snippet via Nix that contains all container hostnames pointing to their IPs.
  * Alternatively, because the flake already knows static IPs per node (if we choose static addressing in config), we can generate the DNS zone file via Nix as well. For example, we could have a NixOS module for the DNS container that reads the `allNodes` list and creates DNS records for each service automatically. This is a very declarative approach (less runtime API calls). The trade-off is we must rebuild the DNS service each time a new container is added – but that could be automated similarly. Given Nix’s nature, this approach fits well.
  * In addition to A records, we’ll manage any other discovery needs, e.g. SRV records if needed (not likely for our use-case, mostly HTTP-based apps). But certainly we’ll manage reverse DNS for completeness and any MX records for mail.
  * If DNS is not an option in some scenarios, an alternative could be etcd/Consul for service discovery. However, DNS is straightforward and universally supported, so we’ll stick with it as planned.
* **TLS and Domains:** The management app (and by extension our NixOS configs) will handle obtaining TLS certificates for service domains. We plan to leverage **Caddy’s automatic HTTPS (Let’s Encrypt)** for any public-facing domains. For internal services on a LAN domain, we might either use our own CA or just also use Let’s Encrypt with a real domain (if port 80/443 accessible). Many self-hosters use split-horizon DNS or nip.io-style tricks; we can keep it simple by recommending using a real domain or at least generating certificates via ACME DNS challenge. Caddy can request wildcard certs if given a DNS API token, which might be ideal if the user has a domain.

  * In NixOS, using Caddy’s ACME is as simple as enabling it on the host (we can do `services.caddy.locations.<site>.enableACME = true` if using the NixOS Caddy module, or just rely on Caddy’s default behavior to get certs).
  * The Authentik server itself will also need a certificate (for its web interface). We can similarly proxy it through Caddy or terminate TLS in Authentik using the same cert. Probably easier to treat Authentik like any app behind Caddy. Authentik’s outpost (if embedded) will work via the proxy too.
* **Internal Data Store:** The management app may need to store some state: e.g., credentials to talk to Proxmox, a list of available services and their Nix module metadata, and audit logs. We can store minimal state in a SQLite or just use the flake as the state (the flake is declarative desired state). The Proxmox credentials and other sensitive info can be provided via environment (and managed by our own use of SOPS for the management app’s config).
* **AI-assisted operations:** As a meta-point, we intend to use AI agents (like GitHub Copilot or ChatGPT) extensively to assist writing Nix modules, debugging configs, and even coding parts of the management application. The plan is to break development into small tasks and use AI to generate or refine solutions, which the human developers will test and integrate. This won’t directly affect the architecture, but it means we will maintain clear documentation and test cases to guide the AI and verify its output. For example, we might prompt an AI to write a NixOS module for Guacamole given certain parameters, or to write a Go function to call the Proxmox API. Ensuring we have this project plan and possibly a specification for each component will help the AI produce correct results.

In summary, the management plane ties everything together: it maintains the declarative config and interfaces with the infrastructure. By having a well-designed API and UI, it will simplify the user experience to a few clicks to deploy complex services. This is a major component to implement, but we will develop it iteratively – first focusing on core functionalities like container creation and basic start/stop, then adding more convenience features.

### Networking and Service Discovery

Reliable networking is crucial for inter-container communication and for users to reach the services. Our networking plan includes:

* **Layer 2 / IP Networking:** All containers will be attached to a Proxmox bridge (e.g. `vmbr0`) which connects to the LAN (or a VLAN). This means containers get IP addresses in a common subnet. We’ll use either DHCP reservations or static IP assignment. Static IP is convenient for stable DNS; Proxmox’s `pct create` allows setting a static IP for the container’s interface (which writes it to the container’s `/etc/systemd/network` config if using systemd-networkd, but since we set `manageNetwork = false` in NixOS, the container will rely on this injected config). We need to ensure no IP conflicts; perhaps keep a dedicated IP range for NixMox containers.

* **DNS Service (Unbound):** For service discovery, we will deploy **Unbound DNS** on a small NixOS container (or could be combined with another utility container). Unbound will serve as an authoritative DNS server for our internal domain (say `nixmox.lan` or the user’s domain). We’ll configure Unbound with a local zone mapping each service hostname to the container’s IP. For example: `authentik.nixmox.lan -> 192.168.50.2`, `jellyfin.nixmox.lan -> 192.168.50.3`, etc. This configuration can be generated via Nix (using the list of nodes). Unbound’s NixOS module supports specifying `extraLocalZones` or even integrating with the host’s `/etc/hosts`. We will likely manage a zone file explicitly for clarity.

  * All containers and possibly the LAN clients will use this DNS server. We will set each container’s NixOS config to use the Unbound’s IP as its primary nameserver (via `/etc/resolv.conf` or NixOS `networking.nameservers`). This ensures even inter-container name resolution works out-of-the-box.
  * If Unbound is set to listen on the bridge and the LAN, even external user devices (if pointed to it) could resolve the `.nixmox.lan` names. Alternatively, we might integrate with an existing DNS (for instance, if the user’s router is doing DNS, we could update that via DNS update if supported). But shipping our own DNS is more self-contained.
  * Unbound can also serve as a recursive resolver/cache for the containers for external domains, which is a nice bonus for performance/privacy.

* **Reverse Proxy Architecture:** Instead of exposing every container to the internet or even to the LAN, we will use a **central reverse proxy (Caddy)** to funnel external HTTP/HTTPS requests to the correct backend services. Likely, we will designate one container as the “gateway” (could be the same container running Unbound, or Authentik, but better as a separate proxy container).

  * **Caddy Setup:** Caddy will be configured with vhosts for each service’s external URL. If using a wildcard domain (e.g. `*.nixmox.example.com`), Caddy can catch all and proxy to respective container IPs. We’ll use Caddy’s NixOS module for configuration. This includes enabling automatic HTTPS via ACME.
  * **Integration with Authentik:** We plan to secure services behind Authentik using *forward authentication*. Authentik provides a **Proxy Provider** mode for integration with proxies like Caddy. In forward-auth, Caddy will check with Authentik (via its outpost) on each request to see if the user is authenticated, before allowing them through to the backend. The Authentik documentation provides a Caddy config snippet for this. We will implement:

    * Deploy Authentik’s **embedded Outpost** on the Authentik server (or possibly run an Authentik Outpost as a separate container if needed, but embedded should suffice for forward-auth).
    * In Caddy’s config for each site, add the `route { forward_auth ... }` directives as per Authentik docs. Essentially: all requests to, say, `jellyfin.mydomain.com` will be forwarded to `authentik` (at e.g. `auth.mydomain.com/outpost.goauthentik.io/auth/caddy`) for auth check. Authentik will handle login if needed, then Caddy will receive headers like `X-Authentik-Username` on the authenticated request.
    * We will ensure Caddy is set to copy the necessary headers to the backend (the Authentik outpost provides user info in headers). As the docs say, capitalization must be preserved in config. This allows certain apps to trust those headers for knowing the user (some apps might not natively support this, but many can accept an `X-Forwarded-User` or similar for basic auth proxy).
    * For applications that can do OAuth2 or SAML, Authentik can also act as an IdP directly. But using the forward-auth approach means we protect *all* apps, even those without built-in SSO support, with a single login portal.
    * We’ll configure Authentik with an LDAP directory (for legacy apps) and possibly as OIDC provider for those that support it (Grafana, Nextcloud could use OIDC). But the primary gate will be the proxy, which simplifies things: users will log into Authentik once per session and gain access to all apps (SSO).
  * **Network Flow:** In practice, a user’s request flow might be: Internet -> Caddy (HTTPS) on gateway container -> (if not logged in, Caddy forward\_auth -> Authentik login -> back to Caddy) -> Caddy reverse\_proxy -> service container (over HTTP). The service container sees either the user’s Authentik headers (if it knows how to use them) or is configured to trust that it’s behind an authenticated proxy.
  * We will also configure Caddy to handle WebSockets or any special subpaths as needed (some services like Guacamole or Kasm have websocket feeds; Caddy supports that by default in reverse proxy).
  * Non-HTTP services (like SMTP, IMAP for mail, or Plex DLNA perhaps) cannot be proxied by Caddy. For those, we’ll either expose them directly or have separate handling:

    * Mail: We will open ports 25, 587, 993 on the mail container via the Proxmox firewall or host NAT, since those need direct access. We’ll secure mail by usual TLS and Auth but not through Authentik.
    * If any service has its own client (not via browser), we’ll consider securing it with alternative methods (for example, Vaultwarden sync is direct but Vaultwarden itself can handle auth).
    * These exceptions will be documented, but majority of user-facing interfaces are web-based and will go through the central Caddy proxy.

* **Firewalling:** Proxmox provides firewall capabilities per container. We can leverage that to restrict access. For instance, we might by default block all inbound connections to containers except those needed (e.g., only allow the proxy or certain trusted networks to talk to them). Since everything goes through Caddy on the front, we can lock down containers like Nextcloud or Jellyfin to only accept traffic from the Caddy host (we could do this by network policy or by running them on a separate bridge network behind the proxy – however that complicates direct container-to-container communication).

  * A simpler approach: we might not enable Proxmox firewall initially (to reduce complexity), but rely on the fact that only the proxy’s domain is advertised. However, in a LAN scenario, someone could directly hit Jellyfin’s IP and bypass SSO. To mitigate that, we can configure the services themselves to *require* the Authentik headers or some shared secret if not proxied. Or we enforce firewall rules: e.g., allow port 8096 (Jellyfin) only from Caddy’s IP, not from general LAN.
  * We will likely implement such restrictions for better security, at least for sensitive services. The management app can automate adding firewall rules when creating containers.

* **Internal Communication:** Containers will talk to each other over the bridge network as needed:

  * e.g., Authentik container needs to send email via Mail container (SMTP) – the Authentik config will point to `mail.nixmox.lan` on port 587, and that resolves via our DNS to the mail container IP.
  * Nextcloud might use Minio (S3) – it would use `minio.nixmox.lan`.
  * Prometheus will scrape other containers – we can have it resolve `<target>.nixmox.lan` names or use the IPs.
  * Because DNS is in place and containers share the network, this should work seamlessly. We need to ensure any necessary ports are open between containers (by default on a LAN bridge they are).
  * If we wanted zero-trust, we could run all internal traffic through Wireguard or similar, but that’s likely overkill here.

Networking will thus be designed to be mostly self-configuring: once a container is defined in Nix, the DNS and proxy configs update to accommodate it. This declarative approach reduces manual steps in integrating a new service.

### Reverse Proxy & Authentication (Caddy and Authentik)

(*This topic overlaps with Networking above, but here we focus on the application-level integration and configuration details.*)

**Authentik** is our identity provider and will be set up early in the project, as it’s central to access control. Key implementation details for Authentik and Caddy:

* **Authentik Deployment:** We’ll deploy Authentik on NixOS using the community module as discussed. It will run on, say, `authentik.nixmox.lan` (and perhaps an external domain like `auth.mydomain.com`). We’ll generate an admin account and connect Authentik to an email server (for user invites, password resets) – likely pointing it to our mail container. We also plan to enable the LDAP directory in Authentik, which makes Authentik act as an LDAP server. Many enterprise apps (Grafana, Nextcloud, etc.) can use LDAP for authentication. We will consider enabling that to give apps an alternative auth method if forward-auth is not suitable.
* **Outposts and Providers:** In Authentik’s terminology, an Outpost is the component that actually does the authentication flow for proxied apps. We have two choices:

  1. **Embedded Outpost:** Authentik can itself act as the outpost (the default “embedded” outpost listens on the main Authentik service port for `/outpost.goauthentik.io/*` paths). This is simplest – we just need to ensure our Caddy is configured to reverse\_proxy those outpost endpoints to the Authentik service. The Authentik module likely sets up the embedded outpost on port 9000 by default.
  2. **Standalone Outpost:** Run a lightweight Authentik Outpost container that communicates with the main Authentik (this can reduce load on Authentik for high traffic). For our scale, embedded should be fine.

  * We will start with the embedded outpost. In Authentik’s admin, we’ll configure a **Proxy Provider** with “Forward auth (domain level)” mode and set up Property Mappings to send user info in headers like `X-Authentik-Username`. This provider will be tied to an Application entry representing, say, “NixMox Services”. We’ll list all our service domains under that application so that one Authentik login session covers all.
  * Authentik will generate the URL for forward\_auth (something like `https://auth.mydomain.com/outpost.goauthentik.io/auth/caddy`).
* **Caddy Configuration:** On our Caddy reverse proxy, we will incorporate the forward\_auth settings. In NixOS, we can use `services.caddy.extraConfig` to inject custom Caddyfile directives. For each site we proxy:

  ```caddy
  {service_domain} {
      route {
          # forward authentication
          forward_auth {authentik_outpost_url} {
              uri /outpost.goauthentik.io/auth/caddy
              copy_headers X-Authentik-Username X-Authentik-Groups X-Authentik-Email ...:contentReference[oaicite:61]{index=61}
              trusted_proxies private_ranges
          }
          # backend service
          reverse_proxy {service_container_ip}:{port}
      }
  }
  ```

  We will transpose such config to the Nix Caddy module (which allows template strings for domains, etc.). The snippet from Authentik docs shows which headers to copy and the importance of their capitalization. We’ll be careful to include all relevant headers (username, email, group membership, JWT if needed for advanced integration). The `trusted_proxies private_ranges` ensures that Authentik only accepts forward-auth requests from our internal proxy’s IP.
* **Header Authentication:** After Caddy authenticates a user via Authentik, it will inject headers into the request sent to the backend. For some services, we can configure them to trust these headers:

  * For example, *Grafana* can be configured with Auth Proxy mode where it trusts `X-WEBAUTH-USER` header for login. We can map Authentik’s `X-Authentik-Email` or username header to that.
  * *Nextcloud* doesn’t directly support auth via reverse proxy headers, but we could use its OIDC login app or just rely on internal login (we might just use OIDC here).
  * *Jellyfin* currently doesn’t support external SSO directly; we might not enforce Authentik for Jellyfin initially (or only protect it via the forward-auth portal but still require logging into Jellyfin separately – not ideal). There is an OAuth plugin for Jellyfin we could explore.
  * We’ll decide on a per-app basis: some will fully SSO (user logs in through Authentik and automatically enters the app), others might still have local accounts but at least the entry point is protected. Over time, we aim to eliminate separate logins by using Authentik’s capabilities (OAuth2 provider, SAML, LDAP).
* **Portal Page:** Authentik provides a user portal where all applications can be listed. We might use this as a launchpad for users – a single page listing “Jellyfin”, “Nextcloud”, etc. When clicked, those go through Authentik’s launch mechanism (ensuring login). This is a nice UX and we get it out-of-the-box with Authentik. Our documentation to end users can be: go to `auth.mydomain.com` to see all your services.
* **Admin Access:** We should secure the management UI (the one we are building) as well. Perhaps we protect it behind Authentik too, or at least a password. It could even be an Authentik application itself. Given it’s mainly for admins, we might have a separate Authentik group for admins and require that for access. Caddy can enforce that by checking the `X-Authentik-Groups` header contains “admins”.
* **Testing the Flow:** We will need to test the end-to-end flow for multiple scenarios:

  * New user on Authentik (sign-up or admin-created) can log in and access apps appropriate to them. (We might tie app access to Authentik groups – e.g., only certain users can access certain apps. Authentik can inject entitlements in headers too which advanced apps could use.)
  * Ensure logout flows propagate (Authentik can force re-auth if user logs out).
  * The forward-auth scheme has some tricky bits (like ensuring Authentik knows where to send the user back). We must configure the Authentik Provider with the correct redirect URLs (the docs mention using domain-level forward auth which is what we’ll do). We might need to add Caddy’s forward\_auth address as an “allowed redirect” in Authentik.
  * We will consult Authentik’s official guide closely during setup to avoid pitfalls (such as the Reddit threads that indicated trouble with Caddy forward\_auth if misconfigured).
* **Non-HTTP Auth:** For services like SMTP/IMAP, Authentik can’t directly help. But Authentik *does* have a LDAP service; we can potentially have our mail server use Authentik’s LDAP for user accounts (so that email credentials are unified with SSO credentials). This is advanced and optional – it might be simpler to keep mail accounts separate. However, it’s a possibility if we want one identity across everything.
* **Caddy vs Traefik/nginx:** We chose Caddy for its simplicity and automatic TLS. There is a possibility we might consider **Traefik** (popular in container environments) or **NGINX**. But NixOS has good modules for Caddy and our team is familiar with it. If any blocking issue arises with Caddy, we can pivot, but currently Caddy forward\_auth is supported and documented by Authentik, so it should work well.

Implementing the reverse proxy and SSO is a critical part of making the platform user-friendly and secure. It will likely be one of the first integrations we set up (after getting a couple of services running) because it ties into how users access everything.

### Modular Service Integration and Scalability

Given the broad range of services we plan to support (media, file sharing, dev tools, etc.), our design emphasizes **modularity**:

* Each service’s deployment is encapsulated in either a NixOS module or a container definition. This means services can be added or removed by toggling those modules without affecting the rest of the system (other than resource usage).
* We will maintain a **repository of Nix modules** for various apps. Some come from NixOS/nixpkgs, some from community flakes, some we might write from scratch. Over time this could form a library for self-hosted applications on NixOS. For instance, if we want to add a new app like `photoprism` (just as an example), we can create a module enabling its Docker image with proper volumes and add it as a new container with minimal changes to the overall system.
* **Scalability considerations:** While this is primarily a homelab/hobbyist project, we keep in mind the possibility of scaling out:

  * Proxmox can handle dozens of containers on decent hardware. We should monitor resource usage and maybe provide recommendations (like “media server container should have at least 4GB RAM”, etc., which our management app can enforce or suggest).
  * If one wanted to scale a particular service (e.g., multiple instances behind a load balancer), our current design isn’t aimed at that (that’s more Kubernetes territory). However, one could spin up another container for the service and manually configure load balancing in Caddy if needed. This is outside initial scope but the platform doesn’t fundamentally prevent running two Jellyfins, for example.
  * Storage: many services need persistent storage (Nextcloud data, media files, databases). We’ll use mounted volumes (Proxmox bind-mounts or directory storage). It might make sense to have an underlying ZFS or Btrfs on the Proxmox host for snapshots, which Proxmox can integrate with. But that’s deployment detail. We will configure containers to mount host directories for large data (for easy backup and not bloating the root FS). In NixOS config this can be done by defining mount points in `fileSystems` that correspond to e.g. `/data` mount inside container pointing to a host path.
  * Backups of data will be handled by restic as described next; however, for very large media files (e.g., movies for Jellyfin), maybe the user doesn’t want to back those up offsite due to size – we can make backup granular (choose which paths to include).
* **High-Level Automation & Customization:** Our goal is to automate the common tasks (deploying standard apps) but still allow customization. Some strategies:

  * Provide sensible **defaults** in each module, but allow overriding them via a config file or UI inputs. For example, Nextcloud by default might get a 100GB volume, but user can customize the size or mount location.
  * Perhaps allow the user to provide custom Nix code snippets through the UI for advanced cases (this is tricky, but maybe a text field for “additional Nix config” per container for power users, which the app will include when rebuilding).
  * Use **profiles**: e.g., a “Media Server” profile that deploys Jellyfin + Sonarr + Radarr in one container or in a set, depending on user choice. This can be pre-defined combinations in the UI that flip multiple switches.
  * Despite high automation, document clearly how someone can manually adjust things if needed (for instance, instruct how they could git clone the flake and edit it if the UI doesn’t expose an option). Since our config is declarative, advanced users could fork or modify the flake to extend the system beyond the UI’s capabilities.

By keeping things modular and declarative, we ensure the project can grow to include “much more” as the user desires, without major refactoring. We just add new building blocks.

## Best Practices and Security Considerations

Throughout the project, we will adhere to best practices to ensure a secure and maintainable system:

* **Reproducibility:** Because everything is defined in Nix, any team member or contributor can reproduce the setup. We will pin Nixpkgs versions (flakes lockfile) to have a known good state. Updating will be deliberate (we’ll periodically update to newer NixOS releases or package versions, testing in dev first).
* **Least Privilege:** Run containers unprivileged by default (no unnecessary Linux capabilities). Grant exceptions only when required (e.g., GPU or Fuse access for media might require adding some allowed devices as shown in wiki for special cases). Services within containers run as unprivileged Unix users (NixOS modules usually handle this).
* **Firewall & Isolation:** Use firewall rules on Proxmox or within NixOS (`networking.firewall`) to limit exposure. We will close all ports on container OS level except those needed. For instance, a Nextcloud container might only allow 80/443 (and even those only from Caddy’s IP if possible). Proxmox’s host firewall can also restrict container network egress if needed (some might want to prevent a compromised service from calling out; optional advanced feature).
* **Regular Updates:** NixOS makes it easy to apply updates (just rebuild with latest packages). We plan to leverage this by enabling something like `system.autoUpgrade` on containers or a central updater. Possibly integrate **nixOS auto-upgrade** or home-grown scheduling so that security patches (especially for internet-exposed software) are applied. Since we have Authentik and critical internet-facing components, we should keep them updated. We can even use **Flake update bots** or Renovate to track new versions of community modules.
* **Secrets Protection:** Already covered via SOPS, but to reiterate: no secret goes in plaintext in Git. We’ll use robust encryption (likely age with a strong key). Also ensure secrets in memory are limited to only the service that needs them (SOPS-nix handles this by creating files with correct permissions).
* **Backups and Recovery:** Ensure that in a disaster scenario (loss of a node, etc.), we can recover quickly. Because NixOS config is in Git, a new Proxmox host could deploy all containers afresh. The data recovery will come from restic backups. We should document recovery steps and maybe build a **script to bootstrap** a new Proxmox with NixMox (e.g., automatically create all defined containers from scratch). This script can leverage the flake outputs (like lucaruby’s `nix build .#NodeName` to produce images).
* **Monitoring & Alerts:** Use Prometheus alerts to catch issues (high CPU, low disk space, service down). Possibly integrate with a notification service (email or Telegram alert). This ensures the operator is aware of problems.
* **Logging and Auditing:** Maintain logs for both the services and the management actions:

  * Services logs centralization (via Loki or similar) helps in troubleshooting security incidents.
  * The management app should log actions like “Created container X”, “User Y triggered deployment of Z”. This audit trail is useful for multi-admin scenarios or debugging automation.
* **User Data & Privacy:** If this hosts personal data (which likely, e.g., Nextcloud files, Vaultwarden passwords), we must secure those properly. For Vaultwarden, we’ll enforce HTTPS and perhaps encourage using the upstream admin invite system (Vaultwarden data is end-to-end encrypted per user anyway). For Nextcloud, ensure it’s not accessible without Authentik SSO unless configured.
* **Testing Changes:** Use the development environment to test any major changes. For instance, upgrading Authentik or switching a module should be tried in dev first. Nix’s virtualization options (like using `nixos-container` or `nix run -c nixos-test`) could simulate some changes. We might even write NixOS tests (VM tests) for certain configurations – e.g. boot an Authentik VM test to ensure it comes up properly. The authentik-nix flake has a basic VM test we can refer to.
* **Community Engagement:** Since we’re using community projects (authentik-nix, sops-nix, etc.), we will keep an eye on their updates/issues. If we encounter problems, we’ll search forums (Discourse, Reddit) which have a wealth of knowledge on NixOS/Proxmox quirks (like the threads on LXC networking and persistent config). For example, one Discourse note suggests that using systemd-networkd in NixOS LXC can conflict with Proxmox networking; our approach of `manageNetwork=false` and letting Proxmox handle it is informed by such discussions.
* **Documentation:** We treat documentation as a first-class part of the project. We will maintain a **docs site or README** that explains how to use NixMox, how to add new services, how the Authentik integration works, etc. This will also cover any manual steps (like obtaining API keys for OAuth integrations, or setting DNS records if external). Good docs are a best practice to make the project usable by others and maintainable by us long-term.

Following these best practices will help avoid common pitfalls (e.g., config drift, security loopholes) and ensure the environment remains stable and secure.

## Monitoring, Logging, and Backup Strategy

A robust self-hosted platform must include monitoring of system health, comprehensive logging, and reliable backups:

### Monitoring & Alerting

We will implement a monitoring stack centered on **Prometheus** and **Grafana**:

* **Prometheus Server:** A NixOS container (perhaps named `monitoring`) will run Prometheus. It will scrape metrics from all containers and itself. NixOS makes this easy:

  * Enable `services.prometheus` on the monitoring host with a configuration that includes scrape targets for each container. Thanks to our service discovery, we can list targets by DNS name (e.g., `jellyfin.nixmox.lan:9100` for node exporter). We’ll also scrape specific application metrics if available (for instance, if we enable `services.postgresql.exporter` on the Postgres container, etc.).
  * Each container will run the **Node Exporter** (`services.prometheus.nodeExporter.enable = true`), which exposes basic CPU/memory/disk metrics. We might also enable the **Caddy exporter** or use the built-in metrics if any to monitor the reverse proxy.
  * For application-level metrics: some apps (like Nextcloud) don’t have built-in Prom metrics, but we can monitor their health (e.g., response time of a login page via a blackbox exporter, or just CPU usage as proxy). Others like Grafana, Prometheus itself, etc., do have metrics endpoints.
* **Grafana:** Another container (or possibly the same monitoring container) will run **Grafana** for visualization. NixOS’s `services.grafana` module will set it up and we can pre-provision dashboards for common stats (there are community dashboards for Linux servers, Docker, etc., which we can adapt to NixOS metrics). Grafana will connect to Prometheus as the data source.

  * We can also use Grafana for alerting if we choose Grafana Alertmanager, but more straightforward is to use **Alertmanager** (comes with Prom stack).
* **Alertmanager:** Configure Prometheus to use Alertmanager (could run on the same monitoring container). Set up some basic alerts, e.g.:

  * Container down (node exporter missing).
  * High CPU or memory usage sustained.
  * Low disk space on host or containers.
  * Specific service not responding (we can have a blackbox probe or even a simple script that checks main websites via HTTP).
  * These alerts can notify via email (send to admin’s email, possibly using our own mail server to send out) or other channels.
* **Integration with Management UI:** It would be nice if the management UI could also display some stats (like a summary of CPU/RAM of each container). We can either query Prometheus from the UI or have the UI collect its own metrics via `pct` (Proxmox API can give resource usage per container). Possibly we’ll do a lightweight integration: the UI calls the Proxmox API to get CPU/Memory usage periodically to show a dashboard. For more detailed metrics, the user can jump into Grafana.
* **Logging (Centralized):** As mentioned, we aim to aggregate logs:

  * **Grafana Loki**: We can deploy Loki along with Promtail on each container. Promtail will tail journald logs and push to Loki. Grafana can then show logs and allow searching across containers. This is a modern, fairly lightweight logging solution.
  * Alternatively, a classic **ELK Stack** (Elasticsearch, Logstash, Kibana) could be used, but that’s heavy for our needs. Loki is preferred for simplicity.
  * We could start without centralized logging and rely on `journalctl` on each host (accessible via `nixos-rebuild` or the management UI’s console), then add Loki once core functionality is stable.
  * If using Loki: deploy it on the monitoring container (it can be co-located with Prom/Grafana, they don’t conflict). Use NixOS `services.loki` module. Configure promtail on each container via NixOS (there’s a `services.fluentbit` or `services.graylogSidecar` or simply run promtail binary as systemd service).
* **Audit Logs for Authentik/Caddy:** Ensure that Authentik logs authentication events (it does, by default to its log or DB) – we might export those logs too in case we need to investigate access issues. Caddy’s access logs can be enabled and centralized via Loki, which can help see who accessed which service and when.
* **UX for Monitoring:** Provide at least a basic Grafana dashboard out-of-the-box to the user, covering:

  * CPU/RAM of each service (small multiples graphs).
  * Disk space usage (with an alert if >80%).
  * Network traffic maybe.
  * Uptime of services.
  * If possible, number of users logged in (maybe from Authentik or apps metrics).
  * We will leverage existing community dashboards when possible to save time.

### Backups and Recovery

Backups are critical. We plan a multi-layer backup strategy:

* **Data Backups with Restic:** We will use **Restic** to perform backups of important persistent data. Restic is ideal as it’s cross-platform, secure (encrypts backups), and efficient with deduplication.

  * We will set up a dedicated container or even just use the monitoring container to run backup jobs. Alternatively, each service container could run its own restic job to back up its data. The choice depends on where we want the backup credentials stored and job control:

    * **Central backup container:** This container (could be called `backup`) will have access (via network or mounts) to all data directories of other containers. For security isolation, giving it network access might be easier: for example, it could SSH into each container (using key auth) and run restic on the remote data, or use restic’s REST server mode on each container. But that’s complex.
    * **Per-container backups:** Simpler – install restic in each container and schedule a systemd timer/cron to run `restic backup` on its own data directories. Each container would push to a common remote repository (with unique host tags). This aligns with the idea of each container being relatively independent.
  * We will likely go with **per-container restic jobs**, using the same repository (to deduplicate across data). We’ll store the restic repository password in each container’s secrets (so they all use the same repo password). The backup target could be:

    * A cloud storage (Backblaze B2, as lucaruby used, or AWS S3, etc.). B2 is cost-effective for personal backups. We’ll need API keys for that, stored via SOPS.
    * Alternatively, a local target like another NAS or an attached disk. We could also run a **Minio** container to act as an S3 target for restic (Minio itself can then snapshot to an external disk). If the user doesn’t want cloud, this is an option.
  * Restic can be run nightly for most data. We might schedule more frequent (hourly) for critical small data (e.g., database dumps).
  * For databases: It’s often better to perform a dump and back up the dump rather than live DB files. For simplicity, we might ensure that each database writes to a persistent volume and trust restic’s consistency (restic can snapshot LXC? Not easily like ZFS, but we could stop service briefly during backup, or use the database’s internal snapshot feature). However, a safer route:

    * Schedule a pre-backup task: e.g., a script in the database container that runs `pg_dump` or `mysqldump` to a file, then include that file in restic backup. This ensures a consistent backup of data without needing to stop the DB.
    * We’ll implement such hooks for services with complex data (Nextcloud files are fine to copy live, but its database should be dumped; same for Authentik’s Postgres if not external, etc.).
  * **Retention Policy:** We’ll configure restic to forget old snapshots: e.g., keep daily backups for 7 days, weekly for 4 weeks, monthly for 12 months, etc. This prevents unlimited growth.
  * We will monitor backup success and perhaps log it to Prometheus (maybe via an exporter that checks last backup timestamp).
* **Configuration Backup:** The NixMox flake and any other config (like Authentik configuration exports) should be backed up as well. Since the flake is in Git (GitHub repo `devnullvoid/nixmox`), that in itself is a backup (assuming remote). We might still want to include a copy in restic or have a second remote for Git (like mirror to another Git service) for redundancy.
* **Proxmox Backup:** Proxmox has a built-in backup tool (vzdump) for containers. We could encourage users to use PVE’s backup to take full container snapshots occasionally (like a weekly full backup separate from restic). However, those backups are not as deduplicated or incremental as restic and can be large. Our stance is that since NixOS containers can be rebuilt from config, a full image backup is less crucial; focusing on data backup is enough. But for convenience, we might integrate with **Proxmox Backup Server (PBS)** if the user has one, or at least allow the management UI to trigger PVE’s backup for a container on demand.
* **Testing Restores:** We will test the restore process: e.g., simulate losing a container, then re-create it from Nix config and restore its `/data` from restic. Document these steps. Possibly automate it by having a “restore” function in the management app for each service: if something is broken, delete container, create new one, and prompt user to run restic restore (maybe not fully automated, as that’s complex to do non-interactively).
* **Snapshots for Upgrades:** Before upgrading a critical service (like major version bump), take a snapshot. This can be a LXC snapshot (Proxmox supports LXC snapshot if on ZFS/LVM-thin). We could incorporate that in our deployment: e.g., management app could snapshot container, then apply upgrade (nixos-rebuild). If something goes wrong, we can rollback by reverting snapshot. NixOS also has an internal rollback (previous generation), but for container-level issues, snapshot is safer. We’ll explore using the Proxmox API to snapshot containers as part of an upgrade workflow.
* **Back up Authentik data:** Authentik stores data in a Postgres database (which we might run locally in the container). We must back that up too. Possibly we’ll rely on restic capturing the DB file or do a pg\_dump regularly.
* **Mail server backup:** Mail data (Maildir, etc.) will be in the mail container’s volume. That will be part of restic backups. Optionally, MX secondary? But likely outside our scope.

In essence, by using **restic** we get an efficient, encrypted backup solution with support for many backends. This covers the data. The declarative configs cover the system. Together, we can recover from catastrophic failure by redeploying configs and restoring data. We will script as much of this as possible to minimize manual work in a crisis.

## Development Approach and Project Roadmap

To execute this project, we will break the work into stages and leverage automation (including AI assistance) at each step. Below is a proposed roadmap with steps and milestones:

1. **Initial Environment Setup (Week 0-1):**

   * Set up a Proxmox VE host (or ensure access to an existing cluster). Configure networking (assign a bridge for containers, etc.).
   * Prepare a development workstation with Nix installed (for building flakes) and Go/Node for coding the management app.
   * Verify the ability to launch a basic NixOS LXC on Proxmox manually as a proof of concept (using the wiki instructions or the provided script). This includes downloading the NixOS LXC template and creating a test container, making sure we can `pct enter` and `nixos-rebuild` inside it successfully.
   * Initialize the Git repository (`devnullvoid/nixmox`) with a baseline Nix flake structure. Perhaps start from a template flake with one simple container defined (like a “hello world” NixOS container that just runs SSH and echo service).

2. **Core NixOS Flake Implementation (Week 2-3):**

   * Define the **multi-container flake** as described: create a `modules/` for common config and service-specific configs, a `hosts/` or `Nodes/` directory for individual container definitions, and update `flake.nix` to generate `nixosConfigurations` for each.
   * Include necessary flake inputs: `nixpkgs`, `sops-nix`, `authentik-nix`, etc. Ensure we can build each config.
   * Test building a container image with `nixos-generators` for one container (e.g., an SSH-only container). Import that into Proxmox and boot it. This will validate our Nix config and image generation pipeline.
   * Integrate **SOPS-nix:** Set up a dummy secrets repo and get a basic secret (like a root password or an API token) to flow into a container’s config using sops-nix, confirming decryption works on the container.
   * At this stage, we can also bring up a container with **Caddy** and verify that we can reach it via the network (without Authentik yet). This tests networking and our ability to enable a NixOS service module.

3. **Authentik and SSO Integration (Week 4):**

   * Deploy the Authentik container via Nix. This includes configuring Authentik with an admin user and its outpost provider.
   * Deploy the Caddy proxy container and configure one test domain with forward\_auth pointing to Authentik. For initial testing, we can use self-signed certs or local CA for HTTPS if Let’s Encrypt is not yet set up (or use HTTP to start).
   * Manually configure Authentik’s UI: create a Provider and Application for forward auth, etc., following Authentik docs. This is a one-time setup (though Authentik also has APIs; scripting it is possible but can be a future improvement).
   * Test the login flow: try to access a dummy service behind Caddy, get redirected to Authentik, login, and back. Adjust configurations until this works.
   * Once working, document the steps or automate parts of it (e.g., use Authentik’s YAML import capability to define the provider/application if available, so a fresh install can be set up easily).

4. **Implement Core Services (Week 5-7):**

   * **Mail Server:** Set up the mail container using Simple NixOS Mailserver module. Configure a basic domain, one test mailbox. Verify sending/receiving (perhaps set DNS MX for a test domain to point to it). This includes integrating it with Authentik LDAP if we choose, or at least ensuring Authentik can send emails via it.
   * **Media Stack:** Deploy Jellyfin container. Load some test media and ensure it’s accessible. Then Sonarr/Radarr: these might be packaged; if not, use docker images via Nix (we might ask AI to help write a Nix module to run Sonarr in a container!). Ensure they can reach Jellyfin or a download client (a torrent client could be another container to consider). This can get complex, so maybe just set up the basics and leave detailed automation (like linking Sonarr to a torrent container) for later.
   * **Nextcloud:** Deploy Nextcloud with a MariaDB (either inside same container or separate). Test basic file upload, etc. Plan out how to integrate Authentik (maybe via OIDC login app or at least forward-auth protect).
   * **Vaultwarden:** Deploy and test web vault login.
   * **Grafana & Prometheus:** Bring up monitoring container with node exporters on others. Import a dashboard and check metrics.
   * It’s a lot to configure, but we can parallelize or gradually add. At each addition, use our flake to rebuild and deploy. Likely we’ll iterate: add one service, deploy, fix issues, then move to next. Each service integration will reveal any missing Nix knowledge or needed modules, which we can consult documentation or use AI help for (for instance, “How to set up X on NixOS” are queries we’ll feed to GPT or search).

5. **Management UI & API (Week 8-10):**

   * Start implementing the Go backend. Outline the REST API (e.g., endpoints for “GET /services”, “POST /deploy”, “GET /containers/status”). Use a Go web framework or stdlib.
   * Implement functions to interface with Proxmox: maybe use the Proxmox API via HTTPS (requires obtaining an API token or using username/password; we’ll store those via SOPS). Alternatively, use SSH to run `pct` commands on the Proxmox host. Evaluate which is more straightforward. Possibly the Proxmox API is better structured and avoids needing direct shell access.
   * Implement a minimal UI in React that can list available services from a JSON, and when clicked, call our API to deploy one. This might start as a very rudimentary interface.
   * Tie in the Nix flake operations: The backend could maintain a working copy of the flake. When a deploy request comes, the backend modifies some flake config (e.g., adds a hostname to the list, writes a module enabling that service), then either commits and runs `nixos-rebuild` on target or builds an image. This part is complex; initial version could cheat by having pre-defined all services in flake but toggled off, and the deploy action simply toggles on and rebuilds. Ultimately, dynamic editing is needed for full flexibility, but we can simplify in first version.
   * Test deploying through the UI a couple of services, ensure the flow triggers container creation and the service comes up accessible.

6. **Testing & Hardening (Week 11-12):**

   * Conduct end-to-end testing of scenarios: fresh installation, adding a service, removing a service, restarting containers, updating a service (e.g., change a config value). Ensure idempotency (running deploy twice doesn’t create duplicate, etc.).
   * Load testing basic performance (can the system run all these services concurrently on given hardware?). Tweak resource allocations if needed.
   * Security testing: try accessing services directly via IP (should be blocked if possible), try an Authentik bypass (shouldn’t be possible), ensure no sensitive info is exposed in logs or UIs.
   * Backup test: simulate data creation (upload files to Nextcloud, add media, etc.), run restic backup, then simulate loss (delete a file or remove container) and restore from backup. Verify integrity.
   * Fix any bugs uncovered. Polish configurations (e.g., ensure proper service dependencies in NixOS, like start order for databases before apps, etc., which NixOS usually handles if declared properly).
   * Write documentation for usage and for contributors. Possibly prepare a demo or screenshots.

7. **Project Handover / Iteration:**

   * At this point, we should have a functional prototype. The plan is to use AI during development for tasks like writing Nix expressions, solving dependency issues, and even generating parts of the documentation. We will keep prompting it with specific tasks (for example, “Configure Sonarr on NixOS” or “Generate a Go struct for Proxmox API JSON”). Each time, we validate and integrate its output.
   * We’ll likely go through another iteration cycle adding any deferred items (like Kasm, or advanced config options), depending on time and priorities.

By following this roadmap, we anticipate having a comprehensive, working system. The use of iterative development with feedback at each stage will ensure we catch issues early (for example, if Authentik forward-auth doesn’t work initially, we focus on fixing that before moving on).

Throughout development, we remain open to adjusting the plan as we learn more. For instance, if we find an existing tool that does some part of this (like a Colmena-based deployment) better, we might integrate it rather than reinvent it. The plan above is ambitious but leveraging Nix’s capabilities and existing modules greatly reduces the heavy lifting for service configuration, allowing us to focus on integration and automation logic.

## Conclusion

In this plan, we outlined how to build **NixMox**, a highly automated self-hosting platform using NixOS containers on Proxmox. We covered everything from technical architecture and security practices to the step-by-step development roadmap. The system will provide a modern way to run dozens of self-hosted services with single sign-on and unified management, benefiting from NixOS’s reproducibility and Proxmox’s efficient virtualization.

By proceeding with the above steps and best practices, we aim to move confidently into the development phase. The extensive use of Nix and the guidance drawn from similar projects give us a strong starting point. Potential challenges (like NixOS-on-LXC quirks or complex service setups) have been identified with possible solutions. Where needed, we’ll lean on the NixOS community resources and automate as much as possible, including using AI assistance for coding tasks.

With planning complete, the next phase is to implement and iterate rapidly, turning this plan into a functional reality. The end result will be a modular, declarative, and user-friendly self-hosting solution, which can be extended and maintained with minimal friction – fulfilling the vision of **NixMox** as an orchestrator for all things self-hostable.

**Sources:**

* NixOS-Server (Multi-node NixOS config examples, Authentik, SOPS, etc.)
* NixOS Wiki – Proxmox LXC Guide (Container setup details)
* Mario Sangiorgio’s Blog – NixOS in Proxmox LXC (Image build and LXC tips)
* Authentik Documentation – Caddy forward\_auth integration
* NixOS Modules – Authentik Nix flake usage
* VGHS-lucaruby’s README (Secrets management and build process)
* Project references for services (Simple NixOS Mailserver, restic, etc.)

