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
import hashlib
import json
import logging
import os
import re
import sys
from datetime import datetime
from pathlib import Path

_raw = os.environ.get("EXPENSE_REPORTS_ACCOUNTS_DIR")
ACCOUNTS_DIR = Path(_raw).resolve() if _raw else Path(__file__).resolve().parent

# Built-in category rules (used if category_rules.json is not present).
_BUILTIN_CATEGORY_RULES = [
    (r"(?i)electronic funds transfer pay windreg|pay windreg|payroll", "Work Income"),
    (r"(?i)payment thank you|paiemen t merci|internet transfer 0{6,}|interac transfer|e-transfer|internet banking", "Transfers & Payments"),
    (r"(?i)rogers \*|rogers\*\*\*\*\*\*|apple\.com|cursor|paypal", "Subscriptions & Bills"),
    (r"(?i)enwin|university of windsor|bill pay", "Utilities & Bills"),
    (r"(?i)tim hortons|starbucks|mcdonald|presotea|taco bell|subway|pizza pizza|chipotle|burger king|new york fries|dollarama|miniso", "Food & Drink"),
    (r"(?i)athidhi|janpath|spago|chilly bliss|paan banaras|restaurant", "Restaurants"),
    (r"(?i)instacart|costco|wal-mart|amazon|amzn|temu", "Shopping & Groceries"),
    (r"(?i)uber|lyft|vets cab|presto fare|pearson parking|michigan flyer|spirit air|air can", "Transport & Travel"),
    (r"(?i)sport chek|cinplex|vue", "Entertainment"),
    (r"(?i)shell|gas|petrol", "Gas & Auto"),
    (r"(?i)interest|service charge|fee|branch transaction|automated banking machine", "Fees & Interest"),
    (r"(?i)chiropractic", "Health"),
    (r"(?i)shoppers drug|pharmacy", "Pharmacy"),
    (r"(?i)sephora", "Personal Care"),
]
# Fallback: generic transfers
TRANSFER_FALLBACK = (r"(?i)e-transfer|internet transfer\s|interac\s+transfer", "Transfers & Payments")

# Must match make_monthly_report.ALL_CATEGORIES (order for dropdown).
_BUILTIN_ALL_CATEGORIES = [
    "Work Income", "Transfers & Payments", "Shopping & Groceries", "Food & Drink",
    "Restaurants", "Transport & Travel", "Subscriptions & Bills", "Utilities & Bills",
    "Entertainment", "Fees & Interest", "Health", "Pharmacy", "Personal Care", "Gas & Auto",
    "Uncategorized",
]


def _load_category_config(base_dir: Path | None = None) -> tuple[list[tuple[str, str]], list[str]]:
    """Load (rules, all_categories) from base_dir/category_rules.json if present; else use built-in."""
    base = base_dir or ACCOUNTS_DIR
    config_path = base / "category_rules.json"
    if not config_path.exists():
        return (_BUILTIN_CATEGORY_RULES, _BUILTIN_ALL_CATEGORIES)
    try:
        with open(config_path, encoding="utf-8") as f:
            data = json.load(f)
        rules = []
        for r in data.get("rules", []):
            if isinstance(r, dict) and r.get("pattern") and r.get("category"):
                rules.append((str(r["pattern"]), str(r["category"])))
        categories = list(data.get("categories", []))
        if rules or categories:
            return (rules if rules else _BUILTIN_CATEGORY_RULES, categories if categories else _BUILTIN_ALL_CATEGORIES)
    except (json.JSONDecodeError, OSError) as e:
        logger.warning("Could not load category_rules.json: %s", e)
    return (_BUILTIN_CATEGORY_RULES, _BUILTIN_ALL_CATEGORIES)


# Resolved at runtime so category_rules.json can override.
def _get_category_rules() -> list[tuple[str, str]]:
    return _load_category_config()[0]


def _get_all_categories() -> list[str]:
    return _load_category_config()[1]

# ML config (override via env ML_CONFIDENCE_THRESHOLD)
MIN_TRAINING_SAMPLES = 10
def _ml_threshold() -> float:
    raw = os.environ.get("ML_CONFIDENCE_THRESHOLD", "0.70")
    try:
        v = float(raw)
        return max(0.0, min(1.0, v))
    except ValueError:
        return 0.70
