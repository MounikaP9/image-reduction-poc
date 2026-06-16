# Oracle Linux 9 Layered Image Factory & Monitoring Control Plane

This repo simulates how to split a big image into multiple layers and use OverlayFS to mount them on the host. It contains the decoupled image infrastructure, deployment scripts, monitoring configuration, and FastAPI control plane used to demonstrate reduced monolithic deployment overhead.

## Directory Manifest
* `prod-config.sh`: Global configurations, shared paths, and primitives.
* `01-build-prod-image.sh`: Allocates a 10GB loop volume, bootstraps OL9, captures a frozen base RPM baseline, then installs platform packages.
* `02-split-prod-image.sh`: Uses the generated RPM manifest to isolate base-owned files, writes a base file inventory, and outputs compressed ZSTD chunks.
* `03-deploy-and-update.sh`: Composes layers with OverlayFS, applies a Day-2 platform package/config delta, rejects base-owned path drift, and rebuilds only the platform layer.
* `04-validate-integrity.sh`: Runs checksum audits, verifies the base layer digest is unchanged, and excludes only recorded Day-2 platform delta paths.
* `app.py`: Background Python/FastAPI supervisor instrumented with Prometheus endpoints.

## Production-Style Demo Model

The 10GB image is a sparse ext4 disk image with 10GB of capacity, not 10GB of populated files. The split process stores real files as SquashFS layers, so unused filesystem space disappears and file contents are compressed.

The demo now treats the base layer as frozen infrastructure:

* Core OL9 packages and available kernel/base-image packages are captured as the `[base]` RPM baseline during `build`.
* Packages installed after that baseline, such as `python3`, `podman`, and `git`, become the `[platform]` package delta.
* During `deploy`, Day-2 package changes are applied to the composed OverlayFS root. Only the OverlayFS upperdir delta is copied back into the platform staging tree.
* If the Day-2 delta touches a file owned by the frozen base package inventory, the update is rejected because it requires a new base layer version.
* Validation checks that the base SquashFS digest stayed unchanged and that all non-Day-2 files still match the original monolithic image.

By default, the Day-2 simulation adds `jq` to the platform layer. Override it at runtime with:

```bash
DAY2_PLATFORM_PACKAGES="jq tmux" deploy
```

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
* `deploy` calls `POST /api/action/deploy`, assembles the layers with OverlayFS on OCI, applies a Day-2 platform delta, and rebuilds only the platform SquashFS.
* `validate` calls `POST /api/action/validate` and writes an integrity report under `/home/opc/ol9-prod-factory/reports` on OCI.
* `factory status` reads `/api/status` from the OCI API service.
* `factory metrics` reads `/metrics` for Prometheus metrics.
* `factory logs <command>` reads the latest API-captured log for a lifecycle command.

## Documentation

- [Design Document](docs/design.md)
- [Non-Technical Overview](docs/non-technical-overview.md)
- [Demo Notes](demo/README.md)
