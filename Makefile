# Makefile for Online Boutique on EKS
# Usage: make <target>

CLUSTER_NAME   ?= online-boutique
AWS_REGION     ?= us-east-1
HELM_RELEASE   ?= online-boutique
HELM_NAMESPACE ?= online-boutique

.PHONY: help init plan apply destroy bootstrap deploy monitoring status clean

help: ## Show available commands
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | \
		awk 'BEGIN {FS = ":.*?## "}; {printf "\033[36m%-20s\033[0m %s\n", $$1, $$2}'

# ---------------------------------------------------------------
# Terraform
# ---------------------------------------------------------------
init: ## Initialise Terraform
	cd infra && terraform init

plan: ## Preview infrastructure changes
	cd infra && terraform plan

apply: ## Provision EKS cluster and supporting AWS resources
	cd infra && terraform apply
	@echo ""
	@echo "Next step: run 'make kubeconfig' to connect kubectl"

destroy: ## Destroy all AWS infrastructure (careful!)
	cd infra && terraform destroy

kubeconfig: ## Configure kubectl to connect to the EKS cluster
	aws eks update-kubeconfig --region $(AWS_REGION) --name $(CLUSTER_NAME)

# ---------------------------------------------------------------
# Cluster bootstrap (run once after terraform apply)
# ---------------------------------------------------------------
bootstrap: bootstrap-cert-manager bootstrap-ingress bootstrap-sealed-secrets bootstrap-issuer ## Bootstrap all cluster dependencies

bootstrap-cert-manager: ## Install cert-manager
	helm repo add jetstack https://charts.jetstack.io
	helm repo update
	helm upgrade --install cert-manager jetstack/cert-manager \
		--namespace cert-manager \
		--create-namespace \
		--set installCRDs=true \
		--wait
	@echo "✅ cert-manager installed"

bootstrap-ingress: ## Install ingress-nginx
	helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx
	helm repo update
	helm upgrade --install ingress-nginx ingress-nginx/ingress-nginx \
		--namespace ingress-nginx \
		--create-namespace \
		-f monitoring/ingress-nginx-values.yaml \
		--wait
	@echo "✅ ingress-nginx installed"

bootstrap-sealed-secrets: ## Install Sealed Secrets controller
	helm repo add sealed-secrets https://bitnami-labs.github.io/sealed-secrets
	helm repo update
	helm upgrade --install sealed-secrets sealed-secrets/sealed-secrets \
		--namespace kube-system \
		--wait
	@echo "✅ sealed-secrets installed"

bootstrap-issuer: ## Apply Let's Encrypt ClusterIssuers
	kubectl apply -f monitoring/cluster-issuer.yaml
	@echo "✅ ClusterIssuers applied"

# ---------------------------------------------------------------
# App deployment
# ---------------------------------------------------------------
deploy: ## Deploy Online Boutique via Helm
	helm upgrade --install $(HELM_RELEASE) ./helm/online-boutique \
		--namespace $(HELM_NAMESPACE) \
		--create-namespace \
		-f helm/online-boutique/values.yaml \
		-f helm/online-boutique/values-prod.yaml \
		--atomic \
		--timeout 5m \
		--wait
	@echo "✅ Online Boutique deployed"

undeploy: ## Remove Online Boutique from the cluster
	helm uninstall $(HELM_RELEASE) --namespace $(HELM_NAMESPACE)

# ---------------------------------------------------------------
# Monitoring
# ---------------------------------------------------------------
monitoring: ## Install Prometheus + Grafana
	helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
	helm repo update
	helm upgrade --install kube-prometheus-stack prometheus-community/kube-prometheus-stack \
		--namespace monitoring \
		--create-namespace \
		-f monitoring/prometheus-values.yaml \
		--wait
	@echo "✅ Monitoring stack installed"

# ---------------------------------------------------------------
# Utilities
# ---------------------------------------------------------------
status: ## Show pod status for the app namespace
	kubectl get pods -n $(HELM_NAMESPACE)

lb: ## Print the Load Balancer hostname (use for DNS CNAME)
	@kubectl get svc ingress-nginx-controller -n ingress-nginx \
		-o jsonpath='{.status.loadBalancer.ingress[0].hostname}'
	@echo ""

seal-secret: ## Seal a secret — usage: make seal-secret NAME=my-secret KEY=MY_KEY VALUE=myvalue
	@kubectl create secret generic $(NAME) \
		--namespace $(HELM_NAMESPACE) \
		--from-literal=$(KEY)=$(VALUE) \
		--dry-run=client -o yaml \
		| kubeseal --format yaml \
		--controller-namespace kube-system \
		--controller-name sealed-secrets \
		> helm/online-boutique/templates/sealed-secrets.yaml
	@echo "✅ Sealed secret written to helm/online-boutique/templates/sealed-secrets.yaml"

clean: ## Remove local Terraform files (keeps state in S3)
	rm -rf infrastructure/.terraform
	rm -f infrastructure/.terraform.lock.hcl