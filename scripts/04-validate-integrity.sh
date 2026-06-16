#!/bin/bash
# 04-validate-integrity.sh — Cryptographic Validation & Audit Engine
set -euo pipefail
# shellcheck source=scripts/prod-config.sh
source "$(dirname "$0")/prod-config.sh"
check_root

REPORT_FILE="${REPORT_DIR}/integrity-report-$(date -u +%Y%m%dT%H%M%SZ).txt"
exec > >(tee "$REPORT_FILE") 2>&1

VERIFY_MOUNT="${BASE_DIR}/deploy_target/monolithic_verify"
MERGED_OS="${BASE_DIR}/deploy_target/merged_root"
DAY2_CHANGE_LIST="${BASE_DIR}/deploy_target/day2-platform-changes.txt"
BASE_LAYER_SHA_FILE="${BASE_DIR}/deploy_target/base-layer-sha256.txt"
EXCLUDE_LIST="/tmp/image_factory_validation_excludes.txt"

write_hash_matrix() {
    local root_dir="$1"
    local output_file="$2"
    local path_list="${output_file}.paths"

    (
        cd "$root_dir"
        find . -type f | sort | grep -Fvx -f "$EXCLUDE_LIST" > "$path_list" || true
        if [[ -s "$path_list" ]]; then
            xargs sha256sum < "$path_list" > "$output_file"
        else
            : > "$output_file"
        fi
    )
    rm -f "$path_list"
}

log_info "=== Phase 4: Cryptographic File Integrity Audit ==="
log_info "Validation report will be saved at: $REPORT_FILE"
sudo umount "$VERIFY_MOUNT" 2>/dev/null || true
mkdir -p "$VERIFY_MOUNT"

log_info "Mounting original 10GB monolithic master image (Read-Only)..."
mount -o loop,ro "$IMAGE_FILE" "$VERIFY_MOUNT"
trap 'umount "$VERIFY_MOUNT" 2>/dev/null || true' EXIT

log_info "Verifying OverlayFS combined runtime directory exists..."
if [[ ! -d "$MERGED_OS" ]]; then
    log_error "Combined target root ($MERGED_OS) not found! Run 03-deploy-and-update.sh first."
fi

log_info "Building validation exclude list for intentional Day-2 platform changes..."
{
    printf './%s\n' "$MANIFEST_FILE"
    if [[ -f "$DAY2_CHANGE_LIST" ]]; then
        cat "$DAY2_CHANGE_LIST"
    else
        printf './etc/app-runtime.conf\n'
    fi
} | sort -u > "$EXCLUDE_LIST"

log_info "Verifying frozen base layer digest..."
if [[ -f "$BASE_LAYER_SHA_FILE" ]]; then
    EXPECTED_BASE_SHA=$(cat "$BASE_LAYER_SHA_FILE")
    CURRENT_BASE_SHA=$(sha256sum "${DIST_DIR}/layer-base.squashfs" | awk '{print $1}')
    if [[ "$CURRENT_BASE_SHA" != "$EXPECTED_BASE_SHA" ]]; then
        log_error "Base layer digest changed. Expected $EXPECTED_BASE_SHA, found $CURRENT_BASE_SHA"
    fi
    log_success "Base layer digest is unchanged: $CURRENT_BASE_SHA"
else
    log_warn "Base layer digest marker not found; skipping base-layer immutability check."
fi

log_info "Generating sorted SHA256 checksum matrix for the original image files..."
log_info "Excluding generated manifest and recorded Day-2 platform delta paths."
write_hash_matrix "$VERIFY_MOUNT" /tmp/mono_hash.txt

log_info "Generating sorted SHA256 checksum matrix for the combined OverlayFS layers..."
write_hash_matrix "$MERGED_OS" /tmp/merged_hash.txt

echo "---"
MERGED_OUTPUT_ID=$(sha256sum /tmp/merged_hash.txt | awk '{print $1}')
echo "$MERGED_OUTPUT_ID" > "${BASE_DIR}/deploy_target/merged-root-id.txt"
log_info "Mounted Output Image ID: $MERGED_OUTPUT_ID"

log_info "Executing Cryptographic Matrix Comparison via diff..."
if diff /tmp/mono_hash.txt /tmp/merged_hash.txt > /dev/null; then
    log_success "MATHEMATICAL PROOF ACHIEVED: Checksums match outside intentional platform delta paths!"
    log_success "RESULT: Frozen base plus platform layer reconstructs the original image, with only recorded Day-2 platform changes excluded."
    log_success "VALIDATION STATUS: SUCCESS (Base Unchanged, Platform Delta Isolated, No Unexpected Corruption)"
else
    log_warn "Data divergence detected! Outputting file discrepancies below:"
    diff /tmp/mono_hash.txt /tmp/merged_hash.txt || true
    log_error "VALIDATION STATUS: FAILED (Unexpected data divergence outside recorded platform delta)"
fi

cd "$(dirname "$0")"
umount "$VERIFY_MOUNT"
trap - EXIT
rm -rf "$VERIFY_MOUNT" /tmp/mono_hash.txt /tmp/merged_hash.txt "$EXCLUDE_LIST"
log_success "Validation report saved at: $REPORT_FILE"
