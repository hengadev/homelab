provider "hcloud" {
  token = var.hcloud_token
}

provider "cloudflare" {
  api_token = var.cloudflare_api_token
}

provider "aws" {
  region = var.aws_region
  # Credentials read from environment: AWS_ACCESS_KEY_ID, AWS_SECRET_ACCESS_KEY
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

# Cloudflare DNS records (proxied=false for Vaultwarden WebSocket support)
resource "cloudflare_record" "root" {
  zone_id = var.cloudflare_zone_id
  name    = "@"
  value   = hcloud_server.homelab.ipv4_address
  type    = "A"
  ttl     = 300
  proxied = false
}

resource "cloudflare_record" "vault" {
  zone_id = var.cloudflare_zone_id
  name    = "vault"
  value   = hcloud_server.homelab.ipv4_address
  type    = "A"
  ttl     = 300
  proxied = false
}
