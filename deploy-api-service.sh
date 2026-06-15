#!/usr/bin/env bash
set -euo pipefail

LOCAL_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OCI_USER="${OCI_USER:-opc}"
OCI_HOST="${OCI_HOST:-}"
OCI_DIR="${OCI_DIR:-/home/opc/ol9-prod-factory}"
SSH_KEY="${OCI_SSH_KEY:-}"

usage() {
    cat <<'EOF'
Usage:
  OCI_HOST=<oci-public-ip> [OCI_USER=opc] [OCI_SSH_KEY=/path/key.pem] ./deploy-api-service.sh

This copies the local project to OCI using the required flat runtime layout:
  local: app.py + scripts/*.sh
  OCI:   /home/opc/ol9-prod-factory/app.py + /home/opc/ol9-prod-factory/*.sh

It also creates a systemd service named ol9-image-factory-api.service.
EOF
}

if [[ -z "$OCI_HOST" ]]; then
    usage
    exit 1
fi

SSH_OPTS=()
if [[ -n "$SSH_KEY" ]]; then
    SSH_OPTS=(-i "$SSH_KEY")
fi

REMOTE="${OCI_USER}@${OCI_HOST}"

ssh "${SSH_OPTS[@]}" "$REMOTE" "sudo mkdir -p '$OCI_DIR' '$OCI_DIR/logs' '$OCI_DIR/reports' && sudo chown ${OCI_USER}:${OCI_USER} '$OCI_DIR' '$OCI_DIR/logs' '$OCI_DIR/reports' && sudo find '$OCI_DIR' -maxdepth 1 -type f -exec chown ${OCI_USER}:${OCI_USER} {} +"
scp "${SSH_OPTS[@]}" "$LOCAL_DIR/app.py" "$REMOTE:$OCI_DIR/app.py"
scp "${SSH_OPTS[@]}" "$LOCAL_DIR/install-monitoring.sh" "$REMOTE:$OCI_DIR/install-monitoring.sh"
scp -r "${SSH_OPTS[@]}" "$LOCAL_DIR/monitoring" "$REMOTE:$OCI_DIR/monitoring"
scp "${SSH_OPTS[@]}" "$LOCAL_DIR/scripts/"*.sh "$REMOTE:$OCI_DIR/"
ssh "${SSH_OPTS[@]}" "$REMOTE" "chmod +x '$OCI_DIR/'*.sh && python3 -m pip install --user fastapi uvicorn prometheus_client"

ssh "${SSH_OPTS[@]}" "$REMOTE" "sudo tee /etc/systemd/system/ol9-image-factory-api.service >/dev/null <<'SERVICE'
[Unit]
Description=OL9 Image Factory API
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=opc
WorkingDirectory=/home/opc/ol9-prod-factory
Environment=PATH=/home/opc/.local/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin
ExecStart=/usr/bin/python3 -m uvicorn app:app --host 0.0.0.0 --port 8000
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
SERVICE
sudo systemctl daemon-reload && sudo systemctl enable ol9-image-factory-api.service && sudo systemctl restart ol9-image-factory-api.service"

cat <<EOF

Deployment complete. On your local terminal run:
  export OL9_FACTORY_API_URL=http://${OCI_HOST}:8000
  export PATH="$LOCAL_DIR:\$PATH"

Then use:
  build
  split
  deploy
  validate
  factory status
  factory logs validate

To start Prometheus/Grafana on OCI:
  ssh ${REMOTE} "cd ${OCI_DIR} && ./install-monitoring.sh"
EOF
