.PHONY: all help prereqs template init validate plan apply ansible storage flux destroy

SHELL        := /bin/bash
TERRAFORM    := terraform -chdir=terraform
ANSIBLE      := ansible-playbook -i ansible/inventory/hosts.yml
CLUSTER      := k8-dev

help: ## Show available targets
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | \
		awk 'BEGIN {FS = ":.*?## "}; {printf "\033[36m%-20s\033[0m %s\n", $$1, $$2}'

prereqs: ## Check all required tools are installed
	@echo "==> Checking prerequisites..."
	@command -v terraform  >/dev/null 2>&1 || (echo "ERROR: terraform not found"  && exit 1)
	@command -v ansible    >/dev/null 2>&1 || (echo "ERROR: ansible not found"    && exit 1)
	@command -v flux       >/dev/null 2>&1 || (echo "ERROR: flux CLI not found"   && exit 1)
	@command -v gh         >/dev/null 2>&1 || (echo "ERROR: gh CLI not found"     && exit 1)
	@echo "✅ All prerequisites found"

template: ## Create Ubuntu 24.04 cloud-init template on Proxmox (copy script to Proxmox host)
	@echo "==> Copy scripts/create-ubuntu-template.sh to your Proxmox host and run it:"
	@echo "    scp scripts/create-ubuntu-template.sh root@172.16.1.2:/tmp/"
	@echo "    ssh root@172.16.1.2 'bash /tmp/create-ubuntu-template.sh'"

init: ## Initialise Terraform
	$(TERRAFORM) init

validate: ## Validate Terraform configuration
	$(TERRAFORM) validate

plan: ## Show Terraform execution plan
	$(TERRAFORM) plan -var-file=secrets.tfvars

apply: ## Provision VMs via Terraform
	$(TERRAFORM) apply -var-file=secrets.tfvars -auto-approve

ping: ## Test Ansible connectivity to all nodes
	ansible all -i ansible/inventory/hosts.yml -m ping

ansible: ## Run full Ansible configuration playbook
	cd ansible && $(ANSIBLE) playbooks/site.yml

storage: ## Install iSCSI initiator on all cluster nodes (prerequisite for Synology CSI driver)
	cd ansible && $(ANSIBLE) playbooks/07-storage.yml

flux: ## Bootstrap Flux GitOps
	bash scripts/bootstrap-flux.sh

destroy: ## DANGER: Destroy all VMs
	$(TERRAFORM) destroy -var-file=secrets.tfvars

all: init apply ansible ## Full deploy: init → provision → configure
