#!/bin/zsh
set -euo pipefail

SCRIPT_DIR="${0:A:h}"
PROJECT_DIR="${SCRIPT_DIR:h}"
cd "${PROJECT_DIR}"

swift test
swift build -c release
"${PROJECT_DIR}/scripts/build-app.sh"
codesign --verify --deep --strict "${PROJECT_DIR}/dist/GrokBot.app"
plutil -lint "${PROJECT_DIR}/dist/GrokBot.app/Contents/Info.plist"
