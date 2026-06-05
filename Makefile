.PHONY: help init setup deploy update destroy ssh logs generate-tfvars generate-inventory deploy-portfolio reload-portfolio rebuild-cluo-prod rebuild-cluo-staging logs-cluo-prod logs-cluo-staging deploy-demos

include .env
export

SERVER_IP    := $(shell cd terraform && terraform output -raw server_ip 2>/dev/null)
PORTFOLIO_DIR ?= $(HOME)/Documents/projects/gary/portfolio

ANSIBLE_VARS = -e domain=$(DOMAIN) \
               -e admin_token=$(ADMIN_TOKEN) \
               -e admin_email=$(ADMIN_EMAIL) \
               -e backup_aws_access_key_id=$(BACKUP_AWS_ACCESS_KEY_ID) \
               -e backup_aws_secret_access_key=$(BACKUP_AWS_SECRET_ACCESS_KEY) \
               -e aws_default_region=$(AWS_DEFAULT_REGION) \
               -e backup_s3_bucket=$(BACKUP_S3_BUCKET) \
               -e backup_passphrase=$(BACKUP_PASSPHRASE) \
               -e github_username=$(GITHUB_USERNAME) \
               -e cluo_registry=$(CLUO_REGISTRY) \
               -e cluo_prod_tag=$(CLUO_PROD_TAG) \
               -e cluo_staging_tag=$(CLUO_STAGING_TAG) \
               -e cluo_prod_db_name=$(CLUO_PROD_DB_NAME) \
               -e cluo_prod_db_user=$(CLUO_PROD_DB_USER) \
               -e cluo_prod_db_password=$(CLUO_PROD_DB_PASSWORD) \
               -e cluo_staging_db_name=$(CLUO_STAGING_DB_NAME) \
               -e cluo_staging_db_user=$(CLUO_STAGING_DB_USER) \
               -e cluo_staging_db_password=$(CLUO_STAGING_DB_PASSWORD) \
	               -e cluo_domain=$(CLUO_DOMAIN) \
	               -e anki_username=$(ANKI_USERNAME) \
	               -e anki_password=$(ANKI_PASSWORD) \
               -e leviosa_demo_admin_email=$(LEVIOSA_DEMO_ADMIN_EMAIL) \
               -e leviosa_demo_admin_password=$(LEVIOSA_DEMO_ADMIN_PASSWORD) \
               -e leviosa_demo_partner_email=$(LEVIOSA_DEMO_PARTNER_EMAIL) \
               -e leviosa_demo_partner_password=$(LEVIOSA_DEMO_PARTNER_PASSWORD) \
               -e leviosa_demo_client_email=$(LEVIOSA_DEMO_CLIENT_EMAIL) \
               -e leviosa_demo_client_password=$(LEVIOSA_DEMO_CLIENT_PASSWORD) \
               -e germinal_demo_admin_email=$(GERMINAL_DEMO_ADMIN_EMAIL) \
               -e germinal_demo_admin_password=$(GERMINAL_DEMO_ADMIN_PASSWORD) \
               -e germinal_demo_staff_email=$(GERMINAL_DEMO_STAFF_EMAIL) \
               -e germinal_demo_staff_password=$(GERMINAL_DEMO_STAFF_PASSWORD)

# SSH_PUBLIC_KEY contains spaces so it must be passed via a vars file, not -e
ANSIBLE_SSH_VARS_FILE := /tmp/homelab_ssh_vars.yml

define write-ssh-vars
	@printf 'ssh_public_key: %s\n' "$${SSH_PUBLIC_KEY}" > $(ANSIBLE_SSH_VARS_FILE)
endef

