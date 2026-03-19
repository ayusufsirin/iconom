#!/usr/bin/env bash
set -euo pipefail

PORT="${XRCE_AGENT_UDP_PORT:-8888}"

exec /opt/microxrce/bin/MicroXRCEAgent udp4 -p "${PORT}"
