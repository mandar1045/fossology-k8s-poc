# Troubleshooting

## Pods Never Become Ready

Check rollout state:

```bash
make status
kubectl -n fossology describe pod -l app=fossology-web
kubectl -n fossology describe pod -l app=fossology-worker
kubectl -n fossology describe pod -l app=fossology-db
```

Useful logs:

```bash
make logs-db
make logs-scheduler
make logs-workers
make logs-config-sync
```

## `[HOSTS]` Shows Fewer Than Two Workers

Inspect the live config:

```bash
make check-conf
kubectl -n fossology logs deployment/fossology-web -c config-sync --tail=200
```

Likely causes:

- a worker pod is not Ready yet
- the sidecar cannot list pods
- the worker label selector does not match

The sidecar uses the service account and RBAC from:

- [`manifests/serviceaccount-web.yaml`](/home/mandar12/Desktop/gsoc/fossology-k8s-poc/manifests/serviceaccount-web.yaml)
- [`manifests/role-config-sync.yaml`](/home/mandar12/Desktop/gsoc/fossology-k8s-poc/manifests/role-config-sync.yaml)

## SSH From Web To Worker Fails

Verify DNS:

```bash
make test-dns
```

Verify SSH:

```bash
make test-ssh
```

Inspect worker logs:

```bash
make logs-workers
```

Common causes:

- SSH keys were not generated or mounted correctly
- the worker pod is not ready yet
- the headless service name or namespace does not match the expected FQDN

## Agents Are Invalidated During Scheduler Startup

This repo specifically fixes a startup issue affecting:

- `ecc`
- `copyright`
- `ojo`
- `keyword`
- `ipra`

The quickest check is:

```bash
kubectl -n fossology logs deployment/fossology-web -c fossology --tail=250 | \
  grep -E 'fossology-workers-[0-9]+\.(ecc|copyright|ipra|ojo|keyword|nomos)' || true
```

If you see invalidation lines, make sure the worker image was rebuilt and loaded into kind again:

```bash
make build
kind load docker-image fossology-worker:poc --name fossology-poc
kubectl rollout restart statefulset/fossology-workers -n fossology
kubectl rollout restart deployment/fossology-web -n fossology
```

If you are proving integration against a local FOSSology branch checkout, rebuild and redeploy with:

```bash
make up-branch FOSSOLOGY_REPO_DIR=../fossology-gsoc/fossology
```

## Jobs Finish But Only One Worker Shows Activity

Run the full smoke test:

```bash
make test
```

That test uploads multiple archives and queues concurrent `nomos` jobs specifically to make worker distribution observable.

If only one worker shows `nomos` traces:

- confirm `[HOSTS]` lists both workers
- confirm both worker pods are Ready
- confirm the worker wrapper logs are visible on both pods

Inspect per-pod logs:

```bash
kubectl -n fossology logs fossology-workers-0 --tail=240
kubectl -n fossology logs fossology-workers-1 --tail=240
```

## Config Changes Are Not Picked Up

The sidecar should log a render and then reload the scheduler.

Check:

```bash
kubectl -n fossology logs deployment/fossology-web -c config-sync --tail=200
```

You should see messages indicating:

- ready workers found
- `fossology.conf` rewritten or already up to date
- scheduler reload command executed

## Need a Shareable Validation Artifact

Use:

```bash
make proof
```

That runs [`scripts/capture-proof.sh`](/home/mandar12/Desktop/gsoc/fossology-k8s-poc/scripts/capture-proof.sh) and writes a timestamped log with:

- pod and service state
- web pod process info
- live `[HOSTS]`
- DNS and SSH checks
- repository visibility
- worker and config-sync logs
