import csv
import subprocess
import sys
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "scripts"))

from preprocess import repair_rows  # noqa: E402


def test_unquoted_comma_is_merged_into_full_name():
    text = "cust_email,full_name,tier,updated_at\r\na@x.com,Smith, Alice,Gold,2026-01-01\r\n"
    rows = repair_rows(text, "full_name")
    assert rows[1] == ["a@x.com", "Smith, Alice", "Gold", "2026-01-01"]


def test_values_are_not_cleaned():
    text = "item_code,description,unit_price\ndrnk-002,Beverage - Latte,$3.00 "
    rows = repair_rows(text, None)
    assert rows[1] == ["drnk-002", "Beverage - Latte", "$3.00 "]


def test_blank_lines_dropped():
    rows = repair_rows("a,b\n1,2\n\n3,4\n", None)
    assert rows == [["a", "b"], ["1", "2"], ["3", "4"]]


def test_wrong_width_without_merge_column_raises():
    with pytest.raises(ValueError, match="line 2: expected 2 fields, got 3"):
        repair_rows("a,b\n1,2,3\n", None)


def test_real_files_produce_rectangular_lf_seeds(tmp_path):
    subprocess.run(
        [sys.executable, str(ROOT / "scripts" / "preprocess.py"),
         "--raw-dir", str(ROOT / "raw"), "--seed-dir", str(tmp_path)],
        check=True,
    )
    expected = {"raw_catalog.csv": (3, 7), "raw_customers.csv": (4, 6), "raw_pos_system.csv": (5, 8)}
    for name, (width, n_rows) in expected.items():
        data = (tmp_path / name).read_bytes()
        assert b"\r" not in data
        assert data.endswith(b"\n")
        rows = list(csv.reader(data.decode("utf-8").splitlines()))
        assert len(rows) == n_rows + 1
        assert all(len(r) == width for r in rows), name
