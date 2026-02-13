# ExpenseReports App Audit — What’s Broken and Why

## 1. Keyboard shortcuts not working

### Cause: Menu commands override view shortcuts

On macOS, **menu bar commands (`.commands`) are global** and take precedence over shortcuts on views (toolbar buttons, `NavigationLink`, etc.).

| Shortcut | Intended (ContentView / Finance OS) | What actually happens |
|----------|-------------------------------------|------------------------|
| **⌘1** | Switch to Dashboard (sidebar) | **Reports → “Merge & create report”** runs instead (menu wins). |
| **⌘2–⌘6** | Switch to Transactions / Rules / Budgets / Subscriptions / Settings | May work only when **sidebar has focus**; otherwise no effect. |
| **⌘R** | Subscription “Scan” (toolbar) | **Reports → “Create report only”** runs instead (menu wins). |
| **⌘N** | Add Transaction (Transactions tab) | Can work when the **Transactions** detail is visible and the window has focus; if the app or system reserves ⌘N for “New”, it may be inconsistent. |

**Where it’s defined:**

- **ExpenseReportsApp.swift** `.commands`:  
  - **⌘1** → “Merge & create report”  
  - **⌘R** → “Create report only”
- **ContentView.swift**:  
  - Sidebar: `.keyboardShortcut(sidebarShortcut(for: item), modifiers: .command)` (⌘1–⌘6).  
  - Toolbar: Scan button with ⌘R, Add Transaction (in TransactionListView) with ⌘N.

So **⌘1 and ⌘R never do the Finance OS actions**; the menu always wins.

### Sidebar ⌘1–⌘6 behavior

Even without the menu conflict, **⌘1–⌘6 on `NavigationLink` in a `List`** only work when the **sidebar list has keyboard focus**. If the user is clicking in the detail area (e.g. Transactions list), the sidebar is not focused and these shortcuts do nothing. So:

- **⌘1**: Replaced by menu “Merge & create report”.
- **⌘2–⌘6**: Only work when the sidebar is focused; otherwise they appear broken.

---

## 2. “View report summary” / “Open last report” from menu does nothing

### Cause: `requestShowReportSummary` is never observed

The app menu sets:

- **View report summary** (⌘⇧L) → `helper.requestShowReportSummary = true`
- **Open last report** (when it falls back) → `helper.requestShowReportSummary = true`

**No view in the app** reads `helper.requestShowReportSummary` or presents a sheet when it becomes `true`. So the flag is set, but:

- No sheet is shown.
- The user sees no feedback.

**ReportSummarySheet** exists and is used in other flows (e.g. from ReportCard / QuickLookChart via `onViewSummary()`), but nothing is bound to `requestShowReportSummary`. So **menu-triggered report summary is broken**.

---

## 3. Two different UIs and mental models

The app mixes two flows:

1. **“Finance OS” (SwiftData)**  
   - Sidebar: Dashboard, Transactions, Rules, Budgets, Subscriptions, Settings.  
   - Data: SwiftData (Transaction, CategoryRule, Budget, RecurringItem).  
   - Import: Drag CSV into window.  
   - Shortcuts intended: ⌘1–⌘6 (tabs), ⌘R (Scan), ⌘N (Add transaction).

2. **“Monthly Reports” (folder-based)**  
   - Menu: “Open Data Folder”, “Merge & create report”, “Create report only”, “View report summary”, etc.  
   - Data: `AccountsHelper`, `selectedFolder`, `monthFolders`, files on disk (e.g. `month_summary.json`, merged CSV).  
   - Shortcuts: ⌘1, ⌘R in the Reports menu.

So:

- **Window title** is “Monthly Reports” (folder-based).
- **Sidebar** is “Finance OS” (SwiftData).
- **Menu items** mostly target the folder-based flow; some (e.g. Settings) affect both.
- **Shortcuts** are split and conflicting.

That makes behavior and shortcuts confusing and contributes to “things not working.”

---

## 4. Other potential issues (minor)

- **SettingsView export**: Temp file is removed with `try?`; if the user cancels the save panel we still remove the temp file (correct). If copy fails we don’t show an error (could improve UX).
- **ManualEntryView**: Amount parsing with `Decimal(string:)` can fail for some locales (e.g. comma as decimal separator); no error message is shown.
- **WelcomeView**: Shown only when **Dashboard** is selected and there are no transactions. If the user goes to Transactions first, they see the empty “Drop a CSV” state instead of the welcome screen (by design, but worth being aware of).

---

## Summary table

| Issue | Cause | Severity |
|-------|--------|----------|
| ⌘1 doesn’t switch to Dashboard | Menu “Merge & create report” uses ⌘1 | High |
| ⌘R doesn’t run Scan | Menu “Create report only” uses ⌘R | High |
| ⌘2–⌘6 don’t switch tabs | Sidebar must have focus; no menu/global alternative | Medium |
| “View report summary” from menu does nothing | `requestShowReportSummary` never triggers a sheet | High |
| Two UIs (Finance OS vs Monthly Reports) | Legacy menu + new SwiftData UI both present | Medium (design) |

---

## Fixes applied

1. **Shortcuts**  
   - In **ExpenseReportsApp**: Remove ⌘1 and ⌘R from the Reports menu (or move them to e.g. ⌘⇧1 and ⌘⇧R) so that ContentView’s ⌘1 (Dashboard) and ⌘R (Scan) can work.
2. **Report summary from menu**  
   - ContentView presents ReportSummarySheet when `helper.requestShowReportSummary` is set (menu "View report summary" / "Open last report").
3. **Optional (later)**  
   - Add a **Window → View** (or similar) menu group that explicitly switches sidebar selection (e.g. “Show Dashboard”, “Show Transactions”) with ⌘1–⌘6, so tabs are switchable even when the detail area has focus.
