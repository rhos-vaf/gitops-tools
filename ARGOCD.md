## ArgoCD Instance Management

### Available Make Targets

### 1. install_gitops_operator
**Purpose**: Install the OpenShift GitOps Operator (Red Hat's distribution of ArgoCD)

**Usage**:
```bash
make install_gitops_operator
```

**What it does**:
- Creates the `openshift-gitops-operator` namespace
- Deploys the operator subscription from Red Hat's catalog
- Automatically installs a default ArgoCD instance in the `openshift-gitops` namespace

**Verification**:
```bash
oc get subscription -n openshift-gitops-operator
oc get csv -n openshift-gitops-operator
oc get pods -n openshift-gitops
```

---

### 2. configure_openshift_gitops
**Purpose**: Configure the default OpenShift GitOps instance with cluster-wide permissions and TLS certificates

**Usage**:
```bash
make configure_openshift_gitops
```

**What it does**:
- Applies ClusterRole with permissions for OpenStack resources, NNCP, MetalLB, etc.
- Creates ClusterRoleBinding for the ArgoCD application controller
- Configures RBAC policy to allow authenticated users admin access to ArgoCD UI
- Applies TLS certificates ConfigMap (`argocd-tls-certs-cm`) for Git repository access
- Enables ArgoCD to trust private/internal Git servers (e.g., `gitlab.cee.redhat.com`)
- **Configures custom resource health checks** for OpenStack and Metal3 resources
- **Restarts ArgoCD controller** to apply health check configuration

**Note**: Run this after the operator installation completes

**Verification**:
```bash
# Verify RBAC configuration
oc get clusterrole openshift-gitops-argocd-application-controller

# Verify TLS certificates ConfigMap
oc get configmap argocd-tls-certs-cm -n openshift-gitops
```

---

### 3. deploy_argocd_instance
**Purpose**: Deploy a new isolated ArgoCD instance (e.g., for a specific customer or team)

**Usage**:
```bash
ARGOCD_INSTANCE=client1 make deploy_argocd_instance
```

**Required Parameters**:
- `ARGOCD_INSTANCE`: Name identifier for this ArgoCD instance (e.g., `client1`, `team-a`, `production`)

**What it does**:
- Creates namespace: `gitops-<ARGOCD_INSTANCE>`
- Deploys dedicated ArgoCD instance with:
  - OpenShift OAuth integration for authentication
  - Cluster root CA bundle for private Git repositories
  - Resource customizations for OpenStack CRDs health checks
  - Resource limits and requests for all components
- Configures RBAC permissions for ArgoCD CRDs:
  - Access to Applications, ApplicationSets, and AppProjects across namespaces
  - Read-only access to namespace list (for UI display)
- Displays the ArgoCD web UI URL

**Important Limitation**:
- ArgoCD instances **cannot manage cluster-scoped resources** (Namespaces, NNCP, MetalLB, StorageClasses, etc.)
- Only namespace-scoped resources can be managed within the configured sourceNamespaces
- For cluster-scoped resources, use the default OpenShift GitOps instance (see `configure_openshift_gitops`)

**Example Output**:
```
ArgoCD URL: https://gitops-client1-server-gitops-client1.apps.example.com
```

---

### 4. create_managed_namespace
**Purpose**: Create a namespace that will be managed by a specific ArgoCD instance

**Usage**:
```bash
NAMESPACE=rhoso1 ARGOCD_INSTANCE=client1 make create_managed_namespace
```

**Required Parameters**:
- `NAMESPACE`: Name of the namespace to create (e.g., `rhoso1`, `app-production`)
- `ARGOCD_INSTANCE`: Name of the ArgoCD instance that will manage this namespace

**What it does**:
- Creates the namespace with labels:
  - `argocd.argoproj.io/managed-by: gitops-<ARGOCD_INSTANCE>`
  - Pod security labels set to `privileged` (required for OpenStack pods)
  - `security.openshift.io/scc.podSecurityLabelSync: "false"` (prevents automatic security context changes)
- Adds the namespace to the ArgoCD instance's `sourceNamespaces` list
  - This allows ArgoCD Application resources to be created in this namespace

**Why sourceNamespaces matters**:
ArgoCD Applications can only be created in namespaces listed in `sourceNamespaces`. This provides namespace-level isolation between different ArgoCD instances.

---

### Accessing ArgoCD UI

#### Getting the URL
After deploying an ArgoCD instance, the URL is displayed automatically. You can also retrieve it manually:

```bash
# Get the route URL for a specific instance
oc get route -n gitops-<ARGOCD_INSTANCE> gitops-<ARGOCD_INSTANCE>-server -o jsonpath='{.spec.host}'

# Example for client1
oc get route -n gitops-client1 gitops-client1-server -o jsonpath='{.spec.host}'

# Open in browser with full URL
echo "https://$(oc get route -n gitops-client1 gitops-client1-server -o jsonpath='{.spec.host}')"
```

#### Authentication
All ArgoCD instances are configured with **OpenShift OAuth integration**:
- Log in with your OpenShift credentials (same as `oc login`)
- No separate username/password to manage
- RBAC is configured to grant admin access to authenticated users

#### Default ArgoCD Instance
The OpenShift GitOps operator also creates a default instance:
```bash
# Get default ArgoCD URL
oc get route -n openshift-gitops openshift-gitops-server -o jsonpath='{.spec.host}'
```

---

## ArgoCD Resource Health Checks

The `configure_openshift_gitops` target automatically configures ArgoCD with custom health checks for OpenStack and Metal3 resources. This enables ArgoCD to understand the health status of custom resources and properly orchestrate sync waves.

### Included Health Checks

The following custom resource health checks are automatically configured:

1. **metal3.io/BareMetalHost** - Healthy when state is "available" or "provisioned"
2. **core.openstack.org/OpenStackControlPlane** - Healthy when Ready condition is True
3. **dataplane.openstack.org/OpenStackDataPlaneNodeSet** - Healthy when SetupReady condition is True
4. **dataplane.openstack.org/OpenStackDataPlaneDeployment** - Healthy when Ready condition is True
5. **nmstate.io/NodeNetworkConfigurationPolicy** - Healthy when Available condition is True
6. **secrets.hashicorp.com/VaultStaticSecret** - Healthy when SecretSynced condition is True
7. **secrets.hashicorp.com/VaultAuth** - Healthy when status.valid is true
8. **secrets.hashicorp.com/VaultConnection** - Healthy when status.valid is true
9. **baremetal.openstack.org/OpenStackProvisionServer** - Healthy when Ready condition is True
10. **operators.coreos.com/Subscription** - Healthy when state is AtLatestKnown or UpgradePending
11. **argoproj.io/Application** - Delegates to application's own health status

### Benefits

With these health checks configured:
- ✅ **Native GitOps** - ArgoCD natively understands resource health without custom wait Jobs
- ✅ **Better visibility** - ArgoCD UI shows actual resource health status
- ✅ **Automatic retries** - ArgoCD handles sync retries automatically
- ✅ **Less complexity** - No ServiceAccount/RBAC needed for basic health checks
- ✅ **Resource efficiency** - No Job pods consuming cluster resources
- ✅ **Sync wave orchestration** - Resources in later waves wait for earlier waves to be healthy

### Manual Configuration

The health checks are stored in [`openshift-gitops-configs/argocd-resource-health-checks.yaml`](openshift-gitops-configs/argocd-resource-health-checks.yaml) and can be manually applied:

```bash
# Apply health checks manually
oc patch configmap argocd-cm -n openshift-gitops \
  --type merge \
  --patch-file openshift-gitops-configs/argocd-resource-health-checks.yaml

# Restart ArgoCD controller to pick up changes
oc rollout restart deployment cluster -n openshift-gitops
```

### Verification

```bash
# Check that health checks are configured
oc get configmap argocd-cm -n openshift-gitops -o yaml | \
  grep -A 5 "resource.customizations.health"

# View logs to verify health checks are being used
oc logs -n openshift-gitops deployment/cluster | grep health
```

### Documentation

For detailed information about the health checks implementation, see:
- [`openshift-gitops-configs/argocd-resource-health-checks.yaml`](openshift-gitops-configs/argocd-resource-health-checks.yaml) - The health check definitions
- [ArgoCD Resource Health Documentation](https://argo-cd.readthedocs.io/en/stable/operator-manual/health/) - Official ArgoCD documentation

---

