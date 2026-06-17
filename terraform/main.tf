provider "hcloud" {
  token = var.hcloud_token
}

provider "cloudflare" {
  alias   = "homelab"
  api_token = var.cloudflare_api_token
}

provider "cloudflare" {
  alias   = "cluo"
  api_token = var.cloudflare_cluo_api_token
}

provider "aws" {
  region = var.aws_region
  # Credentials read from environment: AWS_PROFILE (local CLI profile)
}

# SSH Key resource
resource "hcloud_ssh_key" "homelab" {
  name       = "homelab-deploy-key"
  public_key = var.ssh_public_key
}

# Firewall - only allow necessary ports
resource "hcloud_firewall" "homelab" {
  name = "homelab-firewall"
  rule {
    direction  = "in"
    protocol   = "tcp"
    port       = "22"
    source_ips = ["0.0.0.0/0", "::/0"]
  }
  rule {
    direction  = "in"
    protocol   = "tcp"
    port       = "80"
    source_ips = ["0.0.0.0/0", "::/0"]
  }
  rule {
    direction  = "in"
    protocol   = "tcp"
    port       = "443"
    source_ips = ["0.0.0.0/0", "::/0"]
  }
  rule {
    direction  = "in"
    protocol   = "udp"
    port       = "443"
    source_ips = ["0.0.0.0/0", "::/0"]
  }

  apply_to {
    label_selector = "homelab"
  }
}

# Server with cloud-init to create deploy user
resource "hcloud_server" "homelab" {
  name        = "homelab-01"
  server_type = var.server_type
  location    = var.server_location
  image       = var.server_image
  ssh_keys    = [hcloud_ssh_key.homelab.id]
  firewall_ids = [hcloud_firewall.homelab.id]
  labels      = { homelab = "true" }

  # cloud-init creates deploy user with passwordless sudo
  user_data = <<-EOT
  #cloud-config
  users:
    - name: deploy
      sudo: ALL=(ALL) NOPASSWD:ALL
      shell: /bin/bash
      ssh_authorized_keys:
        - ${var.ssh_public_key}
  EOT
}

# S3 bucket for Vaultwarden backups
resource "aws_s3_bucket" "backup" {
  bucket = var.backup_s3_bucket

  tags = {
    Name       = "homelab-vaultwarden-backup"
    managed-by = "terraform"
  }
}

resource "aws_s3_bucket_versioning" "backup" {
  bucket = aws_s3_bucket.backup.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "backup" {
  bucket = aws_s3_bucket.backup.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "backup" {
  bucket = aws_s3_bucket.backup.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Dedicated IAM user for the backup container (scoped to backup bucket only)
resource "aws_iam_user" "backup" {
  name = "homelab-vaultwarden-backup"

  tags = {
    managed-by = "terraform"
  }
}

resource "aws_iam_user_policy" "backup" {
  name = "homelab-vaultwarden-backup-s3"
  user = aws_iam_user.backup.name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = ["s3:PutObject", "s3:GetObject", "s3:DeleteObject"]
        Resource = "${aws_s3_bucket.backup.arn}/*"
      },
      {
        Effect   = "Allow"
        Action   = "s3:ListBucket"
        Resource = aws_s3_bucket.backup.arn
      }
    ]
  })
}

resource "aws_iam_access_key" "backup" {
  user = aws_iam_user.backup.name
}

# S3 bucket for cluo's MinIO backups (cluo-staging-backup container in
# docker/cluo/staging.docker-compose.yml). Cluo runs on this VPS today, but
# its own Terraform (in the cluo repo) is an unprovisioned future-deployment
# blueprint, not what's live — so this credential is managed here, alongside
# the rest of what's actually deployed on this server.
resource "aws_s3_bucket" "cluo_minio_backup" {
  bucket = "cluo-minio-backups-staging"

  tags = {
    Name       = "cluo-minio-backup-staging"
    managed-by = "terraform"
  }
}

resource "aws_s3_bucket_versioning" "cluo_minio_backup" {
  bucket = aws_s3_bucket.cluo_minio_backup.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "cluo_minio_backup" {
  bucket = aws_s3_bucket.cluo_minio_backup.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "cluo_minio_backup" {
  bucket = aws_s3_bucket.cluo_minio_backup.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_lifecycle_configuration" "cluo_minio_backup" {
  bucket = aws_s3_bucket.cluo_minio_backup.id

  rule {
    id     = "minio-backup-retention"
    status = "Enabled"
    filter {}

    expiration {
      days = 30 # backup.sh also self-prunes after 30 days; this is a backstop
    }
  }
}

# Dedicated IAM user for the cluo-staging-backup container (scoped to this bucket only)
resource "aws_iam_user" "cluo_minio_backup" {
  name = "cluo-minio-backup-staging-user"

  tags = {
    managed-by = "terraform"
  }
}

resource "aws_iam_user_policy" "cluo_minio_backup" {
  name = "cluo-minio-backup-staging-s3"
  user = aws_iam_user.cluo_minio_backup.name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["s3:PutObject", "s3:GetObject", "s3:DeleteObject"]
        Resource = "${aws_s3_bucket.cluo_minio_backup.arn}/*"
      },
      {
        Effect   = "Allow"
        Action   = "s3:ListBucket"
        Resource = aws_s3_bucket.cluo_minio_backup.arn
      }
    ]
  })
}

