# ExpenseReports — User-Facing Flaws Audit

A list of issues a user would likely run into while using the app, ordered by area.

---

## Data & Persistence

### 1. **Rules and budgets may not persist**
- **Where:** RulesView (Add Rule), BudgetSettingsView (Save Budget / delete).
- **What:** After adding a rule or saving/editing/deleting a budget, the code never calls `modelContext.save()`.
- **Result:** Changes can be lost if the app is quit or crashes before an autosave runs. User may reopen the app and find new rules or budget changes missing.
- **Fix:** Call `try? modelContext.save()` after `addRule()`, `saveBudget()`, and `deleteBudgets()`.

### 2. **No Restore from backup**
- **Where:** Settings → Data Management.
- **What:** User can only **Export** a JSON backup. There is no “Import backup” or “Restore from file.”
- **Result:** After “Reset All Data” or a reinstall, the only way to get data back is to re-import CSVs and re-create rules/budgets manually.
- **Fix:** Add a “Restore from backup” flow that reads the JSON and inserts transactions, rules, budgets, and recurring items (with duplicate/conflict handling).

### 3. **Export backup: no feedback on failure**
- **Where:** Settings → Export Backup (JSON).
- **What:** If `BackupManager.createBackup` returns nil or the file copy fails, the user gets no message.
- **Result:** User clicks Export, maybe picks a location, and sees nothing happen or no file; they don’t know if it failed or where the file went.
- **Fix:** Show an alert or toast on failure (“Backup failed” / “Could not save file”) and, on success, e.g. “Backup saved to …”.

### 4. **Duplicate rule keyword can crash or error**
- **Where:** RulesView → Add Rule.
- **What:** `CategoryRule` has `@Attribute(.unique) var keyword`. Adding a second rule with the same keyword can cause a SwiftData uniqueness violation.
- **Result:** Possible crash or unhandled error; no user-visible “This keyword already exists.”
- **Fix:** Before insert, check if a rule with that keyword exists; if so, show an alert or update the existing rule instead of inserting again.

---

## Two parallel systems (confusion)

### 5. **“Report summary” and menu depend on folder, not SwiftData**
- **Where:** App menu “View report summary” (⌘⇧L), “Open last report,” and the sheet that shows “Report summary — \(helper.selectedFolder)”.
- **What:** That sheet and those commands use `AccountsHelper.selectedFolder` and `loadMonthSummary(monthFolder:)`, i.e. the **folder-based** report system (merged CSVs, month folders, etc.), not the SwiftData transactions the user sees in the app.
- **Result:** A user who only uses “Finance OS” (drag CSV, Dashboard, Transactions) may never set a folder. The report summary sheet can show an empty or irrelevant month, and “View report summary” / “Open last report” feel broken or confusing.
- **Fix:** Either (a) drive report summary from SwiftData (e.g. current month’s transactions) when no folder is set, or (b) clearly separate “Folder-based reports” from “Finance OS” and disable/hide report summary when the user hasn’t chosen a folder.

### 6. **Window title and menu don’t match the main UI**
- **Where:** Window title “Monthly Reports”; menu items “Merge & create report,” “Open Data Folder,” “View report summary,” etc.
- **What:** The main UI is “Finance OS” (sidebar: Dashboard, Transactions, Rules, Budgets, Subscriptions, Settings). The window and many menu items refer to the older “Monthly Reports” / folder workflow.
- **Result:** New users don’t know what “Merge & create report” or “Open Data Folder” do, or why the window says “Monthly Reports” when the app looks like “Finance OS.”
- **Fix:** Rename window to “Finance OS” or “ExpenseReports” and/or add a “Reports” or “Legacy” section in the menu and short help text so the two workflows are clear.

---

## Manual entry & input

### 7. **Manual entry: amount parsing and no income**
- **Where:** Transactions → Add Transaction (⌘N) → ManualEntryView.
- **What:** Amount is parsed with `Decimal(string:)`, which in many locales expects a period as decimal separator. Comma (e.g. “12,50”) can fail; no error is shown. The flow is “Add Expense” only (amount is negated); there’s no “Income” option.
- **Result:** Users in locale with comma decimals may think the app “ignores” the amount or saves 0. Users who want to log income (e.g. cash deposit) have to enter a negative amount as a workaround.
- **Fix:** Normalize amount string (e.g. replace comma with period) or use a locale-aware number formatter; show “Invalid amount” if parsing fails. Optionally add an Income/Expense toggle or separate income entry.

### 8. **Manual entry: no feedback if save fails**
- **Where:** ManualEntryView → Save.
- **What:** `try? modelContext.save()` ignores errors; the sheet always dismisses.
- **Result:** If save fails (e.g. constraint, disk full), the user loses the entered data and gets no explanation.
- **Fix:** Check save result; on failure, show an alert and do not dismiss the sheet.

