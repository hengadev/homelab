variable "hcloud_token" {
  type        = string
  description = "Hetzner Cloud API token"
  sensitive   = true
}

variable "cloudflare_api_token" {
  type        = string
  description = "Cloudflare API token (scoped to Zone:DNS:Edit + Zone:Zone:Read)"
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

variable "ssh_public_key" {
  type        = string
  description = "SSH public key string (for server access)"
}

variable "server_type" {
  type        = string
  description = "Hetzner server type"
  default     = "cx22"
}

variable "server_location" {
  type        = string
  description = "Hetzner datacenter location"
  default     = "nbg1"
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
