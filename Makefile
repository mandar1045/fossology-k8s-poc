.PHONY: build up up-phase1 down clean test proof status logs-scheduler logs-config-sync logs-workers logs-db keys check-conf test-ssh test-dns render-phase1 lint-phase1

KIND_CLUSTER ?= fossology-poc
KIND_CONFIG ?= manifests/kind/kind-config.yaml
WORKER_IMAGE ?= fossology-worker:poc
NAMESPACE ?= fossology
WORKER_FQDN ?= fossology-workers-0.fossology-workers.$(NAMESPACE).svc.cluster.local
HELM_RELEASE ?= fossology
HELM_CHART ?= deploy/helm/fossology
HELM_VALUES ?= $(HELM_CHART)/values.yaml

build:
	docker build -t $(WORKER_IMAGE) -f manifests/images/worker/Dockerfile .

keys:
	bash scripts/generate-ssh-keys.sh

up: build
	bash scripts/setup.sh

up-phase1: build
	DEPLOY_MODE=helm HELM_RELEASE=$(HELM_RELEASE) HELM_CHART=$(HELM_CHART) HELM_VALUES=$(HELM_VALUES) bash scripts/setup.sh

test:
	bash scripts/smoke-test.sh

proof:
	bash scripts/capture-proof.sh

down:
	bash scripts/teardown.sh

clean: down
	rm -rf .debug
	rm -f secrets/id_ed25519 secrets/id_ed25519.pub

status:
	kubectl get pods -n $(NAMESPACE) -o wide

logs-scheduler:
	kubectl -n $(NAMESPACE) logs deployment/fossology-web -c fossology -f

logs-config-sync:
	kubectl -n $(NAMESPACE) logs deployment/fossology-web -c config-sync -f

logs-workers:
	kubectl -n $(NAMESPACE) logs -l app=fossology-worker --prefix -f --max-log-requests=10

logs-db:
	kubectl -n $(NAMESPACE) logs statefulset/fossology-db -f

test-ssh:
	kubectl -n $(NAMESPACE) exec deployment/fossology-web -c fossology -- \
		ssh -o StrictHostKeyChecking=no \
		    -o ConnectTimeout=10 \
		    -i /root/.ssh/id_ed25519 \
		    fossy@$(WORKER_FQDN) \
		    "/usr/local/etc/fossology/mods-enabled/nomos/agent/nomos --scheduler_start --userID=0 --groupID=0 --jobId=0 --config=/usr/local/etc/fossology 2>&1 | head -n 4"

test-dns:
	kubectl -n $(NAMESPACE) exec deployment/fossology-web -c fossology -- \
		getent hosts $(WORKER_FQDN)

check-conf:
	kubectl -n $(NAMESPACE) exec deployment/fossology-web -c fossology -- \
		sed -n '/^\[HOSTS\]/,/^\[REPOSITORY\]/p' /usr/local/etc/fossology/fossology.conf

render-phase1:
	bash scripts/run-helm.sh template $(HELM_RELEASE) $(HELM_CHART) -n $(NAMESPACE) -f $(HELM_VALUES)

lint-phase1:
	bash scripts/run-helm.sh lint $(HELM_CHART) -f $(HELM_VALUES)
