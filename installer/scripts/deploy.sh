#!/bin/bash

# OSC Config Deploy Script
# Deploys OSC platform to Kubernetes/OpenShift

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OSC_CONFIG_ROOT="$(dirname "$SCRIPT_DIR")"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Deploy configuration
KUBECTL_CMD=${KUBECTL_CMD:-kubectl}
KUBECTL_ADMIN_CMD="$KUBECTL_CMD --as system:admin"
ENVIRONMENT=${ENVIRONMENT:-development}
NAMESPACE=${NAMESPACE:-}
APPLY_AAP_INSTALLATION=${APPLY_AAP_INSTALLATION:-true}

log() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')] $1${NC}"
}

error() {
    echo -e "${RED}[ERROR] $1${NC}"
    exit 1
}

success() {
    echo -e "${GREEN}[SUCCESS] $1${NC}"
}

warn() {
    echo -e "${YELLOW}[WARNING] $1${NC}"
}

# Check if kubectl/oc is available and connected
check_kubectl() {
    log "Checking Kubernetes connection..."

    if ! command -v "$KUBECTL_CMD" >/dev/null 2>&1; then
        error "$KUBECTL_CMD not found. Please install kubectl or oc CLI"
    fi

    if ! $KUBECTL_ADMIN_CMD cluster-info >/dev/null 2>&1; then
        error "Cannot connect to Kubernetes cluster. Please check your kubeconfig"
    fi

    success "Kubernetes connection verified"
}

# Deploy a specific component
deploy_component() {
    local component=$1
    local overlay_path="$OSC_CONFIG_ROOT/overlays/$ENVIRONMENT/$component"

    if [ ! -d "$overlay_path" ]; then
        error "Component '$component' not found in environment '$ENVIRONMENT'"
    fi

    log "Deploying $component..."

    if [ -n "$NAMESPACE" ]; then
        # Create temporary kustomization that overrides namespace
        local temp_kustomization=$(mktemp -d)
        local relative_path=$(realpath --relative-to="$temp_kustomization" "$overlay_path")
        cat > "$temp_kustomization/kustomization.yaml" << EOF
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization

resources:
- $relative_path

namespace: $NAMESPACE
EOF

        if ! $KUBECTL_ADMIN_CMD apply -k "$temp_kustomization"; then
            rm -rf "$temp_kustomization"
            error "Failed to deploy $component"
        fi

        rm -rf "$temp_kustomization"
    else
        # Use default kustomization namespace
        if ! $KUBECTL_ADMIN_CMD apply -k "$overlay_path"; then
            error "Failed to deploy $component"
        fi
    fi

    success "$component deployed successfully"
}

# Wait for deployment to be ready
wait_for_deployment() {
    local namespace=$1
    local deployment=$2
    local timeout=${3:-300}

    log "Waiting for deployment $deployment in namespace $namespace..."

    if ! $KUBECTL_ADMIN_CMD wait --for=condition=available deployment/"$deployment" -n "$namespace" --timeout="${timeout}s"; then
        warn "Deployment $deployment may not be fully ready"
    else
        success "Deployment $deployment is ready"
    fi
}

# Check deployment status
check_status() {
    log "Checking deployment status..."

    if [ -n "$NAMESPACE" ]; then
        local namespaces=("$NAMESPACE")
    else
        case "$ENVIRONMENT" in
            "development")
                local namespaces=("foobar")
                ;;
            "production")
                local namespaces=("cloudkit-operator-system" "fulfillment-service-system" "cloudkit-aap-system")
                ;;
            *)
                error "Unknown environment: $ENVIRONMENT"
                ;;
        esac
    fi

    for ns in "${namespaces[@]}"; do
        if $KUBECTL_ADMIN_CMD get namespace "$ns" >/dev/null 2>&1; then
            log "Status for namespace: $ns"
            $KUBECTL_ADMIN_CMD get pods -n "$ns"
            echo
        fi
    done
}

# Apply AAP installation if requested
apply_aap_installation() {
    if [ "$APPLY_AAP_INSTALLATION" = "true" ]; then
        local aap_file="$OSC_CONFIG_ROOT/aap-installation.yaml"

        if [ -f "$aap_file" ]; then
            log "Applying AAP installation configuration..."

            if [ -n "$NAMESPACE" ]; then
                # Replace namespace in AAP installation and apply
                sed "s/namespace: foobar/namespace: $NAMESPACE/g" "$aap_file" | $KUBECTL_ADMIN_CMD apply -f -
                if [ ${PIPESTATUS[1]} -ne 0 ]; then
                    error "Failed to apply AAP installation configuration"
                fi
            else
                if ! $KUBECTL_ADMIN_CMD apply -f "$aap_file"; then
                    error "Failed to apply AAP installation configuration"
                fi
            fi

            success "AAP installation configuration applied successfully"
        else
            warn "AAP installation file not found at $aap_file"
        fi
    else
        log "Skipping AAP installation configuration (APPLY_AAP_INSTALLATION=false)"
    fi
}

