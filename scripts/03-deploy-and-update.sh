#!/bin/bash
# 03-deploy-and-update.sh — Layer Composition & Day-2 Update Engine
set -euo pipefail
# shellcheck source=scripts/prod-config.sh
source "$(dirname "$0")/prod-config.sh"
check_root

DEPLOY_DIR="${BASE_DIR}/deploy_target"
RUN_BASE="${DEPLOY_DIR}/lower_base"
RUN_PLAT="${DEPLOY_DIR}/lower_platform"
RUN_WORK="${DEPLOY_DIR}/workdir"
RUN_UPPER="${DEPLOY_DIR}/upper_rw"
MERGED_OS="${DEPLOY_DIR}/merged_root"
BASE_FILE_LIST="${DIST_DIR}/base-owned-files.txt"
DAY2_CHANGE_LIST="${DEPLOY_DIR}/day2-platform-changes.txt"
BASE_LAYER_SHA_FILE="${DEPLOY_DIR}/base-layer-sha256.txt"

snapshot_file_hashes() {
    local root_dir="$1"
    local output_file="$2"

    (
        cd "$root_dir"
        find . -type f -not -name "$MANIFEST_FILE" -exec sha256sum {} + | sort > "$output_file"
    )
}

install_day2_platform_packages() {
    local install_root="$1"
    shift
    local pkg

    if [[ "$#" -eq 0 ]]; then
        log_info "No Day-2 platform packages configured; only config drift will be simulated."
        return
    fi

    for pkg in "$@"; do
        log_info "Applying Day-2 platform package to composed root: $pkg"
        if ! dnf -q repoquery --releasever=9 "$pkg" 2>/dev/null | grep -q .; then
            log_error "Requested Day-2 package $pkg is not available in configured OL9 repositories."
        fi
        dnf install -y "$pkg" --installroot="$install_root" --releasever=9 --setopt=install_weak_deps=False &>/dev/null
    done
}

validate_no_base_overrides() {
    local upper_root="$1"
    local base_file_list="$2"
    local violations_file="$3"
    local file_path

    : > "$violations_file"
    if [[ ! -f "$base_file_list" ]]; then
        log_error "Base-owned file inventory missing at $base_file_list. Run 02-split-prod-image.sh first."
    fi

    while IFS= read -r file_path; do
        [[ -z "$file_path" ]] && continue
        if [[ -e "${upper_root}${file_path}" || -L "${upper_root}${file_path}" ]]; then
            printf '%s\n' "$file_path" >> "$violations_file"
        fi
    done < "$base_file_list"

    if [[ -s "$violations_file" ]]; then
        log_warn "Day-2 platform update attempted to modify frozen base-owned paths:"
        sed -n '1,20p' "$violations_file"
        log_error "Rejecting update. This requires a new base layer version, not a platform-only delta."
    fi
}

copy_overlay_delta_to_platform_stage() {
    local upper_root="$1"
    local platform_root="$2"

    if [[ -n "$(find "$upper_root" -mindepth 1 -print -quit)" ]]; then
        cp -a "$upper_root"/. "$platform_root"/
    fi
}

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
OVERLAY_OPTS="lowerdir=${RUN_PLAT}:${RUN_BASE},upperdir=${RUN_UPPER},workdir=${RUN_WORK}"
mount -t overlay overlay -o "$OVERLAY_OPTS" "$MERGED_OS"
log_success "Composition successful! Merged OS layer is live at: $MERGED_OS"
BASE_LAYER_SHA_BEFORE=$(sha256sum "${DIST_DIR}/layer-base.squashfs" | awk '{print $1}')
echo "$BASE_LAYER_SHA_BEFORE" > "$BASE_LAYER_SHA_FILE"

log_info "Verifying merged OS state contents..."
if [[ -f "${MERGED_OS}/etc/app-runtime.conf" ]]; then
    log_success "  Found Platform File: /etc/app-runtime.conf -> (Value: $(cat "${MERGED_OS}/etc/app-runtime.conf"))"
fi
if [[ -f "${MERGED_OS}/usr/bin/bash" ]]; then
    log_success "  Found Base System Binary: /usr/bin/bash is visible in merged root!"
fi

echo "---"
log_info "=== Phase 2: Simulating Day-2 Platform Package Update ==="
log_info "Applying changes to the composed root so OverlayFS captures a production-style delta..."

