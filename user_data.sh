#!/bin/bash
set -euo pipefail

########################################
# 1) OS packages (Amazon Linux 2)
########################################
yum -y update
yum -y install python3-pip
yum -y install python3-virtualenv || true

########################################
# 2) Python virtualenv + deps
########################################
APP_HOME="/home/ec2-user"
VENV_DIR="$${APP_HOME}/venv"

if [ ! -d "$${VENV_DIR}" ]; then
  python3 -m venv "$${VENV_DIR}"
fi

"$${VENV_DIR}/bin/pip" install --upgrade pip
"$${VENV_DIR}/bin/pip" install flask gunicorn

########################################
# 3) Log directory/file
########################################
LOG_DIR="$${APP_HOME}/sampleapp1"
LOG_FILE="$${LOG_DIR}/app.log"

mkdir -p "$${LOG_DIR}"
touch "$${LOG_FILE}"
chown -R ec2-user:ec2-user "$${LOG_DIR}"
chmod 755 "$${LOG_DIR}"
chmod 644 "$${LOG_FILE}"

########################################
# 4) Flask application code
########################################
cat > "$${APP_HOME}/app1.py" << 'EOF'
import json
import os
import time
import threading
from datetime import datetime, timezone
from flask import Flask, request, jsonify, g
import logging
from logging.handlers import RotatingFileHandler

APP_NAME = "flask-sumo-demo"
LOG_PATH = os.environ.get("APP_LOG_PATH", "/home/ec2-user/sampleapp1/app.log")

slow_mode_enabled = False
slow_mode_lock = threading.Lock()
SLOW_RESPONSE_SECONDS = 5

def create_app():
    app = Flask(__name__)

    log_dir = os.path.dirname(os.path.abspath(LOG_PATH))
    os.makedirs(log_dir, exist_ok=True)

    logger = logging.getLogger(APP_NAME)
    logger.setLevel(logging.INFO)

    handler = RotatingFileHandler(LOG_PATH, maxBytes=25_000_000, backupCount=5)
    handler.setFormatter(logging.Formatter("%(message)s"))
    logger.addHandler(handler)

    @app.before_request
    def start_timer():
        g.start_time = time.perf_counter()

    @app.after_request
    def log_request(response):
        duration_ms = int((time.perf_counter() - g.start_time) * 1000)
        entry = {
            "timestamp": datetime.now(timezone.utc).isoformat(),
            "app": APP_NAME,
            "method": request.method,
            "path": request.path,
            "status": response.status_code,
            "response_time_ms": duration_ms,
            "client_ip": request.headers.get("X-Forwarded-For", request.remote_addr),
            "slow_mode": slow_mode_enabled
        }
        logger.info(json.dumps(entry, separators=(",", ":")))
        return response

    @app.get("/health")
    def health():
        return jsonify({"ok": True})

    @app.get("/api/data")
    def api_data():
        with slow_mode_lock:
            if slow_mode_enabled:
                time.sleep(SLOW_RESPONSE_SECONDS)
        return jsonify({"data": [1, 2, 3], "slow_mode": slow_mode_enabled})

    @app.post("/api/slow-mode/enable")
    def enable_slow_mode():
        global slow_mode_enabled
        with slow_mode_lock:
            slow_mode_enabled = True
        return jsonify({"slow_mode": True, "forced_response_time_sec": SLOW_RESPONSE_SECONDS})

    @app.post("/api/slow-mode/disable")
    def disable_slow_mode():
        global slow_mode_enabled
        with slow_mode_lock:
            slow_mode_enabled = False
        return jsonify({"slow_mode": False})

    return app

app = create_app()
EOF

chown ec2-user:ec2-user "$${APP_HOME}/app1.py"

########################################
# 5) Start Gunicorn automatically (systemd)
# Bind to 0.0.0.0 so you can reach externally if SG allows it.
########################################
cat > /etc/systemd/system/flaskapp.service << EOF
[Unit]
Description=Flask App with Gunicorn
After=network.target

[Service]
User=ec2-user
WorkingDirectory=$${APP_HOME}
Environment=APP_LOG_PATH=$${LOG_FILE}
Environment=PATH=$${VENV_DIR}/bin
ExecStart=$${VENV_DIR}/bin/gunicorn -w 2 -b 0.0.0.0:8080 --timeout 120 app1:app
Restart=always
RestartSec=3

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable flaskapp
systemctl restart flaskapp

########################################
# 6) Install Sumo Collector (Installed Collector)
########################################
cd /tmp
curl -fL --retry 5 --retry-delay 2 -o SumoCollector.sh "https://download-collector.sumologic.com/rest/download/linux/64"
chmod +x SumoCollector.sh

./SumoCollector.sh -q \
  -Vsumo.token_and_url="${sumo_installation_token}" \
  -Vcollector.name="${collector_name}"

echo "Bootstrap complete: Flask+Gunicorn running, logs at $${LOG_FILE}, Sumo collector installed."
