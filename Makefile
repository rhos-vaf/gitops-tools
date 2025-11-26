.DEFAULT_GOAL := help

.PHONY: help
help: ## Display this help message
	@awk 'BEGIN {FS = ":.*##"; printf "\nUsage:\n  make \033[36m<target>\033[0m\n"} /^[a-zA-Z_0-9-]+:.*?##/ { printf "  \033[36m%-30s\033[0m %s\n", $$1, $$2 } /^##@/ { printf "\n\033[1m%s\033[0m\n", substr($$0, 5) } ' $(MAKEFILE_LIST)

##@ DEPLOY ARGOCD INSTANCE
.PHONY: deploy_argocd_instance
deploy_argocd_instance: ## Deploy ArgoCD instance (Usage: ARGOCD_INSTANCE=client1 make deploy_argocd_instance)
	@if [ -z "$(ARGOCD_INSTANCE)" ]; then \
		echo "Error: ARGOCD_INSTANCE is required. Usage: ARGOCD_INSTANCE=client1 make deploy_argocd_instance"; \
		exit 1; \
	fi
	@echo "Deploying ArgoCD instance: $(ARGOCD_INSTANCE)"
	@echo "Creating namespace gitops-$(ARGOCD_INSTANCE)"
	@oc create namespace gitops-$(ARGOCD_INSTANCE) || true
	@echo "Switching to gitops-$(ARGOCD_INSTANCE) namespace"
	@oc project gitops-$(ARGOCD_INSTANCE)
	@echo "Creating cluster root CA bundle ConfigMap"
	@oc create configmap cluster-root-ca-bundle || true
	@oc label configmap cluster-root-ca-bundle config.openshift.io/inject-trusted-cabundle=true --overwrite || true
	@echo "Deploying ArgoCD instance and RBAC configuration"
	@ARGOCD_INSTANCE=$(ARGOCD_INSTANCE) envsubst < argocd-instance-configs/argocd-instance.yaml | oc apply -f -
	@ARGOCD_INSTANCE=$(ARGOCD_INSTANCE) envsubst < argocd-instance-configs/argocd-instance-rbac.yaml | oc apply -f -
	@echo "ArgoCD instance $(ARGOCD_INSTANCE) deployed successfully with cluster-wide permissions"
	@echo "Waiting for ArgoCD route to be available..."
	@sleep 5
	@echo "ArgoCD URL: https://$$(oc get route -n gitops-$(ARGOCD_INSTANCE) gitops-$(ARGOCD_INSTANCE)-server -o jsonpath='{.spec.host}' 2>/dev/null || echo 'Route not ready yet')"

##@ CONFIGURE OPENSHIFT GITOPS
.PHONY: configure_openshift_gitops
configure_openshift_gitops: ## Grant cluster-wide permissions to openshift-gitops instance
	@echo "Configuring OpenShift GitOps with cluster-wide permissions"
	@oc apply -f argocd-instance-configs/openshift-gitops-rbac.yaml
	@echo "Configuring OpenShift GitOps RBAC policy"
	@oc patch argocd openshift-gitops -n openshift-gitops --type=merge -p '{"spec":{"rbac":{"defaultPolicy":"role:readonly","policy":"g, system:cluster-admins, role:admin\ng, kubeadmin, role:admin\ng, system:authenticated, role:admin\n","scopes":"[groups]"}}}'
	@echo "OpenShift GitOps configured successfully with cluster-wide permissions and RBAC policy"

##@ CREATE MANAGED NAMESPACE
.PHONY: create_managed_namespace
create_managed_namespace: ## Create or update managed namespace (Usage: NAMESPACE=rhoso1 ARGOCD_INSTANCE=client1 make create_managed_namespace)
	@if [ -z "$(NAMESPACE)" ]; then \
		echo "Error: NAMESPACE is required. Usage: NAMESPACE=rhoso1 ARGOCD_INSTANCE=client1 make create_managed_namespace"; \
		exit 1; \
	fi
	@if [ -z "$(ARGOCD_INSTANCE)" ]; then \
		echo "Error: ARGOCD_INSTANCE is required. Usage: NAMESPACE=rhoso1 ARGOCD_INSTANCE=client1 make create_managed_namespace"; \
		exit 1; \
	fi
	@echo "Creating/updating managed namespace: $(NAMESPACE) for ArgoCD instance: $(ARGOCD_INSTANCE)"
	@NAMESPACE=$(NAMESPACE) ARGOCD_INSTANCE=$(ARGOCD_INSTANCE) envsubst < argocd-instance-configs/managed-namespace.yaml | oc apply -f -
	@echo "Adding $(NAMESPACE) to ArgoCD instance sourceNamespaces"
	@if ! oc get argocd gitops-$(ARGOCD_INSTANCE) -n gitops-$(ARGOCD_INSTANCE) -o jsonpath='{.spec.sourceNamespaces[*]}' | grep -q "$(NAMESPACE)"; then \
		oc patch argocd gitops-$(ARGOCD_INSTANCE) -n gitops-$(ARGOCD_INSTANCE) --type=json -p='[{"op": "add", "path": "/spec/sourceNamespaces/-", "value": "$(NAMESPACE)"}]'; \
		echo "Namespace $(NAMESPACE) added to sourceNamespaces"; \
	else \
		echo "Namespace $(NAMESPACE) already in sourceNamespaces"; \
	fi
	@echo "Managed namespace $(NAMESPACE) created/updated successfully"
