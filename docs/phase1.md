# Phase 1

Phase 1 in the proposal was the shift from ad hoc manifests to a GitOps-friendly deployment entry point.

This repo now has that layout:

- Helm chart: [`deploy/helm/fossology`](/home/mandar12/Desktop/gsoc/fossology-k8s-poc/deploy/helm/fossology)
- ArgoCD project: [`deploy/argocd/project.yaml`](/home/mandar12/Desktop/gsoc/fossology-k8s-poc/deploy/argocd/project.yaml)
- ArgoCD application: [`deploy/argocd/fossology-application.yaml`](/home/mandar12/Desktop/gsoc/fossology-k8s-poc/deploy/argocd/fossology-application.yaml)

## What Phase 1 Covers

- Helm-packaged deployment for web, scheduler, PostgreSQL, and worker StatefulSet
- Headless worker service and shared repository PVC
- Dynamic `fossology.conf` rendering and config-sync sidecar carried into the chart
- Helm hook job for `fo-postinstall`
- Environment-specific values for local, staging, and production-like deployments
- ArgoCD manifests that point at the Helm chart as the sync source

## Local Use

Deploy on kind:

```bash
make up-phase1
make up-phase1-branch FOSSOLOGY_REPO_DIR=../fossology-gsoc/fossology
make test
```

Render without applying:

```bash
make render-phase1
```

Lint the chart:

```bash
make lint-phase1
```

## ArgoCD Use

1. Apply [`project.yaml`](/home/mandar12/Desktop/gsoc/fossology-k8s-poc/deploy/argocd/project.yaml) in the `argocd` namespace.
2. Apply [`fossology-application.yaml`](/home/mandar12/Desktop/gsoc/fossology-k8s-poc/deploy/argocd/fossology-application.yaml).
3. If you want staging or production-like values, edit the `valueFiles` list in the Application manifest.

## Notes

- The current chart assumes the SSH key secrets are created first by [`scripts/generate-ssh-keys.sh`](/home/mandar12/Desktop/gsoc/fossology-k8s-poc/scripts/generate-ssh-keys.sh).
- The local `values.yaml` keeps the kind-friendly `NodePort` service, `IfNotPresent` web image pull policy, and `Never` worker image pull policy.
- If `helm` is not installed locally, [`scripts/run-helm.sh`](/home/mandar12/Desktop/gsoc/fossology-k8s-poc/scripts/run-helm.sh) falls back to `alpine/helm:3.17.3` through Docker.
- The repo still keeps the older raw-manifest PoC flow because it is useful for low-level debugging.
