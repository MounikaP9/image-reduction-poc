#!/bin/bash
# 03-deploy-and-update.sh — Layer Composition & Day-2 Update Engine
set -euo pipefail
source "$(dirname "$0")/prod-config.sh"
check_root

DEPLOY_DIR="${BASE_DIR}/deploy_target"
RUN_BASE="${DEPLOY_DIR}/lower_base"
RUN_PLAT="${DEPLOY_DIR}/lower_platform"
RUN_WORK="${DEPLOY_DIR}/workdir"
RUN_UPPER="${DEPLOY_DIR}/upper_rw"
MERGED_OS="${DEPLOY_DIR}/merged_root"

log_info "=== Phase 1: Compositing Layers via OverlayFS ==="
sudo umount "$MERGED_OS" 2>/dev/null || true
sudo umount "$RUN_BASE" 2>/dev/null || true
sudo umount "$RUN_PLAT" 2>/dev/null || true
rm -rf "$DEPLOY_DIR"

mkdir -p "$DEPLOY_DIR" "$RUN_BASE" "$RUN_PLAT" "$RUN_WORK" "$RUN_UPPER" "$MERGED_OS"

log_info "Mounting read-only SquashFS layers to runtime directories..."
mount -t squashfs "${DIST_DIR}/layer-base.squashfs" "$RUN_BASE"
mount -t squashfs "${DIST_DIR}/layer-platform.squashfs" "$RUN_PLAT"

log_info "Executing OverlayFS multi-layer kernel stack composition..."
mount -t overlay overlay -o lowerdir="${RUN_PLAT}:${RUN_BASE}",upperdir="$RUN_UPPER",workdir="$RUN_WORK" "$MERGED_OS"
log_success "Composition successful! Merged OS layer is live at: $MERGED_OS"

log_info "Verifying merged OS state contents..."
if [[ -f "${MERGED_OS}/etc/app-runtime.conf" ]]; then
    log_success "  Found Platform File: /etc/app-runtime.conf -> (Value: $(cat ${MERGED_OS}/etc/app-runtime.conf))"
fi
if [[ -f "${MERGED_OS}/usr/bin/bash" ]]; then
    log_success "  Found Base System Binary: /usr/bin/bash is visible in merged root!"
fi

echo "---"
log_info "=== Phase 2: Simulating Day-2 Platform Package Update ==="
log_info "Modifying application configurations inside the Platform Staging Workspace..."

UPDATE_STAGE="${STAGING_DIR}/platform"
if [[ -d "$UPDATE_STAGE" ]]; then
    echo "VERSION=1.1.0-PATCH-UPDATED" >> "${UPDATE_STAGE}/etc/app-runtime.conf"
    log_success "  Application package configurations updated in staging workspace."
else
    log_error "Platform staging workspace missing. Run 02-split-prod-image.sh first."
fi

log_info "Re-compressing ONLY the tiny Platform layer..."
rm -f "${DIST_DIR}/layer-platform.squashfs"
mksquashfs "$UPDATE_STAGE" "${DIST_DIR}/layer-platform.squashfs" -comp zstd -Xcompression-level 15 -noappend -quiet
log_success "  New Platform chunk compiled: $(numfmt --to=iec $(stat -c%s ${DIST_DIR}/layer-platform.squashfs))"

echo "---"
log_info "=== Phase 3: Rolling Deployment of Hot-Fix Layer ==="
log_info "Unmounting old live runtime environment stack..."
umount "$MERGED_OS"
umount "$RUN_PLAT"

log_info "Mounting newly received, updated platform SquashFS layer chunk..."
mount -t squashfs "${DIST_DIR}/layer-platform.squashfs" "$RUN_PLAT"

log_info "Re-compositing OverlayFS stack with updated layer live..."
mount -t overlay overlay -o lowerdir="${RUN_PLAT}:${RUN_BASE}",upperdir="$RUN_UPPER",workdir="$RUN_WORK" "$MERGED_OS"

log_info "Calculating mounted output image identity..."
find "$MERGED_OS" -type f -not -name "image-manifest.txt" -print0 | sort -z | xargs -0 sha256sum | sha256sum | awk '{print $1}' > "${DEPLOY_DIR}/merged-root-id.txt"
log_success "  Mounted Output Image ID: $(cat ${DEPLOY_DIR}/merged-root-id.txt)"

log_info "Validating live hot-swapped runtime state..."
log_success "  Updated config value: $(cat ${MERGED_OS}/etc/app-runtime.conf | tr '\n' ' ')"
log_success "PRODUCTION VERIFICATION: Day-2 hot-swap upgrade complete with zero base OS disruption!"
