#!/usr/bin/env bash
set -euo pipefail

BASE_DIR="${OL9_FACTORY_BASE_DIR:-/home/opc/ol9-prod-factory}"
MONITORING_DIR="${BASE_DIR}/monitoring"
PROM_CONTAINER="ol9-image-factory-prometheus"
GRAFANA_CONTAINER="ol9-image-factory-grafana"

if [[ ! -f "${MONITORING_DIR}/prometheus.yml" ]]; then
    echo "ERROR: ${MONITORING_DIR}/prometheus.yml not found. Deploy project files first."
    exit 1
fi

if ! command -v podman >/dev/null 2>&1; then
    sudo dnf install -y podman
fi

sudo loginctl enable-linger opc >/dev/null 2>&1 || true

podman rm -f "$PROM_CONTAINER" "$GRAFANA_CONTAINER" >/dev/null 2>&1 || true

podman run -d \
    --name "$PROM_CONTAINER" \
    --network host \
    -v "${MONITORING_DIR}/prometheus.yml:/etc/prometheus/prometheus.yml:ro,Z" \
    docker.io/prom/prometheus:latest \
    --config.file=/etc/prometheus/prometheus.yml \
    --storage.tsdb.retention.time=7d

podman run -d \
    --name "$GRAFANA_CONTAINER" \
    --network host \
    -e GF_SECURITY_ADMIN_USER=admin \
    -e GF_SECURITY_ADMIN_PASSWORD=admin \
    -e GF_USERS_ALLOW_SIGN_UP=false \
    -v "${MONITORING_DIR}/grafana/provisioning:/etc/grafana/provisioning:ro,Z" \
    -v "${MONITORING_DIR}/grafana/dashboards:/var/lib/grafana/dashboards:ro,Z" \
    docker.io/grafana/grafana-oss:latest

cat <<EOF
Monitoring started.

Prometheus: http://127.0.0.1:9090
Grafana:    http://127.0.0.1:3000
Grafana login: admin / admin
Dashboard: OL9 Layered Image Factory Demo

If accessing from your Mac, use SSH tunnels:
  ssh -i /path/to/key -L 8000:127.0.0.1:8000 -L 3000:127.0.0.1:3000 -L 9090:127.0.0.1:9090 opc@<oci-ip>
EOF
