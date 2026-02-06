# Monthly Spend Summary

Turn your **CIBC bank CSV exports** into a **monthly spending summary** and Excel report. A macOS app built with SwiftUI.

## What it does

- **Merge** CIBC CSV files from a chosen month into one combined file
- **Generate** an Excel report (Transactions, Summary, By Category) with suggested categories so you can see what you spent and where
- **One data folder** — the app uses a fixed folder in Application Support; you add one folder per month (e.g. "December 2025") with your CSVs inside

## Install

1. Download **ExpenseReports-1.0.dmg** (from [Releases](https://github.com/darshan6122/monthly-spend-summary/releases) or your build).
2. Open the DMG and drag **ExpenseReports** into **Applications**.
3. Open **Monthly Reports** from Applications. On first run, follow the in-app setup (add your month folders, copy helper scripts if needed).

**Requirements:** macOS. The app uses Python scripts for reports; one-time setup may require Python 3 with `openpyxl` in the app's data folder (see in-app instructions).

## Uninstalling

- **From the app (recommended):** Open ExpenseReports → menu **ExpenseReports** (or **Monthly Reports**) → **Uninstall ExpenseReports…** → confirm. The app quits and removes itself and all support files. No Gatekeeper or permission prompts.
- **Double-click uninstaller:** Use **Uninstall ExpenseReports.command** (e.g. from the DMG or project folder). If macOS blocks it, right-click → **Open** → **Open** once; see **Uninstall-Instructions.txt** for details.

## Build from source (optional)

If you want to build and run from Xcode instead of using the DMG:

1. Open `ExpenseReports.xcodeproj` in Xcode.
2. Select the **ExpenseReports** scheme and run (⌘R).
3. First run: add your month folders to the app's data folder (use **Open Data Folder** in the app) and complete the in-app setup.

**Requirements:** Xcode, macOS. Python 3 with `openpyxl` is used by the app's scripts (one-time setup in the data folder).

## Creating the DMG (for maintainers)

To build a **drag-and-drop DMG** for distribution:

1. Install [create-dmg](https://github.com/create-dmg/create-dmg): `brew install create-dmg`
2. From the project folder run: `./create-dmg.sh`
3. The script builds the app in Release and creates **ExpenseReports-1.0.dmg**. See **[DMG-README.md](DMG-README.md)** for details and options.

## Project structure

- **ExpenseReports/** — main app (SwiftUI views, `AccountsHelper`, `UninstallHelper`)
- **ExpenseReportsTests/** — unit tests
- **ExpenseReportsUITests/** — UI tests
- **create-dmg.sh** — build and create DMG installer (see DMG-README.md)
- **uninstall.sh** — command-line uninstall script
- **Uninstall ExpenseReports.command** — double-click uninstaller for distribution
- **Uninstall-Instructions.txt** — instructions when the .command is blocked by macOS
- **DMG-README.md** — DMG creation and options

The app displays as **Monthly Reports** and uses the data folder:  
`~/Library/Application Support/ExpenseReports/Accounts`

### URL scheme (Shortcuts / automation)

You can trigger a report from Shortcuts or the command line using the custom URL scheme:

- **monthlyreports://run/December%202025** — Opens the app, selects that month (if it exists), and runs **Merge & Create Report**.

Example in Terminal: `open "monthlyreports://run/December%202025"`

## License

**All rights reserved.** This project is not licensed for public use. You may not use, copy, modify, or distribute this code without permission from the owner. See [LICENSE](LICENSE) for details.
