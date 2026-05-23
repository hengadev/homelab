# Homelab Context

## Purpose

Personal infrastructure platform running on a single Hetzner VPS. Started as a
personal website host, now a growing set of self-hosted tools. The guiding
principle is full reproducibility: the entire stack can be torn down and
re-created with three commands (`make init`, `make setup`, `make deploy`).

---

## Glossary

### Homelab Stack
The set of services managed under `/opt/homelab/` via the main
`docker-compose.yml`. This is the authoritative boundary of "what the homelab
runs." New self-hosted services are always added here.

**Not to be confused with:** the Cluo tenant (see [Temporary Tenant](#temporary-tenant-cluo)).

### Portfolio
Personal website at `henga.dev`. A containerized app (image: `henga/portfolio`)
displaying CV and projects. Blog section planned but not yet live. Stateless —
no persistent volume; the Docker image is the sole source of truth.

### Vaultwarden
Self-hosted password manager at `vault.henga.dev`. The only stateful homelab
service. Its data lives at `/opt/homelab/data/vaultwarden` on the host and is
the sole target of the backup strategy. User registrations are disabled —
single-user instance.

**WebSocket routing (do not remove):** The Caddyfile routes
`/notifications/hub` to port `3012` on the Vaultwarden container *before* the
catch-all reverse proxy to port `80`. This is required for real-time vault sync
across clients. Removing or reordering that route breaks sync silently — clients
fall back to polling without any visible error.

### Caddy
Reverse proxy and TLS termination layer. Listens on ports 80/443 and routes
inbound traffic to backend containers over the `proxy` Docker network. Handles
automatic HTTPS via Let's Encrypt. The `Caddyfile` is the authoritative list of
exposed services and their subdomains.

### Backup
Nightly encrypted backup of Vaultwarden data (runs at 03:00 via cron inside
the `vaultwarden-backup` container). Flow: `tar` → GPG symmetric encryption
(passphrase) → upload to S3. The S3 bucket has versioning and SSE-AES256
enabled. A dedicated IAM user scoped to the backup bucket handles credentials.

On a fresh deploy, Ansible auto-restores the latest backup from S3 if the
Vaultwarden data directory is empty.

### Deploy
The full service deployment cycle, triggered by `make deploy` or automatically
by GitHub Actions on push to `main`. Runs the Ansible `deploy.yml` playbook,
which syncs compose files, templates the `.env`, pulls images, and starts
containers.

### Temporary Tenant (Cluo)
A separate application (not a homelab tool) co-hosted on this VPS to avoid the
cost of a second server. Cluo runs under `/opt/cluo/` and `/opt/cluo-staging/`
with its own compose files and its own Cloudflare zone (`clientvault.fr`).
It will be migrated to its own VPS later. Treat it as out-of-scope when
reasoning about homelab architecture.

---

## Infrastructure

| Layer | Tool | Responsibility |
|---|---|---|
| Provisioning | Terraform | Hetzner VPS, Cloudflare DNS, S3 bucket, IAM user |
| Configuration | Ansible (`setup.yml`) | Server hardening, Docker install, deploy user |
| Deployment | Ansible (`deploy.yml`) | Compose files, env vars, image pulls, container lifecycle |
| Runtime | Docker Compose | All service containers |
| CI/CD | GitHub Actions | Runs `make deploy` on push to `main` |

### VPS
- Provider: Hetzner Cloud
- Type: `cx23`, location `fsn1` (Falkenstein, Germany)
- OS: Ubuntu 22.04
- IP: `49.12.79.39`
- Access user: `deploy` (passwordless sudo, SSH key auth)

### Domain
- `henga.dev` — managed in Cloudflare, Terraform-provisioned DNS records
- Root (`henga.dev`) proxied through Cloudflare CDN → Portfolio
- `vault.henga.dev` — direct DNS (not proxied) → Vaultwarden

### Docker Networks
- `internal` — bridge network; service-to-service communication, not exposed
- `proxy` — external network; Caddy uses this to reach backend containers

---

## Services (Homelab Stack)

| Container | Image | Exposed at | Persistent data |
|---|---|---|---|
| `homelab-caddy` | `caddy:2-alpine` | `:80`, `:443` | `caddy_data`, `caddy_config` volumes |
| `homelab-vaultwarden` | `vaultwarden/server:latest` | `vault.henga.dev` | `/opt/homelab/data/vaultwarden` |
| `homelab-portfolio` | `henga/portfolio:latest` | `henga.dev` | none |
| `homelab-anki` | `ankicommunity/anki-sync-server:latest` | `anki.henga.dev` | `/opt/homelab/data/anki` |
| `homelab-backup` | `alpine:3.19` | — (internal cron) | reads Vaultwarden and Anki data read-only |

---

## Conventions for Adding New Services

1. Add the service to `/home/henga/Documents/projects/homelab/docker/docker-compose.yml`
2. Add a Caddy block in `docker/Caddyfile` with a new subdomain of `henga.dev`
3. Add a Cloudflare DNS record in `terraform/main.tf` pointing to the VPS IP
4. If the service needs secrets, add them to `ansible/templates/env.j2`
5. If the service is stateful, extend the backup strategy

---

## Operational Commands

```
make init     # Provision VPS + DNS (Terraform) — first time only
make setup    # Harden server, install Docker (Ansible setup.yml)
make deploy   # Deploy all services (Ansible deploy.yml)
make ssh      # SSH into server
make logs     # Stream Docker logs from server
make update   # Pull latest images and restart (without full Ansible run)
make reload-portfolio  # Pull latest portfolio image only
make destroy  # Tear down all Terraform-managed infrastructure
```