resource "aws_iam_access_key" "cluo_minio_backup" {
  user = aws_iam_user.cluo_minio_backup.name
}

# Cloudflare DNS records for homelab (henga.dev)
resource "cloudflare_record" "root" {
  provider = cloudflare.homelab
  zone_id = var.cloudflare_zone_id
  name    = "@"
  value   = hcloud_server.homelab.ipv4_address
  type    = "A"
  ttl     = 1
  proxied = true
}

resource "cloudflare_record" "vault" {
  provider = cloudflare.homelab
  zone_id = var.cloudflare_zone_id
  name    = "vault"
  value   = hcloud_server.homelab.ipv4_address
  type    = "A"
  ttl     = 300
  proxied = false
}

resource "cloudflare_record" "anki" {
  provider = cloudflare.homelab
  zone_id = var.cloudflare_zone_id
  name    = "anki"
  value   = hcloud_server.homelab.ipv4_address
  type    = "A"
  ttl     = 300
  proxied = false
}

resource "cloudflare_record" "anki_api" {
  provider = cloudflare.homelab
  zone_id  = var.cloudflare_zone_id
  name     = "anki-api"
  value    = hcloud_server.homelab.ipv4_address
  type     = "A"
  ttl      = 300
  proxied  = false
}

resource "cloudflare_record" "links" {
  provider = cloudflare.homelab
  zone_id  = var.cloudflare_zone_id
  name     = "links"
  value    = hcloud_server.homelab.ipv4_address
  type     = "A"
  ttl      = 300
  proxied  = false
}

resource "cloudflare_record" "leviosa" {
  provider = cloudflare.homelab
  zone_id  = var.cloudflare_zone_id
  name     = "leviosa"
  value    = hcloud_server.homelab.ipv4_address
  type     = "A"
  ttl      = 300
  proxied  = false
}

resource "cloudflare_record" "germinal" {
  provider = cloudflare.homelab
  zone_id  = var.cloudflare_zone_id
  name     = "germinal"
  value    = hcloud_server.homelab.ipv4_address
  type     = "A"
  ttl      = 300
  proxied  = false
}

# Cluo root domain (clientvault.fr)
resource "cloudflare_record" "cluo_root" {
  provider = cloudflare.cluo
  zone_id = var.cloudflare_cluo_zone_id
  name    = "@"
  value   = hcloud_server.homelab.ipv4_address
  type    = "A"
  ttl     = 1
  proxied = true
}

# Cluo production (clientvault.fr)
resource "cloudflare_record" "cluo_api" {
  provider = cloudflare.cluo
  zone_id = var.cloudflare_cluo_zone_id
  name    = "api"
  value   = hcloud_server.homelab.ipv4_address
  type    = "A"
  ttl     = 1
  proxied = true
}

resource "cloudflare_record" "cluo_mobile" {
  provider = cloudflare.cluo
  zone_id = var.cloudflare_cluo_zone_id
  name    = "mobile"
  value   = hcloud_server.homelab.ipv4_address
  type    = "A"
  ttl     = 1
  proxied = true
}

# Cluo staging (clientvault.fr)
resource "cloudflare_record" "cluo_staging" {
  provider = cloudflare.cluo
  zone_id = var.cloudflare_cluo_zone_id
  name    = "staging"
  value   = hcloud_server.homelab.ipv4_address
  type    = "A"
  ttl     = 1
  proxied = true
}

resource "cloudflare_record" "cluo_staging_api" {
  provider = cloudflare.cluo
  zone_id = var.cloudflare_cluo_zone_id
  name    = "staging-api"
  value   = hcloud_server.homelab.ipv4_address
  type    = "A"
  ttl     = 1
  proxied = true
}

resource "cloudflare_record" "cluo_staging_mobile" {
  provider = cloudflare.cluo
  zone_id = var.cloudflare_cluo_zone_id
  name    = "staging-mobile"
  value   = hcloud_server.homelab.ipv4_address
  type    = "A"
  ttl     = 1
  proxied = true
}
