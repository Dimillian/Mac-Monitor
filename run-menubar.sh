#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$ROOT_DIR"

./stop-menubar.sh || true

DERIVED_DATA_PATH="$ROOT_DIR/.derived-data"

TUIST_SKIP_UPDATE_CHECK=1 tuist generate --no-open
TUIST_SKIP_UPDATE_CHECK=1 tuist xcodebuild build \
  -scheme MacMonitor \
  -workspace MacMonitor.xcworkspace \
  -configuration Debug \
  -destination "platform=macOS,arch=arm64" \
  -derivedDataPath "$DERIVED_DATA_PATH"

APP_PATH="$DERIVED_DATA_PATH/Build/Products/Debug/MacMonitor.app"

if [[ ! -d "$APP_PATH" ]]; then
  echo "Could not locate MacMonitor.app at $APP_PATH" >&2
  exit 1
fi

open "$APP_PATH"
