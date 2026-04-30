variable "hcloud_token" {
  type        = string
  description = "Hetzner Cloud API token"
  sensitive   = true
}

variable "cloudflare_api_token" {
  type        = string
  description = "Cloudflare API token for homelab domain (scoped to Zone:DNS:Edit + Zone:Zone:Read)"
  sensitive   = true
}

variable "cloudflare_cluo_api_token" {
  type        = string
  description = "Cloudflare API token for Cluo app domain (scoped to Zone:DNS:Edit + Zone:Zone:Read)"
  sensitive   = true
}

variable "cloudflare_zone_id" {
  type        = string
  description = "Cloudflare Zone ID for the domain"
}

variable "domain" {
  type        = string
  description = "Domain name (e.g., example.com)"
}

variable "cluo_domain" {
  type        = string
  description = "Cluo app domain name (e.g., clientvault.fr)"
}

variable "cloudflare_cluo_zone_id" {
  type        = string
  description = "Cloudflare Zone ID for the Cluo app domain"
}

variable "ssh_public_key" {
  type        = string
  description = "SSH public key string (for server access)"
}

variable "server_type" {
  type        = string
  description = "Hetzner server type"
  default     = "cx23"
}

variable "server_location" {
  type        = string
  description = "Hetzner datacenter location"
  default     = "fsn1"
}

variable "server_image" {
  type        = string
  description = "Server OS image"
  default     = "ubuntu-22.04"
}

variable "ssh_private_key_path" {
  type        = string
  description = "Local path to SSH private key"
}

variable "backup_s3_bucket" {
  type        = string
  description = "Name of the S3 bucket for Vaultwarden backups (must be globally unique)"
}

variable "aws_region" {
  type        = string
  description = "AWS region for the S3 backup bucket"
  default     = "us-east-1"
}
