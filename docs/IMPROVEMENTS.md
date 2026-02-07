# ExpenseReports – Improvement ideas

Prioritized suggestions across the merge script, report script, app, and docs. Pick what matters most to you.

---

## High impact

### 1. Align categories everywhere (merge ↔ report ↔ app)

Right now three places define categories differently:

- **merge_and_categorize.py:** `CATEGORY_RULES` → e.g. `"Income"`, `"Food & Drink"`, `"Shopping & Groceries"`.
- **make_monthly_report.py:** `ALL_CATEGORIES` + `CATEGORY_RULES` → e.g. `"Work Income"`, `"Food & Drink"`, different order and some different names.
- **AppSettings.swift (CategoryTypes.all):** `"Food & Dining"`, `"Groceries"`, `"Transport"`, etc. – different names and set.

**Effect:** Training sheet dropdown doesn’t match report dropdown; merge can output "Income" while the report expects "Work Income"; Quick Look and Excel can show different category names.

**Improvement:** Choose one source of truth (e.g. `make_monthly_report.py`’s `ALL_CATEGORIES` and rule set) and:

- In **merge_and_categorize.py:** Use the same category names (e.g. "Work Income" instead of "Income") and derive `CATEGORY_RULES` / `ALL_CATEGORIES` from a shared list or a small shared config.
- In **AppSettings.swift:** Set `CategoryTypes.all` to the exact same list as the report’s `ALL_CATEGORIES` (or load from a generated file if you want to avoid manual sync).
- In **Training sheet:** Use the same list so saved mappings always match the report.

---

### 2. Report script: optionally use merge output for categories

`make_monthly_report.py` re-reads raw CIBC CSVs and re-categorizes with its own regex. So Excel categories can differ from `merged.csv` / Quick Look.

**Improvement:** Add an option (e.g. env flag or “use merged data” mode) so the report script can:

- Read `{Month}_combined.csv` or `merged.csv` for the chosen month instead of raw CSVs, and
- Use the **Category** column from the merge (Mapping → Regex → ML) instead of calling `suggest_category()` again.

That way one categorization pipeline drives both the app’s Quick Look and the Excel report.

---

### 3. Surface categorization stats in the app

The merge script already logs: *"Categorized X via Mapping, Y via Regex, Z via ML."*

**Improvement:** Write those counts into `audit.json` (e.g. `categorized_via_mapping`, `categorized_via_regex`, `categorized_via_ml`, `uncategorized`). In the app, show a short line in Data Health or next to the merge button, e.g. “This month: 12 mapping, 89 regex, 3 ML, 2 uncategorized.” Helps you see that Training and ML are actually being used.

---

### 4. Update docs to match current behavior

- **README.md** still says “TF-IDF/Random Forest” and “merge script uses them”; the merge now uses Custom Mapping → Regex → **LogisticRegression** (with char TF-IDF). Update that sentence and any “Smart Category” description.
- **docs/ML-CATEGORY-MODEL.md** still says “no ML”, “merge does not read custom_mapping”. Update it to describe the current 3-step pipeline and point to `merge_and_categorize.py` and this doc for improvements.

---

## Medium impact

### 5. Cache the trained model (merge script)

Today the classifier is retrained on every run. With more history and a larger `custom_mapping.json`, that can get slower.

**Improvement:** After training, pickle the vectorizer and model (and a hash of `custom_mapping.json` + paths of the merged.csv files used). On the next run, if the hash is unchanged, load the pickle and skip `fit()`. Retrain only when mapping or historical data changed.

---

### 6. Config file for categories and rules

Keep category names and regex rules in a single config (e.g. `category_rules.json` or `category_config.json` in the Accounts folder) so you can add merchants or categories without editing Python. Merge and report scripts (and optionally the app) read from that file. Falls back to built-in rules if the file is missing.

---

### 7. Training sheet: category list from report

Have the Training sheet’s category picker use the same list as the Excel report (e.g. from `ALL_CATEGORIES` in the report script, or from a shared config). Right now `CategoryTypes.all` in the app is a different set; aligning it (see #1) fixes this.

---

### 8. Merge script: normalize ML predictions to allowed list

ML might occasionally output a category that’s not in the report’s dropdown (e.g. from old training data). Before assigning the ML prediction, check it’s in `ALL_CATEGORIES` (or the report’s list); if not, treat as Uncategorized or map to the closest allowed category.

---

## Nice to have

### 9. Unit tests for the classifier

Add a small test module (e.g. `test_merge_categorize.py`) that:

- Builds a `TransactionClassifier` with a temp dir, a minimal `custom_mapping.json`, and optional historical merged CSVs.
- Asserts Step 1 (mapping) and Step 2 (regex) give expected categories for a few fixed strings.
- Optionally checks that Step 3 is skipped when there are &lt; 10 samples, and that when trained, predictions respect the confidence threshold.

---

### 10. Slightly better error handling when scripts fail

`runScript` in AccountsHelper already returns success/message. You could extend the audit or script output so that on failure the app can show “Merge failed: …” with the last few stderr lines (or a script exit code), and maybe a “Copy error” button for support.

---

### 11. Export Training data / backup custom_mapping

Allow exporting `custom_mapping.json` (or a CSV of description → category) from the app for backup or use in another machine. Optionally allow importing so you can restore or merge mappings.

---

### 12. Duplicate detection across same file

Currently duplicates are only detected when the same transaction appears in **different** CSV files. If the bank export sometimes has the same row twice in one file, you could optionally detect and skip those as well (e.g. same Date + Description + Amount within one file).

---

## Summary table

| Area        | Improvement                              | Effort |
|------------|-------------------------------------------|--------|
| Consistency| Align categories (merge / report / app)   | Medium |
| Report     | Use merge categories in Excel optionally  | Medium |
| App        | Show categorization stats from audit      | Small  |
| Docs       | Update README + ML-CATEGORY-MODEL.md      | Small  |
| Merge      | Cache trained model                       | Medium |
| Config     | External config for categories/rules      | Medium |
| App        | Training categories = report list         | Small (if #1 done) |
| Merge      | Sanity-check ML output against allowed list | Small |
| Tests      | Unit tests for classifier                 | Small  |
| App        | Clearer script error reporting            | Small  |
| App        | Export/import custom_mapping              | Small  |
| Merge      | Same-file duplicate detection             | Small  |

If you tell me which ones you want to do first (e.g. “1, 2, and 3”), I can implement them step by step.
