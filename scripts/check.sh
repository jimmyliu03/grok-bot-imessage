#!/bin/zsh
set -euo pipefail

SCRIPT_DIR="${0:A:h}"
PROJECT_DIR="${SCRIPT_DIR:h}"
cd "${PROJECT_DIR}"

jq empty \
  "${PROJECT_DIR}/.grok-plugin/marketplace.json" \
  "${PROJECT_DIR}/plugins/grok-bot-mac-bridge/plugin.json"
swift test
swift build -c release
"${PROJECT_DIR}/scripts/build-app.sh"
codesign --verify --deep --strict "${PROJECT_DIR}/dist/GrokBot.app"
plutil -lint "${PROJECT_DIR}/dist/GrokBot.app/Contents/Info.plist"
