import sys
from pathlib import Path

import duckdb
import pytest

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "scripts"))

from export_gold import export_gold  # noqa: E402


def test_exports_each_gold_table_with_types(tmp_path):
    db = tmp_path / "t.duckdb"
    with duckdb.connect(str(db)) as con:
        con.execute("create schema gold")
        con.execute("create table gold.dim_x as select 1::integer as id, 3.50::decimal(10,2) as price")
        con.execute("create schema silver")
        con.execute("create table silver.stg_y as select 1 as id")
    written = export_gold(db, tmp_path / "out")
    assert [p.name for p in written] == ["dim_x.parquet"]
    types = duckdb.sql(f"describe select * from '{written[0].as_posix()}'").fetchall()
    assert [(t[0], t[1]) for t in types] == [("id", "INTEGER"), ("price", "DECIMAL(10,2)")]


def test_missing_database_raises(tmp_path):
    with pytest.raises(FileNotFoundError, match="run `dbt build"):
        export_gold(tmp_path / "missing.duckdb", tmp_path / "out")
