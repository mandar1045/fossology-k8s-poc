# FOSSology Kubernetes PoC — Scalable Agent Architecture

> **GSoC 2026 Proof of Concept**  
> Kubernetes-Native Deployment with Scalable Agent Architecture for [FOSSology](https://www.fossology.org/)

This proof of concept demonstrates that FOSSology's existing scheduler can dispatch license-scanning agents to remote Kubernetes pods over SSH — no ETCD, no `kubectl exec`, no core rewrites. It works *with* FOSSology's architecture instead of against it.

## Why This Approach

Two previous GSoC attempts ([2021](https://github.com/fossology/fossology/pull/2086), [2025](https://github.com/fossology/fossology/wiki/GSoC-2025-Microservices-Infrastructure)) tried to replace FOSSology's internals: swapping SSH for `kubectl exec`, replacing `fossology.conf` with ETCD, and building per-agent Docker images. Both were invasive, fragile, and never merged.

This PoC takes a different path. FOSSology's scheduler already knows how to dispatch agents to remote hosts via SSH. In Kubernetes, that translates directly to worker pods in a StatefulSet with predictable DNS names. The only thing needed is a bridge between Kubernetes pod lifecycle and the scheduler's static `[HOSTS]` config — which is exactly what this repo builds.

**What stayed the same:**
- SSH-based agent dispatch (the scheduler's native mechanism)
- `fossology.conf` for configuration (no new infrastructure dependencies)
- Single unified Docker image for all agents (no per-agent images)

**What's new:**
- A config-sync sidecar that watches the Kubernetes API for ready worker pods and dynamically rewrites `[HOSTS]`, then signals `fo_scheduler` to reload
- An agent wrapper shim that fixes a real `fo_scheduler` bug where remote agents receive duplicate `--scheduler_start` flags
- A Helm chart, ArgoCD manifests, and multi-environment values for GitOps-ready deployment

## Architecture

```
┌──────────────────────────────────────────────────────────┐
│                     kind cluster                         │
│                                                          │
│  ┌─────────────────────────────────────────────┐         │
│  │            fossology-web (Deployment)        │         │
│  │                                              │         │
│  │  ┌──────────────┐  ┌──────────────────────┐ │         │
│  │  │ fo_scheduler │  │ config-sync sidecar  │ │         │
│  │  │              │  │                      │ │         │
│  │  │  dispatches  │  │  watches K8s API for │ │         │
│  │  │  agents via  │  │  ready workers, then │ │         │
│  │  │  SSH ──────────────► updates [HOSTS]   │ │         │
│  │  │              │  │  and sends SIGHUP    │ │         │
│  │  └──────┬───────┘  └──────────────────────┘ │         │
│  └─────────│───────────────────────────────────┘         │
│            │ SSH (port 22)                                │
│            ▼                                             │
│  ┌─────────────────────────────────────────────┐         │
│  │        fossology-workers (StatefulSet)       │         │
│  │                                              │         │
│  │  ┌──────────────────┐ ┌──────────────────┐  │         │
│  │  │   workers-0      │ │   workers-1      │  │         │
│  │  │  sshd + agents   │ │  sshd + agents   │  │         │
│  │  │  nomos, ojo,     │ │  nomos, ojo,     │  │         │
│  │  │  copyright, etc  │ │  copyright, etc  │  │         │
│  │  └──────────────────┘ └──────────────────┘  │         │
│  └─────────────────────────────────────────────┘         │
│                                                          │
│  ┌─────────────────────────────────────────────┐         │
│  │        fossology-db (StatefulSet)            │         │
│  │        PostgreSQL 16 with PVC                │         │
│  └─────────────────────────────────────────────┘         │
│                                                          │
│  ┌─────────────────────────────────────────────┐         │
│  │     Shared PVC: /srv/fossology/repository    │         │
│  └─────────────────────────────────────────────┘         │
└──────────────────────────────────────────────────────────┘
```

**Component breakdown:**

| Component | Kind | Image | Role |
|-----------|------|-------|------|
| `fossology-web` | Deployment | `fossology/fossology:4.4.0` | Apache + PHP + REST API + `fo_scheduler` + config-sync sidecar |
| `fossology-workers` | StatefulSet (2 replicas) | `fossology-worker:poc` | SSH server + all agent binaries (nomos, ojo, copyright, ecc, monk, keyword, ipra) |
| `fossology-db` | StatefulSet | `postgres:16` | PostgreSQL database with persistent storage |

## What This PoC Proves

This isn't just a "FOSSology runs on Kubernetes" demo. The smoke test validates the full dispatch pipeline end-to-end:

1. **Scheduler sees multiple workers** — dynamic `[HOSTS]` is rendered from live pod state, not hardcoded
2. **SSH dispatch works over the pod network** — `fo_scheduler` SSHes into each worker pod as `fossy` and launches agents
3. **Jobs actually run on remote workers** — concurrent `nomos` scans leave execution traces on at least 2 different worker pods
4. **Agent wrapper shim solves a real bug** — several agents (`ecc`, `copyright`, `ojo`, `keyword`, `ipra`) reject duplicate `--scheduler_start` flags sent during remote startup validation. The wrapper deduplicates gracefully while preserving the original process name for `VERSION` lookup

## Quick Start

### Prerequisites

- Docker 20.10+
- [kind](https://kind.sigs.k8s.io/) 0.20+
- kubectl 1.27+
- Helm 3.14+ (optional, for Phase 1 chart path)
- `curl`, `jq`, `ssh-keygen`

### Deploy and verify

```bash
git clone https://github.com/mandar1045/fossology-k8s-poc.git
cd fossology-k8s-poc

# Deploys everything on a local kind cluster
make up

# Runs the full end-to-end smoke test
make test
```

Open the FOSSology UI at **http://localhost:30080/repo** (credentials: `fossy` / `fossy`).

Tear everything down:

```bash
make down
```

### What `make up` does

1. Builds the worker Docker image from `manifests/images/worker/Dockerfile`
2. Creates a `kind` cluster with the config in `manifests/kind/kind-config.yaml`
3. Loads the worker image into the cluster
4. Generates SSH key pairs and creates Kubernetes secrets
5. Renders a dynamic `fossology.conf` from the template using live pod state
6. Deploys PostgreSQL, the web/scheduler pod, and 2 worker pods
7. Waits for all pods to become ready

### What `make test` validates

The [smoke test](scripts/smoke-test.sh) is a 9-step pipeline:

1. Waits for the FOSSology web UI to become reachable
2. Authenticates via the REST API and obtains a bearer token
3. Verifies that `fossology.conf` contains dynamic `[HOSTS]` entries for all ready workers
4. Checks scheduler startup logs for agent validation errors
5. SSH-tests every worker pod from the scheduler container
6. Uploads 4 test archives via the REST API
7. Waits for unpacking to complete
8. Queues concurrent `nomos` scans across all uploads
9. Waits for scan completion and verifies `nomos` execution traces appear on **at least 2 worker pods**

## Deployment Paths

### Raw manifests (debugging-friendly)

```bash
make up      # deploy everything
make test    # run smoke test
make down    # tear down
```

### Helm chart (Phase 1 — production path)

```bash
make up-phase1       # deploy via Helm
make test            # same smoke test
make render-phase1   # dry-run template rendering
make lint-phase1     # lint the chart
```

The Helm chart lives at [`deploy/helm/fossology/`](deploy/helm/fossology/) and includes:

- All templates: web deployment, worker StatefulSet, PostgreSQL StatefulSet, headless services, PVCs, RBAC, Ingress, ConfigMaps
- `fo-postinstall` as a Helm lifecycle hook
- Environment-specific values: [`values.yaml`](deploy/helm/fossology/values.yaml) (local), [`values-staging.yaml`](deploy/helm/fossology/values-staging.yaml), [`values-production.yaml`](deploy/helm/fossology/values-production.yaml)

### ArgoCD (GitOps)

ArgoCD manifests are in [`deploy/argocd/`](deploy/argocd/):

```bash
kubectl apply -f deploy/argocd/project.yaml
kubectl apply -f deploy/argocd/fossology-application.yaml
```

The Application points at the Helm chart as the sync source. Swap `valueFiles` in the Application manifest for staging or production environments.

## Key Implementation Details

### Dynamic `[HOSTS]` registration

The scheduler needs `fossology.conf` to list every worker host. In Kubernetes, pods come and go. This is bridged by:

- **At startup**: An init container (`render-fossology-conf`) polls the Kubernetes API for ready workers pods and renders `fossology.conf` from a [template](manifests/templates/fossology.conf.tmpl), blocking until the minimum worker count is met
- **At runtime**: A `config-sync` sidecar continuously watches for changes in the ready worker set. When a worker is added or removed, it rewrites `fossology.conf` and sends `SIGHUP` to `fo_scheduler`

The renderer is [`scripts/render_fossology_conf.py`](scripts/render_fossology_conf.py) — it talks to the Kubernetes API using the pod's service account token, lists pods matching the `app=fossology-worker` label, and generates `[HOSTS]` entries with stable FQDN names from the headless service.

### Agent wrapper shim

This was the hardest debugging problem in the PoC. When `fo_scheduler` validates remote agents at startup, some agents receive duplicate `--scheduler_start` flags. Agents like `ecc`, `copyright`, `ojo`, `keyword`, and `ipra` reject duplicates and fail validation, causing the scheduler to blacklist them on those workers.

The fix is a [thin wrapper](manifests/images/worker/agent-wrapper.sh) installed during the Docker build:
- Deduplicates `--scheduler_start` if it appears twice
- Preserves the original process name via `exec -a` (critical — without this, agents look for `mods-enabled/<agent>.real/VERSION` and fail)
- Logs every agent invocation to `/tmp/worker-agent-wrapper.log` for observability

### Worker image

A single [Dockerfile](manifests/images/worker/Dockerfile) extends `fossology/fossology:4.4.0` with:
- `openssh-server` configured for key-based auth
- `MaxStartups 100:30:200` to handle concurrent agent validation at scheduler boot
- Agent wrappers installed for all supported agents
- An [entrypoint](manifests/images/worker/entrypoint.sh) that sets up SSH keys and starts `sshd`

No per-agent images. No custom build system. Just the upstream FOSSology image plus SSH.

## Useful Commands

| Command | Description |
|---------|-------------|
| `make up` | Build worker image, create kind cluster, deploy everything |
| `make up-phase1` | Same as above but deploys via the Helm chart |
| `make test` | Run the full end-to-end smoke test |
| `make down` | Delete the kind cluster |
| `make status` | Show pod status |
| `make check-conf` | Print the `[HOSTS]` section from `fossology.conf` |
| `make test-ssh` | Test SSH from scheduler to a worker pod |
| `make test-dns` | Verify worker DNS resolution from the web pod |
| `make logs-scheduler` | Stream scheduler logs |
| `make logs-config-sync` | Stream config-sync sidecar logs |
| `make logs-workers` | Stream all worker pod logs |
| `make logs-db` | Stream database logs |
| `make proof` | Capture a support/proof log bundle |
| `make render-phase1` | Dry-run Helm template rendering |
| `make lint-phase1` | Lint the Helm chart |

## Repository Layout

```
.
├── Makefile                         # All commands in one place
├── README.md
├── deploy/
│   ├── argocd/
│   │   ├── fossology-application.yaml
│   │   └── project.yaml
│   └── helm/fossology/
│       ├── Chart.yaml
│       ├── values.yaml              # local/kind defaults
│       ├── values-staging.yaml
│       ├── values-production.yaml
│       ├── files/
│       └── templates/               # 15 Helm templates
├── docs/
│   ├── architecture.md              # Component-level architecture notes
│   ├── phase1.md                    # Helm and ArgoCD deployment guide
│   └── troubleshooting.md           # Common issues and debugging steps
├── manifests/
│   ├── images/worker/
│   │   ├── Dockerfile               # Worker image (fossology + SSH)
│   │   ├── agent-wrapper.sh         # Duplicate --scheduler_start fix
│   │   └── entrypoint.sh            # Worker boot: SSH keys + sshd
│   ├── kind/kind-config.yaml
│   ├── templates/fossology.conf.tmpl
│   ├── deployment-web.yaml          # Web + scheduler + config-sync
│   ├── statefulset-workers.yaml     # Worker pods
│   ├── statefulset-postgres.yaml    # Database
│   ├── service-*.yaml, pvc-*.yaml   # Networking and storage
│   └── role-config-sync.yaml        # RBAC for the sidecar
├── scripts/
│   ├── setup.sh                     # Cluster creation and deployment
│   ├── teardown.sh                  # Cluster deletion
│   ├── smoke-test.sh                # 9-step end-to-end validation
│   ├── render_fossology_conf.py     # Dynamic [HOSTS] renderer
│   ├── generate-ssh-keys.sh         # SSH keypair generation
│   ├── wait-for-ready.sh            # Pod readiness waiter
│   ├── capture-proof.sh             # Log bundle capture
│   └── run-helm.sh                  # Helm wrapper (Docker fallback)
└── test-data/                       # Sample archives for smoke test
```

## Documentation

- [Architecture](docs/architecture.md) — component layout, dynamic host registration, agent wrapper, observability model
- [Phase 1 Guide](docs/phase1.md) — Helm chart and ArgoCD deployment instructions
- [Troubleshooting](docs/troubleshooting.md) — common issues and debugging steps

## Author

**Mandar Joshi** ([@mandar1045](https://github.com/mandar1045))  
GSoC 2026 applicant for FOSSology — Kubernetes-Native Deployment with Scalable Agent Architecture
