# GitOps Tools

Automation toolkit for deploying and managing multiple ArgoCD instances and their associated namespaces in OpenShift/Kubernetes clusters. This toolset is optimized for multi-tenant OpenStack deployments but can be used for any GitOps workflow requiring isolated ArgoCD instances.

## Overview

This repository provides Make targets that simplify:
- Installing and configuring the OpenShift GitOps Operator
- Deploying multiple isolated ArgoCD instances (e.g., one per customer/team)
- Creating and managing namespaces with proper security and RBAC configurations
- Configuring cluster-wide permissions for OpenStack-related resources (NNCP, MetalLB, etc.)

## Prerequisites

### Required Tools
- **oc CLI**: OpenShift command-line tool (authenticated to your cluster)
- **envsubst**: Environment variable substitution tool (from `gettext` package)
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
which oc envsubst make

# Verify cluster access
oc whoami
oc cluster-info
```

## Quick Start

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

## Available Make Targets

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

## Accessing ArgoCD UI

### Getting the URL
After deploying an ArgoCD instance, the URL is displayed automatically. You can also retrieve it manually:

```bash
# Get the route URL for a specific instance
oc get route -n gitops-<ARGOCD_INSTANCE> gitops-<ARGOCD_INSTANCE>-server -o jsonpath='{.spec.host}'

# Example for client1
oc get route -n gitops-client1 gitops-client1-server -o jsonpath='{.spec.host}'

# Open in browser with full URL
echo "https://$(oc get route -n gitops-client1 gitops-client1-server -o jsonpath='{.spec.host}')"
```

### Authentication
All ArgoCD instances are configured with **OpenShift OAuth integration**:
- Log in with your OpenShift credentials (same as `oc login`)
- No separate username/password to manage
- RBAC is configured to grant admin access to authenticated users

### Default ArgoCD Instance
The OpenShift GitOps operator also creates a default instance:
```bash
# Get default ArgoCD URL
oc get route -n openshift-gitops openshift-gitops-server -o jsonpath='{.spec.host}'
```