# Deploy all components
deploy_all() {
    log "Starting OSC Config deployment..."
    log "Environment: $ENVIRONMENT"
    log "Kubectl command: $KUBECTL_CMD"
    if [ -n "$NAMESPACE" ]; then
        log "Target namespace: $NAMESPACE"
    fi
    log "Apply AAP installation: $APPLY_AAP_INSTALLATION"

    check_kubectl

    # Deploy the entire environment
    local overlay_path="$OSC_CONFIG_ROOT/overlays/$ENVIRONMENT"

    if [ ! -d "$overlay_path" ]; then
        error "Environment '$ENVIRONMENT' not found"
    fi

    log "Deploying all components for $ENVIRONMENT environment..."

    if [ -n "$NAMESPACE" ]; then
        # Create temporary kustomization that overrides namespace
        local temp_kustomization=$(mktemp -d)
        local relative_path=$(realpath --relative-to="$temp_kustomization" "$overlay_path")

        # Create base kustomization with namespace override
        cat > "$temp_kustomization/kustomization.yaml" << EOF
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization

resources:
- $relative_path

namespace: $NAMESPACE
EOF

        # If this is the development environment, add AAP URL patches for custom namespace
        if [ "$ENVIRONMENT" = "development" ]; then
            cat >> "$temp_kustomization/kustomization.yaml" << EOF

patches:
- patch: |-
    - op: replace
      path: /spec/template/spec/initContainers/0/env/0/value
      value: dev-cloudkit-$NAMESPACE.apps.acm.local.lab
    - op: replace
      path: /spec/template/spec/initContainers/0/env/1/value
      value: dev-cloudkit-eda-$NAMESPACE.apps.acm.local.lab
    - op: replace
      path: /spec/template/spec/initContainers/0/env/4/value
      value: dev-cloudkit-controller-$NAMESPACE.apps.acm.local.lab
  target:
    kind: Job
    name: dev-aap-bootstrap
- patch: |-
    - op: replace
      path: /stringData
      value:
        AAP_HOSTNAME: https://dev-cloudkit-$NAMESPACE.apps.acm.local.lab
        AAP_VALIDATE_CERTS: "false"
        AAP_ORGANIZATION_NAME: dev
        AAP_PROJECT_NAME: bar
        AAP_PROJECT_GIT_URI: https://github.com/innabox/cloudkit-aap.git
        AAP_PROJECT_GIT_BRANCH: main
        AAP_EE_IMAGE: quay.io/rh-ee-jkary/cloudkit-aap-ee
        LICENSE_MANIFEST_PATH: /var/secrets/config-as-code-manifest/license.zip
  target:
    kind: Secret
    name: dev-bar-config-as-code-ig
- patch: |-
    - op: replace
      path: /subjects/0/namespace
      value: $NAMESPACE
  target:
    kind: ClusterRoleBinding
    name: dev-manager-rolebinding
EOF
        fi

        if ! $KUBECTL_ADMIN_CMD apply -k "$temp_kustomization"; then
            rm -rf "$temp_kustomization"
            error "Failed to deploy $ENVIRONMENT environment"
        fi

        rm -rf "$temp_kustomization"
    else
        # Use default kustomization namespace
        if ! $KUBECTL_ADMIN_CMD apply -k "$overlay_path"; then
            error "Failed to deploy $ENVIRONMENT environment"
        fi
    fi

    success "All components deployed successfully"

    # Apply AAP installation after kustomization
    apply_aap_installation

    # Wait for key deployments
    case "$ENVIRONMENT" in
        "development")
            local target_namespace=${NAMESPACE:-foobar}
            wait_for_deployment "$target_namespace" "dev-controller-manager" 180
            wait_for_deployment "$target_namespace" "dev-fulfillment-service" 180
            ;;
        "production")
            local target_namespace=${NAMESPACE:-cloudkit-operator-system}
            wait_for_deployment "$target_namespace" "controller-manager" 300
            local fulfillment_namespace=${NAMESPACE:-fulfillment-service-system}
            wait_for_deployment "$fulfillment_namespace" "fulfillment-service" 300
            ;;
    esac

    check_status
}

# Undeploy components
undeploy() {
    log "Undeploying OSC Config..."

    local overlay_path="$OSC_CONFIG_ROOT/overlays/$ENVIRONMENT"

    if [ ! -d "$overlay_path" ]; then
        error "Environment '$ENVIRONMENT' not found"
    fi

    if [ -n "$NAMESPACE" ]; then
        # Create temporary kustomization that overrides namespace
        local temp_kustomization=$(mktemp -d)
        local relative_path=$(realpath --relative-to="$temp_kustomization" "$overlay_path")
        cat > "$temp_kustomization/kustomization.yaml" << EOF
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization

resources:
- $relative_path

namespace: $NAMESPACE
EOF

        if ! $KUBECTL_ADMIN_CMD delete -k "$temp_kustomization"; then
            rm -rf "$temp_kustomization"
            warn "Some resources may not have been deleted cleanly"
        fi

        rm -rf "$temp_kustomization"
    else
        # Use default kustomization namespace
        if ! $KUBECTL_ADMIN_CMD delete -k "$overlay_path"; then
            warn "Some resources may not have been deleted cleanly"
        fi
    fi

    success "OSC Config undeployed"
}

