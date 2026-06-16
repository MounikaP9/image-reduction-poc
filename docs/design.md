# OL9 Layered Image Factory - Design Document

## 1. Purpose

This project demonstrates a remote Oracle Linux 9 image factory that is controlled from a local developer machine while all heavy image operations execute on an OCI instance. The system builds a monolithic OL9 image, splits it into reusable layers, deploys those layers with OverlayFS, validates integrity, and exposes live operational metrics to Prometheus and Grafana.

## 2. Goals

- Trigger OCI image lifecycle operations from simple local commands: `build`, `split`, `deploy`, and `validate`.
- Keep compute-heavy image processing on the OCI instance.
- Split a monolithic image into a frozen base layer and a platform delta layer.
- Recompose the layers into a mounted output root using OverlayFS.
- Apply Day-2 platform package/config changes without modifying the base layer.
- Validate that the recomposed output matches the original image, excluding only recorded Day-2 platform delta files.
- Provide a Grafana dashboard that clearly shows demo progress and artifact sizes.

## 3. High-Level Architecture

```text
Mac Terminal
  build / split / deploy / validate
        |
        v
SSH Tunnel or Direct HTTP
        |
        v
FastAPI Control Plane on OCI
        |
        v
Shell Lifecycle Scripts
        |
        v
OL9 Image, SquashFS Layers, OverlayFS Mount, Validation Report
        |
        v
Prometheus Metrics Endpoint
        |
        v
Grafana Dashboard
```

## 4. Components

### Local Command Wrapper

The local `factory` command maps user-friendly commands to FastAPI endpoints. Wrapper commands `build`, `split`, `deploy`, and `validate` call the same API through `OL9_FACTORY_API_URL`.

### FastAPI Control Plane

`app.py` runs on OCI and exposes:

- `POST /api/action/build`
- `POST /api/action/split`
- `POST /api/action/deploy`
- `POST /api/action/validate`
- `GET /api/status`
- `GET /api/logs/{step}`
- `GET /metrics/`

The API launches lifecycle scripts as background tasks and updates Prometheus metrics.

### Lifecycle Scripts

- `01-build-prod-image.sh`: creates the monolithic OL9 image, installs the Core/base package set, snapshots the base RPM list, then installs platform packages.
- `02-split-prod-image.sh`: separates base-owned RPM files from platform files, emits `dist/base-owned-files.txt`, and creates base/platform SquashFS layers.
- `03-deploy-and-update.sh`: mounts layers, composes them with OverlayFS, applies Day-2 platform changes to the composed root, copies only upperdir changes back into the platform layer, and verifies the base SquashFS digest is unchanged.
- `04-validate-integrity.sh`: compares the original image with the recomposed output outside recorded Day-2 delta paths and writes a report.

## 4.1 Base Freeze And Platform Delta

The split is driven by RPM ownership, not hardcoded file paths:

- The build step captures every RPM installed after Core/kernel/base setup as the frozen base baseline.
- The platform package list is computed as the RPM delta introduced after platform tools are installed.
- The split step starts with a full copy in the platform staging tree, then moves files owned by base RPMs into the base staging tree.
- The generated `dist/base-owned-files.txt` inventory is used during Day-2 updates to reject platform changes that would override base-owned files.

This models a production rollout rule: platform-only updates can add or change platform-owned content, but any change to base-owned paths requires a new base layer version.

### Monitoring

Prometheus scrapes FastAPI metrics from `/metrics/`. Grafana reads Prometheus and displays a focused dashboard for the live demo.

## 5. Metrics Design

Key metrics:

- `image_factory_current_step`: current lifecycle stage.
  - `-1`: Not Run
  - `0`: Completed
  - `1`: Simulate
  - `2`: Split
  - `3`: Deploy
  - `4`: Validate
- `image_factory_step_status{step="..."}`: per-step status.
  - `-1`: Idle/Not Run
  - `0`: Failed
  - `0.5`: Running
  - `1`: Success
- `image_factory_artifact_size_bytes{artifact="..."}`: size of original image, base layer, platform layer, and mounted output.
- `image_factory_validation_success`: validation result.
  - `-1`: Not Run
  - `0`: Failed
  - `1`: Passed

Validation also writes an integrity report that includes the mounted output ID and verifies the frozen base layer digest recorded during deployment.

## 6. Dashboard Panels

The Grafana dashboard intentionally keeps only the most demo-relevant panels:

- Current Step
- Validation
- Original Image Size
- Lifecycle Step Status
- Artifact Sizes

The lifecycle order is simulate, split, deploy, validate. The artifact order is original-size, layer-base, layer-platform, mounted.

## 7. Reset Procedure

`reset-factory-state.sh` unmounts factory mounts, deletes generated images/layers/logs/reports, restarts the API, and clears Prometheus/Grafana runtime containers. After reset, run `install-monitoring.sh` to start a clean dashboard.

## 8. Security Notes

For demos, SSH tunneling is preferred instead of exposing FastAPI, Prometheus, or Grafana publicly. If direct access is required, restrict OCI ingress rules to the presenter's public IP and add authentication before using this outside a demo environment.
