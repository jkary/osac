# OSAC Mono-Repository

This repository consolidates the OSAC (OpenShift AI-in-a-Box Cloud) components into a single mono-repo.

## Repository Structure

```
osac/
├── fulfillment/
│   ├── api/                    # gRPC/protobuf definitions
│   └── service/                # Fulfillment service (Go)
│
├── openshift/
│   └── operator/               # CloudKit Kubernetes operator (Go)
│       ├── crds/               # Custom Resource Definitions
│       └── controllers/        # Controller implementations
│
├── cloudkit-aap/               # Ansible Automation Platform playbooks
│   ├── collections/            # Ansible collections
│   ├── playbooks/              # Playbooks
│   └── execution-environment/  # Execution environment config
│
├── templates/                  # Shared cluster/VM templates
│
├── test-infra/                 # Consolidated test infrastructure
│   ├── integration/            # Integration tests
│   └── e2e/                    # End-to-end tests
│
└── go.work                     # Go workspace file
```

## Components

### Fulfillment Service

A Go-based gRPC/REST service for cloud-in-a-box fulfillment.

```bash
cd fulfillment/service
go build ./...
go test ./...
```

### CloudKit Operator

A Kubernetes operator for managing ClusterOrders using Hosted Control Planes.

```bash
cd openshift/operator
make build
make test
```

### CloudKit AAP

Ansible playbooks for CloudKit infrastructure management.

```bash
cd cloudkit-aap
uv sync
uv run ansible-lint
```

## Development

This repository uses Go workspaces for multi-module development:

```bash
# From the root directory
go work sync
go build ./...
```

## License

Apache 2.0
