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

apply-storage: ## Apply terraform for Storage (MinIO + Zot) only
	@echo "$(BLUE)Applying Storage module via Admin VM...$(NC)"
	sshpass -p $(SSH_PASS) ssh $(ADMIN_VM_USER)@$(ADMIN_VM_IP) "cd ~/homelab-iac/terraform && terraform apply -target=module.storage -auto-approve"

apply-k3s: ## Apply terraform for K3s cluster (3 nodes)
	@echo "$(BLUE)Applying K3s cluster via Admin VM...$(NC)"
	sshpass -p $(SSH_PASS) ssh $(ADMIN_VM_USER)@$(ADMIN_VM_IP) "cd ~/homelab-iac/terraform && terraform apply -target=module.k3s_nodes -auto-approve"

destroy-postgres: ## Destroy PostgreSQL VM
	@echo "$(BLUE)Destroying PostgreSQL module via Admin VM...$(NC)"
	sshpass -p $(SSH_PASS) ssh $(ADMIN_VM_USER)@$(ADMIN_VM_IP) "cd ~/homelab-iac/terraform && terraform destroy -target=module.postgres -auto-approve"

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