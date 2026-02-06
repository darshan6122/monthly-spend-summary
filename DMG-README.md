# Creating the DMG installer

The project includes a script that builds the app and creates a **drag-and-drop DMG** (like installers you download from the web). When users open the DMG, they see the app and an Applications folder and drag the app to install.

## One-time setup

Install **create-dmg** (used to build the DMG):

```bash
brew install create-dmg
```

## Create the DMG

From the **ExpenseReports** project folder, run:

```bash
./create-dmg.sh
```

This will:

1. Build **ExpenseReports** in Release.
2. Create a DMG with the app icon and an Applications shortcut.
3. Save **ExpenseReports-1.0.dmg** in the project folder and reveal it in Finder.

### Custom version number

Pass a version as the first argument to change the DMG filename:

```bash
./create-dmg.sh 2.0
# Creates ExpenseReports-2.0.dmg
```

## Uninstall options (for users)

- **From the app (recommended):** Open ExpenseReports → app menu → **Uninstall ExpenseReports…** → confirm. No permission or Gatekeeper issues. See [README.md](README.md#uninstalling).
- **Uninstall .command:** You can copy **Uninstall ExpenseReports.command** and **Uninstall-Instructions.txt** into the DMG (or share them separately) for users who prefer a double-click uninstaller. If macOS blocks the .command, users right-click → Open (see Uninstall-Instructions.txt).

## Optional: custom background or volume icon

- **Background image:** Add a PNG (e.g. `dmg-background.png`) in the project, then in `create-dmg.sh` add after the other `create-dmg` options:  
  `--background "$PROJECT_DIR/dmg-background.png" \`
- **Volume icon:** Use your app's `.icns` (e.g. from the built app's `Contents/Resources`) and add:  
  `--volicon "/path/to/AppIcon.icns" \`

Then run `./create-dmg.sh` again.

## Code signing and notarization

To avoid "unidentified developer" warnings on other Macs, sign and notarize the app or DMG with an Apple Developer account. See **[NOTARIZE.md](NOTARIZE.md)** for step-by-step instructions.
