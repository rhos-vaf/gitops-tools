# gitops-tools
GitOps Tooling for managing ArgoCD instances and namespaces

## Overview

This repository provides Makefile targets to easily deploy and manage ArgoCD instances and their managed namespaces in OpenShift/Kubernetes clusters.

## Prerequisites

- `oc` CLI installed and configured
- Access to an OpenShift/Kubernetes cluster
- Proper RBAC permissions to create namespaces and ArgoCD instances

## Available Targets

### Display Help
```bash
make help
```
Shows all available targets with their descriptions.

### Deploy ArgoCD Instance
Deploy a new ArgoCD instance with the specified name:

```bash
ARGOCD_INSTANCE=client1 make deploy_argocd_instance
```

**Required Parameters:**
- `ARGOCD_INSTANCE`: Name of the ArgoCD instance to deploy (e.g., `client1`, `client2`)

**What it does:**
- Creates a namespace `gitops-<ARGOCD_INSTANCE>`
- Deploys an ArgoCD instance in that namespace
- Configures RBAC permissions for the instance
- Enables OpenShift OAuth integration
- Sets up resource customizations for OpenStack CRDs
- Grants cluster-wide permissions for:
  - **NNCP (NodeNetworkConfigurationPolicy)** management
  - **MetalLB** resources (IPAddressPool, L2Advertisement) management
  - **Namespace** label/annotation management
- Displays the ArgoCD web UI URL upon completion

### Create/Update Managed Namespace
Create or update a namespace that will be managed by an ArgoCD instance:

```bash
NAMESPACE=rhoso1 ARGOCD_INSTANCE=client1 make create_managed_namespace
```

**Required Parameters:**
- `NAMESPACE`: Name of the namespace to create/update (e.g., `rhoso1`, `rhoso2`)
- `ARGOCD_INSTANCE`: Name of the ArgoCD instance that will manage this namespace (e.g., `client1`)

**What it does:**
- Creates a namespace with the specified name
- Adds the label `argocd.argoproj.io/managed-by: gitops-<ARGOCD_INSTANCE>` to link it to the ArgoCD instance
- Configures privileged pod security settings required for OpenStack workloads
- Automatically adds the namespace to the ArgoCD instance's `sourceNamespaces` list (required for ArgoCD to manage resources in this namespace)

## Usage Examples

### Example 1: Deploy a new ArgoCD instance for client1
```bash
ARGOCD_INSTANCE=client1 make deploy_argocd_instance
```

### Example 2: Create a managed namespace for OpenStack deployment
```bash
NAMESPACE=rhoso1 ARGOCD_INSTANCE=client1 make create_managed_namespace
```

### Example 3: Full workflow
```bash
# 1. Deploy ArgoCD instance
ARGOCD_INSTANCE=client1 make deploy_argocd_instance

# 2. Create managed namespaces for this instance
NAMESPACE=rhoso1 ARGOCD_INSTANCE=client1 make create_managed_namespace
NAMESPACE=rhoso2 ARGOCD_INSTANCE=client1 make create_managed_namespace
```

## Accessing ArgoCD UI

After deploying an ArgoCD instance, the URL will be displayed automatically. You can also retrieve it manually:

```bash
# Get the route URL
oc get route -n gitops-<ARGOCD_INSTANCE> gitops-<ARGOCD_INSTANCE>-server -o jsonpath='{.spec.host}'

# Example for client1
oc get route -n gitops-client1 gitops-client1-server -o jsonpath='{.spec.host}'
```

The ArgoCD instance uses OpenShift OAuth for authentication. Log in with your OpenShift credentials.

## Cluster Permissions

The `deploy_argocd_instance` target automatically grants the following cluster-level permissions to the ArgoCD application controller:

1. **NNCP Manager**: Full permissions for `NodeNetworkConfigurationPolicy` resources (nmstate.io)
2. **MetalLB Manager**: Full permissions for `IPAddressPool` and `L2Advertisement` resources (metallb.io)
3. **Namespace Manager**: Read and update permissions for namespace labels and annotations

These permissions allow ArgoCD to manage network configuration and load balancer resources required for OpenStack deployments.

## Configuration Files

The Makefile uses the following configuration files from `argocd-instance-configs/`:

- **argocd-instance.yaml**: Main ArgoCD instance configuration
- **argocd-instance-rbac.yaml**: RBAC permissions for the ArgoCD instance
- **managed-namespace.yaml**: Template for creating managed namespaces

