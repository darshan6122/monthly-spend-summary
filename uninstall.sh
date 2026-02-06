#!/usr/bin/env bash
# Uninstall ExpenseReports and all associated files (app, preferences, caches, etc.).

set -e

APP_NAME="ExpenseReports"
BUNDLE_ID="DarshanBodara.ExpenseReports"

# Paths to remove
APP_PATH="/Applications/${APP_NAME}.app"
PATHS=(
    "$APP_PATH"
    "$HOME/Library/Application Support/${APP_NAME}"
    "$HOME/Library/Application Support/${BUNDLE_ID}"
    "$HOME/Library/Caches/${BUNDLE_ID}"
    "$HOME/Library/Containers/${BUNDLE_ID}"
    "$HOME/Library/Preferences/${BUNDLE_ID}.plist"
    "$HOME/Library/Saved Application State/${BUNDLE_ID}.savedState"
    "$HOME/Library/Logs/${APP_NAME}"
    "$HOME/Library/Logs/${BUNDLE_ID}"
)

echo "This will remove ${APP_NAME} and all its data:"
echo ""
for p in "${PATHS[@]}"; do
    if [[ -e "$p" ]]; then
        echo "  • $p"
    fi
done
echo ""

# Check if anything exists
FOUND=0
for p in "${PATHS[@]}"; do
    [[ -e "$p" ]] && FOUND=1 && break
done
if [[ $FOUND -eq 0 ]]; then
    echo "No ${APP_NAME} files found. Nothing to uninstall."
    exit 0
fi

read -p "Continue? [y/N] " -n 1 -r
echo
if [[ ! $REPLY =~ ^[yY]$ ]]; then
    echo "Cancelled."
    exit 0
fi

# Quit the app if running
if pgrep -x "${APP_NAME}" &>/dev/null; then
    echo "Quitting ${APP_NAME}..."
    osascript -e "quit app \"${APP_NAME}\"" 2>/dev/null || killall "${APP_NAME}" 2>/dev/null || true
    sleep 1
fi

echo "Removing..."
for p in "${PATHS[@]}"; do
    if [[ -e "$p" ]]; then
        rm -rf "$p"
        echo "  Removed: $p"
    fi
done

echo ""
echo "Uninstall complete."
