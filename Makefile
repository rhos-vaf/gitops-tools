# GitOps Tools Makefile
# This Makefile provides automation for deploying and managing ArgoCD instances
# and their associated namespaces in OpenShift/Kubernetes clusters.
#
# Prerequisites:
#   - oc CLI installed and authenticated to your cluster
#   - Proper RBAC permissions to create namespaces and ArgoCD resources
#
# Quick Start:
#   1. Install OpenShift GitOps operator:        make install_gitops_operator
#   2. Configure OpenShift GitOps instance:      make configure_openshift_gitops
#   3. Deploy a new ArgoCD instance:             ARGOCD_INSTANCE=client1 make deploy_argocd_instance
#   4. Create managed namespaces:                NAMESPACE=rhoso1 ARGOCD_INSTANCE=client1 make create_managed_namespace

.DEFAULT_GOAL := help

# Variables
APPROLE_SECRET_ID ?=
APPROLE_ROLE_ID ?=

.PHONY: help
help: ## Display this help message with all available targets
	@awk 'BEGIN {FS = ":.*##"; printf "\nUsage:\n  make \033[36m<target>\033[0m\n"} /^[a-zA-Z_0-9-]+:.*?##/ { printf "  \033[36m%-30s\033[0m %s\n", $$1, $$2 } /^##@/ { printf "\n\033[1m%s\033[0m\n", substr($$0, 5) } ' $(MAKEFILE_LIST)

##@ INTERNAL TARGETS
.PHONY: verify_gitops_examples
verify_gitops_examples: ## Verify and clone rhos-gitops/examples repository if needed (internal target)
	@if [ ! -d "examples" ]; then \
		echo "Cloning examples repository..."; \
		git clone https://gitlab.cee.redhat.com/rhos-gitops/examples.git; \
	else \
		echo "examples directory already exists, skipping clone"; \
	fi

##@ ARGOCD INSTANCE MANAGEMENT
.PHONY: deploy_argocd_instance
deploy_argocd_instance: ## Deploy a new ArgoCD instance (Usage: ARGOCD_INSTANCE=client1 make deploy_argocd_instance)
	# Validate required parameter
	@if [ -z "$(ARGOCD_INSTANCE)" ]; then \
		echo "Error: ARGOCD_INSTANCE is required. Usage: ARGOCD_INSTANCE=client1 make deploy_argocd_instance"; \
		exit 1; \
	fi
	@echo "Deploying ArgoCD instance: $(ARGOCD_INSTANCE)"
	# Create dedicated namespace for this ArgoCD instance
	@echo "Creating namespace gitops-$(ARGOCD_INSTANCE)"
	@oc create namespace gitops-$(ARGOCD_INSTANCE) || true
	@echo "Switching to gitops-$(ARGOCD_INSTANCE) namespace"
	@oc project gitops-$(ARGOCD_INSTANCE)
	# Create ConfigMap for cluster CA bundle (required for Git repos with private certificates)
	@echo "Creating cluster root CA bundle ConfigMap"
	@oc create configmap cluster-root-ca-bundle || true
	@oc label configmap cluster-root-ca-bundle config.openshift.io/inject-trusted-cabundle=true --overwrite || true
	# Deploy ArgoCD instance using sed to replace ARGOCD_INSTANCE placeholder in YAML templates
	# NOTE: This instance can only manage namespace-scoped resources
	# For cluster-scoped resources (NNCP, MetalLB, etc.), use openshift-gitops instance
	@echo "Deploying ArgoCD instance and RBAC configuration"
	@sed 's/ARGOCD_INSTANCE/$(ARGOCD_INSTANCE)/g' argocd-instance-configs/argocd-instance.yaml | oc apply -f -
	@sed 's/ARGOCD_INSTANCE/$(ARGOCD_INSTANCE)/g' argocd-instance-configs/argocd-instance-rbac.yaml | oc apply -f -
	@echo "ArgoCD instance $(ARGOCD_INSTANCE) deployed successfully"
	@echo "NOTE: This instance can only manage namespace-scoped resources"
	# Display the ArgoCD UI URL for easy access
	@echo "Waiting for ArgoCD route to be available..."
	@sleep 5
	@echo "ArgoCD URL: https://$$(oc get route -n gitops-$(ARGOCD_INSTANCE) gitops-$(ARGOCD_INSTANCE)-server -o jsonpath='{.spec.host}' 2>/dev/null || echo 'Route not ready yet')"

