"""Check that the physical ER diagram in docs/erd.md contains exactly the
tables/columns/types defined in docs/project_plan.md section 6."""
import re
import sys
from pathlib import Path

EXPECTED = {
    "dim_customer": {"customer_id": "VARCHAR", "cust_email": "VARCHAR", "full_name": "VARCHAR",
                     "tier": "VARCHAR", "updated_at": "TIMESTAMP", "customer_type": "VARCHAR"},
    "dim_item": {"item_code": "VARCHAR", "item_category": "VARCHAR",
                 "item_category_sub": "VARCHAR", "unit_price": "DECIMAL"},
    "dim_store": {"store_id": "VARCHAR", "city": "VARCHAR", "region": "VARCHAR"},
    "dim_date": {"date_day": "DATE", "year": "INTEGER", "month": "INTEGER", "month_name": "VARCHAR",
                 "week_start_date": "DATE", "day_of_week": "INTEGER", "day_name": "VARCHAR",
                 "is_weekend": "BOOLEAN"},
    "fct_orders": {"tx_id": "VARCHAR", "sale_timestamp": "TIMESTAMP", "date_day": "DATE",
                   "customer_id": "VARCHAR", "store_id": "VARCHAR", "line_count": "INTEGER",
                   "unit_count": "INTEGER", "order_revenue": "DECIMAL", "is_return_order": "BOOLEAN"},
    "fct_order_items": {"tx_id": "VARCHAR", "item_code": "VARCHAR", "sale_timestamp": "TIMESTAMP",
                        "date_day": "DATE", "customer_id": "VARCHAR", "store_id": "VARCHAR",
                        "quantity": "INTEGER", "is_return": "BOOLEAN", "unit_price": "DECIMAL",
                        "line_revenue": "DECIMAL", "order_fraction": "DECIMAL"},
}
EXPECTED_PK = {"dim_customer": {"customer_id"}, "dim_item": {"item_code"}, "dim_store": {"store_id"},
               "dim_date": {"date_day"}, "fct_orders": {"tx_id"},
               "fct_order_items": {"tx_id", "item_code"}}


def parse_physical(text: str) -> dict:
    section = text.split("## 3. Physical model", 1)
    if len(section) < 2:
        sys.exit("FAIL: heading '## 3. Physical model' not found")
    block = re.search(r"```mermaid\s*\nerDiagram(.*?)```", section[1], re.S)
    if not block:
        sys.exit("FAIL: no mermaid erDiagram in physical model section")
    tables = {}
    # Entity blocks only: "name {" alone on its line (relationship lines also contain "{").
    for name, body in re.findall(r"^\s*(\w+)\s*\{\s*$(.*?)^\s*\}\s*$", block.group(1), re.S | re.M):
        cols = {}
        for line in body.strip().splitlines():
            parts = line.split()
            if len(parts) < 2:
                continue
            keys = set(re.findall(r"\b(PK|FK)\b", line))
            cols[parts[1]] = {"type": parts[0], "keys": keys}
        tables[name] = cols
    return tables


def main() -> int:
    tables = parse_physical(Path("docs/erd.md").read_text(encoding="utf-8"))
    errors = []
    if set(tables) != set(EXPECTED):
        errors.append(f"tables differ: got {sorted(tables)} expected {sorted(EXPECTED)}")
    for t, cols in EXPECTED.items():
        got = tables.get(t, {})
        if list(got) != list(cols):
            errors.append(f"{t}: columns/order differ: got {list(got)} expected {list(cols)}")
        for c, typ in cols.items():
            if c in got and got[c]["type"] != typ:
                errors.append(f"{t}.{c}: type {got[c]['type']} expected {typ}")
        pks = {c for c, v in got.items() if "PK" in v["keys"]}
        if pks != EXPECTED_PK[t]:
            errors.append(f"{t}: PK {sorted(pks)} expected {sorted(EXPECTED_PK[t])}")
    for e in errors:
        print("FAIL:", e)
    print("PASS" if not errors else f"{len(errors)} error(s)")
    return 1 if errors else 0


if __name__ == "__main__":
    sys.exit(main())
