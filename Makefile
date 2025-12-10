# GitOps Tools Makefile
# This Makefile provides automation for deploying and managing ArgoCD instances
# and their associated namespaces in OpenShift/Kubernetes clusters.
#
# Prerequisites:
#   - oc CLI installed and authenticated to your cluster
#   - envsubst command available (usually from gettext package)
#   - Proper RBAC permissions to create namespaces and ArgoCD resources
#
# Quick Start:
#   1. Install OpenShift GitOps operator:        make install_gitops_operator
#   2. Configure OpenShift GitOps instance:      make configure_openshift_gitops
#   3. Deploy a new ArgoCD instance:             ARGOCD_INSTANCE=client1 make deploy_argocd_instance
#   4. Create managed namespaces:                NAMESPACE=rhoso1 ARGOCD_INSTANCE=client1 make create_managed_namespace

.DEFAULT_GOAL := help

.PHONY: help
help: ## Display this help message with all available targets
	@awk 'BEGIN {FS = ":.*##"; printf "\nUsage:\n  make \033[36m<target>\033[0m\n"} /^[a-zA-Z_0-9-]+:.*?##/ { printf "  \033[36m%-30s\033[0m %s\n", $$1, $$2 } /^##@/ { printf "\n\033[1m%s\033[0m\n", substr($$0, 5) } ' $(MAKEFILE_LIST)

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
	# Deploy ArgoCD instance using envsubst to replace ${ARGOCD_INSTANCE} in YAML templates
	# NOTE: This instance can only manage namespace-scoped resources
	# For cluster-scoped resources (NNCP, MetalLB, etc.), use openshift-gitops instance
	@echo "Deploying ArgoCD instance and RBAC configuration"
	@ARGOCD_INSTANCE=$(ARGOCD_INSTANCE) envsubst < argocd-instance-configs/argocd-instance.yaml | oc apply -f -
	@ARGOCD_INSTANCE=$(ARGOCD_INSTANCE) envsubst < argocd-instance-configs/argocd-instance-rbac.yaml | oc apply -f -
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
	@NAMESPACE=$(NAMESPACE) ARGOCD_INSTANCE=$(ARGOCD_INSTANCE) envsubst < argocd-instance-configs/managed-namespace.yaml | oc apply -f -
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
	@oc apply -f openshift-gitops-configs/gitops-operator-install.yaml
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
configure_openshift_gitops: ## Configure the default openshift-gitops ArgoCD instance with cluster-wide permissions and TLS certificates
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
	@oc apply -f openshift-gitops-configs/argocd-cert-bundle.yaml -n openshift-gitops
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