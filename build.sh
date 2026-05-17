#!/usr/bin/env bash
# Vault — produit un .app bundle macOS sans dépendre d'Xcode complet.
set -euo pipefail
cd "$(dirname "$0")"

# Utilise les Command Line Tools (suffisant : SwiftUI / SwiftCharts sont dans le SDK macOS).
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Library/Developer/CommandLineTools}"

CONFIG="${CONFIG:-release}"
APP_NAME="Vault"
APP_DIR="$APP_NAME.app"
BIN_DIR="$APP_DIR/Contents/MacOS"
RES_DIR="$APP_DIR/Contents/Resources"

echo "→ Compilation Swift ($CONFIG)…"
swift build -c "$CONFIG"

BIN_PATH=$(swift build -c "$CONFIG" --show-bin-path)

echo "→ Construction du bundle $APP_DIR"
rm -rf "$APP_DIR"
mkdir -p "$BIN_DIR" "$RES_DIR"

cp "$BIN_PATH/$APP_NAME" "$BIN_DIR/$APP_NAME"
cp "Bundle/Info.plist" "$APP_DIR/Contents/Info.plist"

# Signature ad-hoc (nécessaire pour l'écriture en Application Support sans avertissement)
codesign --force --deep --sign - "$APP_DIR" >/dev/null 2>&1 || true

echo "✓ Build terminé : $(pwd)/$APP_DIR"
echo "  Lance avec :  open $APP_DIR"
