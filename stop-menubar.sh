#!/usr/bin/env bash
set -euo pipefail

pkill -x "MacMonitor" >/dev/null 2>&1 || true
