#!/usr/bin/env bash
set -euo pipefail

APP_NAME="CodexMonitor"
SCHEME="CodexMonitor"
CONFIGURATION="Release"
DERIVED_DATA_DIR=".build/xcode"
DIST_DIR="dist"
APP_DIR="$DIST_DIR/$APP_NAME.app"
BUILT_APP="$DERIVED_DATA_DIR/Build/Products/$CONFIGURATION/$APP_NAME.app"

if command -v xcodegen >/dev/null 2>&1; then
  xcodegen generate
elif [[ ! -d "$APP_NAME.xcodeproj" ]]; then
  echo "xcodegen is required to generate $APP_NAME.xcodeproj" >&2
  exit 1
fi

xcodebuild \
  -project "$APP_NAME.xcodeproj" \
  -scheme "$SCHEME" \
  -configuration "$CONFIGURATION" \
  -derivedDataPath "$DERIVED_DATA_DIR" \
  CODE_SIGN_IDENTITY=- \
  CODE_SIGN_STYLE=Manual \
  build

if [[ ! -d "$BUILT_APP" ]]; then
  echo "Expected build output not found: $BUILT_APP" >&2
  exit 1
fi

rm -rf "$APP_DIR"
mkdir -p "$DIST_DIR"
cp -R "$BUILT_APP" "$APP_DIR"

echo "Built $APP_DIR"

if [[ "${1:-}" == "--install" ]]; then
  INSTALL_PATH="/Applications/$APP_NAME.app"
  rm -rf "$INSTALL_PATH"
  cp -R "$APP_DIR" "$INSTALL_PATH"
  echo "Installed to $INSTALL_PATH"
  open "$INSTALL_PATH"
fi
