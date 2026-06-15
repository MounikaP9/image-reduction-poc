#!/bin/bash
# prod-config.sh — Global Pipeline Configurations & Shared Primitives

BASE_DIR="/home/opc/ol9-prod-factory"
IMAGE_FILE="${BASE_DIR}/ol9-monolithic-prod.img"
MOUNT_DIR="${BASE_DIR}/mnt_prod"
STAGING_DIR="${BASE_DIR}/staging"
DIST_DIR="${BASE_DIR}/dist"
REPORT_DIR="${BASE_DIR}/reports"
MANIFEST_FILE="image-manifest.txt"

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