##@ NAMESPACE MANAGEMENT
.PHONY: create_managed_namespace
create_managed_namespace: ## Create/update a namespace managed by an ArgoCD instance (Usage: NAMESPACE=rhoso1 ARGOCD_INSTANCE=client1 make create_managed_namespace)
	# Validate required parameters
	@if [ -z "$(NAMESPACE)" ]; then \
		echo "Error: NAMESPACE is required. Usage: NAMESPACE=rhoso1 ARGOCD_INSTANCE=client1 make create_managed_namespace"; \
		exit 1; \
	fi
	@if [ -z "$(ARGOCD_INSTANCE)" ]; then \
		echo "Error: ARGOCD_INSTANCE is required. Usage: NAMESPACE=rhoso1 ARGOCD_INSTANCE=client1 make create_managed_namespace"; \
		exit 1; \
	fi
	@echo "Creating/updating managed namespace: $(NAMESPACE) for ArgoCD instance: $(ARGOCD_INSTANCE)"
	# Create namespace with proper labels for ArgoCD management and pod security
	@sed -e 's/NAMESPACE/$(NAMESPACE)/g' -e 's/ARGOCD_INSTANCE/$(ARGOCD_INSTANCE)/g' argocd-instance-configs/managed-namespace.yaml | oc apply -f -
	# Register namespace in ArgoCD's sourceNamespaces (allows ArgoCD Applications to be created in this namespace)
	@echo "Adding $(NAMESPACE) to ArgoCD instance sourceNamespaces"
	@if ! oc get argocd gitops-$(ARGOCD_INSTANCE) -n gitops-$(ARGOCD_INSTANCE) -o jsonpath='{.spec.sourceNamespaces[*]}' | grep -q "$(NAMESPACE)"; then \
		oc patch argocd gitops-$(ARGOCD_INSTANCE) -n gitops-$(ARGOCD_INSTANCE) --type=json -p='[{"op": "add", "path": "/spec/sourceNamespaces/-", "value": "$(NAMESPACE)"}]'; \
		echo "Namespace $(NAMESPACE) added to sourceNamespaces"; \
	else \
		echo "Namespace $(NAMESPACE) already in sourceNamespaces"; \
	fi
	@echo "Managed namespace $(NAMESPACE) created/updated successfully"

##@ OPENSHIFT GITOPS OPERATOR SETUP
.PHONY: install_gitops_operator
install_gitops_operator: ## Install the OpenShift GitOps Operator (Red Hat's ArgoCD distribution)
	@echo "=========================================="
	@echo "Installing OpenShift GitOps Operator"
	@echo "=========================================="
	# Apply operator subscription to install OpenShift GitOps
	# This creates: namespace, operatorgroup, and subscription
	@oc apply -f openshift-gitops-configs/openshift-gitops-operator-install.yaml
	@echo ""
	@echo "✅ OpenShift GitOps Operator installation initiated"
	@echo ""
	@echo "Monitor installation progress with:"
	@echo "  oc get subscription -n openshift-gitops-operator"
	@echo "  oc get csv -n openshift-gitops-operator"
	@echo "  oc get pods -n openshift-gitops"
	@echo ""
	@echo "Once installed, run: make configure_openshift_gitops"


.PHONY: configure_openshift_gitops
configure_openshift_gitops: verify_gitops_examples ## Configure the default openshift-gitops ArgoCD instance with cluster-wide permissions and TLS certificates
	@echo "=========================================="
	@echo "Configuring OpenShift GitOps"
	@echo "=========================================="
	# Apply ClusterRole and ClusterRoleBinding for managing cluster-scoped resources
	# This grants permissions for: Namespaces, NNCP, MetalLB, OpenStack CRDs, etc.
	@oc apply -f openshift-gitops-configs/openshift-gitops-rbac.yaml
	@echo "Configuring OpenShift GitOps RBAC policy for user access"
	# Patch ArgoCD instance to allow authenticated users to access the UI with admin privileges
	@oc patch argocd openshift-gitops -n openshift-gitops --type=merge -p '{"spec":{"rbac":{"defaultPolicy":"role:readonly","policy":"g, system:cluster-admins, role:admin\ng, kubeadmin, role:admin\ng, system:authenticated, role:admin\n","scopes":"[groups]"}}}'
	@echo ""
	@echo "Configuring ArgoCD TLS certificates for Git repository access"
	# Apply ConfigMap with TLS certificates for Git repository access
	# This allows ArgoCD to trust private/internal Git servers (e.g., gitlab.cee.redhat.com)
	@oc apply -f examples/infra/configmap/argocd-cert-bundle.yaml -n openshift-gitops
	@echo ""
	@echo "Configuring ArgoCD custom resource health checks"
	# Apply custom health checks for OpenStack and Metal3 resources
	# This teaches ArgoCD how to determine if custom resources are healthy
	@oc patch configmap argocd-cm -n openshift-gitops --type merge --patch-file openshift-gitops-configs/argocd-resource-health-checks.yaml
	@echo "Restarting ArgoCD controller to apply health check configuration"
	@oc rollout restart deployment cluster -n openshift-gitops
	@echo ""
	@echo "✅ OpenShift GitOps configured successfully"
	@echo ""
	@echo "This instance can now manage:"
	@echo "  - Cluster-scoped resources (Namespaces, NNCP, MetalLB, etc.)"
	@echo "  - OpenStack CRDs across all namespaces"
	@echo "  - All Kubernetes resources cluster-wide"
	@echo "  - Git repositories with custom TLS certificates"
	@echo ""
	@echo "Access the UI at:"
	@echo "  oc get route -n openshift-gitops openshift-gitops-server -o jsonpath='{.spec.host}'"

