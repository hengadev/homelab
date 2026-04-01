# Homelab Infrastructure

Production-ready, fully reproducible homelab infrastructure deployed with a single command. Provisions a Hetzner VPS, hardens it, and runs Caddy + Vaultwarden + Portfolio + backup services via Docker Compose.

## Architecture

```
┌─────────────────┐      ┌──────────────┐      ┌─────────────┐
│   Cloudflare    │ ───→ │  Hetzner VPS │ ───→ │  Caddy      │
│   (DNS)         │      │  (Ubuntu)    │      │  (Reverse   │
└─────────────────┘      └──────────────┘      │   Proxy)    │
                                                 └─────────────┘
                                                      │
                       ┌──────────────────────────────┼─────────────────┐
                       ↓                              ↓                 ↓
                 ┌─────────────┐            ┌──────────────┐   ┌──────────────┐
                 │  Vaultwarden│            │   Portfolio  │   │   Backup     │
                 │  (Passwords)│            │   (Website)  │   │   (S3)       │
                 └─────────────┘            └──────────────┘   └──────────────┘
```

**Stack Components:**
- **Terraform**: Provisions Hetzner VPS + Cloudflare DNS
- **Ansible**: Hardens server, installs Docker, deploys services
- **Docker Compose**: Caddy (TLS) + Vaultwarden + Portfolio + Backup
- **Caddy**: Automatic HTTPS, reverse proxy
- **Vaultwarden**: Self-hosted password manager
- **Backup**: Encrypted nightly backups to S3

## Prerequisites

- Hetzner Cloud account with API token
- Cloudflare account with API token and zone ID
- AWS S3 bucket for backups
- Domain name pointing to Cloudflare
- SSH key pair for server access

## Quick Start

1. **Clone and configure**
   ```bash
   cd /home/henga/Documents/projects/homelab
   cp .env.example .env
   # Edit .env with your credentials
   ```

2. **Generate admin token**
   ```bash
   openssl rand -base64 48
   # Set as ADMIN_TOKEN in .env
   ```

3. **Deploy**
   ```bash
   make init    # Provision VPS and DNS (~2 min)
   make setup   # Configure server (~3 min)
   make deploy  # Deploy services (~1 min)
   ```

4. **Access services**
   - Portfolio: `https://yourdomain.com`
   - Vaultwarden: `https://vault.yourdomain.com`

## Environment Variables

| Variable | Description | Example |
|----------|-------------|---------|
| `HCLOUD_TOKEN` | Hetzner API token | `foobar123...` |
| `CLOUDFLARE_API_TOKEN` | Cloudflare API token | `abc123...` |
| `CLOUDFLARE_ZONE_ID` | Cloudflare Zone ID | `1a2b3c4d...` |
| `DOMAIN` | Root domain | `example.com` |
| `SSH_PUBLIC_KEY` | Full SSH public key | `ssh-ed25519 AAAA...` |
| `SSH_PRIVATE_KEY_PATH` | Path to private key | `~/.ssh/id_ed25519` |
| `ADMIN_TOKEN` | Vaultwarden admin token | `random48chars...` |
| `ADMIN_EMAIL` | Let's Encrypt email | `admin@example.com` |
| `AWS_ACCESS_KEY_ID` | S3 access key | `AKIAIOSFODNN7EXAMPLE` |
| `AWS_SECRET_ACCESS_KEY` | S3 secret key | `wJalrXUtnFEMI/K7MDENG...` |
| `AWS_DEFAULT_REGION` | S3 region | `us-east-1` |
| `BACKUP_S3_BUCKET` | S3 bucket URI | `s3://homelab-backups` |
| `BACKUP_PASSPHRASE` | Backup encryption | `strongpassphrase` |
| `GITHUB_USERNAME` | For portfolio ref | `yourusername` |

## GitHub Actions

Add these secrets to your repository:

```
SERVER_IP, SSH_PRIVATE_KEY, DOMAIN, ADMIN_TOKEN, ADMIN_EMAIL,
AWS_ACCESS_KEY_ID, AWS_SECRET_ACCESS_KEY, AWS_DEFAULT_REGION,
BACKUP_S3_BUCKET, BACKUP_PASSPHRASE, GITHUB_USERNAME, SSH_PUBLIC_KEY
```

The workflow triggers on push to `main`.

## Day-2 Operations

```bash
make ssh    # SSH into server
make logs   # View Docker logs
make update # Pull and restart services
```

### Manual backup

```bash
make ssh
docker compose exec vaultwarden-backup /backup.sh
```

### Restore from backup

```bash
# Download backup from S3
aws s3 cp s3://bucket/backup.tar.gz.gpg /tmp/backup.gpg

# Decrypt
gpg --decrypt /tmp/backup.gpg > /tmp/backup.tar.gz

# Restore
docker compose stop vaultwarden
tar -xzf /tmp/backup.tar.gz -C /opt/homelab/data/
docker compose start vaultwarden
```

## Vaultwarden Initial Setup

1. Visit `https://vault.yourdomain.com`
2. Admin interface: `https://vault.yourdomain.com/admin`
3. Use `ADMIN_TOKEN` from `.env`
4. Disable user registrations (already set via env var)
5. Create your account

## Upgrading to Remote Terraform State

Uncomment the `backend "s3"` block in `terraform/versions.tf` and run:

```bash
terraform init -migrate-state
```

## Troubleshooting

### DNS propagation
After `make init`, wait 2-3 minutes for DNS to propagate before running `make deploy`.

### ACME rate limits
If Let's Encrypt fails, use the staging server in `Caddyfile`:
```
{
  acme_ca https://acme-staging-v02.api.letsencrypt.org/directory
}
```

### Port already in use
Check with `sudo netstat -tulpn | grep :443` and stop conflicting services.

### Terraform state lock
If state is locked: `terraform force-unlock <LOCK_ID>`
