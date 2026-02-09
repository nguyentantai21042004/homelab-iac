# Homelab IaC Makefile
# Sync commands for Mutagen

# Variables
ADMIN_VM_IP ?= 192.168.1.100
ADMIN_VM_USER ?= tantai
SSH_PASS ?= 21042004

# Colors for output
GREEN = \033[0;32m
BLUE = \033[0;34m
NC = \033[0m # No Color

.PHONY: help sync-start sync-stop sync-status apply apply-postgres apply-storage apply-k3s destroy-postgres destroy-storage destroy-k3s init output

# Default target
help: ## Show available commands
	@echo "$(BLUE)Available Commands:$(NC)"
	@awk 'BEGIN {FS = ":.*?## "} /^[a-zA-Z_-]+:.*?## / {printf "  $(GREEN)%-15s$(NC) %s\n", $$1, $$2}' $(MAKEFILE_LIST)

# ===== SYNC COMMANDS =====
sync-start: ## Start Mutagen sync with Admin VM
	@echo "$(BLUE)Starting Mutagen sync...$(NC)"
	./scripts/sync-start.sh $(ADMIN_VM_IP) $(ADMIN_VM_USER)

sync-stop: ## Stop Mutagen sync
	@echo "$(BLUE)Stopping Mutagen sync...$(NC)"
	./scripts/sync-stop.sh

sync-status: ## Show Mutagen sync status
	@echo "$(BLUE)Mutagen sync status:$(NC)"
	@mutagen sync list || echo "No sync sessions running"

apply: ## Apply terraform via Admin VM (all modules)
	@echo "$(BLUE)Applying terraform via Admin VM...$(NC)"
	./scripts/remote-apply.sh $(ADMIN_VM_IP) $(ADMIN_VM_USER)

apply-postgres: ## Apply terraform for PostgreSQL only
	@echo "$(BLUE)Applying PostgreSQL module via Admin VM...$(NC)"
	./scripts/remote-apply-postgres.sh $(ADMIN_VM_IP) $(ADMIN_VM_USER)

apply-qdrant: ## Apply terraform for Qdrant only
	@echo "$(BLUE)Applying Qdrant module via Admin VM...$(NC)"
	sshpass -p $(SSH_PASS) ssh $(ADMIN_VM_USER)@$(ADMIN_VM_IP) "cd ~/homelab-iac/terraform && terraform apply -target=module.qdrant -auto-approve"

apply-storage: ## Apply terraform for Storage (MinIO + Zot) only
	@echo "$(BLUE)Applying Storage module via Admin VM...$(NC)"
	sshpass -p $(SSH_PASS) ssh $(ADMIN_VM_USER)@$(ADMIN_VM_IP) "cd ~/homelab-iac/terraform && terraform apply -target=module.storage -auto-approve"

apply-k3s: ## Apply terraform for K3s cluster (3 nodes)
	@echo "$(BLUE)Applying K3s cluster via Admin VM...$(NC)"
	sshpass -p $(SSH_PASS) ssh $(ADMIN_VM_USER)@$(ADMIN_VM_IP) "cd ~/homelab-iac/terraform && terraform apply -target=module.k3s_nodes -auto-approve"

destroy-postgres: ## Destroy PostgreSQL VM
	@echo "$(BLUE)Destroying PostgreSQL module via Admin VM...$(NC)"
	sshpass -p $(SSH_PASS) ssh $(ADMIN_VM_USER)@$(ADMIN_VM_IP) "cd ~/homelab-iac/terraform && terraform destroy -target=module.postgres -auto-approve"

destroy-qdrant: ## Destroy Qdrant VM
	@echo "$(BLUE)Destroying Qdrant module via Admin VM...$(NC)"
	sshpass -p $(SSH_PASS) ssh $(ADMIN_VM_USER)@$(ADMIN_VM_IP) "cd ~/homelab-iac/terraform && terraform destroy -target=module.qdrant -auto-approve"

destroy-storage: ## Destroy Storage VM
	@echo "$(BLUE)Destroying Storage module via Admin VM...$(NC)"
	sshpass -p $(SSH_PASS) ssh $(ADMIN_VM_USER)@$(ADMIN_VM_IP) "cd ~/homelab-iac/terraform && terraform destroy -target=module.storage -auto-approve"

destroy-k3s: ## Destroy K3s cluster
	@echo "$(BLUE)Destroying K3s cluster via Admin VM...$(NC)"
	sshpass -p $(SSH_PASS) ssh $(ADMIN_VM_USER)@$(ADMIN_VM_IP) "cd ~/homelab-iac/terraform && terraform destroy -target=module.k3s_nodes -auto-approve"

output: ## Output terraform on Admin VM
	@echo "$(BLUE)Outputing terraform on Admin VM...$(NC)"
	sshpass -p $(SSH_PASS) ssh $(ADMIN_VM_USER)@$(ADMIN_VM_IP) "cd ~/homelab-iac/terraform && terraform output"
init: ## Initialize terraform on Admin VM  
	@echo "$(BLUE)Initializing terraform on Admin VM...$(NC)"
	sshpass -p $(SSH_PASS) ssh $(ADMIN_VM_USER)@$(ADMIN_VM_IP) "cd ~/homelab-iac/terraform && terraform init"

# ===== POSTGRES SCHEMA MANAGEMENT =====
pg-init-db: ## Initialize new isolated database (Usage: make pg-init-db DB=smap)
	@echo "$(BLUE)Initializing database $(DB) with schema isolation...$(NC)"
	cd ansible && ansible-playbook playbooks/postgres-init-isolated-db.yml -e "db_name=$(DB)"

pg-add-schema: ## Add new service schema (Usage: make pg-add-schema SERVICE=auth DB=smap)
	@echo "$(BLUE)Adding schema for service $(SERVICE)...$(NC)"
	cd ansible && ansible-playbook playbooks/postgres-add-service-schema.yml -e "service_name=$(SERVICE) db_name=$(DB)"

pg-list: ## List all schemas and users (Usage: make pg-list DB=smap)
	@echo "$(BLUE)Listing schemas in database $(DB)...$(NC)"
	cd ansible && ansible-playbook playbooks/postgres-list-schemas.yml -e "db_name=$(DB)"

pg-verify: ## Verify schema isolation (Usage: make pg-verify DB=smap)
	@echo "$(BLUE)Verifying isolation in database $(DB)...$(NC)"
	cd ansible && ansible-playbook playbooks/postgres-verify-isolation.yml -e "db_name=$(DB)"

pg-delete-schema: ## Delete service schema (Usage: make pg-delete-schema SERVICE=auth DB=smap)
	@echo "$(BLUE)⚠️  WARNING: This will DELETE all data in schema_$(SERVICE)!$(NC)"
	@echo "$(BLUE)Press Ctrl+C to cancel, or Enter to continue...$(NC)"
	@read confirm
	cd ansible && ansible-playbook playbooks/postgres-delete-service-schema.yml -e "service_name=$(SERVICE) db_name=$(DB) confirm_delete=yes"

pg-update-password: ## Update service user password (Usage: make pg-update-password SERVICE=auth USER=prod PASS=newpass)
	@echo "$(BLUE)Updating password for $(SERVICE)_$(USER)...$(NC)"
	cd ansible && ansible-playbook playbooks/postgres-update-service-password.yml -e "service_name=$(SERVICE) user_type=$(USER) new_password=$(PASS)"

pg-fix-isolation: ## Fix isolation for existing database (Usage: make pg-fix-isolation DB=smap)
	@echo "$(BLUE)Fixing isolation in database $(DB)...$(NC)"
	cd ansible && ansible-playbook playbooks/postgres-fix-isolation.yml -e "db_name=$(DB)"