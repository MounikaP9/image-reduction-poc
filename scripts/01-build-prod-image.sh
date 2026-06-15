#!/bin/bash
# 01-build-prod-image.sh — Real Oracle Linux 9 OS Image Builder
set -euo pipefail
source "$(dirname "$0")/prod-config.sh"
check_root

log_info "=== Phase 1: Allocating True 10GB Disk Volume ==="
truncate -s 10G "$IMAGE_FILE"
mkfs.ext4 -F -L "OL9_REAL_ROOT" "$IMAGE_FILE" &>/dev/null

log_info "Mounting block storage loop device..."
mount -o loop "$IMAGE_FILE" "$MOUNT_DIR"
trap "umount $MOUNT_DIR 2>/dev/null || true" EXIT

log_info "Installing real, functional Core Base OS packages via DNF..."
dnf groupinstall -y "Core" --installroot="$MOUNT_DIR" --releasever=9 --setopt=install_weak_deps=False &>/dev/null

log_info "Installing real Platform Application packages..."
dnf install -y python3 podman git --installroot="$MOUNT_DIR" --releasever=9 &>/dev/null

log_info "Writing engineering manifest configuration file inside real image..."
cat > "${MOUNT_DIR}/${MANIFEST_FILE}" << 'EOF'
# OL9 Live Image Manifest
[base]
coreutils
glibc
systemd
bash

[platform]
python3
podman
git
EOF

log_info "Seeding real-world untracked data (dynamic application logs and custom configs)..."
echo "ENV=PRODUCTION_VERIFIED" > "${MOUNT_DIR}/etc/app-runtime.conf"
echo "LOG_LEVEL=DEBUG" > "${MOUNT_DIR}/var/log/app-engine.log"

log_info "Finalizing block storage sync and unmounting clean..."
umount "$MOUNT_DIR"
trap - EXIT

log_success "Real 10GB Linux Master Image successfully built at: $IMAGE_FILE"
