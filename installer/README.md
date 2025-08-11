# CloudKit Installer

This repository contains Kubernetes/OpenShift deployment configurations for the CloudKit platform, providing comprehensive cluster lifecycle management through multiple integrated components.

## Overview

CloudKit is a comprehensive platform that provides:

- **Cluster Lifecycle Management** - Automated cluster provisioning, scaling, and decommissioning
- **Event Driven Automation** - Responds to cluster events and webhook notifications
- **Service Management** - Fulfillment services for cluster operations
- **Configuration as Code** - Manages cluster configurations through Ansible playbooks and Kubernetes manifests

## Architecture

The CloudKit platform consists of three main components:

1. **CloudKit AAP (Ansible Automation Platform)** - Automated cluster provisioning and lifecycle management
2. **CloudKit Operator** - Kubernetes operator for cluster order management and HyperShift integration
3. **Fulfillment Service** - Backend service for cluster fulfillment operations with PostgreSQL database

## Prerequisites

Before deploying CloudKit, ensure you have:

### Core Requirements
- OpenShift cluster with admin access (version 4.17+ recommended)
- `oc` CLI configured with cluster admin privileges
- `kustomize` CLI tool (or use `oc apply -k`)

### Certificate Management
- **cert-manager** operator installed and configured
- Certificate issuers configured for TLS certificate management
- Required for secure communication between components

### HyperShift Integration
- **MultiCluster Engine (MCE)** installed with HyperShift support
- HyperShift operator deployed and configured
- Required for hosted cluster management capabilities

### Component-Specific Prerequisites

