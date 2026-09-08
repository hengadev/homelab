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
Nightly encrypted backup of Vaultwarden data, Anki data, and the Infisical
Postgres database (runs at 03:00 via cron inside the `vaultwarden-backup`
container). Flow: Vaultwarden/Anki are `tar`'d; Infisical is `pg_dump`'d and
gzipped — both then go through GPG symmetric encryption (passphrase) →
upload to S3, and are pruned after 30 days by the script itself. The S3
bucket (`homelab-backups-henga`) has versioning, SSE-AES256, and a lifecycle
rule (90-day expiration on current objects as a safety net behind the
script's own pruning, 30-day expiration on noncurrent versions so deleted
objects don't linger — and cost money — indefinitely under versioning). A
dedicated IAM user (`homelab-vaultwarden-backup`) scoped to that bucket
handles credentials for all three backups; it predates Infisical and keeps
its original name.

On a fresh deploy, Ansible auto-restores the latest backup from S3 if the
Vaultwarden data directory is empty. Infisical has no equivalent restore
automation yet — same as Anki, its backup is one-directional until a
service needs restore.

### Infisical
Self-hosted secrets manager at `secrets.henga.dev` (image `infisical/infisical:latest`).
Backed by its own Postgres (`infisical-db`) and Redis with AOF persistence
(`infisical-redis`), both internal-only. Data lives at
`/opt/homelab/data/infisical-db` and `/opt/homelab/data/infisical-redis`.

**Bootstrap (manual, one-time, after first `make deploy`):** visit
`https://secrets.henga.dev` and create the first admin account through the
UI — Infisical has no non-interactive first-admin API, so this can't be
automated by Ansible (same constraint as Vaultwarden's admin panel and
Woodpecker's OAuth app setup). Once an org exists, create a Machine Identity
(Settings → Machine Identities) scoped to whichever projects other homelab
services need to read secrets from, using Universal Auth. Store the
resulting client ID/secret wherever the consuming service's own secrets
live — nothing in this repo consumes Infisical secrets yet, so there's no
integration to wire up until a specific service needs one.

### Deploy
The full service deployment cycle, triggered by `make deploy` or automatically
by GitHub Actions on push to `main`. Runs the Ansible `deploy.yml` playbook,
which syncs compose files, templates the `.env`, pulls images, and starts
containers.

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
| `homelab-anki-api` | local build (`docker/anki-api/`) | `anki-api.henga.dev` | `/opt/homelab/data/anki` (shared with anki) |
| `homelab-backup` | `alpine:3.19` | — (internal cron) | reads Vaultwarden and Anki data read-only, dumps Infisical's Postgres |
| `homelab-infisical` | `infisical/infisical:latest` | `secrets.henga.dev` | none (state lives in infisical-db/infisical-redis) |
| `homelab-infisical-db` | `postgres:14-alpine` | — (internal) | `/opt/homelab/data/infisical-db` |
| `homelab-infisical-redis` | `redis:7-alpine` (AOF) | — (internal) | `/opt/homelab/data/infisical-redis` |

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