### 9. **Budget amount: numbers only**
- **Where:** BudgetSettingsView → Amount field.
- **What:** `saveBudget()` uses `trimmed.filter { $0.isNumber || $0 == "." }`; a comma decimal or currency symbol is stripped, which can change or break the value.
- **Result:** “100,00” or “$100” may be misparsed or rejected.
- **Fix:** Same as manual entry: normalize or use a proper number parser and show validation errors.

---

## CSV import

### 10. **Re-importing the same CSV can create duplicates**
- **Where:** Dropping a CSV file onto the window.
- **What:** Transactions are inserted every time. There is no check for “same file + same rows already imported” (Transaction has unique `id` per row, but re-exporting the same bank CSV can generate new UUIDs or same data with different IDs).
- **Result:** User drags the same CSV again (e.g. by mistake) and gets duplicate transactions.
- **Fix:** Deduplicate by (e.g.) date + description + amount + source file, or offer “Replace/Update” vs “Add new only” when dropping.

### 11. **Import errors only in banner**
- **Where:** Dropping a CSV; failed parse shows `lastImportMessage = "Failed to import ..."`.
- **What:** Message is shown in a dismissible banner at the top of the Transactions list. If the user is on Dashboard or another tab, they may never see it.
- **Result:** User drops a CSV, switches to Dashboard, and doesn’t know the import failed.
- **Fix:** Show a modal or global toast for import failure, or switch to Transactions and show the banner there automatically.

### 12. **No progress for large CSVs**
- **Where:** CSV drop.
- **What:** No progress indicator; parsing and insert happen synchronously.
- **Result:** For large files, the UI can freeze with no indication that work is in progress.
- **Fix:** Run import in a task, show a progress or “Importing…” overlay, and show success/failure when done.

---

## Dashboard & charts

### 13. **Donut chart not interactive**
- **Where:** Dashboard → Spending Breakdown (donut).
- **What:** The donut shows categories but is not tappable/clickable. Phase 9 text mentioned “click to filter” or “deep dive.”
- **Result:** User expects to tap a slice (e.g. “Food”) to see only those transactions but nothing happens.
- **Fix:** Add chart selection (e.g. `chartAngleSelection`) and either filter the dashboard by category or switch to Transactions with a category filter/search.

### 14. **Budget Health only for “this month”**
- **Where:** Dashboard → Budget Health.
- **What:** Budget limits are monthly; “spent” is for the selected month only. There’s no indication that it’s “this month” vs “all time” or that changing the month picker changes the budget comparison.
- **Result:** User can think the budget is “total” or “all time” and misinterpret over/under.
- **Fix:** Label explicitly e.g. “Budget Health (January 2025)” or “Spent this month vs limit.”

### 15. **Many categories: bar chart and list get crowded**
- **Where:** Dashboard → bar chart and category list below.
- **What:** With many categories, the bar chart and the list become hard to read; no scrolling or “top N” option.
- **Result:** Cluttered or truncated labels and a long list.
- **Fix:** Limit to top N categories in the chart, add “Show all” in the list with scrolling, or make the chart scrollable.

---

## Subscriptions

### 16. **Subscription scan only adds, never updates**
- **Where:** SubscriptionScanner; “Scan” (⌘R).
- **What:** Scan only inserts new `RecurringItem`s when the name isn’t in `existingNames`. It doesn’t update amount or last date for existing items.
- **Result:** If a subscription price changes or the user edits transactions, the subscription list stays stale until they delete and re-scan (and then they might get duplicates if names differ).
- **Fix:** When a matching name exists, update amount and/or last paid date instead of skipping.

### 17. **No way to “reactivate” a subscription**
- **Where:** SubscriptionsView → swipe to delete (deactivate).
- **What:** Deactivation sets `isActive = false`. There’s no UI to turn it back on.
- **Result:** User accidentally swipes; the subscription disappears from the list with no undo or “Show inactive” / “Reactivate.”
- **Fix:** Add “Show inactive” and a “Reactivate” action, or an Undo toast after deactivate.

---

## Menu bar & global behavior

### 18. **Menu bar popover doesn’t close on “Open Finance OS”**
- **Where:** Menu bar icon → popover → “Open Finance OS.”
- **What:** Button calls `NSApp.activate(ignoringOtherApps: true)`. Popover has `.transient` behavior; whether it closes when the main window becomes key is platform-dependent.
- **Result:** Popover may stay open and cover part of the main window, or close only after a click outside.
- **Fix:** Explicitly close the popover in the button action, e.g. `menuBarManager.popover.performClose(nil)` (if you have a reference to the manager from the view).

### 19. **Menu bar shows “Today’s Spend” with no date context**
- **Where:** MenuBarView.
- **What:** “Today’s Spend” is clear, but “Recent” is just the last 3 transactions by date (newest first) with no “as of today” or time context.
- **Result:** Minor: user might assume “Recent” is “today’s” transactions; it’s actually global latest.
- **Fix:** Optionally label “Recent (latest)” or “Last 3 transactions.”

