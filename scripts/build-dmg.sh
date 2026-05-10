#!/usr/bin/env bash
# Gera Thunar.dmg para distribuição (sem Developer ID).
# Uso: ./scripts/build-dmg.sh

set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$PROJECT_DIR"

APP_NAME="Thunar"
BUILD_DIR="build"
APP_PATH="${BUILD_DIR}/Build/Products/Release/${APP_NAME}.app"
STAGING_DIR="dmg-staging"

echo "==> Compilando Release..."
xcodebuild -project thunar.xcodeproj \
  -scheme thunar \
  -configuration Release \
  -derivedDataPath "${BUILD_DIR}" \
  clean build | tail -5

if [ ! -d "${APP_PATH}" ]; then
  echo "Falha: ${APP_PATH} nao foi gerado." >&2
  exit 1
fi

VERSION=$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" "${APP_PATH}/Contents/Info.plist")
BUILD_NUMBER=$(/usr/libexec/PlistBuddy -c "Print CFBundleVersion" "${APP_PATH}/Contents/Info.plist" 2>/dev/null || echo "")

if [ -n "${BUILD_NUMBER}" ] && [ "${BUILD_NUMBER}" != "${VERSION}" ]; then
  DMG_NAME="${APP_NAME}-${VERSION}-${BUILD_NUMBER}.dmg"
else
  DMG_NAME="${APP_NAME}-${VERSION}.dmg"
fi

echo "==> Montando DMG (${DMG_NAME})..."
rm -rf "${STAGING_DIR}" "${DMG_NAME}"
mkdir -p "${STAGING_DIR}"
cp -R "${APP_PATH}" "${STAGING_DIR}/"
ln -s /Applications "${STAGING_DIR}/Applications"

hdiutil create \
  -volname "${APP_NAME}" \
  -srcfolder "${STAGING_DIR}" \
  -ov -format UDZO \
  "${DMG_NAME}" >/dev/null

rm -rf "${STAGING_DIR}"

echo "==> Pronto: ${DMG_NAME} ($(du -h "${DMG_NAME}" | cut -f1))"
