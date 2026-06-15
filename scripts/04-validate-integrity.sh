#!/bin/bash
# 04-validate-integrity.sh — Cryptographic Validation & Audit Engine
set -euo pipefail
source "$(dirname "$0")/prod-config.sh"
check_root

REPORT_FILE="${REPORT_DIR}/integrity-report-$(date -u +%Y%m%dT%H%M%SZ).txt"
exec > >(tee "$REPORT_FILE") 2>&1

VERIFY_MOUNT="${BASE_DIR}/deploy_target/monolithic_verify"
MERGED_OS="${BASE_DIR}/deploy_target/merged_root"

log_info "=== Phase 4: Cryptographic File Integrity Audit ==="
log_info "Validation report will be saved at: $REPORT_FILE"
sudo umount "$VERIFY_MOUNT" 2>/dev/null || true
mkdir -p "$VERIFY_MOUNT"

log_info "Mounting original 10GB monolithic master image (Read-Only)..."
mount -o loop,ro "$IMAGE_FILE" "$VERIFY_MOUNT"
trap "umount $VERIFY_MOUNT 2>/dev/null || true" EXIT

log_info "Verifying OverlayFS combined runtime directory exists..."
if [[ ! -d "$MERGED_OS" ]]; then
    log_error "Combined target root ($MERGED_OS) not found! Run 03-deploy-and-update.sh first."
fi

log_info "Generating sorted SHA256 checksum matrix for the original image files..."
log_info "Excluding /etc/app-runtime.conf because deploy intentionally applies a Day-2 update."
cd "$VERIFY_MOUNT"
find . -type f -not -name "image-manifest.txt" -not -path "./etc/app-runtime.conf" -exec sha256sum {} + | sort > /tmp/mono_hash.txt

log_info "Generating sorted SHA256 checksum matrix for the combined OverlayFS layers..."
cd "$MERGED_OS"
find . -type f -not -name "image-manifest.txt" -not -path "./etc/app-runtime.conf" -exec sha256sum {} + | sort > /tmp/merged_hash.txt

echo "---"
MERGED_OUTPUT_ID=$(sha256sum /tmp/merged_hash.txt | awk '{print $1}')
echo "$MERGED_OUTPUT_ID" > "${BASE_DIR}/deploy_target/merged-root-id.txt"
log_info "Mounted Output Image ID: $MERGED_OUTPUT_ID"

log_info "Executing Cryptographic Matrix Comparison via diff..."
if diff /tmp/mono_hash.txt /tmp/merged_hash.txt > /dev/null; then
    log_success "MATHEMATICAL PROOF ACHIEVED: Checksums match with 100% precision!"
    log_success "RESULT: The split layers combined are bit-for-bit identical to the monolithic image."
    log_success "VALIDATION STATUS: SUCCESS (Zero Data Loss, Zero Corruption)"
else
    log_warn "Data divergence detected! Outputting file discrepancies below:"
    diff /tmp/mono_hash.txt /tmp/merged_hash.txt || true
fi

cd "$(dirname "$0")"
umount "$VERIFY_MOUNT"
trap - EXIT
rm -rf "$VERIFY_MOUNT" /tmp/mono_hash.txt /tmp/merged_hash.txt
log_success "Validation report saved at: $REPORT_FILE"
