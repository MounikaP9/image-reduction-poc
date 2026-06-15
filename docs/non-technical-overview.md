# OL9 Image Factory - Non-Technical Overview

## Executive Summary

This project shows how a large Oracle Linux 9 system image can be built, split into smaller reusable pieces, reassembled, and validated automatically on an OCI cloud instance. A presenter can run simple commands from a local Mac, while the actual image processing happens remotely in the cloud. A Grafana dashboard shows the progress live so the audience can see what is happening at each stage.

## Value Statement

Traditional system images can be large, slow to move, and hard to inspect during updates. This project demonstrates a more modular approach. Instead of treating the image as one large block, it separates the operating system base from the platform/application layer. That makes updates easier to understand and helps show how only part of an image can change while the base remains stable.

The dashboard makes the process demo-friendly. It shows when each step is running or completed, how large each artifact is, and whether final validation passed.

## What The Demo Shows

- A local user runs `build`, `split`, `deploy`, and `validate` from a Mac terminal.
- The commands call an API running on an OCI instance.
- OCI builds the original Oracle Linux image.
- OCI splits the image into base and platform layers.
- OCI combines the layers using OverlayFS.
- OCI validates that the final mounted result matches the original image.
- Grafana displays live status and sizes during the process.

## Technologies Used

### Oracle Cloud Infrastructure (OCI)

Used as the remote compute environment where the image is built, split, deployed, and validated. This keeps heavy processing away from the local laptop.

### Oracle Linux 9

Used as the operating system image being built and processed.

### Python FastAPI

Used to provide a simple API service on OCI. Local commands call this API to start each lifecycle step.

### Bash Scripts

Used for the actual image operations: building the image, splitting layers, mounting with OverlayFS, and running validation.

### SquashFS

Used to compress the base and platform layers into efficient read-only filesystem images.

### OverlayFS

Used to combine the base and platform layers into one mounted output view.

### Prometheus

Used to collect live metrics from the FastAPI service, such as current step, status, artifact size, and validation result.

### Grafana

Used to display the live dashboard for the project demo.

### SSH Tunnel

Used to securely access the OCI API and dashboard from the Mac without exposing ports publicly to the internet.

## Dashboard Meaning

- **Current Step** shows what is happening now: Not Run, Simulate, Split, Deploy, Validate, or Completed.
- **Validation** shows Not Run before validation starts, then Passed or Failed after validation.
- **Original Image Size** shows the size of the monolithic image.
- **Lifecycle Step Status** shows the state of each major step.
- **Artifact Sizes** shows the size of the original image, base layer, platform layer, and final mounted output.

## Demo Outcome

A successful run proves that the project can remotely build an Oracle Linux image, split it into layers, reassemble it, validate data integrity, and visualize the full process in a dashboard.
