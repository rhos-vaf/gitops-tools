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
# Verify health checks are configured
oc get configmap argocd-cm -n openshift-gitops -o yaml | \
  grep "resource.customizations.health"

# Restart ArgoCD controller
oc rollout restart deployment cluster -n openshift-gitops

# Check controller logs for health check evaluation
oc logs -n openshift-gitops deployment/cluster | grep -i health

# View resource health status in ArgoCD UI
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
# Check VaultAuth status
oc get vaultauth -n <NAMESPACE>

# Check VaultConnection status
oc get vaultconnection -n <NAMESPACE>

# View External Secrets Operator logs
oc logs -n external-secrets-operator deployment/external-secrets
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

# Check custom resource health in ArgoCD
oc get configmap argocd-cm -n openshift-gitops -o yaml | \
  grep -A 10 "resource.customizations.health"

# View ArgoCD controller deployment
oc get deployment cluster -n openshift-gitops
```

---

