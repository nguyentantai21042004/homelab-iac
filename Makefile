# Homelab IaC Makefile
# Sync commands for Mutagen

# Variables
ADMIN_VM_IP ?= 192.168.1.100
ADMIN_VM_USER ?= tantai

# Colors for output
GREEN = \033[0;32m
BLUE = \033[0;34m
NC = \033[0m # No Color

.PHONY: help sync-start sync-stop sync-status apply

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

apply: ## Apply terraform via Admin VM
	@echo "$(BLUE)Applying terraform via Admin VM...$(NC)"
	./scripts/remote-apply.sh $(ADMIN_VM_IP) $(ADMIN_VM_USER)

init: ## Initialize terraform on Admin VM  
	@echo "$(BLUE)Initializing terraform on Admin VM...$(NC)"
	ssh $(ADMIN_VM_USER)@$(ADMIN_VM_IP) "cd ~/homelab-iac/terraform && terraform init"