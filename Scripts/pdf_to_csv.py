#!/usr/bin/env python3
"""
Extract transaction table from a bank statement PDF and write a CSV in our format.
Output: Date, Description, Debit, Credit (same as CIBC CSV for merge script).

Usage:
  EXPENSE_REPORTS_ACCOUNTS_DIR=/path python pdf_to_csv.py /path/to/statement.pdf

If pdfplumber is installed, uses it to extract tables. Falls back to tabula-py if available.
Writes to ACCOUNTS_DIR/<MONTH YEAR>/cibc_pdf_export.csv and prints the month folder name.
"""

import csv
import os
import re
import sys
from pathlib import Path

_raw = os.environ.get("EXPENSE_REPORTS_ACCOUNTS_DIR")
ACCOUNTS_DIR = Path(_raw).resolve() if _raw else Path(__file__).resolve().parent


def parse_amount(s):
    if not s or not str(s).strip():
        return 0.0
    s = str(s).strip().replace(",", "").replace("$", "")
    try:
        return float(s)
    except ValueError:
        return 0.0


def detect_month_from_dates(dates: list[str]) -> str | None:
    """Return 'DECEMBER 2025' from list of date strings."""
    for fmt in ["%m/%d/%Y", "%Y-%m-%d", "%d/%m/%Y", "%b %d, %Y", "%d %b %Y"]:
        for d in dates:
            d = (d or "").strip()
            if not d:
                continue
            try:
                from datetime import datetime
                dt = datetime.strptime(d[:10], fmt[:10].replace("%b", "%m"))
                return dt.strftime("%B %Y").upper()
            except Exception:
                continue
    return None


def extract_with_pdfplumber(pdf_path: Path) -> list[dict] | None:
    try:
        import pdfplumber
    except ImportError:
        return None
    rows = []
    with pdfplumber.open(pdf_path) as pdf:
        for page in pdf.pages:
            tables = page.extract_tables()
            for table in tables or []:
                if len(table) < 2:
                    continue
                # First row as header; find column indices
                header = [str(c or "").strip().lower() for c in table[0]]
                date_idx = next((i for i, h in enumerate(header) if "date" in h), 0)
                desc_idx = next((i for i, h in enumerate(header) if "desc" in h or "description" in h or "details" in h), 1)
                debit_idx = next((i for i, h in enumerate(header) if "debit" in h or "withdrawal" in h), 2)
                credit_idx = next((i for i, h in enumerate(header) if "credit" in h or "deposit" in h), 3)
                for r in table[1:]:
                    if len(r) <= max(desc_idx, date_idx):
                        continue
                    date = str(r[date_idx] or "").strip()
                    desc = str(r[desc_idx] or "").strip()
                    debit = parse_amount(r[debit_idx] if len(r) > debit_idx else "")
                    credit = parse_amount(r[credit_idx] if len(r) > credit_idx else "")
                    if desc or date:
                        rows.append({"Date": date, "Description": desc, "Debit": debit, "Credit": credit})
    return rows if rows else None


def extract_with_tabula(pdf_path: Path) -> list[dict] | None:
    try:
        import tabula
    except ImportError:
        return None
    dfs = tabula.read_pdf(str(pdf_path), pages="all", multiple_tables=True)
    rows = []
    for df in dfs:
        if df is None or df.empty:
            continue
        cols = [str(c).lower() for c in df.columns]
        date_col = next((c for c in df.columns if "date" in str(c).lower()), df.columns[0])
        desc_col = next((c for c in df.columns if "desc" in str(c).lower() or "description" in str(c).lower()), df.columns[min(1, len(df.columns)-1)])
        debit_col = next((c for c in df.columns if "debit" in str(c).lower()), None)
        credit_col = next((c for c in df.columns if "credit" in str(c).lower()), None)
        for _, r in df.iterrows():
            date = str(r.get(date_col, "")).strip()
            desc = str(r.get(desc_col, "")).strip()
            debit = parse_amount(r.get(debit_col, 0))
            credit = parse_amount(r.get(credit_col, 0))
            if desc or date:
                rows.append({"Date": date, "Description": desc, "Debit": debit, "Credit": credit})
    return rows if rows else None


def main():
    if not _raw:
        print("Set EXPENSE_REPORTS_ACCOUNTS_DIR", file=sys.stderr)
        sys.exit(1)
    if len(sys.argv) < 2:
        print("Usage: pdf_to_csv.py <path/to/statement.pdf>", file=sys.stderr)
        sys.exit(1)
    pdf_path = Path(sys.argv[1]).resolve()
    if not pdf_path.exists():
        print(f"File not found: {pdf_path}", file=sys.stderr)
        sys.exit(1)
    rows = extract_with_pdfplumber(pdf_path) or extract_with_tabula(pdf_path)
    if not rows:
        print("Could not extract table. Install pdfplumber: pip install pdfplumber (or tabula-py).", file=sys.stderr)
        sys.exit(1)
    dates = [r["Date"] for r in rows if r.get("Date")]
    month_folder = detect_month_from_dates(dates) or "UNKNOWN"
    month_path = ACCOUNTS_DIR / month_folder
    month_path.mkdir(parents=True, exist_ok=True)
    out_csv = month_path / "cibc_pdf_export.csv"
    with open(out_csv, "w", newline="", encoding="utf-8") as f:
        w = csv.writer(f)
        w.writerow(["Date", "Description", "Debit", "Credit"])
        for r in rows:
            w.writerow([r["Date"], r["Description"], r["Debit"], r["Credit"]])
    print(month_folder)
    print(f"Wrote {len(rows)} rows to {out_csv}", file=sys.stderr)


if __name__ == "__main__":
    main()