##@ VAULT INTEGRATION
.PHONY: install_vault_secrets_operator
install_vault_secrets_operator: ## Install the Vault Secrets Operator from certified operators
	@echo "=========================================="
	@echo "Installing Vault Secrets Operator"
	@echo "=========================================="
	# Apply operator subscription to install Vault Secrets Operator
	# This creates the subscription in the openshift-operators namespace
	# The operator will be available cluster-wide once installed
	@oc apply -f vault-configs/vault-secrets-operator-install.yaml
	@echo ""
	@echo "✅ Vault Secrets Operator installation initiated"
	@echo ""
	@echo "Monitor installation progress with:"
	@echo "  oc get subscription vault-secrets-operator -n openshift-operators"
	@echo "  oc get csv -n openshift-operators | grep vault-secrets"
	@echo "  oc get pods -n openshift-operators | grep vault-secrets"
	@echo ""
	@echo "Once installed, you can configure Vault integration with:"
	@echo "  make setup_vault NAMESPACE=<namespace> APPROLE_ROLE_ID=<role-id> APPROLE_SECRET_ID=<secret-id>"

.PHONY: setup_vault
setup_vault: verify_gitops_examples ## Setup Vault namespace and deploy vault configuration (Usage: NAMESPACE=<namespace> APPROLE_ROLE_ID=<role-id> APPROLE_SECRET_ID=<secret-id> make setup_vault)
	# Validate required parameters
	@if [ -z "$(NAMESPACE)" ] || [ -z "$(APPROLE_ROLE_ID)" ] || [ -z "$(APPROLE_SECRET_ID)" ]; then \
		echo "Error: Missing required parameter(s)"; \
		[ -z "$(NAMESPACE)" ] && echo "  - NAMESPACE is required"; \
		[ -z "$(APPROLE_ROLE_ID)" ] && echo "  - APPROLE_ROLE_ID is required"; \
		[ -z "$(APPROLE_SECRET_ID)" ] && echo "  - APPROLE_SECRET_ID is required"; \
		echo ""; \
		echo "Usage: make setup_vault NAMESPACE=<namespace> APPROLE_ROLE_ID=<role-id> APPROLE_SECRET_ID=<secret-id>"; \
		exit 1; \
	fi
	@echo "Setting up Vault in namespace: $(NAMESPACE)"
	@echo "Creating namespace..."
	@oc create namespace $(NAMESPACE) --dry-run=client -o yaml | oc apply -f -
	@echo "Encoding AppRole secret ID..."
	$(eval APPROLE_SECRET_ID_BASE64 := $(shell echo -n "$(APPROLE_SECRET_ID)" | base64 -w 0))
	@echo "Applying Red Hat CA certificate..."
	@cat examples/infra/secret/redhat-ca.yaml | \
		sed 's/namespace: openstack/namespace: $(NAMESPACE)/' | \
		oc apply -f -
	@echo "Creating kustomization from template..."
	@sed -e 's/NAMESPACE_PLACEHOLDER/$(NAMESPACE)/g' \
	     -e 's|APPROLE_SECRET_ID_BASE64_PLACEHOLDER|$(APPROLE_SECRET_ID_BASE64)|g' \
	     -e 's/APPROLE_ROLE_ID_PLACEHOLDER/$(APPROLE_ROLE_ID)/g' \
	     vault-configs/vault-approle-kustomization.yaml.template > examples/infra/vault/kustomization.yaml
	@echo "Building and applying vault configuration..."
	@oc apply -k examples/infra/vault
	@echo "Vault setup complete for namespace: $(NAMESPACE)"

.PHONY: clean_gitops_examples
clean_gitops_examples: ## Remove the cloned examples directory
	@rm -rf examples
	@echo "Cleaned up examples directory"