# GitOps Tools

Automation toolkit for deploying and managing multiple ArgoCD instances, custom resource health checks, namespaces, and HashiCorp Vault integration in OpenShift/Kubernetes clusters. This toolset is optimized for multi-tenant RHOSO (Red Hat OpenStack Services on OpenShift) deployments but can be used for any GitOps workflow requiring isolated ArgoCD instances.

## Table of Contents

- [Overview](#overview)
- [Prerequisites](#prerequisites)
- [Quick Start](#quick-start)
- [ArgoCD Instance Management](#argocd-instance-management)
- [ArgoCD Resource Health Checks](#argocd-resource-health-checks)
- [Vault Integration](#vault-integration)
- [Accessing ArgoCD UI](#accessing-argocd-ui)
- [Troubleshooting](#troubleshooting)

## Overview

This repository provides Make targets that simplify:
- **ArgoCD Management**: Installing and configuring the OpenShift GitOps Operator
- **Resource Health Checks**: Custom health checks for OpenStack and Metal3 resources
- **Multi-tenancy**: Deploying multiple isolated ArgoCD instances (e.g., one per customer/team)
- **Namespace Management**: Creating and managing namespaces with proper security and RBAC configurations
- **Cluster Permissions**: Configuring cluster-wide permissions for OpenStack-related resources (NNCP, MetalLB, etc.)
- **Secret Management**: Integrating HashiCorp Vault for centralized secret management

## Prerequisites

### Required Tools
- **oc CLI**: OpenShift command-line tool (authenticated to your cluster)
- **make**: GNU Make for running automation targets

### Required Permissions
You need cluster-admin or equivalent permissions to:
- Install operators
- Create namespaces
- Create ClusterRoles and ClusterRoleBindings
- Deploy ArgoCD custom resources

### Installation Check
```bash
# Verify required tools are installed
which oc make

# Verify cluster access
oc whoami
oc cluster-info
```

## Quick Start

### ArgoCD Setup

```bash
# 1. Display all available commands
make help

# 2. Install OpenShift GitOps Operator (one-time setup)
make install_gitops_operator

# 3. Configure the default OpenShift GitOps instance (one-time setup)
make configure_openshift_gitops

# 4. Deploy a customer-specific ArgoCD instance
ARGOCD_INSTANCE=client1 make deploy_argocd_instance

# 5. Create managed namespaces for this ArgoCD instance
NAMESPACE=rhoso1 ARGOCD_INSTANCE=client1 make create_managed_namespace
NAMESPACE=rhoso2 ARGOCD_INSTANCE=client1 make create_managed_namespace
```

### Vault Integration Setup

```bash
# Set up Vault integration for a namespace
make setup_vault \
  NAMESPACE=rhoso-dev-nova04delta \
  APPROLE_ROLE_ID=my-role \
  APPROLE_SECRET_ID=<your-secret-id>

# Clean up cloned examples repository
make clean_gitops_examples
```

---

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

The health checks are stored in [`argocd-health-checks/resource-health-checks.yaml`](argocd-health-checks/resource-health-checks.yaml) and can be manually applied:

```bash
# Apply health checks manually
oc patch configmap argocd-cm -n openshift-gitops \
  --type merge \
  --patch-file argocd-health-checks/resource-health-checks.yaml

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
- [`argocd-health-checks/resource-health-checks.yaml`](argocd-health-checks/resource-health-checks.yaml) - The health check definitions
- [ArgoCD Resource Health Documentation](https://argo-cd.readthedocs.io/en/stable/operator-manual/health/) - Official ArgoCD documentation

---

## Vault Integration

This repository includes automation for deploying HashiCorp Vault integration for RHOSO deployments using the External Secrets Operator. This enables centralized secret management for OpenStack credentials, database passwords, encryption keys, and TLS certificates.

### Vault Overview

The Vault integration automates the setup of Vault authentication and connection configuration by:
1. Creating a dedicated namespace for Vault resources
2. Cloning the required configuration templates from the examples repository
3. Generating a kustomization.yaml from the template in `vault-configs/kustomization-template.yaml`
4. Applying kustomize patches to customize the configuration with your namespace, Role ID, and Secret ID
5. Deploying the Vault integration to the OpenShift cluster

### Vault Prerequisites

- OpenShift cluster with admin access
- External Secrets Operator installed
- HashiCorp Vault instance accessible from the cluster
- AppRole authentication configured in Vault
- Valid AppRole Role ID and Secret ID for authentication

### Vault Make Targets

#### 5. setup_vault

**Purpose**: Deploy Vault configuration to integrate with HashiCorp Vault for secret management

**Usage**:
```bash
make setup_vault NAMESPACE=<rhoso-namespace> APPROLE_ROLE_ID=<role-id> APPROLE_SECRET_ID=<secret-id>
```

**Required Parameters**:
- `NAMESPACE`: Target RHOSO namespace for Vault resources (required)
- `APPROLE_ROLE_ID`: Vault AppRole Role ID for authentication (required)
- `APPROLE_SECRET_ID`: Vault AppRole Secret ID for authentication (required)
  - The Secret ID can be retrieved from the Vault UI at: https://vault.corp.redhat.com:8200/ui/vault/dashboard

**Example**:
```bash
make setup_vault NAMESPACE=rhoso-dev-nova04delta APPROLE_ROLE_ID=my-role APPROLE_SECRET_ID=my-secret
```

**What it does**:
- Creates the target namespace if it doesn't exist
- Clones configuration templates from `https://gitlab.cee.redhat.com/rhos-gitops/examples.git`
- Deploys Red Hat CA certificate for Vault TLS validation
- Configures Vault authentication using AppRole method
- Deploys VaultConnection and VaultAuth resources
- Stores the AppRole Secret ID securely

**Resources Deployed**:
1. **Secret - Red Hat CA Certificate** (`redhat-ca`): Red Hat internal CA certificate for Vault TLS validation
2. **VaultAuth** (`vaultauth-${APPROLE_ROLE_ID}`): Configures Vault authentication using AppRole method with the specified role ID
3. **VaultConnection**: Defines the connection to the Vault server with TLS configuration
4. **Secret - AppRole Secret ID** (`vault-approle-secret-corp-redhat`): Stores the base64-encoded AppRole Secret ID

#### 6. clean_gitops_examples

**Purpose**: Remove the cloned examples directory

**Usage**:
```bash
make clean_gitops_examples
```

**What it does**:
- Removes the `examples/` directory that was cloned during `setup_vault` or `configure_openshift_gitops`

---

## Vault Configuration Details

### What Gets Deployed

The `setup_vault` target deploys four main resources to enable Vault integration:

#### 1. Secret - Red Hat CA Certificate (redhat-ca)
Red Hat internal CA certificate for Vault TLS validation:
- **Name**: `redhat-ca`
- **Namespace**: `${NAMESPACE}`
- **Type**: Opaque
- **Data**: Red Hat IT Root CA and Internal Root CA certificates

#### 2. VaultAuth (vault-auth.yaml)
Configures Vault authentication using AppRole method:
- **Name**: `vaultauth-${APPROLE_ROLE_ID}`
- **Namespace**: `${NAMESPACE}`
- **Role ID**: `${APPROLE_ROLE_ID}`
- **Authentication Method**: AppRole

#### 3. VaultConnection (vault-connection.yaml)
Defines the connection to the Vault server:
- **Namespace**: `${NAMESPACE}`
- **Connection Details**: Vault server URL and TLS configuration
- **CA Certificate**: References `redhat-ca` secret

#### 4. Secret - AppRole Secret ID (vault-approle-secret-corp-redhat)
Stores the AppRole Secret ID:
- **Name**: `vault-approle-secret-corp-redhat`
- **Namespace**: `${NAMESPACE}`
- **Data**: Base64-encoded AppRole Secret ID

### Configuration Template

The kustomization configuration is defined in `vault-configs/kustomization-template.yaml` with placeholders that are replaced at runtime:
- `NAMESPACE_PLACEHOLDER` - Replaced with the target namespace
- `APPROLE_SECRET_ID_BASE64_PLACEHOLDER` - Replaced with the base64-encoded Secret ID
- `APPROLE_ROLE_ID_PLACEHOLDER` - Replaced with the AppRole Role ID

### Workflow

1. **Validate Parameters**: Checks that `NAMESPACE`, `APPROLE_ROLE_ID`, and `APPROLE_SECRET_ID` are provided
2. **Create Namespace**: Creates the target namespace if it doesn't exist (idempotent operation)
3. **Clone Repository**: Clones configuration templates from GitLab (skipped if already exists)
4. **Encode Secret**: Base64-encodes the AppRole Secret ID using `base64 -w 0`
5. **Apply CA Certificate**: Deploys Red Hat CA certificate to the target namespace
6. **Generate Kustomization**: Processes template using `sed` to replace placeholders
7. **Apply Configuration**: Uses `oc apply -k` to deploy all vault resources

### Integration with RHOSO

This Vault configuration is designed to work with RHOSO (Red Hat OpenStack Services on OpenShift) deployments by providing:
- Centralized secret management for OpenStack credentials
- Dynamic secret generation for database passwords
- Encryption key storage for sensitive data
- Certificate management for TLS-enabled services

### References

- [External Secrets Operator Documentation](https://external-secrets.io/)
- [HashiCorp Vault AppRole Documentation](https://www.vaultproject.io/docs/auth/approle)
- [Kustomize Documentation](https://kustomize.io/)
- [RHOSO GitOps Examples](https://gitlab.cee.redhat.com/rhos-gitops/examples)

---

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

## References

- [OpenShift GitOps Documentation](https://docs.openshift.com/container-platform/latest/cicd/gitops/understanding-openshift-gitops.html)
- [ArgoCD Documentation](https://argo-cd.readthedocs.io/)
- [ArgoCD Resource Health Checks](https://argo-cd.readthedocs.io/en/stable/operator-manual/health/)
- [External Secrets Operator](https://external-secrets.io/)
- [HashiCorp Vault](https://www.vaultproject.io/)
- [RHOSO Documentation](https://access.redhat.com/documentation/en-us/red_hat_openstack_services_on_openshift)