ML_CONFIDENCE_THRESHOLD = _ml_threshold()

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
        self._regex_rules, self._all_categories = _load_category_config(self.accounts_dir)
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
        for pattern, category in self._regex_rules:
            if re.search(pattern, description):
                return category
        if re.search(TRANSFER_FALLBACK[0], description):
            return TRANSFER_FALLBACK[1]
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

    def _training_data_hash(self, training: list[tuple[str, str]]) -> str:
        """Stable hash of training data for cache invalidation."""
        content = json.dumps(sorted(training), sort_keys=True)
        return hashlib.sha256(content.encode("utf-8")).hexdigest()[:16]

    def _cache_path(self) -> Path:
        return self.accounts_dir / ".ml_cache" / "classifier.pkl"

    def fit(self) -> None:
        """Load custom mapping and optionally train the ML model (or load from cache)."""
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

        current_hash = self._training_data_hash(training)
        cache_path = self._cache_path()
        if cache_path.exists():
            try:
                import pickle
                with open(cache_path, "rb") as f:
                    data = pickle.load(f)
                if isinstance(data, dict) and data.get("hash") == current_hash and "vectorizer" in data and "model" in data:
                    self._vectorizer = data["vectorizer"]
                    self._model = data["model"]
                    self._ml_trained = True
                    return
            except Exception:
                pass

        try:
            self._vectorizer = TfidfVectorizer(analyzer="char", ngram_range=(3, 5), max_features=2000, min_df=1)
            X = self._vectorizer.fit_transform(X_raw)
            self._model = LogisticRegression(max_iter=500, class_weight="balanced")
            self._model.fit(X, y)
            self._ml_trained = True
            cache_path.parent.mkdir(parents=True, exist_ok=True)
            import pickle
            with open(cache_path, "wb") as f:
                pickle.dump({"hash": current_hash, "vectorizer": self._vectorizer, "model": self._model}, f)
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
            if confidence > _ml_threshold():
                pred = self._model.classes_[max_idx]
                if pred in self._all_categories:
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


def _load_bank_profile(base_dir: Path) -> tuple[str, int, int, int, int, int]:
    """Return (file_pattern, date_col, desc_col, debit_col, credit_col, account_col). Default CIBC."""
    path = base_dir / "profiles.json"
    if not path.exists():
        return ("cibc*.csv", 0, 1, 2, 3, 4)
    try:
        with open(path, encoding="utf-8") as f:
            data = json.load(f)
        default_name = data.get("default", "cibc")
        profiles = data.get("profiles") or {}
        pro = profiles.get(default_name) or {}
        cols = pro.get("columns") or {}
        return (
            str(pro.get("file_pattern", "cibc*.csv")),
            int(cols.get("date", 0)),
            int(cols.get("description", 1)),
            int(cols.get("debit", 2)),
            int(cols.get("credit", 3)),
            int(cols.get("account", 4)),
        )
    except (json.JSONDecodeError, OSError, TypeError, ValueError):
        return ("cibc*.csv", 0, 1, 2, 3, 4)


def read_bank_csv(filepath: Path, date_col: int, desc_col: int, debit_col: int, credit_col: int, account_col: int) -> list[dict]:
    """Read one bank CSV with given column indices. Does not assign category."""
    rows = []
    source_name = filepath.stem
    with open(filepath, newline="", encoding="utf-8", errors="replace") as f:
        reader = csv.reader(f)
        for row in reader:
            if len(row) <= max(desc_col, date_col):
                continue
            date = (row[date_col] or "").strip()
            desc = (row[desc_col] or "").strip()
            debit = parse_amount(row[debit_col] if len(row) > debit_col else "")
            credit = parse_amount(row[credit_col] if len(row) > credit_col else "")
            account = (row[account_col] if len(row) > account_col else "").strip()
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