### 20. **Menu bar popover can show stale data**
- **Where:** MenuBarView is created once and set as `popover.contentViewController`.
- **What:** The hosting controller’s SwiftUI view uses `@Query`, but the popover might not refresh until the next time it’s shown or the main window updates.
- **Result:** User adds a transaction in the main window, clicks the menu bar icon, and still sees old “Today’s Spend” or “Recent.”
- **Fix:** Ensure the menu bar view is bound to the same model container and that SwiftData updates propagate (e.g. avoid holding a stale snapshot); if needed, refresh or recreate the content when the popover is shown.

---

## Settings & reset

### 21. **Reset All Data has no undo**
- **Where:** Settings → Reset All Data.
- **What:** Confirmation alert then permanent delete of all transactions, rules, budgets, subscriptions. No “Are you absolutely sure?” or “Type DELETE to confirm.”
- **Result:** Accidental tap or misread can wipe everything.
- **Fix:** Add a second confirmation or a required text confirmation (e.g. “Type RESET to confirm”).

### 22. **Two “Settings” entry points**
- **Where:** Sidebar “Settings” (Finance OS) vs toolbar “Settings” button.
- **What:** Sidebar opens the SwiftData Settings (backup, reset, about). Toolbar opens the legacy `SettingsSheet` (tips, ML threshold, merge, reports, etc.).
- **Result:** User doesn’t know which “Settings” to use for what; feels like two different apps.
- **Fix:** Merge into one Settings screen with sections (Data & backup | Reports & folder | Tips & ML), or rename one (e.g. “Data & backup” in sidebar, “Report options” in toolbar).

---

## Accessibility & polish

### 23. **No VoiceOver / accessibility labels on charts**
- **Where:** Dashboard charts (donut, bar), insight cards.
- **What:** Chart segments and key numbers may not have accessible labels or hints.
- **Result:** Screen-reader users get little or no useful description of the chart.
- **Fix:** Add `.accessibilityLabel` / `.accessibilityValue` to chart containers and key figures.

### 24. **Empty states not consistent**
- **Where:** Transactions (empty), Subscriptions (empty), Dashboard (no data for month), Rules (no rules), Budgets (no budgets).
- **What:** Some use `ContentUnavailableView`, others plain text; wording and tone vary.
- **Result:** Inconsistent feel and some empty states less helpful than others.
- **Fix:** Standardize on `ContentUnavailableView` with icon + title + description + optional action where it makes sense.

### 25. **Logos load in background with no retry**
- **Where:** Transaction list → MerchantLogoView.
- **What:** If Clearbit/Google favicon fails, the view shows the initial and doesn’t retry. User has no way to “Refresh logo” for a row.
- **Result:** Some merchants stay as initials forever; user can’t fix it.
- **Fix:** Optional “Retry” on long-press or a global “Refresh logos” in Settings; optionally show a small “failed” state so the user knows it’s not just slow.

---

## Summary table

| # | Area            | Flaw (short)                                      | Severity |
|---|-----------------|---------------------------------------------------|----------|
| 1 | Data            | Rules/budgets not saved explicitly                | High     |
| 2 | Data            | No restore from backup                           | High     |
| 3 | Data            | Export backup failure has no feedback             | Medium   |
| 4 | Data            | Duplicate rule keyword can crash                  | Medium   |
| 5 | Two systems     | Report summary depends on folder, not SwiftData  | High     |
| 6 | Two systems     | Window/menu name vs “Finance OS”                  | Medium   |
| 7 | Manual entry    | Amount locale (comma) + no income option          | Medium   |
| 8 | Manual entry    | Save failure not shown                            | Medium   |
| 9 | Budgets         | Amount input locale/format                        | Low      |
|10 | CSV             | Re-import creates duplicates                     | High     |
|11 | CSV             | Import error only in Transactions banner         | Medium   |
|12 | CSV             | No progress for large files                      | Low      |
|13 | Dashboard       | Donut not clickable to filter                     | Medium   |
|14 | Dashboard       | Budget health “this month” not labeled            | Low      |
|15 | Dashboard       | Many categories clutter chart/list               | Low      |
|16 | Subscriptions   | Scan doesn’t update existing items               | Medium   |
|17 | Subscriptions   | No reactivate after deactivate                   | Low      |
|18 | Menu bar        | Popover may not close on Open app                 | Low      |
|19 | Menu bar        | “Recent” label ambiguous                          | Low      |
|20 | Menu bar        | Popover data can be stale                         | Medium   |
|21 | Settings        | Reset has no strong confirmation                 | Medium   |
|22 | Settings        | Two different Settings entry points              | Medium   |
|23 | A11y            | Charts not fully accessible                       | Low      |
|24 | Polish          | Empty states inconsistent                        | Low      |
|25 | Polish          | Logo fetch no retry / feedback                   | Low      |

---

**Suggested order to fix first:** 1 (persist rules/budgets), 2 (restore backup), 5 (report summary vs SwiftData), 10 (CSV duplicates), 22 (unify Settings), then 3, 4, 7, 8, 11.