# Show usage
show_usage() {
    cat << EOF
Usage: $0 [OPTIONS] [COMMAND] [COMPONENT]

Deploy OSC Config platform to Kubernetes/OpenShift

OPTIONS:
  --aap                Apply AAP installation configuration (default)
  --no-aap             Skip AAP installation configuration
  -n, --namespace NS   Target namespace for deployment (overrides environment default)
  -h, --help           Show this help message

COMMANDS:
  deploy               Deploy components (default)
  undeploy            Remove deployed components
  status              Show deployment status
  wait                Wait for deployments to be ready

COMPONENTS (for deploy command):
  cloudkit-operator    Deploy only CloudKit Operator
  fulfillment-service  Deploy only Fulfillment Service
  cloudkit-aap         Deploy only CloudKit AAP
  all                  Deploy all components (default)

ENVIRONMENT VARIABLES:
  ENVIRONMENT         Target environment: development, production (default: development)
  NAMESPACE           Target namespace for deployment (can also use -n flag)
  KUBECTL_CMD         Kubectl command to use (default: kubectl)
  APPLY_AAP_INSTALLATION  Apply aap-installation.yaml after kustomization (default: true)

EXAMPLES:
  $0                                    # Deploy all to development with AAP installation
  $0 --no-aap deploy                   # Deploy all without AAP installation
  $0 -n my-namespace deploy            # Deploy to specific namespace
  $0 deploy cloudkit-operator          # Deploy only operator
  $0 --aap deploy all                  # Deploy all with AAP installation (explicit)
  ENVIRONMENT=production $0             # Deploy all to production with AAP installation
  NAMESPACE=my-namespace $0             # Deploy to specific namespace (env var)
  KUBECTL_CMD=oc $0                     # Use OpenShift CLI
  APPLY_AAP_INSTALLATION=false $0       # Deploy all without AAP installation (env var)
  $0 status                            # Check deployment status
  $0 undeploy                          # Remove all deployments

EOF
}

# Parse command line arguments
COMMAND=""
COMPONENT=""

# Parse flags and arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --no-aap)
            APPLY_AAP_INSTALLATION=false
            shift
            ;;
        --aap)
            APPLY_AAP_INSTALLATION=true
            shift
            ;;
        -n|--namespace)
            if [ -z "$2" ]; then
                error "Namespace argument required for -n/--namespace option"
            fi
            NAMESPACE=$2
            shift 2
            ;;
        -h|--help|help)
            show_usage
            exit 0
            ;;
        *)
            if [ -z "$COMMAND" ]; then
                COMMAND=$1
            elif [ -z "$COMPONENT" ]; then
                COMPONENT=$1
            else
                error "Unknown argument: $1"
            fi
            shift
            ;;
    esac
done

# Set defaults if not provided
COMMAND=${COMMAND:-deploy}
COMPONENT=${COMPONENT:-all}

case "$COMMAND" in
    "deploy")
        case "$COMPONENT" in
            "cloudkit-operator"|"operator")
                deploy_component "cloudkit-operator"
                ;;
            "fulfillment-service"|"fulfillment")
                deploy_component "fulfillment-service"
                ;;
            "cloudkit-aap"|"aap")
                deploy_component "cloudkit-aap"
                ;;
            "all")
                deploy_all
                ;;
            *)
                error "Unknown component: $COMPONENT"
                ;;
        esac
        ;;
    "undeploy"|"remove"|"delete")
        undeploy
        ;;
    "status"|"check")
        check_kubectl
        check_status
        ;;
    "wait")
        check_kubectl
        case "$ENVIRONMENT" in
            "development")
                local target_namespace=${NAMESPACE:-foobar}
                wait_for_deployment "$target_namespace" "dev-controller-manager" 300
                wait_for_deployment "$target_namespace" "dev-fulfillment-service" 300
                ;;
            "production")
                local target_namespace=${NAMESPACE:-cloudkit-operator-system}
                wait_for_deployment "$target_namespace" "controller-manager" 300
                local fulfillment_namespace=${NAMESPACE:-fulfillment-service-system}
                wait_for_deployment "$fulfillment_namespace" "fulfillment-service" 300
                ;;
        esac
        ;;
    *)
        error "Unknown command: $COMMAND. Use '$0 --help' for usage information."
        ;;
esac
