# Oracle Linux 9 Layered Image Factory & Monitoring Control Plane

This repo simulates how to split a big image into multiple layers and use OverlayFS to mount them on the host. It contains the decoupled image infrastructure, deployment scripts, monitoring configuration, and FastAPI control plane used to demonstrate reduced monolithic deployment overhead.

## Directory Manifest
* `prod-config.sh`: Global configurations, shared paths, and primitives.
* `01-build-prod-image.sh`: Allocates a 10GB loop volume, handles real DNF system bootstrapping.
* `02-split-prod-image.sh`: Queries the live image RPM database, runs Catch-All segmentation, outputs compressed ZSTD chunks.
* `03-deploy-and-update.sh`: Executes multi-layer kernel OverlayFS assembly and Day-2 package updates.
* `04-validate-integrity.sh`: Runs byte-level cryptographic file tree comparison audits.
* `app.py`: Background Python/FastAPI supervisor instrumented with Prometheus endpoints.

## Local Deployment Setup Instructions
Your local repository keeps scripts under `scripts/`, but the OCI instance should receive them directly under `/home/opc/ol9-prod-factory` because `app.py` calls those absolute paths.

Deploy the API service and flattened scripts to OCI:

```bash
cd /Users/mounikapasham/ol9-prod-factory
OCI_HOST=<oci-public-ip> OCI_SSH_KEY=/path/to/private-key.pem ./deploy-api-service.sh
```

If your SSH agent already has the key loaded, you can omit `OCI_SSH_KEY`. The deploy helper copies:

* `app.py` to `/home/opc/ol9-prod-factory/app.py`
* `scripts/*.sh` to `/home/opc/ol9-prod-factory/*.sh`

It also installs the Python API dependencies for the `opc` user and starts `ol9-image-factory-api.service` on port `8000`.

## Local Command Wrapper
After the FastAPI service is running on the OCI instance, run lifecycle actions from your local terminal:

```bash
cd /Users/mounikapasham/ol9-prod-factory
export OL9_FACTORY_API_URL=http://<oci-public-ip>:8000
export PATH="/Users/mounikapasham/ol9-prod-factory:$PATH"

build
split
deploy
validate
factory status
factory logs validate
```

You can also run the commands without changing `PATH`:

```bash
./factory build
./factory split
./factory deploy
./factory validate
```

Command mapping:

* `build` calls `POST /api/action/build` and runs the OCI image builder.
* `split` calls `POST /api/action/split` and creates the base/platform SquashFS layers on OCI.
* `deploy` calls `POST /api/action/deploy` and assembles the layers with OverlayFS on OCI.
* `validate` calls `POST /api/action/validate` and writes an integrity report under `/home/opc/ol9-prod-factory/reports` on OCI.
* `factory status` reads `/api/status` from the OCI API service.
* `factory metrics` reads `/metrics` for Prometheus metrics.
* `factory logs <command>` reads the latest API-captured log for a lifecycle command.
