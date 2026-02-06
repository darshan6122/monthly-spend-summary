#!/usr/bin/env bash
# Build ExpenseReports and create a drag-and-drop DMG installer.
# Requires: Xcode, create-dmg (brew install create-dmg)

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$SCRIPT_DIR"
SCHEME="ExpenseReports"
APP_NAME="ExpenseReports"
VERSION="${1:-1.0}"
DMG_NAME="ExpenseReports-${VERSION}"
BUILD_DIR="$PROJECT_DIR/build"
DMG_SOURCE="$BUILD_DIR/dmg-source"
OUTPUT_DMG="$PROJECT_DIR/${DMG_NAME}.dmg"

# Check for create-dmg
if ! command -v create-dmg &>/dev/null; then
    echo "create-dmg is not installed. Install it with:"
    echo "  brew install create-dmg"
    exit 1
fi

echo "Building $APP_NAME (Release)..."
xcodebuild -scheme "$SCHEME" \
    -configuration Release \
    -derivedDataPath "$BUILD_DIR" \
    -quiet

APP_PATH="$BUILD_DIR/Build/Products/Release/${APP_NAME}.app"
if [[ ! -d "$APP_PATH" ]]; then
    echo "Build failed: $APP_PATH not found."
    exit 1
fi

echo "Preparing DMG contents..."
rm -rf "$DMG_SOURCE"
mkdir -p "$DMG_SOURCE"
cp -R "$APP_PATH" "$DMG_SOURCE/"
# Include uninstaller and instructions in the DMG
if [[ -f "$PROJECT_DIR/Uninstall ExpenseReports.command" ]]; then
    cp "$PROJECT_DIR/Uninstall ExpenseReports.command" "$DMG_SOURCE/"
    chmod +x "$DMG_SOURCE/Uninstall ExpenseReports.command"
fi
if [[ -f "$PROJECT_DIR/Uninstall-Instructions.txt" ]]; then
    cp "$PROJECT_DIR/Uninstall-Instructions.txt" "$DMG_SOURCE/"
fi

# Remove previous DMG if present
rm -f "$OUTPUT_DMG"

echo "Creating DMG..."
create-dmg \
    --volname "Install $APP_NAME" \
    --window-pos 200 120 \
    --window-size 640 420 \
    --icon-size 100 \
    --icon "${APP_NAME}.app" 150 190 \
    --hide-extension "${APP_NAME}.app" \
    --app-drop-link 450 190 \
    "$OUTPUT_DMG" \
    "$DMG_SOURCE/"

echo "Done: $OUTPUT_DMG"
open -R "$OUTPUT_DMG"
