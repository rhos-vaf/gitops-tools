## Troubleshooting

### Common Issues

#### ArgoCD instance not accessible
```bash
# Check if the ArgoCD instance is running
oc get argocd -n gitops-<ARGOCD_INSTANCE>

# Check pods status
oc get pods -n gitops-<ARGOCD_INSTANCE>

# View ArgoCD logs
oc logs -n gitops-<ARGOCD_INSTANCE> -l app.kubernetes.io/name=argocd-server
```

#### Resource health checks not working
```bash
# IMPORTANT: Always patch the ArgoCD CR, not the ConfigMap directly
# The operator manages the ConfigMap and will revert manual changes

# 1. Verify health checks are in the ArgoCD CR (source of truth)
oc get argocd openshift-gitops -n openshift-gitops -o jsonpath='{.spec.resourceHealthChecks}' | jq

# 2. Verify operator propagated them to the ConfigMap
oc get configmap argocd-cm -n openshift-gitops -o yaml | \
  grep "resource.customizations.health"

# 3. If ConfigMap is missing health checks, re-apply the ArgoCD CR patch
oc patch argocd openshift-gitops -n openshift-gitops --type merge \
  --patch-file openshift-gitops-configs/argocd-cr-resource-health-checks.yaml

# 4. Wait for operator reconciliation (usually ~10 seconds)
sleep 10

# 5. Check controller logs for health check evaluation
oc logs -n openshift-gitops deployment/openshift-gitops-server | grep -i health

# 6. View resource health status in ArgoCD UI
# Navigate to Application → Select Resource → View Health Status
```

#### Namespace not appearing in ArgoCD
```bash
# Verify namespace is in sourceNamespaces
oc get argocd gitops-<ARGOCD_INSTANCE> -n gitops-<ARGOCD_INSTANCE> -o jsonpath='{.spec.sourceNamespaces}'

# Verify namespace labels
oc get namespace <NAMESPACE> --show-labels
```

#### Vault authentication failing
```bash
# List VaultAuth resources
oc get vaultauth -n <NAMESPACE>

# Check VaultAuth status - should return "true"
oc -n <NAMESPACE> get vaultauths.secrets.hashicorp.com <vaultauth-name> -ojsonpath='{.status.valid}'

# View detailed VaultAuth status
oc -n <NAMESPACE> get vaultauths.secrets.hashicorp.com <vaultauth-name> -ojsonpath='{.status}' | jq

# List VaultConnection resources
oc get vaultconnection -n <NAMESPACE>

# Check VaultConnection status - should return "true"
oc -n <NAMESPACE> get vaultconnections.secrets.hashicorp.com vaultconnection-corp-redhat -ojsonpath='{.status.valid}'

# View detailed VaultConnection status
oc -n <NAMESPACE> get vaultconnections.secrets.hashicorp.com vaultconnection-corp-redhat -ojsonpath='{.status}' | jq
```

#### Examples repository clone fails
```bash
# Remove and re-clone
make clean_gitops_examples
make setup_vault NAMESPACE=<namespace> APPROLE_ROLE_ID=<role-id> APPROLE_SECRET_ID=<secret-id>
```

### Getting Help

```bash
# Display all available make targets with descriptions
make help

# View detailed information about a specific resource
oc describe argocd <instance-name> -n gitops-<instance-name>
oc describe vaultauth <vaultauth-name> -n <namespace>
```

### Useful Commands

```bash
# List all ArgoCD instances
oc get argocd --all-namespaces

# List all managed namespaces for an instance
oc get namespace -l argocd.argoproj.io/managed-by=gitops-<ARGOCD_INSTANCE>

# Check operator status
oc get csv -n openshift-gitops-operator

# View all Vault resources in a namespace
oc get vaultauth,vaultconnection,secret -n <NAMESPACE>

# Check custom resource health checks configuration
# Source of truth: ArgoCD CR
oc get argocd openshift-gitops -n openshift-gitops \
  -o jsonpath='{.spec.resourceHealthChecks[*].kind}' | tr ' ' '\n'

# Verify propagation to ConfigMap
oc get configmap argocd-cm -n openshift-gitops -o yaml | \
  grep "resource.customizations.health" | cut -d: -f1

# View full health check for specific resource
oc get argocd openshift-gitops -n openshift-gitops \
  -o jsonpath='{.spec.resourceHealthChecks[?(@.kind=="BareMetalHost")]}' | jq

# View ArgoCD controller deployment
oc get deployment openshift-gitops-server -n openshift-gitops
oc get deployment openshift-gitops-repo-server -n openshift-gitops
oc get deployment openshift-gitops-applicationset-controller -n openshift-gitops
```

---

