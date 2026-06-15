#!/usr/bin/env bash
set -euo pipefail

BASE_DIR="${OL9_FACTORY_BASE_DIR:-/home/opc/ol9-prod-factory}"

sudo umount "${BASE_DIR}/deploy_target/merged_root" 2>/dev/null || true
sudo umount "${BASE_DIR}/deploy_target/lower_platform" 2>/dev/null || true
sudo umount "${BASE_DIR}/deploy_target/lower_base" 2>/dev/null || true
sudo umount "${BASE_DIR}/deploy_target/monolithic_verify" 2>/dev/null || true
sudo umount "${BASE_DIR}/mnt_prod" 2>/dev/null || true

sudo rm -rf \
  "${BASE_DIR}/ol9-monolithic-prod.img" \
  "${BASE_DIR}/staging" \
  "${BASE_DIR}/dist" \
  "${BASE_DIR}/deploy_target" \
  "${BASE_DIR}/logs" \
  "${BASE_DIR}/reports" \
  "${BASE_DIR}/mnt_prod"

mkdir -p "${BASE_DIR}/staging" "${BASE_DIR}/dist" "${BASE_DIR}/logs" "${BASE_DIR}/reports" "${BASE_DIR}/mnt_prod"
sudo chown -R opc:opc "${BASE_DIR}/staging" "${BASE_DIR}/dist" "${BASE_DIR}/logs" "${BASE_DIR}/reports" "${BASE_DIR}/mnt_prod"

podman rm -f ol9-image-factory-prometheus ol9-image-factory-grafana >/dev/null 2>&1 || true
sudo systemctl restart ol9-image-factory-api.service

echo "Factory artifacts, logs, reports, mounts, and Prometheus/Grafana runtime state were reset."
echo "Run ./install-monitoring.sh to start a fresh dashboard."
