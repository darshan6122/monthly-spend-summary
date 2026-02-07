#!/usr/bin/env python3
"""
Merge CIBC CSV exports from a month folder and add suggested categories.
Uses a 3-step waterfall: Custom Mapping -> Regex Rules -> ML Fallback.

Outputs:
  - {Month}_combined.csv (full columns)
  - merged.csv (Date, Description, Amount, Category) for app Quick Look
  - audit.json for app Data Health

Usage (from app or CLI):
  EXPENSE_REPORTS_ACCOUNTS_DIR=/path python merge_and_categorize.py "DECEMBER 2025"
"""

import csv
import json
import logging
import os
import re
import sys
from datetime import datetime
from pathlib import Path

_raw = os.environ.get("EXPENSE_REPORTS_ACCOUNTS_DIR")
ACCOUNTS_DIR = Path(_raw).resolve() if _raw else Path(__file__).resolve().parent

# Same category rules as your Desktop version (order matters; first match wins)
CATEGORY_RULES = [
    (r"(?i)tim hortons|starbucks|mcdonald|presotea|taco bell|subway|pizza pizza|chipotle|burger king|new york fries|dollarama|miniso", "Food & Drink"),
    (r"(?i)uber|lyft|vets cab|presto fare|pearson parking|michigan flyer|spirit air|air can", "Transport & Travel"),
    (r"(?i)instacart|costco|wal-mart|amazon|amzn|temu", "Shopping & Groceries"),
    (r"(?i)apple\.com|cursor|rogers|paypal", "Subscriptions & Bills"),
    (r"(?i)payment thank you|e-transfer|internet transfer|internet banking", "Transfers & Payments"),
    (r"(?i)interest|service charge|fee", "Fees & Interest"),
    (r"(?i)pay windreg|payroll", "Income"),
    (r"(?i)enwin|university of windsor|bill pay", "Utilities & Bills"),
    (r"(?i)athidhi|janpath|spago|chilly bliss|paan banaras|restaurant", "Restaurants"),
    (r"(?i)sport chek|cinplex|vue", "Entertainment"),
    (r"(?i)shell|gas|petrol", "Gas & Auto"),
    (r"(?i)chiropractic|vets cab", "Health"),
    (r"(?i)shoppers drug|pharmacy", "Pharmacy"),
    (r"(?i)sephora", "Personal Care"),
]

# All valid categories (for ML and output consistency)
ALL_CATEGORIES = sorted({cat for _, cat in CATEGORY_RULES} | {"Uncategorized"})

# ML config
MIN_TRAINING_SAMPLES = 10
ML_CONFIDENCE_THRESHOLD = 0.70

logging.basicConfig(level=logging.INFO, format="%(message)s")
logger = logging.getLogger(__name__)


# ---------------------------------------------------------------------------
# TransactionClassifier: Custom Mapping -> Regex -> ML Fallback
# ---------------------------------------------------------------------------

