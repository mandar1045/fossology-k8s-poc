# FOSSology Helm Chart

This chart packages the original Phase 1 PoC layout used by the repo-level `make` targets.

## What It Deploys

- A combined web Deployment that runs Apache, PHP, REST, and `fo_scheduler`
- A `config-sync` sidecar that keeps `fossology.conf` aligned with the ready worker set
- A worker StatefulSet that exposes SSH for remote agent execution
- A PostgreSQL StatefulSet when `database.internal.enabled=true`

## Runtime Config Flow

The chart mounts a small set of helper scripts from the runtime ConfigMap:

1. `wait-for-db.sh` blocks until PostgreSQL is reachable.
2. `init-config-runtime.sh` copies image defaults into a writable `emptyDir`.
3. `run-render-fossology-conf.sh` renders `fossology.conf` from the current ready workers.
4. `start-web.sh` configures SSH for the scheduler path, prints the active `[HOSTS]` block, and starts the main entrypoint.
5. The `config-sync` sidecar keeps the config current during worker changes.

## Important Values

| Key | Purpose |
| --- | --- |
| `workers.replicas` | Number of SSH-reachable worker pods |
| `workers.maxAgentsPerWorker` | Advertised scheduler capacity for each worker |
| `workers.minReadyStartup` | Minimum ready workers required before the first config render succeeds |
| `workers.minReadySync` | Minimum ready workers preserved during steady-state config refresh |
| `web.startupProbe` | Startup window for the combined web/scheduler container before liveness checks apply |
| `runtimeConfig.startupPollIntervalSeconds` | Fast poll loop used only during pod startup |
| `runtimeConfig.pollIntervalSeconds` | Steady-state config reconciliation interval |
| `ssh.privateSecretName` | Secret containing the scheduler private key |
| `ssh.publicSecretName` | Secret mounted into workers as `authorized_keys` |