def read_cibc_csv(filepath: Path) -> list[dict]:
    """Read one CIBC CSV (no header). Columns: Date, Description, Debit, Credit, Account."""
    return read_bank_csv(filepath, 0, 1, 2, 3, 4)


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
    if not folder_name:
        print("Error: Month folder name cannot be empty.", file=sys.stderr)
        sys.exit(1)
    month_path = ACCOUNTS_DIR / folder_name
    if not month_path.is_dir():
        print(f"Folder not found: {month_path}", file=sys.stderr)
        sys.exit(1)
    print(f"Merge folder: {month_path.name}", file=sys.stderr)
    file_pattern, date_col, desc_col, debit_col, credit_col, account_col = _load_bank_profile(ACCOUNTS_DIR)
    csv_files = sorted(month_path.glob(file_pattern))
    if not csv_files:
        print(f"No {file_pattern} in that folder.", file=sys.stderr)
        sys.exit(1)

    # Global ignore list: descriptions matching any entry are excluded from merge (e.g. credit card payment duplicates)
    ignore_list: list[str] = []
    ignore_path = ACCOUNTS_DIR / "ignore_list.json"
    if ignore_path.exists():
        try:
            with open(ignore_path, encoding="utf-8") as f:
                data = json.load(f)
            if isinstance(data, list):
                ignore_list = [str(s).strip().lower() for s in data if s]
            elif isinstance(data, dict) and "descriptions" in data:
                ignore_list = [str(s).strip().lower() for s in data["descriptions"] if s]
        except (json.JSONDecodeError, OSError) as e:
            logger.warning("Could not load ignore_list.json: %s", e)

    def should_ignore(description: str) -> bool:
        if not (description and description.strip()):
            return False
        d = description.strip().lower()
        return any(ign in d for ign in ignore_list)

    # Classifier: load custom mapping, optional ML from custom_mapping + last 3 months merged
    classifier = TransactionClassifier(ACCOUNTS_DIR, current_month_folder=folder_name)
    classifier.fit()

    # Merge: same as before (dedupe across files, sort); skip rows matching ignore list
    all_rows = []
    key_to_files: dict[tuple, set] = {}
    duplicate_count = 0
    total_credits = 0.0
    total_debits = 0.0
    ignored_count = 0

    for file_idx, csv_path in enumerate(csv_files):
        rows = read_bank_csv(csv_path, date_col, desc_col, debit_col, credit_col, account_col)
        seen_in_file: set[tuple] = set()
        for r in rows:
            if should_ignore(r["Description"] or ""):
                ignored_count += 1
                continue
            total_credits += r["Credit"] or 0
            total_debits += r["Debit"] or 0
            key = (r["Date"], r["Description"], r["Amount"])
            if key in seen_in_file:
                duplicate_count += 1
                continue
            seen_in_file.add(key)
            files_with = key_to_files.setdefault(key, set())
            if files_with and file_idx not in files_with:
                duplicate_count += 1
                continue
            files_with.add(file_idx)
            all_rows.append(r)

    all_rows.sort(key=lambda r: (r["Date"], r["Description"]))

    # Vendor normalization: replace description with clean name from vendor_aliases.json (longest match first)
    vendor_aliases: dict[str, str] = {}
    alias_path = ACCOUNTS_DIR / "vendor_aliases.json"
    if alias_path.exists():
        try:
            with open(alias_path, encoding="utf-8") as f:
                data = json.load(f)
            if isinstance(data, dict):
                vendor_aliases = {k.strip(): str(v).strip() for k, v in data.items() if k and v}
        except (json.JSONDecodeError, OSError) as e:
            logger.warning("Could not load vendor_aliases.json: %s", e)
    alias_keys_sorted = sorted(vendor_aliases.keys(), key=len, reverse=True)

    def normalize_description(desc: str) -> str:
        if not (desc and desc.strip()):
            return desc
        for key in alias_keys_sorted:
            if key in desc:
                return vendor_aliases[key]
        return desc

    for r in all_rows:
        r["Description"] = normalize_description(r["Description"] or "")

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
        "ignored_count": ignored_count,
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
        "Merged %d transactions from %d file(s). Duplicates skipped: %d. Ignored: %d. Wrote %s, merged.csv, audit.json",
        len(all_rows), len(csv_files), duplicate_count, ignored_count, out_combined.name,
    )


if __name__ == "__main__":
    main()
