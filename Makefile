TF_DIR ?= terraform

.PHONY: init validate fmt plan apply destroy test help

help:
	@echo "Available commands:"
	@echo "  make init      - Initialize Terraform and download provider plugins"
	@echo "  make validate  - Validate syntax and configuration integrity"
	@echo "  make fmt       - Format all Terraform files recursively"
	@echo "  make plan      - Generate and display execution plan"
	@echo "  make apply     - Provision infrastructure"
	@echo "  make destroy   - Tear down all managed infrastructure"
	@echo "  make test      - Test end-to-end HTTPS traffic and HTTP redirect against AWS ALB"

init:
	terraform -chdir=$(TF_DIR) init

validate:
	terraform -chdir=$(TF_DIR) validate

fmt:
	terraform -chdir=$(TF_DIR) fmt -recursive

plan:
	terraform -chdir=$(TF_DIR) plan -var-file="terraform.tfvars"

apply:
	terraform -chdir=$(TF_DIR) apply -var-file="terraform.tfvars"

destroy:
	terraform -chdir=$(TF_DIR) destroy -var-file="terraform.tfvars"

test:
	@ALB_DNS=$$(terraform -chdir=$(TF_DIR) output -raw alb_dns_name 2>/dev/null); \
	if [ -z "$$ALB_DNS" ]; then \
		echo "Error: Could not retrieve alb_dns_name output. Has 'make apply' completed?"; \
		exit 1; \
	fi; \
	echo "1. Testing HTTP to HTTPS 301 Redirect on port 80:"; \
	curl -I -s "http://$$ALB_DNS" | head -n 5; \
	echo ""; \
	echo "2. Querying AWS Application Load Balancer HTTPS endpoint: https://$$ALB_DNS"; \
	curl -k -s "https://$$ALB_DNS"
