import json
import os
import time
import random
from datetime import datetime, timezone
from logging.handlers import RotatingFileHandler
import logging
import threading

from flask import Flask, request, jsonify, g

APP_NAME = "flask-sumo-demo"
LOG_PATH = os.environ.get("APP_LOG_PATH", "./app.log")

# Slow mode toggle (master switch)
slow_mode_enabled = False
slow_mode_lock = threading.Lock()

# When slow mode is enabled, some % of requests will be slow
SLOW_RESPONSE_SECONDS = 5
SLOW_PROBABILITY = float(os.environ.get("SLOW_PROBABILITY", "0.5"))  # 0.5 = 50%


def create_app():
    app = Flask(__name__)

    # Avoid strict / vs / trailing slash issues
    app.url_map.strict_slashes = False

    # Ensure log directory exists (only if LOG_PATH includes a directory)
    log_dir = os.path.dirname(LOG_PATH)
    if log_dir:
        os.makedirs(log_dir, exist_ok=True)

    logger = logging.getLogger(APP_NAME)
    logger.setLevel(logging.INFO)

    # Prevent duplicate handlers if reloaded
    if not logger.handlers:
        handler = RotatingFileHandler(LOG_PATH, maxBytes=25_000_000, backupCount=5)
        handler.setFormatter(logging.Formatter("%(message)s"))  # JSON per line
        logger.addHandler(handler)

    @app.before_request
    def start_timer():
        g.start_time = time.perf_counter()

    @app.after_request
    def log_request(response):
        duration_ms = int((time.perf_counter() - g.start_time) * 1000)

        # If api_data set per-request flags, include them; otherwise default
        entry = {
            "timestamp": datetime.now(timezone.utc).isoformat(),
            "app": APP_NAME,
            "method": request.method,
            "path": request.path,
            "status": response.status_code,
            "response_time_ms": duration_ms,
            "client_ip": request.headers.get("X-Forwarded-For", request.remote_addr),
            "slow_mode_enabled": getattr(g, "slow_mode_enabled", slow_mode_enabled),
            "slow_mode_applied": getattr(g, "slow_mode_applied", False),
        }
        logger.info(json.dumps(entry, separators=(",", ":")))
        return response

    @app.get("/health")
    def health():
        return jsonify({"ok": True})

    @app.get("/api/data")
    def api_data():
        # Snapshot the master switch safely
        with slow_mode_lock:
            enabled = slow_mode_enabled

        # Only inject slowness randomly when enabled
        applied = enabled and (random.random() < SLOW_PROBABILITY)

        # Store flags for logging (so log reflects what happened for THIS request)
        g.slow_mode_enabled = enabled
        g.slow_mode_applied = applied

        if applied:
            time.sleep(SLOW_RESPONSE_SECONDS)

        return jsonify({
            "data": [1, 2, 3],
            "slow_mode_enabled": enabled,
            "slow_mode": applied,  # true only when slowness actually applied
            "slow_probability": SLOW_PROBABILITY,
            "forced_response_time_sec": SLOW_RESPONSE_SECONDS if applied else 0
        })

    @app.post("/api/slow-mode/enable")
    def enable_slow_mode():
        global slow_mode_enabled
        with slow_mode_lock:
            slow_mode_enabled = True
        return jsonify({
            "slow_mode_enabled": True,
            "slow_probability": SLOW_PROBABILITY,
            "forced_response_time_sec": SLOW_RESPONSE_SECONDS
        })

    @app.post("/api/slow-mode/disable")
    def disable_slow_mode():
        global slow_mode_enabled
        with slow_mode_lock:
            slow_mode_enabled = False
        return jsonify({"slow_mode_enabled": False})

    return app


app = create_app()

if __name__ == "__main__":
    # Flask dev server (for demo). In production use gunicorn/systemd.
    app.run(host="0.0.0.0", port=8080)

