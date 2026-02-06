#!/usr/bin/env bash
# Double-click to uninstall ExpenseReports and all associated files.

# Clear quarantine so double-click works on this and other Macs (e.g. after copying from DMG).
xattr -d com.apple.quarantine "$0" 2>/dev/null || true

APP_NAME="ExpenseReports"
BUNDLE_ID="DarshanBodara.ExpenseReports"

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

FOUND=0
for p in "${PATHS[@]}"; do
    [[ -e "$p" ]] && FOUND=1 && break
done
if [[ $FOUND -eq 0 ]]; then
    echo "No ${APP_NAME} files found. Nothing to uninstall."
    echo ""
    read -p "Press Enter to close."
    exit 0
fi

read -p "Continue? [y/N] " -n 1 -r
echo
if [[ ! $REPLY =~ ^[yY]$ ]]; then
    echo "Cancelled."
    echo ""
    read -p "Press Enter to close."
    exit 0
fi

if pgrep -x "${APP_NAME}" &>/dev/null; then
    echo "Quitting ${APP_NAME}..."
    osascript -e "quit app \"${APP_NAME}\"" 2>/dev/null || killall "${APP_NAME}" 2>/dev/null || true
    sleep 1
fi

remove_path() {
    local p="$1"
    if [[ ! -e "$p" ]]; then return 0; fi
    if rm -rf "$p" 2>/dev/null; then
        echo "  Removed: $p"
        return 0
    fi
    echo "  Need administrator permission for: $p"
    if sudo rm -rf "$p" 2>/dev/null; then
        echo "  Removed: $p"
        return 0
    else
        echo "  Failed to remove: $p"
        return 1
    fi
}

echo "Removing..."
for p in "${PATHS[@]}"; do
    remove_path "$p"
done

echo ""
echo "Uninstall complete."
echo ""
read -p "Press Enter to close."
