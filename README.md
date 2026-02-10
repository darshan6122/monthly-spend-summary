# Monthly Spend Summary

Turn your **CIBC bank CSV exports** into a **monthly spending summary** and Excel report. A macOS app built with SwiftUI.

## What it does

- **Merge** CIBC CSV files from a chosen month into one combined file
- **Generate** an Excel report (Transactions, Summary, By Category) with suggested categories so you can see what you spent and where
- **One data folder** — the app uses a fixed folder in Application Support; you add one folder per month (e.g. "December 2025") with your CSVs inside

### Extra features

- **Smart Category Trainer** — In **Train categories** you can assign a category to any transaction the script didn’t recognize. Corrections are saved to `custom_mapping.json` The merge script uses a 3-step pipeline: **Custom Mapping** → **Regex rules** → **ML fallback** (char TF-IDF + LogisticRegression when `scikit-learn` is installed; model is cached so re-runs are fast).
- **Month-over-month insights** — After a report is generated, a **Quick Stats** bar shows spending vs last month, category alerts (e.g. “Dining is up $150”), and **Transfer to Savings** when present.
- **Data Health** — A **Data Health** view shows a simple reconciliation (total credits vs debits, file count) and warns when duplicate transactions were detected and ignored.
- **Quick Look dashboard** — A bar chart of spending by category is shown from the merged CSV (no Excel needed). It updates when you switch months with the month pills.
- **Drag-and-drop CSV import** — Drag a CIBC CSV onto the app window; the app detects the month from the file (or creation date) and moves it into the correct month folder (creating it if needed).
- **Batch regenerate** — In **Settings**, use **Regenerate all reports** to re-run merge + report for every month folder (e.g. after updating `custom_mapping.json`).
- **Watch Downloads** — In Settings, enable **Watch Downloads for new bank CSV**; when a `cibc*.csv` appears in ~/Downloads, the app offers to move it to your data folder.
- **ML confidence** — In Settings, adjust the **ML confidence threshold** (strict = fewer auto-categories; loose = more ML guesses).
- **Ignore list** — In your data folder, add `ignore_list.json` (array of description substrings). Transactions whose description contains any entry are excluded from the merge. See `docs/ignore_list.example.json`.
- **Split transactions** — In **More → Split transactions**, split a single transaction into multiple categories (e.g. Costco: $60 Groceries, $40 Pharmacy). Stored in `transaction_splits.json` per month; re-run report to apply.
- **Sparklines & forecasting** — Quick Stats shows a 6-month trend for top categories and “On track to spend $X this month” when you have partial data.
- **Calendar heatmap** — **More → Calendar heatmap** shows spending by day for the selected month (darker = more spent).
- **Sankey diagram** — In **Year in review**, **View Sankey diagram** opens an HTML flow (Income → categories) in your browser.
- **Tax / Export packet** — **More → Tax report…** lets you select categories (e.g. Health, Donations) and export a CSV of totals across all months.
- **Custom Excel template** — Put `template.xlsx` in your data folder; the report script will use it and add Transactions, Summary, and By Category sheets.
- **HTML dashboard** — If `plotly` is installed, the report script also writes `dashboard.html` per month (bar chart of spending by category).
- **Bank profiles** — Add `profiles.json` in your data folder to support RBC, TD, or other CSVs via column mapping. See `docs/profiles.example.json`.
- **Excel dark mode** — Report styling uses light gray fills and dark text so sheets are readable in Excel’s Dark Mode.
- **Subscription Hunter** — **Recurring transactions** lists “Active subscriptions” (same amount in 2+ months) and total monthly.
- **Inflation tracker** — **More → Inflation tracker** compares average transaction amount at the same merchant year-over-year.
- **Secrets** — Use `KeychainHelper.set(_:forKey:)` / `KeychainHelper.get(forKey:)` in code for API keys (e.g. future bank API).

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

**Canonical location:** All app source and scripts live under **Desktop/ACCOUNTS/ExpenseReports** (this repo).

- **ExpenseReports/** — main app (SwiftUI views, `AccountsHelper`, `UninstallHelper`, `InsightsModels`)
- **Scripts/** — Python scripts: `merge_and_categorize.py`, `make_monthly_report.py`, `requirements.txt`. The app copies these into its **data folder** when you use **Copy from Desktop** (it looks for `Desktop/ACCOUNTS/ExpenseReports` and copies from `Scripts/` and `.venv`).
- **ExpenseReportsTests/** — unit tests
- **ExpenseReportsUITests/** — UI tests
- **create-dmg.sh** — build and create DMG installer (see DMG-README.md)
- **uninstall.sh** — command-line uninstall script
- **Uninstall ExpenseReports.command** — double-click uninstaller for distribution
- **Uninstall-Instructions.txt** — instructions when the .command is blocked by macOS
- **DMG-README.md** — DMG creation and options

**Data folder (runtime):** The app uses a separate data folder for month folders and generated reports (Excel). Default:  
`~/Library/Application Support/ExpenseReports/Accounts`  
Scripts are copied there from **ExpenseReports/Scripts** so the Excel report and month summary are created inside each month folder.

### URL scheme (Shortcuts / automation)

You can trigger a report from Shortcuts or the command line using the custom URL scheme:

- **monthlyreports://run/December%202025** — Opens the app, selects that month (if it exists), and runs **Merge & Create Report**.

Example in Terminal: `open "monthlyreports://run/December%202025"`

## License

**All rights reserved.** This project is not licensed for public use. You may not use, copy, modify, or distribute this code without permission from the owner. See [LICENSE](LICENSE) for details.