#### CloudKit AAP
- **Red Hat Ansible Automation Platform Operator** installed
- **Red Hat Advanced Cluster Management (ACM)** installed (for cluster provisioning)
- **Valid AAP license manifest** - Download from [Red Hat Customer Portal](https://access.redhat.com/downloads/content/480/ver=2.4/rhel---9/2.4/x86_64/product-software) as `License.zip`
- Container registry credentials for execution environments

#### CloudKit Operator
- **HyperShift CRDs** (`HostedCluster`, `NodePool`) available
- **ClusterOrder CRDs** deployed
- Proper RBAC permissions for cluster-wide operations

#### Fulfillment Service
- **PostgreSQL** for database storage
- **TLS certificates** for secure database connections
- **Private registry access** for container images

## Repository Structure

```
cloudkit-installer/
├── base/                           # Base Kustomize configurations
│   ├── shared/                     # Shared namespace and resources
│   ├── cloudkit-aap/              # Ansible Automation Platform
│   ├── cloudkit-operator/         # CloudKit Operator
│   └── fulfillment-service/       # Fulfillment Service
│       ├── ca/                    # Certificate Authority setup
│       ├── database/              # PostgreSQL database
│       ├── service/               # Main service deployment
│       ├── controller/            # Controller component
│       ├── admin/                 # Admin service account
│       └── client/                # Client service account
├── overlays/                      # Environment-specific overlays
│   └── development/               # Development environment
│       ├── cloudkit-aap/
│       ├── cloudkit-operator/
│       └── fulfillment-service/
└── README.md
```

## Components

### 1. CloudKit AAP (Ansible Automation Platform)

Provides automated cluster provisioning and lifecycle management through:
- **Controller**: Job template management and execution
- **EDA (Event Driven Automation)**: Webhook processing and event handling
- **Bootstrap Job**: Initial configuration of AAP resources

### 2. CloudKit Operator

Kubernetes operator that manages:
- **ClusterOrder CRDs**: Custom resources for cluster provisioning requests
- **HyperShift Integration**: Management of hosted clusters
- **Namespace Management**: Automatic namespace creation and RBAC
- **Service Account Management**: Cluster-specific service accounts

### 3. Fulfillment Service

Backend service providing:
- **Database**: PostgreSQL for persistent storage
- **Service**: Main fulfillment service with gRPC API
- **Controller**: Fulfillment operation management
- **Gateway**: HTTP/gRPC gateway with Envoy proxy

## Installation

### Step 1: Install Prerequisites

#### Install cert-manager
```bash
# Install cert-manager operator
oc apply -f https://github.com/cert-manager/cert-manager/releases/download/v1.13.0/cert-manager.yaml

# Wait for cert-manager to be ready
oc wait --for=condition=Available deployment/cert-manager -n cert-manager --timeout=300s
```

#### Install MultiCluster Engine with HyperShift
```bash
# Create MCE namespace
oc new-project multicluster-engine

# Install MCE operator
cat << EOF | oc apply -f -
apiVersion: operators.coreos.com/v1
kind: OperatorGroup
metadata:
  name: multicluster-engine
  namespace: multicluster-engine
spec:
  targetNamespaces:
  - multicluster-engine
---
apiVersion: operators.coreos.com/v1alpha1
kind: Subscription
metadata:
  name: multicluster-engine
  namespace: multicluster-engine
spec:
  channel: stable-2.8
  name: multicluster-engine
  source: redhat-operators
  sourceNamespace: openshift-marketplace
EOF

# Create MCE instance
cat << EOF | oc apply -f -
apiVersion: multicluster.openshift.io/v1
kind: MultiClusterEngine
metadata:
  name: multiclusterengine
  namespace: multicluster-engine
spec:
  availabilityConfig: Basic
  targetNamespace: multicluster-engine
EOF

# Wait for MCE to be ready
oc wait --for=condition=Available multiclusterengine/multiclusterengine -n multicluster-engine --timeout=600s
```

### Step 2: Deploy CloudKit Components

#### Development Environment
```bash
# Set required environment variables
export AAP_USERNAME="admin"
export AAP_PASSWORD="your-aap-password"
export LICENSE_MANIFEST_PATH="/path/to/license.zip"

# Deploy all components
oc apply -k overlays/development/

# Wait for deployment to complete
oc wait --for=condition=Available deployment/dev-fulfillment-service -n foobar --timeout=300s
oc wait --for=condition=Available deployment/dev-controller-manager -n foobar --timeout=300s
```

## Configuration

### Environment Variables

For AAP configuration, set these environment variables:

```bash
export AAP_USERNAME="admin"              # AAP administrator username
export AAP_PASSWORD="your-password"      # AAP administrator password
export LICENSE_MANIFEST_PATH="/path/to/license.zip"  # Path to AAP license
```

**Note**: The AAP license file must be named exactly `License.zip` (with capital L) and can be downloaded from the [Red Hat Customer Portal](https://access.redhat.com/downloads/content/480/ver=2.4/rhel---9/2.4/x86_64/product-software). Navigate to your AAP subscription and download the license manifest.

### Registry Credentials

Update container registry credentials in:
- `overlays/development/dockerconfig.json` for development
- Include credentials for accessing private registries (quay.io, registry.redhat.io, etc.)

### TLS Certificates

The fulfillment service uses cert-manager for TLS certificate management:
- CA certificates are automatically generated
- Service certificates are issued for database connections
- API certificates are issued for service endpoints

## Verification

### Check Deployment Status

```bash
# Check all pods in the deployment namespace
oc get pods -n foobar

# Check specific components
oc get pods -n foobar -l app=fulfillment-service
oc get pods -n foobar -l app.kubernetes.io/name=cloudkit-operator
oc get ansibleautomationplatform -n foobar

# Check certificates
oc get certificates -n foobar
```

### Check Component Health

```bash
# CloudKit Operator
oc logs -n foobar deployment/dev-controller-manager -f

# Fulfillment Service
oc logs -n foobar deployment/dev-fulfillment-service -c server -f

# Database
oc logs -n foobar statefulset/dev-fulfillment-database -f

# AAP Bootstrap Job
oc logs -n foobar job/dev-aap-bootstrap -f
```

### Verify Prerequisites

```bash
# Check cert-manager
oc get pods -n cert-manager

# Check HyperShift CRDs
oc get crd | grep hypershift
oc get crd | grep clusterorder

# Check MultiCluster Engine
oc get multiclusterengine -n multicluster-engine
```

## Customization

### Adding New Environments

To create a new environment overlay:

1. Create new directory under `overlays/`
2. Copy and modify kustomization.yaml from development
3. Create environment-specific patch files
4. Update environment variables and secrets

### Modifying Components

Each component can be customized by:

1. Editing base configurations in `base/component-name/`
2. Creating overlay patches for environment-specific changes
3. Testing changes in development overlay first
4. Validating with `kustomize build` before applying

## Security Considerations

### Certificate Management
- All inter-service communication uses TLS
- Certificates are managed by cert-manager
- CA certificates are automatically rotated

### RBAC
- Each component has minimal required permissions
- Service accounts are created per component
- Cluster-wide permissions are limited to necessary operations

### Network Security
- Services communicate over TLS
- Database connections use SSL/TLS
- Network policies can be applied for additional isolation

## Troubleshooting

### Common Issues

1. **cert-manager not ready**: Ensure cert-manager operator is installed and running
2. **HyperShift CRDs missing**: Verify MultiCluster Engine is deployed with HyperShift enabled
3. **Certificate issues**: Check cert-manager logs and certificate status
4. **Database connection failures**: Verify database certificates and connectivity
5. **cloudkit-operator CrashLoopBackOff**: Usually indicates missing HyperShift permissions or CRDs not available
6. **ImagePullBackOff errors**: Verify registry credentials in `dockerconfig.json` and `dev-quay-pull-secret`
7. **namePrefix conflicts**: Certificate and secret name mismatches due to kustomize namePrefix application

### Debug Commands

```bash
# Check certificate status
oc describe certificate -n foobar

# Check certificate issuer status
oc describe issuer -n foobar

# Check pod events
oc describe pod -n foobar <pod-name>

# Check service endpoints
oc get endpoints -n foobar

# Check secrets
oc get secrets -n foobar

# Check HyperShift CRDs and permissions
oc get crd | grep hypershift
oc get clusterrole dev-manager-role -o yaml | grep -A 10 hypershift
oc get clusterrolebinding dev-manager-rolebinding -o yaml

# Check MultiCluster Engine status
oc get multiclusterengine -n multicluster-engine
oc get pods -n multicluster-engine
oc get pods -n hypershift
```

### Log Analysis

```bash
# Get all events in namespace
oc get events -n foobar --sort-by=.metadata.creationTimestamp

# Check resource usage
oc top pods -n foobar

# Component-specific logs
oc logs -n foobar deployment/dev-fulfillment-service -c server --tail=100
oc logs -n foobar deployment/dev-controller-manager --tail=100
oc logs -n foobar statefulset/dev-fulfillment-database --tail=100
```

## Development

### Prerequisites for Development

- Understanding of Kubernetes/OpenShift
- Familiarity with Kustomize
- Knowledge of cert-manager and HyperShift
- Experience with PostgreSQL and gRPC services

### Testing Changes

1. Test in development environment first
2. Validate with `kustomize build overlays/development/`
3. Check for resource conflicts
4. Verify certificate generation
5. Test service connectivity

## Support

For issues and questions:
- Check the troubleshooting section above
- Review component logs for error messages
- Verify prerequisites are properly installed
- Consult cert-manager and HyperShift documentation
- Open an issue in the component repository

## License

This project is licensed under the Apache License, Version 2.0.
