# Category prediction model (for improvements)

## Current state

- **Merge script** (`Scripts/merge_and_categorize.py`): **3-step waterfall** — (1) Custom mapping from `custom_mapping.json`, (2) Regex rules (or `category_rules.json`), (3) ML fallback (char TF-IDF + LogisticRegression). Model cached in `.ml_cache/classifier.pkl`. Optional **`category_rules.json`** in the Accounts folder: `{"categories": [...], "rules": [{"pattern": "...", "category": "..."}]}` — see `docs/category_rules.example.json`.
- **App Training sheet**: Lets you assign a category to a transaction description and writes to **`custom_mapping.json`** in the Accounts folder. Merge script uses it in step 1.
- **Report script** (`make_monthly_report.py`): When **`USE_MERGED_CATEGORIES=1`** (app), uses the merge's Suggested Category; otherwise re-categorizes from raw CSVs. Both scripts can load **`category_rules.json`** from the Accounts folder.


---

## Intended ML design (Smart Category)

### Goal

Predict **category** for a transaction from its **description** (e.g. `"STARBUCKS #12345"` → `"Food & Drink"`), using:

1. **Exact/custom rules** from the user (e.g. `custom_mapping.json`: description substring → category).
2. **Keyword/regex rules** (fast, interpretable).
3. **Optional ML fallback** when (1) and (2) don’t match, trained on the user’s past corrections so it gets better over time.

### Data

- **Input**: One string per transaction, e.g. `"INTERAC E-TRANSFER FROM JOHN DOE"`.
- **Output**: One of a fixed set of categories (e.g. `Work Income`, `Transfers & Payments`, `Food & Drink`, …).
- **Training data**: Pairs `(description, category)` from:
  - **custom_mapping.json**: `{ "description_substring_or_full": "Category" }`. Each key can be used as one training example (description = key, label = category). Optionally you can also use **historical merged/Excel data** (description + category from past months) if you export it.

### Model (current implementation)

- **Step 1 – Custom mapping**: If the transaction description **contains** a key from `custom_mapping.json` (longest match first), return that category.
- **Step 2 – Regex rules**: If any rule in `CATEGORY_RULES` (or from `category_rules.json`) matches, return that category.
- **Step 3 – ML fallback**: If step 1 and 2 give "Uncategorized", use **TfidfVectorizer** (char n-grams) + **LogisticRegression**. Trained on custom_mapping plus (description, category) from the last 3 months’ merged.csv. Cached in `.ml_cache/classifier.pkl`; only retrains when training data hash changes. Predictions are accepted only when confidence > 0.70 and the predicted category is in `ALL_CATEGORIES`.

### Where it lives

- **Merge script** (`merge_and_categorize.py`): Loads `custom_mapping.json` (from month folder or Accounts root), loads rules/categories from `category_rules.json` if present, then for each transaction: (1) custom mapping, (2) regex, (3) ML with cached model. Writes `audit.json` with counts (mapping / regex / ML / uncategorized) for the app’s Data Health view.

### Hyperparameters (for your improvements)

- **TF-IDF**: `max_features` (e.g. 200–1000), `ngram_range` (e.g. (1,2) or (1,3)), `min_df`, `strip_accents`, `lowercase`.
- **Random Forest**: `n_estimators`, `max_depth`, `min_samples_leaf`, `class_weight` (e.g. `balanced` if some categories are rare).
- **Training set**: Only custom_mapping vs custom_mapping + historical exports; whether to normalize descriptions (e.g. lowercasing, remove numbers) before training.

### Limitations of this design

1. **Small training set**: Only what’s in custom_mapping (and any history you add). So the model can overfit quickly; shallow trees and strong regularization help.
2. **No semantic features**: Pure bag-of-words TF-IDF; no embeddings or external knowledge. You could add word embeddings (e.g. sentence-transformers or a small embedding table) as extra features.
3. **Category set**: Must match the report’s categories (e.g. `ALL_CATEGORIES` in `make_monthly_report.py`). Predictions should be constrained to that set.
4. **Cold start**: New users have few or no custom_mapping entries; ML only helps after some training data exists.

### Possible improvements you can make

- **Better features**: Add character n-grams, or embed descriptions with a small transformer/embedding model and train a classifier on top.
- **Smoother integration**: Merge script reads `custom_mapping.json` and uses it (step 1); then add optional TF-IDF + RF (or another classifier) for step 3.
- **More training data**: Export (description, category) from last N months’ merged/Excel data and add them to the training set (with or without writing them into custom_mapping).
- **Thresholding**: Only use ML when the classifier’s confidence (e.g. `predict_proba` max) is above a threshold; otherwise return "Uncategorized".
- **Different classifier**: e.g. logistic regression, XGBoost, or a small neural net if you add embeddings.
- **Retraining**: Retrain the model each time the merge runs (current design) or cache a small pickle and only retrain when custom_mapping (or training data) has changed.

---

## File locations

- **Custom mapping**: `~/Library/Application Support/ExpenseReports/Accounts/custom_mapping.json` (or `ACCOUNTS_DIR/custom_mapping.json` when run by the app).
- **Merge script**: `Scripts/merge_and_categorize.py` (and a copy in the Accounts folder when using the app).
- **Report categories**: `Scripts/make_monthly_report.py` → `ALL_CATEGORIES` and `CATEGORY_RULES`; keep the merge script’s category set aligned with this so the Excel and merge output stay consistent.
