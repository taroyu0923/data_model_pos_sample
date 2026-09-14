"""Repair the vendor CSV *file structure* so dbt can load it as seeds.

Only structural fixes happen here (value cleaning is done in dbt Silver):
- a row with more fields than the header (unquoted comma inside a value) has
  the extra fields merged back into the configured column, then re-quoted;
- line endings are normalised to LF and every file ends with a newline;
- blank lines are dropped.

Usage: python scripts/preprocess.py [--raw-dir raw] [--seed-dir seeds]
"""
from __future__ import annotations

import argparse
import csv
import io
from pathlib import Path

# raw file name -> (seed file name, column that may contain unquoted commas)
FILES = {
    "raw_catalog 2 1.csv": ("raw_catalog.csv", None),
    "raw_customers 2 1.csv": ("raw_customers.csv", "full_name"),
    "raw_pos_system 2 1.csv": ("raw_pos_system.csv", None),
}


def repair_rows(text: str, merge_column: str | None) -> list[list[str]]:
    """Parse CSV text and return rows that all have the header's field count."""
    rows = [r for r in csv.reader(io.StringIO(text)) if r]
    header, body = rows[0], rows[1:]
    width = len(header)
    repaired = [header]
    for line_no, row in enumerate(body, start=2):
        extra = len(row) - width
        if extra > 0 and merge_column is not None:
            i = header.index(merge_column)
            row = row[:i] + [",".join(row[i : i + extra + 1])] + row[i + extra + 1 :]
        if len(row) != width:
            raise ValueError(f"line {line_no}: expected {width} fields, got {len(row)}: {row}")
        repaired.append(row)
    return repaired


def write_rows(rows: list[list[str]], path: Path) -> None:
    with path.open("w", encoding="utf-8", newline="") as f:
        csv.writer(f, lineterminator="\n").writerows(rows)


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--raw-dir", default="raw", type=Path)
    parser.add_argument("--seed-dir", default="seeds", type=Path)
    args = parser.parse_args()
    args.seed_dir.mkdir(parents=True, exist_ok=True)
    for raw_name, (seed_name, merge_column) in FILES.items():
        text = (args.raw_dir / raw_name).read_text(encoding="utf-8")
        rows = repair_rows(text, merge_column)
        write_rows(rows, args.seed_dir / seed_name)
        print(f"{raw_name} -> {args.seed_dir / seed_name}: {len(rows) - 1} rows")


if __name__ == "__main__":
    main()
