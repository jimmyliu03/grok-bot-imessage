#!/bin/zsh
set -euo pipefail

SCRIPT_DIR="${0:A:h}"
PROJECT_DIR="${SCRIPT_DIR:h}"
APP_PATH="${PROJECT_DIR}/dist/GrokBot.app"
ICON_WORK="${PROJECT_DIR}/.build/GrokBot.iconset"
BASE_ICON="${PROJECT_DIR}/.build/GrokBot-1024.png"

cd "${PROJECT_DIR}"
swift build -c release

if [[ -d "${APP_PATH}" && "${APP_PATH}" == "${PROJECT_DIR}/dist/GrokBot.app" ]]; then
  rm -rf "${APP_PATH}"
fi
mkdir -p "${APP_PATH}/Contents/MacOS" "${APP_PATH}/Contents/Resources" "${PROJECT_DIR}/dist"
cp "${PROJECT_DIR}/.build/release/GrokBot" "${APP_PATH}/Contents/MacOS/GrokBot"
cp "${PROJECT_DIR}/Resources/Info.plist" "${APP_PATH}/Contents/Info.plist"

if sips -s format png "${PROJECT_DIR}/Resources/AppIcon.svg" --out "${BASE_ICON}" >/dev/null 2>&1; then
  if [[ -d "${ICON_WORK}" && "${ICON_WORK}" == "${PROJECT_DIR}/.build/GrokBot.iconset" ]]; then
    rm -rf "${ICON_WORK}"
  fi
  mkdir -p "${ICON_WORK}"
  for size in 16 32 128 256 512; do
    sips -z "${size}" "${size}" "${BASE_ICON}" --out "${ICON_WORK}/icon_${size}x${size}.png" >/dev/null
    double=$((size * 2))
    sips -z "${double}" "${double}" "${BASE_ICON}" --out "${ICON_WORK}/icon_${size}x${size}@2x.png" >/dev/null
  done
  iconutil -c icns "${ICON_WORK}" -o "${APP_PATH}/Contents/Resources/AppIcon.icns"
fi

codesign --force --sign - --entitlements "${PROJECT_DIR}/Resources/GrokBot.entitlements" "${APP_PATH}"
echo "Built ${APP_PATH}"
