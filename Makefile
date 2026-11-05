.PHONY: all fmt validate lint test security

DIRS := . modules/context modules/aws modules/azure modules/gcp $(wildcard examples/*/)

all: fmt validate test

fmt:
	terraform fmt -recursive

validate:
	@for d in $(DIRS); do \
	  [ -n "$$(ls $$d/*.tf 2>/dev/null)" ] || continue; \
	  echo "==> $$d"; \
	  (cd $$d && terraform init -backend=false -input=false >/dev/null && terraform validate) || exit 1; \
	done

lint:
	tflint --init && tflint --recursive --config "$(CURDIR)/.tflint.hcl"

test:
	terraform init -backend=false -input=false >/dev/null && terraform test

security: ## Run the same scanners as CI (requires gitleaks, trivy, checkov installed)
	gitleaks detect --source . --redact
	trivy config --severity CRITICAL,HIGH,MEDIUM --ignorefile .trivyignore.yaml .
	checkov -d . --config-file .checkov.yaml --quiet