class TransactionClassifier:
    """
    Three-step waterfall categorizer:
    1. Custom mapping (custom_mapping.json)
    2. Regex rules (CATEGORY_RULES)
    3. ML fallback (TfidfVectorizer + LogisticRegression) when confidence > threshold
    """

    SOURCE_MAPPING = "mapping"
    SOURCE_REGEX = "regex"
    SOURCE_ML = "ml"
    SOURCE_UNCATEGORIZED = "uncategorized"

    def __init__(self, accounts_dir: Path, current_month_folder: str | None = None):
        self.accounts_dir = Path(accounts_dir)
        self.current_month_folder = (current_month_folder or "").strip()
        self.custom_mapping: dict[str, str] = {}
        self._mapping_keys_sorted: list[str] = []  # longest first for substring match
        self._vectorizer = None
        self._model = None
        self._ml_trained = False
        self._counts = {self.SOURCE_MAPPING: 0, self.SOURCE_REGEX: 0, self.SOURCE_ML: 0, self.SOURCE_UNCATEGORIZED: 0}

    def _load_custom_mapping(self) -> None:
        path = self.accounts_dir / "custom_mapping.json"
        self.custom_mapping = {}
        self._mapping_keys_sorted = []
        if not path.exists():
            return
        try:
            with open(path, encoding="utf-8") as f:
                data = json.load(f)
            if isinstance(data, dict):
                # Only include non-empty category values (e.g. skip "Uncategorized" if we don't want to train on it)
                self.custom_mapping = {k.strip(): v.strip() for k, v in data.items() if v and str(v).strip() and str(v).strip().lower() != "uncategorized"}
            self._mapping_keys_sorted = sorted(self.custom_mapping.keys(), key=len, reverse=True)
        except (json.JSONDecodeError, OSError) as e:
            logger.warning("Could not load custom_mapping.json: %s", e)

    def _regex_category(self, description: str) -> str:
        if not (description and description.strip()):
            return "Uncategorized"
        for pattern, category in CATEGORY_RULES:
            if re.search(pattern, description):
                return category
        return "Uncategorized"

    def _load_historical_training_data(self) -> list[tuple[str, str]]:
        """Load (description, category) from merged.csv in up to 3 other month folders."""
        pairs: list[tuple[str, str]] = []
        merged_files: list[tuple[datetime, Path]] = []

        for path in self.accounts_dir.iterdir():
            if not path.is_dir():
                continue
            merged_path = path / "merged.csv"
            if not merged_path.exists():
                continue
            if path.name == self.current_month_folder:
                continue
            try:
                dt = datetime.strptime(path.name, "%B %Y")
                merged_files.append((dt, merged_path))
            except ValueError:
                continue

        merged_files.sort(key=lambda x: x[0], reverse=True)
        for _, merged_path in merged_files[:3]:
            try:
                with open(merged_path, newline="", encoding="utf-8", errors="replace") as f:
                    reader = csv.DictReader(f)
                    for row in reader:
                        desc = (row.get("Description") or "").strip()
                        cat = (row.get("Category") or "").strip()
                        if desc and cat and cat != "Uncategorized":
                            pairs.append((desc, cat))
            except OSError:
                continue
        return pairs

    def _build_training_data(self) -> list[tuple[str, str]]:
        """Combine custom_mapping entries and historical merged.csv rows (non-Uncategorized)."""
        pairs: list[tuple[str, str]] = []
        for key, category in self.custom_mapping.items():
            if category and category != "Uncategorized":
                pairs.append((key, category))
        historical = self._load_historical_training_data()
        seen = {d for d, _ in pairs}
        for desc, cat in historical:
            if desc not in seen and cat != "Uncategorized":
                pairs.append((desc, cat))
                seen.add(desc)
        return pairs

    def fit(self) -> None:
        """Load custom mapping and optionally train the ML model if enough data."""
        self._load_custom_mapping()
        self._vectorizer = None
        self._model = None
        self._ml_trained = False

        training = self._build_training_data()
        if len(training) < MIN_TRAINING_SAMPLES:
            return

        try:
            from sklearn.feature_extraction.text import TfidfVectorizer
            from sklearn.linear_model import LogisticRegression
        except ImportError:
            return

        X_raw = [t[0] for t in training]
        y = [t[1] for t in training]
        classes = sorted(set(y))
        if len(classes) < 2:
            return

        try:
            self._vectorizer = TfidfVectorizer(analyzer="char", ngram_range=(3, 5), max_features=2000, min_df=1)
            X = self._vectorizer.fit_transform(X_raw)
            self._model = LogisticRegression(max_iter=500, class_weight="balanced")
            self._model.fit(X, y)
            self._ml_trained = True
        except Exception as e:
            logger.warning("ML training skipped: %s", e)

    def _predict_ml(self, description: str) -> tuple[str | None, float]:
        """Return (category, confidence) or (None, 0.0) if not confident."""
        if not self._ml_trained or not self._vectorizer or not self._model:
            return None, 0.0
        try:
            X = self._vectorizer.transform([description])
            proba = self._model.predict_proba(X)[0]
            max_idx = proba.argmax()
            confidence = float(proba[max_idx])
            if confidence > ML_CONFIDENCE_THRESHOLD:
                pred = self._model.classes_[max_idx]
                return pred, confidence
        except Exception:
            pass
        return None, 0.0

    def categorize(self, description: str) -> tuple[str, str]:
        """
        Run the 3-step waterfall. Returns (category, source).
        source is one of: mapping, regex, ml, uncategorized.
        """
        if not (description and description.strip()):
            self._counts[self.SOURCE_UNCATEGORIZED] += 1
            return "Uncategorized", self.SOURCE_UNCATEGORIZED

        # Step 1: Custom mapping (longest key match first)
        for key in self._mapping_keys_sorted:
            if key in description or description == key:
                cat = self.custom_mapping[key]
                if cat and cat != "Uncategorized":
                    self._counts[self.SOURCE_MAPPING] += 1
                    return cat, self.SOURCE_MAPPING

        # Step 2: Regex rules
        cat = self._regex_category(description)
        if cat != "Uncategorized":
            self._counts[self.SOURCE_REGEX] += 1
            return cat, self.SOURCE_REGEX

        # Step 3: ML fallback
        pred, _ = self._predict_ml(description)
        if pred is not None:
            self._counts[self.SOURCE_ML] += 1
            return pred, self.SOURCE_ML

        self._counts[self.SOURCE_UNCATEGORIZED] += 1
        return "Uncategorized", self.SOURCE_UNCATEGORIZED

    def get_stats(self) -> dict[str, int]:
        return dict(self._counts)


# ---------------------------------------------------------------------------
# CIBC CSV parsing (unchanged contract)
# ---------------------------------------------------------------------------

def parse_amount(s: str) -> float:
    if not s or not s.strip():
        return 0.0
    try:
        return float(s.strip().replace(",", ""))
    except ValueError:
        return 0.0


