# Architecture

## Overview

This PoC runs FOSSology in a split-control-plane model:

- [`manifests/deployment-web.yaml`](/home/mandar12/Desktop/gsoc/fossology-k8s-poc/manifests/deployment-web.yaml)
  hosts Apache, PHP, REST API, and `fo_scheduler`
- [`manifests/statefulset-postgres.yaml`](/home/mandar12/Desktop/gsoc/fossology-k8s-poc/manifests/statefulset-postgres.yaml)
  hosts PostgreSQL
- [`manifests/statefulset-workers.yaml`](/home/mandar12/Desktop/gsoc/fossology-k8s-poc/manifests/statefulset-workers.yaml)
  hosts the SSH-reachable agent workers

All FOSSology components share the repository PVC mounted at `/srv/fossology/repository`.

## Web Pod

The web deployment includes:

- `wait-for-db` init container
- `init-config-runtime` init container
- `render-fossology-conf` init container
- main `fossology` container
- `config-sync` sidecar

The main container mounts a writable runtime config directory at `/usr/local/etc/fossology` so the rendered `fossology.conf` can be updated without rebuilding the image.

## Worker Pods

The worker image lives in [`manifests/images/worker/Dockerfile`](/home/mandar12/Desktop/gsoc/fossology-k8s-poc/manifests/images/worker/Dockerfile).

Each worker pod:

- runs `sshd`
- mounts the shared repository PVC
- mounts `Db.conf`
- mounts the scheduler public key as `authorized_keys`

The worker entrypoint is [`manifests/images/worker/entrypoint.sh`](/home/mandar12/Desktop/gsoc/fossology-k8s-poc/manifests/images/worker/entrypoint.sh).

## Dynamic Host Registration

The dynamic host list is rendered from:

- template: [`manifests/templates/fossology.conf.tmpl`](/home/mandar12/Desktop/gsoc/fossology-k8s-poc/manifests/templates/fossology.conf.tmpl)
- renderer: [`scripts/render_fossology_conf.py`](/home/mandar12/Desktop/gsoc/fossology-k8s-poc/scripts/render_fossology_conf.py)

The renderer:

- lists ready worker pods through the Kubernetes API
- writes a fresh `[HOSTS]` block
- optionally signals `fo_scheduler` after changes

This makes the PoC much more reproducible than a static config map with a hard-coded worker list.

## Worker Compatibility Shim

The most important runtime fix in this repo is the worker wrapper:

- [`manifests/images/worker/agent-wrapper.sh`](/home/mandar12/Desktop/gsoc/fossology-k8s-poc/manifests/images/worker/agent-wrapper.sh)

It exists because several agents fail the remote scheduler startup test when invoked with duplicate `--scheduler_start` flags. The wrapper:

- deduplicates that flag
- preserves the original agent process name with `exec -a`
- logs the execution trace to `/tmp/worker-agent-wrapper.log`

Without the preserved process name, agents like `ecc` and `copyright` try to load `mods-enabled/<agent>.real/VERSION`, which fails.

## Observability

Three layers are intentionally visible:

- scheduler and bootstrap logs in the web container
- config reconciliation logs in the `config-sync` sidecar
- SSH and agent execution logs in each worker pod

This lets you trace:

1. worker discovery
2. scheduler startup
3. SSH connection establishment
4. agent process launch on a worker

## Scaling Model

The worker StatefulSet defaults to two replicas and parallel pod management.

That gives:

- stable DNS names through the headless service
- predictable worker identities
- simple horizontal scaling through StatefulSet replicas

The smoke test validates that the scheduler sees multiple workers and that concurrent `nomos` jobs leave traces on at least two worker pods.