UPDATE_STAGE="${STAGING_DIR}/platform"
if [[ -d "$UPDATE_STAGE" ]]; then
    BEFORE_PLATFORM_HASHES="${DEPLOY_DIR}/platform-before.sha256"
    AFTER_PLATFORM_HASHES="${DEPLOY_DIR}/platform-after.sha256"
    BASE_OVERRIDE_VIOLATIONS="${DEPLOY_DIR}/base-override-violations.txt"
    if [[ -n "${DAY2_PLATFORM_PACKAGES:-}" ]]; then
        read -r -a DAY2_PACKAGES <<< "$DAY2_PLATFORM_PACKAGES"
    else
        DAY2_PACKAGES=("${PLATFORM_DAY2_PACKAGES[@]}")
    fi

    snapshot_file_hashes "$UPDATE_STAGE" "$BEFORE_PLATFORM_HASHES"
    echo "VERSION=1.1.0-PATCH-UPDATED" >> "${MERGED_OS}/etc/app-runtime.conf"
    install_day2_platform_packages "$MERGED_OS" "${DAY2_PACKAGES[@]}"
    validate_no_base_overrides "$RUN_UPPER" "$BASE_FILE_LIST" "$BASE_OVERRIDE_VIOLATIONS"
    copy_overlay_delta_to_platform_stage "$RUN_UPPER" "$UPDATE_STAGE"
    snapshot_file_hashes "$UPDATE_STAGE" "$AFTER_PLATFORM_HASHES"
    comm -3 "$BEFORE_PLATFORM_HASHES" "$AFTER_PLATFORM_HASHES" | sed 's/^\t//' | awk '{print $2}' | sort -u > "$DAY2_CHANGE_LIST"
    log_success "  Day-2 platform delta captured in staging workspace."
    log_success "  Recorded changed platform paths: $(wc -l < "$DAY2_CHANGE_LIST")"
else
    log_error "Platform staging workspace missing. Run 02-split-prod-image.sh first."
fi

log_info "Re-compressing ONLY the Platform layer..."
rm -f "${DIST_DIR}/layer-platform.squashfs"
mksquashfs "$UPDATE_STAGE" "${DIST_DIR}/layer-platform.squashfs" -comp zstd -Xcompression-level 15 -noappend -quiet
PLATFORM_LAYER_SIZE=$(stat -c%s "${DIST_DIR}/layer-platform.squashfs")
log_success "  New Platform chunk compiled: $(numfmt --to=iec "$PLATFORM_LAYER_SIZE")"
BASE_LAYER_SHA_AFTER=$(sha256sum "${DIST_DIR}/layer-base.squashfs" | awk '{print $1}')
if [[ "$BASE_LAYER_SHA_AFTER" != "$BASE_LAYER_SHA_BEFORE" ]]; then
    log_error "Base layer changed during a platform-only update."
fi
log_success "  Base layer remained unchanged: ${BASE_LAYER_SHA_AFTER}"

echo "---"
log_info "=== Phase 3: Rolling Deployment of Hot-Fix Layer ==="
log_info "Unmounting old live runtime environment stack..."
umount "$MERGED_OS"
umount "$RUN_PLAT"
rm -rf "$RUN_UPPER" "$RUN_WORK"
mkdir -p "$RUN_UPPER" "$RUN_WORK"

log_info "Mounting newly received, updated platform SquashFS layer chunk..."
mount -t squashfs "${DIST_DIR}/layer-platform.squashfs" "$RUN_PLAT"

log_info "Re-compositing OverlayFS stack with updated layer live..."
OVERLAY_OPTS="lowerdir=${RUN_PLAT}:${RUN_BASE},upperdir=${RUN_UPPER},workdir=${RUN_WORK}"
mount -t overlay overlay -o "$OVERLAY_OPTS" "$MERGED_OS"

log_info "Calculating mounted output image identity..."
find "$MERGED_OS" -type f -not -name "image-manifest.txt" -print0 | sort -z | xargs -0 sha256sum | sha256sum | awk '{print $1}' > "${DEPLOY_DIR}/merged-root-id.txt"
log_success "  Mounted Output Image ID: $(cat "${DEPLOY_DIR}/merged-root-id.txt")"

log_info "Validating live hot-swapped runtime state..."
log_success "  Updated config value: $(tr '\n' ' ' < "${MERGED_OS}/etc/app-runtime.conf")"
log_success "PRODUCTION VERIFICATION: Day-2 hot-swap upgrade complete with zero base OS disruption!"
