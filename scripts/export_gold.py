"""Export every Gold table from the DuckDB file to Parquet for Power BI.

Usage: python scripts/export_gold.py [--db daily_grind.duckdb] [--out exports]
"""
from __future__ import annotations

import argparse
from pathlib import Path

import duckdb


def export_gold(db_path: Path, out_dir: Path) -> list[Path]:
    if not db_path.exists():
        raise FileNotFoundError(f"{db_path} not found - run `dbt build --profiles-dir .` first")
    out_dir.mkdir(parents=True, exist_ok=True)
    written = []
    with duckdb.connect(str(db_path), read_only=True) as con:
        tables = [r[0] for r in con.sql(
            "select table_name from information_schema.tables "
            "where table_schema = 'gold' order by table_name"
        ).fetchall()]
        if not tables:
            raise RuntimeError("no tables in schema 'gold' - did dbt build succeed?")
        for table in tables:
            target = out_dir / f"{table}.parquet"
            con.execute(f"copy gold.{table} to '{target.as_posix()}' (format parquet)")
            rows = con.sql(f"select count(*) from gold.{table}").fetchone()[0]
            print(f"gold.{table} -> {target} ({rows} rows)")
            written.append(target)
    return written


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--db", default="daily_grind.duckdb", type=Path)
    parser.add_argument("--out", default="exports", type=Path)
    args = parser.parse_args()
    export_gold(args.db, args.out)


if __name__ == "__main__":
    main()