help: ## Show this help message
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-15s\033[0m %s\n", $$1, $$2}'

generate-tfvars: ## Generate terraform.tfvars from .env
	@echo "hcloud_token = \"$(HCLOUD_TOKEN)\"" > terraform/terraform.tfvars
	@echo "cloudflare_api_token = \"$(CLOUDFLARE_API_TOKEN)\"" >> terraform/terraform.tfvars
	@echo "cloudflare_zone_id = \"$(CLOUDFLARE_ZONE_ID)\"" >> terraform/terraform.tfvars
	@echo "domain = \"$(DOMAIN)\"" >> terraform/terraform.tfvars
	@echo "cloudflare_cluo_api_token = \"$(CLOUDFLARE_CLUO_API_TOKEN)\"" >> terraform/terraform.tfvars
	@echo "cloudflare_cluo_zone_id = \"$(CLOUDFLARE_CLUO_ZONE_ID)\"" >> terraform/terraform.tfvars
	@echo "cluo_domain = \"$(CLUO_DOMAIN)\"" >> terraform/terraform.tfvars
	@echo "ssh_public_key = \"$(SSH_PUBLIC_KEY)\"" >> terraform/terraform.tfvars
	@echo "ssh_private_key_path = \"$(SSH_PRIVATE_KEY_PATH)\"" >> terraform/terraform.tfvars
	@echo "backup_s3_bucket     = \"$(BACKUP_S3_BUCKET)\"" >> terraform/terraform.tfvars
	@echo "aws_region           = \"$(AWS_DEFAULT_REGION)\"" >> terraform/terraform.tfvars
	@chmod 600 terraform/terraform.tfvars

generate-inventory: ## Generate Ansible inventory from Terraform output
	@mkdir -p ansible/inventory
	@echo "all:" > ansible/inventory/hosts.yml
	@echo "  hosts:" >> ansible/inventory/hosts.yml
	@echo "    homelab:" >> ansible/inventory/hosts.yml
	@echo "      ansible_host: $(SERVER_IP)" >> ansible/inventory/hosts.yml
	@echo "      ansible_user: deploy" >> ansible/inventory/hosts.yml
	@echo "      ansible_ssh_private_key_file: $(SSH_PRIVATE_KEY_PATH)" >> ansible/inventory/hosts.yml
	@echo "      ansible_ssh_common_args: '-o StrictHostKeyChecking=accept-new'" >> ansible/inventory/hosts.yml

init: generate-tfvars ## Provision infrastructure (first time)
	@echo "Initializing Terraform..."
	@cd terraform && terraform init
	@echo "Planning Terraform changes..."
	@cd terraform && terraform plan
	@echo "Applying Terraform configuration..."
	@cd terraform && terraform apply -auto-approve
	@$(MAKE) generate-inventory
	@echo "Injecting generated backup IAM credentials into .env..."
	@KEY_ID=$$(cd terraform && terraform output -raw backup_iam_access_key_id) && \
	 SECRET=$$(cd terraform && terraform output -raw backup_iam_secret_access_key) && \
	 sed -i "s|^BACKUP_AWS_ACCESS_KEY_ID=.*|BACKUP_AWS_ACCESS_KEY_ID=$$KEY_ID|" .env && \
	 sed -i "s|^BACKUP_AWS_SECRET_ACCESS_KEY=.*|BACKUP_AWS_SECRET_ACCESS_KEY=$$SECRET|" .env
	@echo "Waiting for server to be ready..."
	@sleep 30
	@echo "Infrastructure provisioned. Run 'make setup' to configure the server."

setup: generate-inventory ## Configure server with Ansible
	@echo "Running setup playbook..."
	$(write-ssh-vars)
	@ansible-playbook -i ansible/inventory/hosts.yml ansible/setup.yml $(ANSIBLE_VARS) --extra-vars @$(ANSIBLE_SSH_VARS_FILE)
	@rm -f $(ANSIBLE_SSH_VARS_FILE)

deploy: generate-inventory ## Deploy Docker services
	@echo "Running deploy playbook..."
	$(write-ssh-vars)
	@ansible-playbook -i ansible/inventory/hosts.yml ansible/deploy.yml $(ANSIBLE_VARS) --extra-vars @$(ANSIBLE_SSH_VARS_FILE)
	@rm -f $(ANSIBLE_SSH_VARS_FILE)

deploy-portfolio: ## Build, push, and restart the portfolio container
	@$(MAKE) -C $(PORTFOLIO_DIR) ship
	@scp -i $(SSH_PRIVATE_KEY_PATH) docker/docker-compose.yml deploy@$(SERVER_IP):/opt/homelab/docker-compose.yml
	@ssh -i $(SSH_PRIVATE_KEY_PATH) deploy@$(SERVER_IP) "cd /opt/homelab && docker compose pull portfolio && docker compose up -d --no-deps portfolio"

reload-portfolio: ## Pull latest portfolio image and restart the container (skip build)
	@ssh -i $(SSH_PRIVATE_KEY_PATH) deploy@$(SERVER_IP) "cd /opt/homelab && docker compose pull portfolio && docker compose up -d --no-deps portfolio"

update: ## Update Docker services on server
	@ssh -i $(SSH_PRIVATE_KEY_PATH) deploy@$(SERVER_IP) "cd /opt/homelab && docker compose pull && docker compose up -d"

destroy: generate-tfvars ## Destroy all infrastructure
	@echo "WARNING: This will destroy all infrastructure!"
	@bash -c 'read -p "Are you sure? [y/N] " -n 1 -r; \
	echo; \
	if [[ $$REPLY =~ ^[Yy]$$ ]]; then \
		cd terraform && terraform destroy; \
	fi'

ssh: ## SSH into the server
	@ssh -i $(SSH_PRIVATE_KEY_PATH) deploy@$(SERVER_IP)

logs: ## View Docker logs
	@ssh -i $(SSH_PRIVATE_KEY_PATH) deploy@$(SERVER_IP) "cd /opt/homelab && docker compose logs -f"

rebuild-cluo-prod: ## Pull latest images and restart cluo production
	@ssh -i $(SSH_PRIVATE_KEY_PATH) deploy@$(SERVER_IP) "cd /opt/cluo && docker compose pull && docker compose up -d --remove-orphans"

rebuild-cluo-staging: ## Pull latest images and restart cluo staging
	@ssh -i $(SSH_PRIVATE_KEY_PATH) deploy@$(SERVER_IP) "cd /opt/cluo-staging && docker compose pull && docker compose up -d --remove-orphans"

logs-cluo-prod: ## View cluo production logs
	@ssh -i $(SSH_PRIVATE_KEY_PATH) deploy@$(SERVER_IP) "cd /opt/cluo && docker compose logs -f"

logs-cluo-staging: ## View cluo staging logs
	@ssh -i $(SSH_PRIVATE_KEY_PATH) deploy@$(SERVER_IP) "cd /opt/cluo-staging && docker compose logs -f"

deploy-demos: ## Pull latest demo images and restart leviosa-demo and germinal-demo
	@scp -i $(SSH_PRIVATE_KEY_PATH) docker/docker-compose.yml deploy@$(SERVER_IP):/opt/homelab/docker-compose.yml
	@scp -i $(SSH_PRIVATE_KEY_PATH) docker/Caddyfile deploy@$(SERVER_IP):/opt/homelab/Caddyfile
	@ssh -i $(SSH_PRIVATE_KEY_PATH) deploy@$(SERVER_IP) "cd /opt/homelab && docker compose pull leviosa-demo germinal-demo && docker compose up -d --no-deps leviosa-demo germinal-demo && docker compose exec caddy caddy reload --config /etc/caddy/Caddyfile"
