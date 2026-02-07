# Category prediction model (for improvements)

## Current state

- **Merge script** (`Scripts/merge_and_categorize.py`): **regex-only**. It uses a fixed list of `CATEGORY_RULES` (regex pattern → category). No ML, no `custom_mapping.json`.
- **App Training sheet**: Lets you assign a category to a transaction description and writes to **`custom_mapping.json`** in the Accounts folder. The **current** merge script does **not** read this file, so training does not affect merge output until you wire it back in.
- **Report script** (`make_monthly_report.py`): Reads **raw** CIBC CSVs and uses its own regex rules; it does not use the merge output for categorization. So the Excel report’s categories come from `make_monthly_report.py`’s rules, not from the merge script.

So today there is **no ML model in the pipeline**. The doc below describes the **intended** design so you can add or improve it.

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

### Model (as originally sketched)

- **Step 1 – Custom mapping**: If the transaction description **contains** a key from `custom_mapping.json` (or exact match), return that category. User corrections always override.
- **Step 2 – Regex rules**: If any of the fixed regex rules (e.g. `tim hortons|starbucks|...`) matches, return that category.
- **Step 3 – ML fallback** (optional): If step 1 and 2 give nothing (e.g. "Uncategorized"), call a **classifier** that predicts category from the **raw description string**.
  - **Features**: **TF-IDF** over the description (unigrams + bigrams). Example: `TfidfVectorizer(max_features=500, ngram_range=(1, 2))`.
  - **Classifier**: **Random Forest** (e.g. `RandomForestClassifier(n_estimators=50, max_depth=10)`). Trained only on examples from `custom_mapping` (and optionally other labeled data).
  - **Training**: When the script runs, load `custom_mapping.json`, build a list of `(description, category)` pairs, then `fit(descriptions, categories)`. If there are fewer than ~3–5 examples (or too few per class), skip the ML step and return "Uncategorized".
  - **Inference**: For each new description that reached step 3, call `predict([description])` and map the predicted label to one of the allowed categories; if the predicted label is not in the allowed set, return "Uncategorized".

### Where it lives

- **Merge script** is the right place: it already assigns a "Suggested Category" per row. So:
  - In `merge_and_categorize.py`, after loading `CATEGORY_RULES`, also load `custom_mapping.json` (from `ACCOUNTS_DIR`).
  - In the categorization function:
    1. Check custom_mapping (substring or exact match).
    2. Then regex rules.
    3. Then, if you have sklearn and enough training data, run the TF-IDF + Random Forest model; otherwise return "Uncategorized".

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
