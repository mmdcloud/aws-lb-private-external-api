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
	@echo "  make test      - Test end-to-end traffic against AWS ALB endpoint"

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
	echo "Querying AWS Application Load Balancer endpoint: http://$$ALB_DNS"; \
	curl -s "http://$$ALB_DNS"

