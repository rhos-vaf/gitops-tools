# GitOps Tools

Automation toolkit for deploying and managing multiple ArgoCD instances, custom resource health checks, namespaces, and HashiCorp Vault integration in OpenShift/Kubernetes clusters. This toolset is optimized for multi-tenant RHOSO (Red Hat OpenStack Services on OpenShift) deployments but can be used for any GitOps workflow requiring isolated ArgoCD instances.

## Table of Contents

- [Overview](#overview)
- [Prerequisites](#prerequisites)
- [Quick Start](#quick-start)
- [Documentation](#documentation)
- [References](#references)

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

## Quick Start

### ArgoCD Setup

```bash
# 1. Display all available commands
make help

# 2. Install OpenShift GitOps Operator (one-time setup)
make install_gitops_operator

# 3. Configure the default OpenShift GitOps instance (one-time setup)
make configure_openshift_gitops

# 4. Deploy a customer-specific ArgoCD instance (optional)
ARGOCD_INSTANCE=client1 make deploy_argocd_instance

# 5. Create managed namespaces for this ArgoCD instance (optional)
NAMESPACE=rhoso1 ARGOCD_INSTANCE=client1 make create_managed_namespace
NAMESPACE=rhoso2 ARGOCD_INSTANCE=client1 make create_managed_namespace
```

### Vault Integration Setup

```bash
# Set up Vault integration for a namespace
make setup_vault \
  NAMESPACE=rhoso1 \
  APPROLE_ROLE_ID=my-role \
  APPROLE_SECRET_ID=<your-secret-id>

# Clean up cloned examples repository
make clean_gitops_examples
```

## Documentation

### 📘 [ARGOCD.md](ARGOCD.md)
Comprehensive guide for ArgoCD instance management and resource health checks:
- Installing the OpenShift GitOps Operator
- Configuring cluster-wide permissions and TLS certificates
- Deploying isolated ArgoCD instances for multi-tenancy
- Managing namespaces with proper RBAC
- Accessing ArgoCD UI
- Custom resource health checks for OpenStack and Metal3 resources

### 🔐 [VAULT.md](VAULT.md)
Complete documentation for HashiCorp Vault integration:
- Vault authentication and connection setup
- AppRole configuration
- Secret management for RHOSO deployments
- Configuration templates and placeholders
- Deployment workflow

### 🔧 [TROUBLESHOOTING.md](TROUBLESHOOTING.md)
Troubleshooting guide for common issues:
- ArgoCD instance accessibility problems
- Resource health check issues
- Namespace visibility in ArgoCD
- Vault authentication failures
- Useful diagnostic commands

## References

- [OpenShift GitOps Documentation](https://docs.openshift.com/container-platform/latest/cicd/gitops/understanding-openshift-gitops.html)
- [ArgoCD Documentation](https://argo-cd.readthedocs.io/)
- [ArgoCD Resource Health Checks](https://argo-cd.readthedocs.io/en/stable/operator-manual/health/)
- [External Secrets Operator](https://external-secrets.io/)
- [HashiCorp Vault](https://www.vaultproject.io/)
- [RHOSO Documentation](https://access.redhat.com/documentation/en-us/red_hat_openstack_services_on_openshift)
