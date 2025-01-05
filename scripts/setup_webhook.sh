#!/usr/bin/env bash

TARGET_USER="$(whoami)"
PROJECT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )/.." && pwd )"
ENV_FILE="$PROJECT_DIR/.env"

source ENV_FILE

TRIGGER_PATH="${PROJECT_DIR}/${CONFIG}/webhooks/triggers"
mkdir -p "${TRIGGER_PATH}"
sudo chown -R "${UID}:${GID}" "${TRIGGER_PATH}"
sudo chmod -R 775 "${TRIGGER_PATH}"

sudo bash -c "cat > /etc/systemd/system/pull-trigger.service <<EOF
[Unit]
Description=Pull trigger for ${TARGET_USER}

[Service]
User=${TARGET_USER}
WorkingDirectory=${PROJECT_DIR}
ExecStart=${PROJECT_DIR}/scripts/webhooks/gh_pull.sh
Restart=always

[Install]
WantedBy=multi-user.target
EOF"

sudo systemctl daemon-reload
sudo systemctl enable pull-trigger.service
sudo systemctl start pull-trigger.service
