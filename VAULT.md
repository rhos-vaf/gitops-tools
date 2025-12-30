## Vault Integration

This repository includes automation for deploying HashiCorp Vault integration for RHOSO deployments using the External Secrets Operator. This enables centralized secret management for OpenStack credentials, database passwords, encryption keys, and TLS certificates.

### Vault Overview

The Vault integration automates the setup of Vault authentication and connection configuration by:
1. Installing the Vault Secrets Operator (one-time setup)
2. Creating a dedicated namespace for Vault resources
3. Cloning the required configuration templates from the examples repository
4. Generating a kustomization.yaml from the template in `vault-configs/vault-approle-kustomization.yaml.template`
5. Applying kustomize patches to customize the configuration with your namespace, Role ID, and Secret ID
6. Deploying the Vault integration to the OpenShift cluster

### Vault Prerequisites

- OpenShift cluster with admin access
- Vault Secrets Operator installed (can be installed using `make install_vault_secrets_operator`)
- HashiCorp Vault instance accessible from the cluster
- AppRole authentication configured in Vault
- Valid AppRole Role ID and Secret ID for authentication

### Vault Make Targets

#### 1. install_vault_secrets_operator

**Purpose**: Install the Vault Secrets Operator from the certified operators catalog

**Usage**:
```bash
make install_vault_secrets_operator
```

**What it does**:
- Creates a Subscription resource in the `openshift-operators` namespace
- Installs the Vault Secrets Operator from the certified-operators catalog
- Configures automatic installation plan approval
- Makes the operator available cluster-wide

**Monitoring Installation**:
After running the command, you can monitor the installation progress with:
```bash
# Check subscription status
oc get subscription vault-secrets-operator -n openshift-operators

# Check ClusterServiceVersion (CSV) status
oc get csv -n openshift-operators | grep vault-secrets

# Check operator pods
oc get pods -n openshift-operators | grep vault-secrets
```

**What Gets Installed**:
- **Operator**: Vault Secrets Operator (from certified-operators)
- **Channel**: stable
- **Install Mode**: Automatic
- **Scope**: Cluster-wide (openshift-operators namespace)

The Vault Secrets Operator enables Kubernetes to sync secrets from HashiCorp Vault, providing:
- Dynamic secret management
- Automatic secret rotation
- Centralized secret storage
- Integration with Vault authentication methods (AppRole, Kubernetes, etc.)

#### 2. setup_vault

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
make setup_vault NAMESPACE=rhoso1 APPROLE_ROLE_ID=my-role APPROLE_SECRET_ID=my-secret
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

#### 3. clean_gitops_examples

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

The kustomization configuration is defined in `vault-configs/vault-approle-kustomization.yaml.template` with placeholders that are replaced at runtime:
- `NAMESPACE_PLACEHOLDER` - Replaced with the target namespace
- `APPROLE_SECRET_ID_BASE64_PLACEHOLDER` - Replaced with the base64-encoded Secret ID
- `APPROLE_ROLE_ID_PLACEHOLDER` - Replaced with the AppRole Role ID

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
