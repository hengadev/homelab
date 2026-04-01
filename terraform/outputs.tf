output "server_ip" {
  description = "Server IPv4 address"
  value       = hcloud_server.homelab.ipv4_address
}

output "server_name" {
  description = "Server hostname"
  value       = hcloud_server.homelab.name
}

output "server_id" {
  description = "Hetzner server ID"
  value       = hcloud_server.homelab.id
}

output "ssh_command" {
  description = "SSH command to connect to the server"
  value       = "ssh -i ${var.ssh_private_key_path} deploy@${hcloud_server.homelab.ipv4_address}"
}

output "backup_bucket_name" {
  description = "S3 bucket name for Vaultwarden backups"
  value       = aws_s3_bucket.backup.bucket
}
