#!/bin/bash
# prod-config.sh — Global Pipeline Configurations & Shared Primitives

BASE_DIR="/home/opc/ol9-prod-factory"
IMAGE_FILE="${BASE_DIR}/ol9-monolithic-prod.img"
MOUNT_DIR="${BASE_DIR}/mnt_prod"
STAGING_DIR="${BASE_DIR}/staging"
DIST_DIR="${BASE_DIR}/dist"
REPORT_DIR="${BASE_DIR}/reports"
MANIFEST_FILE="image-manifest.txt"

# Packages that should belong to the reusable base image layer when they are
# available in the configured OL9 repositories.
BASE_IMAGE_PACKAGE_CANDIDATES=(
  kernel
  kernel-core
  kernel-modules
  kernel-modules-core
  kernel-uek
  kernel-uek-core
  kernel-uek-modules
  dracut
)

# Demo platform/tooling payload. Packages installed after the base package
# snapshot are treated as platform-layer content.
PLATFORM_PACKAGES=(
  python3
  podman
  git
)

# Packages added during the Day-2 platform update simulation. These are applied
# to the composed root and then captured back into the platform staging tree.
PLATFORM_DAY2_PACKAGES=(
  jq
)

# Ensure directories exist
mkdir -p "$MOUNT_DIR" "$STAGING_DIR" "$DIST_DIR" "$REPORT_DIR"

# Common log formatters for clear reporting
log_info()    { echo -e "\e[34m[INFO]\e[0m $1"; }
log_success() { echo -e "\e[32m[SUCCESS]\e[0m $1"; }
log_warn()    { echo -e "\e[33m[WARN]\e[0m $1"; }
log_error()   { echo -e "\e[31m[ERROR]\e[0m $1"; exit 1; }

# Structural prerequisite validation
check_root() {
    if [[ $EUID -ne 0 ]]; then
        log_error "This operation requires root privileges. Please run via sudo."
    fi
}