def read_cibc_csv(filepath: Path) -> list[dict]:
    """Read one CIBC CSV (no header). Columns: Date, Description, Debit, Credit, Account.
    Does not assign category; caller will set Suggested Category after classification."""
    rows = []
    source_name = filepath.stem
    with open(filepath, newline="", encoding="utf-8", errors="replace") as f:
        reader = csv.reader(f)
        for row in reader:
            if len(row) < 2:
                continue
            date = (row[0] or "").strip()
            desc = (row[1] or "").strip()
            debit = parse_amount(row[2] if len(row) > 2 else "")
            credit = parse_amount(row[3] if len(row) > 3 else "")
            account = (row[4] if len(row) > 4 else "").strip()
            amount = debit if debit else -credit
            rows.append({
                "Date": date,
                "Description": desc,
                "Debit": debit,
                "Credit": credit,
                "Amount": amount,
                "Account": account,
                "Source": source_name,
            })
    return rows


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

def main() -> None:
    if not _raw:
        print("Set EXPENSE_REPORTS_ACCOUNTS_DIR", file=sys.stderr)
        sys.exit(1)
    if len(sys.argv) < 2:
        print("Usage: merge_and_categorize.py <month_folder_name>", file=sys.stderr)
        sys.exit(1)

    folder_name = sys.argv[1].strip()
    month_path = ACCOUNTS_DIR / folder_name
    if not month_path.is_dir():
        print(f"Folder not found: {month_path}", file=sys.stderr)
        sys.exit(1)

    csv_files = sorted(month_path.glob("cibc*.csv"))
    if not csv_files:
        print("No cibc*.csv in that folder.", file=sys.stderr)
        sys.exit(1)

    # Classifier: load custom mapping, optional ML from custom_mapping + last 3 months merged
    classifier = TransactionClassifier(ACCOUNTS_DIR, current_month_folder=folder_name)
    classifier.fit()

    # Merge: same as before (dedupe across files, sort)
    all_rows = []
    key_to_files: dict[tuple, set] = {}
    duplicate_count = 0
    total_credits = 0.0
    total_debits = 0.0

    for file_idx, csv_path in enumerate(csv_files):
        rows = read_cibc_csv(csv_path)
        for r in rows:
            total_credits += r["Credit"] or 0
            total_debits += r["Debit"] or 0
            key = (r["Date"], r["Description"], r["Amount"])
            files_with = key_to_files.setdefault(key, set())
            if files_with and file_idx not in files_with:
                duplicate_count += 1
                continue
            files_with.add(file_idx)
            all_rows.append(r)

    all_rows.sort(key=lambda r: (r["Date"], r["Description"]))

    # Assign category via 3-step waterfall (and add Suggested Category for output)
    for r in all_rows:
        category, _ = classifier.categorize(r["Description"])
        r["Suggested Category"] = category

    stats = classifier.get_stats()

    # 1) Combined CSV (same format as before)
    fieldnames = ["Date", "Description", "Debit", "Credit", "Amount", "Account", "Source", "Suggested Category"]
    out_combined = month_path / f"{month_path.name}_combined.csv"
    with open(out_combined, "w", newline="", encoding="utf-8") as f:
        writer = csv.DictWriter(f, fieldnames=fieldnames)
        writer.writeheader()
        for r in all_rows:
            writer.writerow({k: r[k] for k in fieldnames})

    # 2) merged.csv for app (Amount = credit - debit; same format make_monthly_report / app expect)
    merged_path = month_path / "merged.csv"
    with open(merged_path, "w", newline="", encoding="utf-8") as f:
        w = csv.writer(f)
        w.writerow(["Date", "Description", "Amount", "Category"])
        for r in all_rows:
            amt = (r["Credit"] or 0) - (r["Debit"] or 0)
            w.writerow([r["Date"], r["Description"], amt, r["Suggested Category"]])

    # 3) audit.json for app Data Health (include categorization breakdown)
    audit = {
        "total_credits": round(total_credits, 2),
        "total_debits": round(total_debits, 2),
        "duplicate_count": duplicate_count,
        "files_processed": len(csv_files),
        "transaction_count": len(all_rows),
        "categorized_via_mapping": stats.get(TransactionClassifier.SOURCE_MAPPING, 0),
        "categorized_via_regex": stats.get(TransactionClassifier.SOURCE_REGEX, 0),
        "categorized_via_ml": stats.get(TransactionClassifier.SOURCE_ML, 0),
        "uncategorized": stats.get(TransactionClassifier.SOURCE_UNCATEGORIZED, 0),
    }
    with open(month_path / "audit.json", "w", encoding="utf-8") as f:
        json.dump(audit, f, indent=2)

    # Logging summary
    logger.info(
        "Categorized %d rows via Mapping, %d via Regex, and %d via ML.",
        stats[TransactionClassifier.SOURCE_MAPPING],
        stats[TransactionClassifier.SOURCE_REGEX],
        stats[TransactionClassifier.SOURCE_ML],
    )
    logger.info(
        "Merged %d transactions from %d file(s). Duplicates skipped: %d. Wrote %s, merged.csv, audit.json",
        len(all_rows), len(csv_files), duplicate_count, out_combined.name,
    )


if __name__ == "__main__":
    main()
