#!/usr/bin/env python3
import json
import time
from http.server import HTTPServer, BaseHTTPRequestHandler
from urllib.parse import urlparse, parse_qs
import threading

REF_PORT = 45678
FIXTURE_CREDENTIALS = {"username": "test_pilot", "password": "test_pass_123"}
DETERMINISTIC_TIME_START = 1700000000.0

session_token = None
server_start_time = time.time()


class RefereeHandler(BaseHTTPRequestHandler):
    def log_message(self, format, *args):
        pass

    def send_json_response(self, status_code, data):
        self.send_response(status_code)
        self.send_header("Content-Type", "application/json")
        self.end_headers()
        self.wfile.write(json.dumps(data).encode())

    def do_GET(self):
        parsed = urlparse(self.path)
        path = parsed.path

        if path == "/health":
            self.send_json_response(200, {"status": "ok", "service": "referee"})
        elif path == "/time":
            elapsed = time.time() - server_start_time
            deterministic_time = DETERMINISTIC_TIME_START + elapsed
            self.send_json_response(200, {
                "server_time": deterministic_time,
                "server_time_iso": "2025-01-01T00:00:00Z",
                "timestamp": int(deterministic_time * 1000)
            })
        else:
            self.send_json_response(404, {"error": "not found"})

    def do_POST(self):
        parsed = urlparse(self.path)
        path = parsed.path

        content_length = int(self.headers.get("Content-Length", 0))
        body = self.rfile.read(content_length).decode() if content_length > 0 else "{}"

        try:
            data = json.loads(body) if body else {}
        except json.JSONDecodeError:
            self.send_json_response(400, {"error": "invalid json"})
            return

        if path == "/login":
            username = data.get("username", "")
            password = data.get("password", "")
            if username == FIXTURE_CREDENTIALS["username"] and password == FIXTURE_CREDENTIALS["password"]:
                global session_token
                session_token = "fixture_session_001"
                self.send_json_response(200, {
                    "status": "success",
                    "token": session_token,
                    "pilot_id": "test_pilot_001"
                })
            else:
                self.send_json_response(401, {"status": "unauthorized", "error": "invalid credentials"})
        elif path == "/telemetry":
            self.send_json_response(200, {
                "status": "received",
                "rival_state": {
                    "aircraft_id": "plane_02",
                    "position": {"x": 50.0, "y": 100.0, "z": 50.0},
                    "velocity": {"x": 10.0, "y": 5.0, "z": 0.0},
                    "heading": 45.0,
                    "timestamp": int(time.time() * 1000)
                },
                "competition_state": {
                    "active": True,
                    "round": 1
                }
            })
        else:
            self.send_json_response(404, {"error": "not found"})


def run_server(port=REF_PORT):
    server = HTTPServer(("0.0.0.0", port), RefereeHandler)
    print(f"referee server listening on port {port}")
    server.serve_forever()


if __name__ == "__main__":
    run_server()
