# Task 2 Pipeline (dbt Medallion) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the Daily Grind pipeline: raw CSVs → pre-processing → dbt on DuckDB (raw seeds, Bronze, Silver, Gold star schema) with data tests → Parquet exports for Power BI, run automatically in GitHub Actions.

**Architecture:** `scripts/preprocess.py` repairs file structure only and writes `seeds/`. dbt loads seeds as all-varchar tables (schema `raw`), exposes them as Bronze views, cleans/casts/splits in Silver views, and builds the Gold star schema as tables exactly matching `docs/erd.md`. `scripts/export_gold.py` copies `gold.*` to `exports/*.parquet`. CI runs the same commands on every push to `main` and every PR.

**Tech Stack:** Python 3.10 (Anaconda locally, 3.10 in CI), dbt-core 1.12.4, dbt-duckdb 1.11.0, duckdb 1.5.5, pytest 9.1.1, GitHub Actions.

**Provenance:** every file below was built and run in a throwaway copy before this plan was written; each "Expected" block is real output from replaying these tasks in order on a clean directory.

## Global Constraints

- Source of truth for decisions: `docs/project_plan.md`; physical schema: `docs/erd.md`. Do not change a confirmed decision; stop and ask.
- Branch `feat/task2-pipeline` off `main`. Albert merges. Never commit to `main`. Do not push (the controller pushes).
- Never put a date or time in a file name.
- Never commit `.venv/`, `*.duckdb`, `seeds/*.csv`, `exports/`, `target/`, `logs/`, credentials.
- Work from the repo root: `C:/Users/Albert Liu/Desktop/2024 internship/UPM Case Assignment`. Use the existing venv: Python `.venv/Scripts/python.exe`, dbt `.venv/Scripts/dbt.exe` (Git Bash paths; quote paths with spaces).
- Versions exactly: `dbt-core==1.12.4`, `dbt-duckdb==1.11.0`, `duckdb==1.5.5`, `pytest==9.1.1`.
- Seeds load every column as `varchar`; all casting happens in Silver.
- Schemas: `raw` (seeds), `bronze` (views), `silver` (views), `gold` (tables).
- Gold table and column names, order and DuckDB types must match `docs/erd.md` §3 exactly.
- Generic test arguments use the dbt 1.12 `arguments:` block.
- dbt partial parsing can keep a previously disabled test disabled. If a `TOTAL=` count is lower than expected after adding files, re-run once with `--no-partial-parse` before reporting a mismatch.
- Copy file contents verbatim. If a command's output differs from "Expected", stop and report the difference (status BLOCKED) — do not edit SQL to force a match.
- Working style: "I don't know — stopping to ask" is always acceptable. Only a tool call counts as verification; every report ends with a verification status (verified by which command / unverified and the check that would confirm it).

## Model assignment

| Task | Content | Model | Effort |
|---|---|---|---|
| 1 | Repo layout, requirements, pre-processing + tests | Sonnet 5 | low |
| 2 | dbt project config + Bronze | Haiku 4.5 | low |
| 3 | Silver: catalog, customers | Sonnet 5 | medium |
| 4 | Silver: POS orders, POS order items | Sonnet 5 | high |
| 5 | Gold dimensions | Sonnet 5 | medium |
| 6 | Gold facts + reconciliation tests + negative check | Sonnet 5 | high |
| 7 | Parquet export + CI workflow | Sonnet 5 | low |
| 8 | README, CLAUDE.md commands, project plan stack section | Haiku 4.5 | low |
| 9 | Clean-run verification, push, PR description | Opus 5 | high |

## File structure

```
raw/                         vendor CSVs, moved unchanged (git mv)
scripts/preprocess.py        structural CSV repair -> seeds/
scripts/export_gold.py       gold.* -> exports/*.parquet
tests_py/                    pytest for the two scripts
dbt_project.yml, profiles.yml
macros/generate_schema_name.sql   schema = layer name
macros/title_case.sql             reusable Title Case expression
models/bronze/               brz_*.sql + _bronze.yml
models/silver/               stg_*.sql + one yml per model
models/gold/                 dim_*.sql, fct_*.sql + one yml per model
tests/                       singular dbt tests
.github/workflows/pipeline.yml
requirements.txt, .gitattributes, .gitignore, README.md
```

---

### Task 1: Repo layout and pre-processing

**Files:**
- Move: `raw_catalog 2 1.csv`, `raw_customers 2 1.csv`, `raw_pos_system 2 1.csv` → `raw/`
- Create: `.gitattributes`, `requirements.txt`, `scripts/preprocess.py`, `tests_py/test_preprocess.py`
- Modify: `.gitignore`

**Interfaces:**
- Produces: `seeds/raw_catalog.csv`, `seeds/raw_customers.csv`, `seeds/raw_pos_system.csv` (same columns as raw, rectangular, LF). `preprocess.repair_rows(text: str, merge_column: str | None) -> list[list[str]]`.

- [ ] **Step 1: Create the branch**

```bash
git checkout main && git pull --ff-only && git checkout -b feat/task2-pipeline
```
Expected: `Switched to a new branch 'feat/task2-pipeline'`

- [ ] **Step 2: Move raw files and protect their bytes**

```bash
mkdir -p raw && git mv "raw_catalog 2 1.csv" "raw_customers 2 1.csv" "raw_pos_system 2 1.csv" raw/
printf '*.csv -text\n' > .gitattributes
```

Append to `.gitignore` (keep existing lines):
```
.venv/
*.duckdb
*.duckdb.wal
logs/
dbt_packages/
seeds/*.csv
exports/
__pycache__/
.pytest_cache/
```

- [ ] **Step 3: Pin dependencies**

Create `requirements.txt`:

```text
dbt-core==1.12.4
dbt-duckdb==1.11.0
duckdb==1.5.5
pytest==9.1.1
```

Run: `.venv/Scripts/python.exe -m pip install -q -r requirements.txt && .venv/Scripts/python.exe -m pip freeze | grep -iE "^(dbt-core|dbt-duckdb|duckdb|pytest)=="`
Expected:
```
dbt-core==1.12.4
dbt-duckdb==1.11.0
duckdb==1.5.5
pytest==9.1.1
```

- [ ] **Step 4: Write the failing tests**

Create `tests_py/test_preprocess.py`:

```python
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
```

- [ ] **Step 5: Run tests to verify they fail**

Run: `.venv/Scripts/python.exe -m pytest tests_py -q`
Expected: collection error `ModuleNotFoundError: No module named 'preprocess'`.

- [ ] **Step 6: Implement the pre-processing script**

Create `scripts/preprocess.py`:

```python
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
```

- [ ] **Step 7: Run tests and the script**

Run: `.venv/Scripts/python.exe -m pytest tests_py -q`
Expected: `5 passed`

Run: `.venv/Scripts/python.exe scripts/preprocess.py && cat seeds/raw_customers.csv`
Expected:
```
raw_catalog 2 1.csv -> seeds\raw_catalog.csv: 7 rows
raw_customers 2 1.csv -> seeds\raw_customers.csv: 6 rows
raw_pos_system 2 1.csv -> seeds\raw_pos_system.csv: 8 rows
cust_email,full_name,tier,updated_at
Alice.Smith@Example.com,"Smith, Alice",Gold,2026-01-01
b.jones@example.com,Bob Jones,silver,2026-02-15
c.davis@example.com,Charlie Davis,NONE,2026-03-10
alice.smith@example.com,Alice S.,Gold,2026-08-01
null,Guest User,,2026-04-01
d.wilson@example.com,wilson diana,GOLD,2026-05-20
```

- [ ] **Step 8: Commit**

Run `git status --short` first: expected renames of the three CSVs plus `.gitattributes`, `.gitignore`, `requirements.txt`, `scripts/preprocess.py`, `tests_py/test_preprocess.py`; no `seeds/`, no `.venv/`.

```bash
git add -A raw .gitattributes .gitignore requirements.txt scripts/preprocess.py tests_py/test_preprocess.py
git commit -m "feat: add raw folder, pinned requirements and CSV pre-processing

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

---

### Task 2: dbt project and Bronze layer

**Files:**
- Create: `dbt_project.yml`, `profiles.yml`, `macros/generate_schema_name.sql`, `models/bronze/brz_catalog.sql`, `models/bronze/brz_customers.sql`, `models/bronze/brz_pos_system.sql`, `models/bronze/_bronze.yml`

**Interfaces:**
- Consumes: `seeds/raw_*.csv` from Task 1 (run `scripts/preprocess.py` first).
- Produces: relations `raw.raw_catalog`, `raw.raw_customers`, `raw.raw_pos_system` (tables, all varchar) and views `bronze.brz_catalog`, `bronze.brz_customers`, `bronze.brz_pos_system` (`select *` of the seeds). Database file `daily_grind.duckdb` in repo root.

- [ ] **Step 1: Confirm dbt has no project yet (red)**

Run: `.venv/Scripts/dbt.exe build --profiles-dir .`
Expected: error containing `No dbt_project.yml found`.

- [ ] **Step 2: Project and profile**

Create `dbt_project.yml`:

```yaml
name: daily_grind
version: "1.0.0"
profile: daily_grind

model-paths: ["models"]
seed-paths: ["seeds"]
test-paths: ["tests"]
macro-paths: ["macros"]
clean-targets: ["target", "dbt_packages"]

seeds:
  daily_grind:
    +schema: raw
    raw_catalog:
      +column_types: {item_code: varchar, description: varchar, unit_price: varchar}
    raw_customers:
      +column_types: {cust_email: varchar, full_name: varchar, tier: varchar, updated_at: varchar}
    raw_pos_system:
      +column_types: {tx_id: varchar, sale_timestamp: varchar, customer_contact: varchar, items_sold: varchar, store_metadata: varchar}

models:
  daily_grind:
    bronze:
      +schema: bronze
      +materialized: view
    silver:
      +schema: silver
      +materialized: view
    gold:
      +schema: gold
      +materialized: table
```

Create `profiles.yml`:

```yaml
daily_grind:
  target: dev
  outputs:
    dev:
      type: duckdb
      path: daily_grind.duckdb
      threads: 4
```

Create `macros/generate_schema_name.sql`:

```sql
{#- Use the layer name (raw / bronze / silver / gold) as the schema, without a target prefix. -#}
{% macro generate_schema_name(custom_schema_name, node) -%}
    {%- if custom_schema_name is none -%}
        {{ target.schema }}
    {%- else -%}
        {{ custom_schema_name | trim }}
    {%- endif -%}
{%- endmacro %}
```

- [ ] **Step 3: Bronze models**

Create `models/bronze/brz_catalog.sql`:

```sql
-- Bronze: vendor file as delivered (after structural repair), every column varchar.
select * from {{ ref('raw_catalog') }}
```

Create `models/bronze/brz_customers.sql`:

```sql
-- Bronze: vendor file as delivered (after structural repair), every column varchar.
select * from {{ ref('raw_customers') }}
```

Create `models/bronze/brz_pos_system.sql`:

```sql
-- Bronze: vendor file as delivered (after structural repair), every column varchar.
select * from {{ ref('raw_pos_system') }}
```

Create `models/bronze/_bronze.yml`:

```yaml
version: 2

models:
  - name: brz_catalog
    description: "Bronze product catalog. Grain: one row per catalog line as delivered. No cleaning; all columns varchar."
  - name: brz_customers
    description: "Bronze loyalty customers. Grain: one row per source record (duplicates kept). No cleaning; all columns varchar."
  - name: brz_pos_system
    description: "Bronze POS transaction log. Grain: one row per transaction; items_sold and store_metadata still nested. All columns varchar."
```

- [ ] **Step 4: Build (green)**

Run: `.venv/Scripts/python.exe scripts/preprocess.py && .venv/Scripts/dbt.exe build --profiles-dir .`
Expected (the warning is expected until Task 5 adds Gold models):
```
[WARNING]: Configuration paths exist in your dbt_project.yml file which do not apply to any resources.
Done. PASS=6 WARN=0 ERROR=0 SKIP=0 NO-OP=0 REUSED=0 TOTAL=6
```

- [ ] **Step 5: Commit**

```bash
git add dbt_project.yml profiles.yml macros/generate_schema_name.sql models/bronze
git commit -m "feat: add dbt project, raw seeds config and Bronze views

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

---

### Task 3: Silver — catalog and customers

**Files:**
- Create: `macros/title_case.sql`, `models/silver/stg_catalog.sql`, `models/silver/stg_catalog.yml`, `models/silver/stg_customers.sql`, `models/silver/stg_customers.yml`, `tests/assert_customer_latest_is_unique.sql`

**Interfaces:**
- Consumes: `bronze.brz_catalog`, `bronze.brz_customers`.
- Produces: macro `title_case(expr)` (SQL expression, NULL-safe). `silver.stg_catalog(item_code VARCHAR, item_category VARCHAR, item_category_sub VARCHAR, unit_price DECIMAL(10,2))`. `silver.stg_customers(cust_email VARCHAR, full_name VARCHAR, tier VARCHAR, updated_at TIMESTAMP, is_latest BOOLEAN)`.

- [ ] **Step 1: Confirm the models do not exist yet (red)**

Run: `.venv/Scripts/python.exe -c "import duckdb; con = duckdb.connect('daily_grind.duckdb', read_only=True); print(con.sql('select * from silver.stg_catalog').fetchall())"`
Expected: `CatalogException` — table `stg_catalog` does not exist.

- [ ] **Step 2: Title Case macro**

Create `macros/title_case.sql`:

```sql
{#- Title Case a string: trim, collapse repeated spaces, capitalise each word. NULL stays NULL. -#}
{% macro title_case(expr) -%}
array_to_string(
    list_transform(
        list_filter(string_split(lower(trim({{ expr }})), ' '), lambda w: w <> ''),
        lambda w: upper(left(w, 1)) || substr(w, 2)
    ),
    ' '
)
{%- endmacro %}
```

- [ ] **Step 3: Catalog model and tests**

Create `models/silver/stg_catalog.sql`:

```sql
-- Grain: one row per item_code. Codes upper-cased; description split into category / sub-category; price cast.
with source as (
    select
        upper(trim(item_code)) as item_code,
        trim(description) as description,
        try_cast(nullif(regexp_replace(unit_price, '[$\s]', '', 'g'), '') as decimal(10, 2)) as unit_price
    from {{ ref('brz_catalog') }}
)

select
    item_code,
    case
        when regexp_matches(description, '\s[-|]\s') then trim(regexp_extract(description, '^(.*?)\s[-|]\s', 1))
        else 'Unknown'
    end as item_category,
    case
        when regexp_matches(description, '\s[-|]\s') then trim(regexp_extract(description, '\s[-|]\s(.*)$', 1))
        else description
    end as item_category_sub,
    unit_price
from source
```

Create `models/silver/stg_catalog.yml`:

```yaml
version: 2

models:
  - name: stg_catalog
    description: "Cleaned catalog. Grain: one row per item_code. Codes upper-cased; '$' and spaces stripped from price; description split on ' - ' or ' | ' (no separator -> category 'Unknown')."
    columns:
      - name: item_code
        description: "Upper-case, trimmed item code. Primary key."
        data_tests: [unique, not_null]
      - name: item_category
        description: "Text before the separator, e.g. Beverage."
        data_tests: [not_null]
      - name: item_category_sub
        description: "Text after the separator, e.g. Latte."
        data_tests: [not_null]
      - name: unit_price
        description: "Price in USD, DECIMAL(10,2). NULL would mean an unparseable price."
        data_tests: [not_null]
```

- [ ] **Step 4: Customers model and tests**

Create `models/silver/stg_customers.sql`:

```sql
-- Grain: one row per source customer record (history kept). is_latest marks the record dim_customer uses.
with source as (
    select
        case when lower(trim(cust_email)) in ('', 'null') then null else lower(trim(cust_email)) end as cust_email,
        trim(full_name) as raw_full_name,
        trim(tier) as raw_tier,
        try_cast(trim(updated_at) as timestamp) as updated_at
    from {{ ref('brz_customers') }}
),

cleaned as (
    select
        cust_email,
        {{ title_case("case when raw_full_name like '%,%'
                then split_part(raw_full_name, ',', 2) || ' ' || split_part(raw_full_name, ',', 1)
                else raw_full_name end") }} as full_name,
        case
            when raw_tier is null or upper(raw_tier) in ('', 'NONE') then 'None'
            else {{ title_case('raw_tier') }}
        end as tier,
        updated_at
    from source
)

select
    cust_email,
    full_name,
    tier,
    updated_at,
    cust_email is not null
        and row_number() over (partition by cust_email order by updated_at desc nulls last, full_name) = 1
        as is_latest
from cleaned
```

Create `models/silver/stg_customers.yml`:

```yaml
version: 2

models:
  - name: stg_customers
    description: "Cleaned loyalty records with history. Grain: one row per source record. Email lower-cased ('null'/blank -> NULL); names Title Case with 'Last, First' swapped; tier Title Case with NONE/blank -> None. is_latest = newest updated_at per email (tie-break full_name)."
    columns:
      - name: cust_email
        description: "Lower-case email; NULL when missing or the literal 'null'."
      - name: full_name
        description: "Title Case name."
      - name: tier
        description: "Gold, Silver or None."
        data_tests:
          - accepted_values:
              arguments:
                values: ["Gold", "Silver", "None"]
      - name: updated_at
        description: "Record timestamp."
        data_tests: [not_null]
      - name: is_latest
        description: "True for exactly one record per non-null email."
```

Create `tests/assert_customer_latest_is_unique.sql`:

```sql
-- Exactly one is_latest record per non-null email.
select
    cust_email,
    count(*) filter (where is_latest) as latest_records
from {{ ref('stg_customers') }}
where cust_email is not null
group by cust_email
having count(*) filter (where is_latest) <> 1
```

- [ ] **Step 5: Build (green)**

Run: `.venv/Scripts/dbt.exe build --profiles-dir .`
Expected:
```
[WARNING]: Configuration paths exist in your dbt_project.yml file which do not apply to any resources.
Done. PASS=16 WARN=0 ERROR=0 SKIP=0 NO-OP=0 REUSED=0 TOTAL=16
```

- [ ] **Step 6: Check row-level output**

Run: `.venv/Scripts/python.exe -c "import duckdb; con = duckdb.connect('daily_grind.duckdb', read_only=True); [print(repr(r)) for r in con.sql('''select * from silver.stg_catalog order by item_code''').fetchall()]"`
Expected:
```
('DRNK-001', 'Beverage', 'Espresso', Decimal('3.50'))
('DRNK-002', 'Beverage', 'Latte', Decimal('4.75'))
('DRNK-003', 'Beverage', 'Cold Brew', Decimal('4.50'))
('FOOD-001', 'Food', 'Croissant', Decimal('3.00'))
('FOOD-002', 'Food', 'Blueberry Muffin', Decimal('3.50'))
('MERCH-001', 'Merch', 'Ceramic Mug', Decimal('12.00'))
('UNKNOWN_ITEM', 'Unknown', 'Mystery Box', Decimal('0.00'))
```

Run: `.venv/Scripts/python.exe -c "import duckdb; con = duckdb.connect('daily_grind.duckdb', read_only=True); [print(repr(r)) for r in con.sql('''select * from silver.stg_customers order by cust_email nulls last, updated_at''').fetchall()]"`
Expected:
```
('alice.smith@example.com', 'Alice Smith', 'Gold', datetime.datetime(2026, 1, 1, 0, 0), False)
('alice.smith@example.com', 'Alice S.', 'Gold', datetime.datetime(2026, 8, 1, 0, 0), True)
('b.jones@example.com', 'Bob Jones', 'Silver', datetime.datetime(2026, 2, 15, 0, 0), True)
('c.davis@example.com', 'Charlie Davis', 'None', datetime.datetime(2026, 3, 10, 0, 0), True)
('d.wilson@example.com', 'Wilson Diana', 'Gold', datetime.datetime(2026, 5, 20, 0, 0), True)
(None, 'Guest User', 'None', datetime.datetime(2026, 4, 1, 0, 0), False)
```

- [ ] **Step 7: Commit**

```bash
git add macros/title_case.sql models/silver/stg_catalog.sql models/silver/stg_catalog.yml models/silver/stg_customers.sql models/silver/stg_customers.yml tests/assert_customer_latest_is_unique.sql
git commit -m "feat: add Silver catalog and customer models with tests

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

---

### Task 4: Silver — POS orders and order items

**Files:**
- Create: `models/silver/stg_pos_orders.sql`, `models/silver/stg_pos_orders.yml`, `models/silver/stg_pos_order_items.sql`, `models/silver/stg_pos_order_items.yml`, `tests/assert_pos_items_exist_in_catalog.sql`

**Interfaces:**
- Consumes: `bronze.brz_pos_system`, macro `title_case`, `silver.stg_catalog` (warn test only).
- Produces: `silver.stg_pos_orders(tx_id VARCHAR, sale_timestamp TIMESTAMP, customer_contact VARCHAR, contact_type VARCHAR ∈ {email, invalid, guest}, store_id VARCHAR, city VARCHAR, region VARCHAR)`. `silver.stg_pos_order_items(tx_id VARCHAR, item_code VARCHAR, quantity INTEGER)` unique on `(tx_id, item_code)`.

- [ ] **Step 1: Confirm the models do not exist yet (red)**

Run: `.venv/Scripts/python.exe -c "import duckdb; con = duckdb.connect('daily_grind.duckdb', read_only=True); print(con.sql('select * from silver.stg_pos_orders').fetchall())"`
Expected: `CatalogException` — table `stg_pos_orders` does not exist.

- [ ] **Step 2: Orders model and tests**

Create `models/silver/stg_pos_orders.sql`:

```sql
-- Grain: one row per tx_id. Timestamp parsed from two formats; contact classified; store JSON extracted.
with source as (
    select
        trim(tx_id) as tx_id,
        trim(sale_timestamp) as raw_sale_timestamp,
        case when trim(customer_contact) = '' then null else lower(trim(customer_contact)) end as customer_contact,
        store_metadata
    from {{ ref('brz_pos_system') }}
)

select
    tx_id,
    coalesce(
        try_strptime(raw_sale_timestamp, '%m/%d/%Y %H:%M'),
        try_strptime(raw_sale_timestamp, '%Y-%m-%d %H:%M:%S')
    ) as sale_timestamp,
    customer_contact,
    case
        when customer_contact is null then 'guest'
        when regexp_full_match(customer_contact, '[^@\s]+@[^@\s]+\.[^@\s]+') then 'email'
        else 'invalid'
    end as contact_type,
    trim(json_extract_string(store_metadata, '$.store_id')) as store_id,
    {{ title_case("json_extract_string(store_metadata, '$.city')") }} as city,
    upper(trim(json_extract_string(store_metadata, '$.region'))) as region
from source
```

Create `models/silver/stg_pos_orders.yml`:

```yaml
version: 2

models:
  - name: stg_pos_orders
    description: "Transaction headers. Grain: one row per tx_id. sale_timestamp parsed from 'MM/DD/YYYY HH:MM' or 'YYYY-MM-DD HH:MM:SS' (store-local, no time zone). Store attributes extracted from store_metadata JSON."
    columns:
      - name: tx_id
        description: "Transaction id. Primary key."
        data_tests: [unique, not_null]
      - name: sale_timestamp
        description: "Sale time; NULL would mean an unknown date format."
        data_tests: [not_null]
      - name: customer_contact
        description: "Lower-case contact as given; NULL when blank."
      - name: contact_type
        description: "email (valid address), invalid (not an address) or guest (blank)."
        data_tests:
          - accepted_values:
              arguments:
                values: ["email", "invalid", "guest"]
      - name: store_id
        description: "Store id from store_metadata JSON."
        data_tests: [not_null]
      - name: city
        description: "Title Case city."
      - name: region
        description: "Upper-case region code."
```

- [ ] **Step 3: Order items model and tests**

Create `models/silver/stg_pos_order_items.sql`:

```sql
-- Grain: one row per (tx_id, item_code). items_sold split on '|', "<qty>x <code>" parsed; repeats of a code summed.
with tokens as (
    select
        trim(tx_id) as tx_id,
        trim(unnest(string_split(items_sold, '|'))) as item_token
    from {{ ref('brz_pos_system') }}
),

parsed as (
    select
        tx_id,
        try_cast(regexp_extract(item_token, '^(-?\d+)\s*x\s+(\S+)$', 1) as integer) as quantity,
        upper(regexp_extract(item_token, '^(-?\d+)\s*x\s+(\S+)$', 2)) as item_code
    from tokens
)

select
    tx_id,
    nullif(item_code, '') as item_code,
    cast(sum(quantity) as integer) as quantity
from parsed
group by tx_id, item_code
```

Create `models/silver/stg_pos_order_items.yml`:

```yaml
version: 2

models:
  - name: stg_pos_order_items
    description: "Line items. Grain: one row per (tx_id, item_code). items_sold split on '|', each '<qty>x <code>' parsed; repeated codes in one transaction are summed. quantity is signed (-1 = return)."
    data_tests:
      - unique:
          column_name: "tx_id || '|' || item_code"
    columns:
      - name: tx_id
        description: "Transaction id."
        data_tests:
          - not_null
          - relationships:
              arguments:
                to: ref('stg_pos_orders')
                field: tx_id
      - name: item_code
        description: "Upper-case code as sold; NULL would mean an unparseable token."
        data_tests: [not_null]
      - name: quantity
        description: "Signed quantity; NULL would mean an unparseable token."
        data_tests: [not_null]
```

Create `tests/assert_pos_items_exist_in_catalog.sql`:

```sql
{{ config(severity='warn') }}
-- Warn (not fail) when the POS sells a code missing from the catalog; Gold maps it to UNKNOWN_ITEM.
select distinct
    l.tx_id,
    l.item_code
from {{ ref('stg_pos_order_items') }} as l
left join {{ ref('stg_catalog') }} as c
    on l.item_code = c.item_code
where c.item_code is null
```

- [ ] **Step 4: Build (green)**

Run: `.venv/Scripts/dbt.exe build --profiles-dir .`
Expected:
```
[WARNING]: Configuration paths exist in your dbt_project.yml file which do not apply to any resources.
Done. PASS=29 WARN=0 ERROR=0 SKIP=0 NO-OP=0 REUSED=0 TOTAL=29
```

- [ ] **Step 5: Check row-level output**

Run: `.venv/Scripts/python.exe -c "import duckdb; con = duckdb.connect('daily_grind.duckdb', read_only=True); [print(repr(r)) for r in con.sql('''select * from silver.stg_pos_orders order by tx_id''').fetchall()]"`
Expected:
```
('TX-1001', datetime.datetime(2026, 8, 1, 7, 15), 'alice.smith@example.com', 'email', 'S-1', 'Seattle', 'WA')
('TX-1002', datetime.datetime(2026, 8, 1, 8, 22), 'b.jones@example.com', 'email', 'S-2', 'Portland', 'OR')
('TX-1003', datetime.datetime(2026, 8, 1, 8, 45), None, 'guest', 'S-1', 'Seattle', 'WA')
('TX-1004', datetime.datetime(2026, 8, 2, 9, 10), 'd.wilson@example.com', 'email', 'S-1', 'Seattle', 'WA')
('TX-1005', datetime.datetime(2026, 8, 2, 10, 5), 'e.brown@example.com', 'email', 'S-2', 'Portland', 'OR')
('TX-1006', datetime.datetime(2026, 8, 3, 7, 30), 'alice.smith@example.com', 'email', 'S-1', 'Seattle', 'WA')
('TX-1007', datetime.datetime(2026, 8, 3, 11, 15), 'c.davis@example.com', 'email', 'S-3', 'Vancouver', 'BC')
('TX-1008', datetime.datetime(2026, 8, 4, 8, 0), 'invalid_email', 'invalid', 'S-1', 'Seattle', 'WA')
```

Run: `.venv/Scripts/python.exe -c "import duckdb; con = duckdb.connect('daily_grind.duckdb', read_only=True); [print(repr(r)) for r in con.sql('''select * from silver.stg_pos_order_items order by tx_id, item_code''').fetchall()]"`
Expected:
```
('TX-1001', 'DRNK-001', 1)
('TX-1001', 'FOOD-001', 2)
('TX-1002', 'DRNK-002', 1)
('TX-1003', 'DRNK-003', 1)
('TX-1004', 'DRNK-002', 1)
('TX-1004', 'MERCH-001', 1)
('TX-1005', 'FOOD-002', -1)
('TX-1006', 'DRNK-001', 1)
('TX-1007', 'DRNK-003', 2)
('TX-1008', 'DRNK-002', 1)
('TX-1008', 'FOOD-001', 1)
```

- [ ] **Step 6: Commit**

```bash
git add models/silver/stg_pos_orders.sql models/silver/stg_pos_orders.yml models/silver/stg_pos_order_items.sql models/silver/stg_pos_order_items.yml tests/assert_pos_items_exist_in_catalog.sql
git commit -m "feat: add Silver POS order and line-item models with tests

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

---

### Task 5: Gold — dimensions

**Files:**
- Create: `models/gold/dim_item.sql`, `models/gold/dim_item.yml`, `models/gold/dim_store.sql`, `models/gold/dim_store.yml`, `models/gold/dim_date.sql`, `models/gold/dim_date.yml`, `models/gold/dim_customer.sql`, `models/gold/dim_customer.yml`

**Interfaces:**
- Consumes: `silver.stg_catalog`, `silver.stg_customers`, `silver.stg_pos_orders`.
- Produces (tables, columns exactly as `docs/erd.md` §3): `gold.dim_item`, `gold.dim_store`, `gold.dim_date`, `gold.dim_customer` with sentinel ids `__guest__` and `__unknown__`.

- [ ] **Step 1: Confirm the models do not exist yet (red)**

Run: `.venv/Scripts/python.exe -c "import duckdb; con = duckdb.connect('daily_grind.duckdb', read_only=True); print(con.sql('select * from gold.dim_customer').fetchall())"`
Expected: `CatalogException` — schema or table `gold.dim_customer` does not exist.

- [ ] **Step 2: Item, store and date dimensions**

Create `models/gold/dim_item.sql`:

```sql
-- Grain: one row per item_code (includes UNKNOWN_ITEM, used for POS codes missing from the catalog).
select
    item_code,
    item_category,
    item_category_sub,
    unit_price
from {{ ref('stg_catalog') }}
```

Create `models/gold/dim_item.yml`:

```yaml
version: 2

models:
  - name: dim_item
    description: "Product dimension. Grain: one row per item_code."
    columns:
      - name: item_code
        description: "Primary key."
        data_tests: [unique, not_null]
      - name: item_category
        description: "e.g. Beverage, Food, Merch, Unknown."
        data_tests: [not_null]
      - name: item_category_sub
        description: "e.g. Latte."
        data_tests: [not_null]
      - name: unit_price
        description: "Current catalog price, USD, DECIMAL(10,2)."
        data_tests: [not_null]
```

Create `models/gold/dim_store.sql`:

```sql
-- Grain: one row per store_id, extracted from POS store_metadata. Conflicting attributes fail the unique test.
select distinct
    store_id,
    city,
    region
from {{ ref('stg_pos_orders') }}
```

Create `models/gold/dim_store.yml`:

```yaml
version: 2

models:
  - name: dim_store
    description: "Store dimension. Grain: one row per store_id. A store with conflicting city/region fails the unique test."
    columns:
      - name: store_id
        description: "Primary key."
        data_tests: [unique, not_null]
      - name: city
        description: "Title Case city."
        data_tests: [not_null]
      - name: region
        description: "Upper-case region code."
        data_tests: [not_null]
```

Create `models/gold/dim_date.sql`:

```sql
-- Grain: one row per calendar day from the first to the last sale date.
with bounds as (
    select
        min(cast(sale_timestamp as date)) as first_day,
        max(cast(sale_timestamp as date)) as last_day
    from {{ ref('stg_pos_orders') }}
),

days as (
    select cast(unnest(generate_series(first_day, last_day, interval 1 day)) as date) as date_day
    from bounds
)

select
    date_day,
    cast(year(date_day) as integer) as year,
    cast(month(date_day) as integer) as month,
    monthname(date_day) as month_name,
    cast(date_trunc('week', date_day) as date) as week_start_date,
    cast(isodow(date_day) as integer) as day_of_week,
    dayname(date_day) as day_name,
    isodow(date_day) in (6, 7) as is_weekend
from days
```

Create `models/gold/dim_date.yml`:

```yaml
version: 2

models:
  - name: dim_date
    description: "Calendar dimension. Grain: one row per day from first to last sale date. week_start_date is Monday; day_of_week is ISO (1 = Monday)."
    columns:
      - name: date_day
        description: "Primary key."
        data_tests: [unique, not_null]
```

- [ ] **Step 3: Customer dimension**

Create `models/gold/dim_customer.sql`:

```sql
-- Grain: one row per customer_id. Latest record per email (member), POS emails not in the loyalty list
-- (inferred), plus the sentinel rows __guest__ and __unknown__ so every sale joins to a customer.
with members as (
    select
        cust_email as customer_id,
        cust_email,
        full_name,
        tier,
        updated_at,
        'member' as customer_type
    from {{ ref('stg_customers') }}
    where is_latest
),

inferred as (
    select
        customer_contact as customer_id,
        customer_contact as cust_email,
        'Unknown' as full_name,
        'None' as tier,
        min(sale_timestamp) as updated_at,
        'inferred' as customer_type
    from {{ ref('stg_pos_orders') }}
    where contact_type = 'email'
        and customer_contact not in (select customer_id from members)
    group by customer_contact
),

sentinels as (
    select * from (values
        ('__guest__', null, 'Guest', 'None', null, 'guest'),
        ('__unknown__', null, 'Unknown', 'None', null, 'unknown')
    ) as t (customer_id, cust_email, full_name, tier, updated_at, customer_type)
)

select * from members
union all
select * from inferred
union all
select
    customer_id,
    cast(cust_email as varchar),
    full_name,
    tier,
    cast(updated_at as timestamp),
    customer_type
from sentinels
```

Create `models/gold/dim_customer.yml`:

```yaml
version: 2

models:
  - name: dim_customer
    description: "Customer dimension. Grain: one row per customer_id. customer_type: member (latest loyalty record), inferred (valid POS email not in loyalty list; updated_at = first purchase), guest (__guest__, blank contact), unknown (__unknown__, invalid contact)."
    columns:
      - name: customer_id
        description: "Lower-case email, or __guest__ / __unknown__. Primary key."
        data_tests: [unique, not_null]
      - name: cust_email
        description: "Lower-case email; NULL for guest and unknown."
      - name: full_name
        description: "Title Case name; 'Unknown' for inferred, 'Guest' / 'Unknown' for sentinels."
        data_tests: [not_null]
      - name: tier
        description: "Gold, Silver or None."
        data_tests:
          - not_null
          - accepted_values:
              arguments:
                values: ["Gold", "Silver", "None"]
      - name: updated_at
        description: "Latest record time (member) or first purchase (inferred); NULL for sentinels."
      - name: customer_type
        description: "member, inferred, guest or unknown."
        data_tests:
          - accepted_values:
              arguments:
                values: ["member", "inferred", "guest", "unknown"]
```

- [ ] **Step 4: Build (green)**

Run: `.venv/Scripts/dbt.exe build --profiles-dir .`
Expected (the configuration-path warning is now gone):
```
Done. PASS=50 WARN=0 ERROR=0 SKIP=0 NO-OP=0 REUSED=0 TOTAL=50
```

- [ ] **Step 5: Check row-level output**

Run: `.venv/Scripts/python.exe -c "import duckdb; con = duckdb.connect('daily_grind.duckdb', read_only=True); [print(repr(r)) for r in con.sql('''select * from gold.dim_customer order by customer_type, customer_id''').fetchall()]"`
Expected:
```
('__guest__', None, 'Guest', 'None', None, 'guest')
('e.brown@example.com', 'e.brown@example.com', 'Unknown', 'None', datetime.datetime(2026, 8, 2, 10, 5), 'inferred')
('alice.smith@example.com', 'alice.smith@example.com', 'Alice S.', 'Gold', datetime.datetime(2026, 8, 1, 0, 0), 'member')
('b.jones@example.com', 'b.jones@example.com', 'Bob Jones', 'Silver', datetime.datetime(2026, 2, 15, 0, 0), 'member')
('c.davis@example.com', 'c.davis@example.com', 'Charlie Davis', 'None', datetime.datetime(2026, 3, 10, 0, 0), 'member')
('d.wilson@example.com', 'd.wilson@example.com', 'Wilson Diana', 'Gold', datetime.datetime(2026, 5, 20, 0, 0), 'member')
('__unknown__', None, 'Unknown', 'None', None, 'unknown')
```

Run: `.venv/Scripts/python.exe -c "import duckdb; con = duckdb.connect('daily_grind.duckdb', read_only=True); [print(repr(r)) for r in con.sql('''select * from gold.dim_store order by store_id''').fetchall()]"`
Expected:
```
('S-1', 'Seattle', 'WA')
('S-2', 'Portland', 'OR')
('S-3', 'Vancouver', 'BC')
```

Run: `.venv/Scripts/python.exe -c "import duckdb; con = duckdb.connect('daily_grind.duckdb', read_only=True); [print(repr(r)) for r in con.sql('''select * from gold.dim_date order by date_day''').fetchall()]"`
Expected:
```
(datetime.date(2026, 8, 1), 2026, 8, 'August', datetime.date(2026, 7, 27), 6, 'Saturday', True)
(datetime.date(2026, 8, 2), 2026, 8, 'August', datetime.date(2026, 7, 27), 7, 'Sunday', True)
(datetime.date(2026, 8, 3), 2026, 8, 'August', datetime.date(2026, 8, 3), 1, 'Monday', False)
(datetime.date(2026, 8, 4), 2026, 8, 'August', datetime.date(2026, 8, 3), 2, 'Tuesday', False)
```

Run: `.venv/Scripts/python.exe -c "import duckdb; con = duckdb.connect('daily_grind.duckdb', read_only=True); [print(repr(r)) for r in con.sql('''select item_code, item_category, item_category_sub, unit_price from gold.dim_item order by item_code''').fetchall()]"`
Expected:
```
('DRNK-001', 'Beverage', 'Espresso', Decimal('3.50'))
('DRNK-002', 'Beverage', 'Latte', Decimal('4.75'))
('DRNK-003', 'Beverage', 'Cold Brew', Decimal('4.50'))
('FOOD-001', 'Food', 'Croissant', Decimal('3.00'))
('FOOD-002', 'Food', 'Blueberry Muffin', Decimal('3.50'))
('MERCH-001', 'Merch', 'Ceramic Mug', Decimal('12.00'))
('UNKNOWN_ITEM', 'Unknown', 'Mystery Box', Decimal('0.00'))
```

- [ ] **Step 6: Commit**

```bash
git add models/gold/dim_item.sql models/gold/dim_item.yml models/gold/dim_store.sql models/gold/dim_store.yml models/gold/dim_date.sql models/gold/dim_date.yml models/gold/dim_customer.sql models/gold/dim_customer.yml
git commit -m "feat: add Gold dimension tables with tests

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

---

### Task 6: Gold — facts and reconciliation tests

**Files:**
- Create: `models/gold/fct_order_items.sql`, `models/gold/fct_order_items.yml`, `models/gold/fct_orders.sql`, `models/gold/fct_orders.yml`, `tests/assert_quantity_reconciles_to_bronze.sql`, `tests/assert_order_count_reconciles_to_bronze.sql`, `tests/assert_order_revenue_equals_lines.sql`, `tests/assert_order_fraction_sums_to_one.sql`

**Interfaces:**
- Consumes: `silver.stg_pos_orders`, `silver.stg_pos_order_items`, `gold.dim_item`; relationship tests reference all four dimensions.
- Produces: `gold.fct_order_items` and `gold.fct_orders`, columns exactly as `docs/erd.md` §3. `fct_orders` is aggregated from `fct_order_items`.

- [ ] **Step 1: Write the reconciliation tests first**

Create `tests/assert_quantity_reconciles_to_bronze.sql`:

```sql
-- Total signed quantity parsed straight from the raw items_sold strings must equal the line fact.
with bronze as (
    select sum(list_sum(list_transform(
        regexp_extract_all(items_sold, '(-?\d+)\s*x\s', 1), lambda q: cast(q as integer)
    ))) as qty
    from {{ ref('brz_pos_system') }}
),

gold as (
    select sum(quantity) as qty from {{ ref('fct_order_items') }}
)

select bronze.qty as bronze_qty, gold.qty as gold_qty
from bronze, gold
where bronze.qty is distinct from gold.qty
```

Create `tests/assert_order_count_reconciles_to_bronze.sql`:

```sql
-- Every distinct raw transaction appears exactly once in fct_orders.
with bronze as (
    select count(distinct trim(tx_id)) as n from {{ ref('brz_pos_system') }}
),

gold as (
    select count(*) as n from {{ ref('fct_orders') }}
)

select bronze.n as bronze_orders, gold.n as gold_orders
from bronze, gold
where bronze.n <> gold.n
```

Create `tests/assert_order_revenue_equals_lines.sql`:

```sql
-- Order revenue must equal the sum of its line revenue.
select
    o.tx_id,
    o.order_revenue,
    sum(i.line_revenue) as line_total
from {{ ref('fct_orders') }} as o
inner join {{ ref('fct_order_items') }} as i
    on o.tx_id = i.tx_id
group by o.tx_id, o.order_revenue
having o.order_revenue <> sum(i.line_revenue)
```

Create `tests/assert_order_fraction_sums_to_one.sql`:

```sql
-- order_fraction per transaction sums to 1 (tolerance for DECIMAL(10,4) rounding, e.g. 3 x 0.3333).
select
    tx_id,
    sum(order_fraction) as total_fraction
from {{ ref('fct_order_items') }}
group by tx_id
having abs(sum(order_fraction) - 1) > 0.001
```

- [ ] **Step 2: Run to verify they fail (red)**

Run: `.venv/Scripts/dbt.exe build --profiles-dir .`
Expected: the build still exits 0, but prints four warnings of the form
`[WARNING]: Test 'test.daily_grind.assert_order_revenue_equals_lines' (tests\assert_order_revenue_equals_lines.sql) depends on a node named 'fct_orders' in package '' which was not found`
— dbt disables a singular test whose `ref()` target is missing instead of failing it, so these four tests do not run yet.

- [ ] **Step 3: Line-item fact**

Create `models/gold/fct_order_items.sql`:

```sql
-- Grain: one row per (tx_id, item_code). Codes missing from the catalog map to UNKNOWN_ITEM.
-- quantity is signed (returns negative); order_fraction = 1 / number of lines in the transaction.
with orders as (
    select
        tx_id,
        sale_timestamp,
        case contact_type
            when 'guest' then '__guest__'
            when 'invalid' then '__unknown__'
            else customer_contact
        end as customer_id,
        store_id
    from {{ ref('stg_pos_orders') }}
),

lines as (
    select
        l.tx_id,
        coalesce(i.item_code, 'UNKNOWN_ITEM') as item_code,
        cast(sum(l.quantity) as integer) as quantity
    from {{ ref('stg_pos_order_items') }} as l
    left join {{ ref('dim_item') }} as i
        on l.item_code = i.item_code
    group by l.tx_id, coalesce(i.item_code, 'UNKNOWN_ITEM')
)

select
    l.tx_id,
    l.item_code,
    o.sale_timestamp,
    cast(o.sale_timestamp as date) as date_day,
    o.customer_id,
    o.store_id,
    l.quantity,
    l.quantity < 0 as is_return,
    i.unit_price,
    cast(l.quantity * i.unit_price as decimal(10, 2)) as line_revenue,
    cast(1.0 / count(*) over (partition by l.tx_id) as decimal(10, 4)) as order_fraction
from lines as l
inner join orders as o
    on l.tx_id = o.tx_id
inner join {{ ref('dim_item') }} as i
    on l.item_code = i.item_code
```

Create `models/gold/fct_order_items.yml`:

```yaml
version: 2

models:
  - name: fct_order_items
    description: "Order line fact. Grain: one row per (tx_id, item_code). quantity signed (-1 = return); line_revenue = quantity x unit_price; order_fraction = 1 / lines in the transaction."
    data_tests:
      - unique:
          column_name: "tx_id || '|' || item_code"
    columns:
      - name: tx_id
        description: "FK to fct_orders."
        data_tests:
          - not_null
          - relationships:
              arguments:
                to: ref('fct_orders')
                field: tx_id
      - name: item_code
        description: "FK to dim_item; codes missing from the catalog map to UNKNOWN_ITEM."
        data_tests:
          - not_null
          - relationships:
              arguments:
                to: ref('dim_item')
                field: item_code
      - name: date_day
        description: "FK to dim_date."
        data_tests:
          - relationships:
              arguments:
                to: ref('dim_date')
                field: date_day
      - name: customer_id
        description: "FK to dim_customer."
        data_tests:
          - not_null
          - relationships:
              arguments:
                to: ref('dim_customer')
                field: customer_id
      - name: store_id
        description: "FK to dim_store."
        data_tests:
          - not_null
          - relationships:
              arguments:
                to: ref('dim_store')
                field: store_id
      - name: quantity
        description: "Signed quantity; -1 = one unit returned."
        data_tests: [not_null]
      - name: unit_price
        description: "Catalog price, USD."
        data_tests: [not_null]
      - name: line_revenue
        description: "quantity x unit_price, USD."
        data_tests: [not_null]
```

- [ ] **Step 4: Order fact**

Create `models/gold/fct_orders.sql`:

```sql
-- Grain: one row per tx_id, aggregated from fct_order_items so both facts always reconcile.
-- is_return_order is true only when every line is a return.
select
    tx_id,
    sale_timestamp,
    date_day,
    customer_id,
    store_id,
    cast(count(*) as integer) as line_count,
    cast(sum(quantity) as integer) as unit_count,
    cast(sum(line_revenue) as decimal(10, 2)) as order_revenue,
    bool_and(is_return) as is_return_order
from {{ ref('fct_order_items') }}
group by tx_id, sale_timestamp, date_day, customer_id, store_id
```

Create `models/gold/fct_orders.yml`:

```yaml
version: 2

models:
  - name: fct_orders
    description: "Order fact. Grain: one row per tx_id. Aggregated from fct_order_items. is_return_order = every line is a return (excluded from order count and AOV)."
    columns:
      - name: tx_id
        description: "Primary key."
        data_tests: [unique, not_null]
      - name: date_day
        description: "Sale date, FK to dim_date."
        data_tests:
          - not_null
          - relationships:
              arguments:
                to: ref('dim_date')
                field: date_day
      - name: customer_id
        description: "FK to dim_customer."
        data_tests:
          - not_null
          - relationships:
              arguments:
                to: ref('dim_customer')
                field: customer_id
      - name: store_id
        description: "FK to dim_store."
        data_tests:
          - not_null
          - relationships:
              arguments:
                to: ref('dim_store')
                field: store_id
      - name: order_revenue
        description: "Signed sum of line_revenue, USD."
        data_tests: [not_null]
```

- [ ] **Step 5: Build (green)**

Run: `.venv/Scripts/dbt.exe build --profiles-dir . --no-partial-parse`
(`--no-partial-parse` is required once here: with partial parsing, the four tests disabled in Step 2 stay disabled and the build reports `PASS=74 ... TOTAL=74`. Verified behaviour of dbt-core 1.12.4.)
Expected:
```
Done. PASS=78 WARN=0 ERROR=0 SKIP=0 NO-OP=0 REUSED=0 TOTAL=78
```

- [ ] **Step 6: Check row-level output and headline KPIs**

Run: `.venv/Scripts/python.exe -c "import duckdb; con = duckdb.connect('daily_grind.duckdb', read_only=True); [print(repr(r)) for r in con.sql('''select tx_id, customer_id, line_count, unit_count, order_revenue, is_return_order from gold.fct_orders order by tx_id''').fetchall()]"`
Expected:
```
('TX-1001', 'alice.smith@example.com', 2, 3, Decimal('9.50'), False)
('TX-1002', 'b.jones@example.com', 1, 1, Decimal('4.75'), False)
('TX-1003', '__guest__', 1, 1, Decimal('4.50'), False)
('TX-1004', 'd.wilson@example.com', 2, 2, Decimal('16.75'), False)
('TX-1005', 'e.brown@example.com', 1, -1, Decimal('-3.50'), True)
('TX-1006', 'alice.smith@example.com', 1, 1, Decimal('3.50'), False)
('TX-1007', 'c.davis@example.com', 1, 2, Decimal('9.00'), False)
('TX-1008', '__unknown__', 2, 2, Decimal('7.75'), False)
```

Run: `.venv/Scripts/python.exe -c "import duckdb; con = duckdb.connect('daily_grind.duckdb', read_only=True); [print(repr(r)) for r in con.sql('''select tx_id, item_code, quantity, is_return, line_revenue, order_fraction from gold.fct_order_items order by tx_id, item_code''').fetchall()]"`
Expected:
```
('TX-1001', 'DRNK-001', 1, False, Decimal('3.50'), Decimal('0.5000'))
('TX-1001', 'FOOD-001', 2, False, Decimal('6.00'), Decimal('0.5000'))
('TX-1002', 'DRNK-002', 1, False, Decimal('4.75'), Decimal('1.0000'))
('TX-1003', 'DRNK-003', 1, False, Decimal('4.50'), Decimal('1.0000'))
('TX-1004', 'DRNK-002', 1, False, Decimal('4.75'), Decimal('0.5000'))
('TX-1004', 'MERCH-001', 1, False, Decimal('12.00'), Decimal('0.5000'))
('TX-1005', 'FOOD-002', -1, True, Decimal('-3.50'), Decimal('1.0000'))
('TX-1006', 'DRNK-001', 1, False, Decimal('3.50'), Decimal('1.0000'))
('TX-1007', 'DRNK-003', 2, False, Decimal('9.00'), Decimal('1.0000'))
('TX-1008', 'DRNK-002', 1, False, Decimal('4.75'), Decimal('0.5000'))
('TX-1008', 'FOOD-001', 1, False, Decimal('3.00'), Decimal('0.5000'))
```

Run: `.venv/Scripts/python.exe -c "import duckdb; con = duckdb.connect('daily_grind.duckdb', read_only=True); [print(repr(r)) for r in con.sql('''select sum(order_revenue) as net_revenue, count(*) filter (where not is_return_order) as orders, round(sum(order_revenue) filter (where not is_return_order) / count(*) filter (where not is_return_order), 2) as aov from gold.fct_orders''').fetchall()]"`
Expected:
```
(Decimal('52.25'), 7, 7.96)
```

Hand calculation for the last query: 9.50 + 4.75 + 4.50 + 16.75 − 3.50 + 3.50 + 9.00 + 7.75 = 52.25 net revenue; 7 non-return orders; 55.75 ÷ 7 = 7.96 AOV.

- [ ] **Step 7: Check the schema matches the ERD**

Run:
```bash
.venv/Scripts/python.exe -c "
import duckdb, re, importlib.util
spec = importlib.util.spec_from_file_location('chk', 'scripts/check_erd_columns.py'); m = importlib.util.module_from_spec(spec); spec.loader.exec_module(m)
con = duckdb.connect('daily_grind.duckdb', read_only=True); errs = []
for t, cols in m.EXPECTED.items():
    got = con.sql(f\"select column_name, data_type from information_schema.columns where table_schema='gold' and table_name='{t}' order by ordinal_position\").fetchall()
    if [g[0] for g in got] != list(cols): errs.append((t, [g[0] for g in got]))
    errs += [(t, n, d) for n, d in got if re.sub(r'\(.*', '', d) != cols.get(n)]
print('ERD mismatches:', errs or 'none')
"
```
Expected: `ERD mismatches: none`

- [ ] **Step 8: Negative check — tests catch bad data**

Append two bad transactions to the generated seed (not to `raw/`):
```bash
cat >> seeds/raw_pos_system.csv <<'EOF'
TX-2001,2026-08-05 09:00:00,x@y.com,1x DRNK-001|1x FOOD-001|1x DRNK-001|1x NEW-999,"{""store_id"": ""S-1"", ""city"": ""Seattle"", ""region"": ""WA""}"
TX-2002,05.08.2026 09:00,x@y.com,1x DRNK-001,"{""store_id"": ""S-1"", ""city"": ""Seattle"", ""region"": ""WA""}"
EOF
.venv/Scripts/dbt.exe build --profiles-dir .
```
Expected: exit code 1; output includes `WARN 1 assert_pos_items_exist_in_catalog`, `FAIL 1 not_null_stg_pos_orders_sale_timestamp`, `SKIP relation gold.dim_customer`, `SKIP relation gold.fct_order_items`, `SKIP relation gold.fct_orders` (`gold.dim_item` still builds — it does not depend on POS data), and ends with `Done. PASS=33 WARN=1 ERROR=1 SKIP=43 NO-OP=0 REUSED=0 TOTAL=78`.

Restore and rebuild:
```bash
.venv/Scripts/python.exe scripts/preprocess.py && .venv/Scripts/dbt.exe build --profiles-dir .
```
Expected: `Done. PASS=78 WARN=0 ERROR=0 SKIP=0 NO-OP=0 REUSED=0 TOTAL=78`

- [ ] **Step 9: Commit**

```bash
git add models/gold/fct_order_items.sql models/gold/fct_order_items.yml models/gold/fct_orders.sql models/gold/fct_orders.yml tests/assert_quantity_reconciles_to_bronze.sql tests/assert_order_count_reconciles_to_bronze.sql tests/assert_order_revenue_equals_lines.sql tests/assert_order_fraction_sums_to_one.sql
git commit -m "feat: add Gold fact tables and reconciliation tests

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

---

### Task 7: Parquet export and CI

**Files:**
- Create: `scripts/export_gold.py`, `tests_py/test_export_gold.py`, `.github/workflows/pipeline.yml`

**Interfaces:**
- Consumes: `daily_grind.duckdb` with schema `gold`.
- Produces: `export_gold.export_gold(db_path: Path, out_dir: Path) -> list[Path]`; files `exports/<table>.parquet` for every Gold table; CI artifact `gold-parquet`.

- [ ] **Step 1: Write the failing tests**

Create `tests_py/test_export_gold.py`:

```python
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
```

- [ ] **Step 2: Run to verify they fail**

Run: `.venv/Scripts/python.exe -m pytest tests_py/test_export_gold.py -q`
Expected: collection error `ModuleNotFoundError: No module named 'export_gold'`.

- [ ] **Step 3: Implement the export**

Create `scripts/export_gold.py`:

```python
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
```

- [ ] **Step 4: Run tests and export**

Run: `.venv/Scripts/python.exe -m pytest tests_py -q`
Expected: `7 passed`

Run: `.venv/Scripts/python.exe scripts/export_gold.py`
Expected:
```
gold.dim_customer -> exports\dim_customer.parquet (7 rows)
gold.dim_date -> exports\dim_date.parquet (4 rows)
gold.dim_item -> exports\dim_item.parquet (7 rows)
gold.dim_store -> exports\dim_store.parquet (3 rows)
gold.fct_order_items -> exports\fct_order_items.parquet (11 rows)
gold.fct_orders -> exports\fct_orders.parquet (8 rows)
```

- [ ] **Step 5: CI workflow**

Create `.github/workflows/pipeline.yml`:

```yaml
name: pipeline

on:
  push:
    branches: [main]
  pull_request:

jobs:
  build:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v7

      - uses: actions/setup-python@v7
        with:
          python-version: "3.10"
          cache: pip

      - name: Install dependencies
        run: pip install -r requirements.txt

      - name: Pre-process raw CSVs into seeds
        run: python scripts/preprocess.py

      - name: Python unit tests
        run: python -m pytest tests_py -q

      - name: dbt build (seeds, models, tests)
        run: dbt build --profiles-dir .

      - name: Export Gold tables to Parquet
        run: python scripts/export_gold.py

      - uses: actions/upload-artifact@v7
        with:
          name: gold-parquet
          path: exports/
```

Run: `.venv/Scripts/python.exe -c "import yaml; d = yaml.safe_load(open('.github/workflows/pipeline.yml')); print([s.get('name', s.get('uses')) for s in d['jobs']['build']['steps']])"`
Expected: `['actions/checkout@v7', 'actions/setup-python@v7', 'Install dependencies', 'Pre-process raw CSVs into seeds', 'Python unit tests', 'dbt build (seeds, models, tests)', 'Export Gold tables to Parquet', 'actions/upload-artifact@v7']`

- [ ] **Step 6: Commit**

Run `git status --short`: `exports/` must not appear.
```bash
git add scripts/export_gold.py tests_py/test_export_gold.py .github/workflows/pipeline.yml
git commit -m "feat: add Parquet export for Power BI and CI pipeline

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

---

### Task 8: Documentation

**Files:**
- Create: `README.md`
- Modify: `CLAUDE.md` (Commands section), `docs/project_plan.md` (§2 Stack and repository, §4 unknown item code row)

- [ ] **Step 1: README**

Create `README.md`:

````markdown
# The Daily Grind — POS Analytics Pipeline

Weekly POS CSVs → dbt on DuckDB (Bronze / Silver / Gold) → Parquet for a Power BI store-manager dashboard.

- Design decisions: [docs/project_plan.md](docs/project_plan.md)
- Data model (conceptual, logical, star schema): [docs/erd.md](docs/erd.md)

## Run it

Requires Python 3.10+ (tested with Anaconda Python 3.10.9 on Windows and Python 3.10 on Ubuntu in CI).

```bash
python -m venv .venv
.venv\Scripts\activate            # Windows  (macOS/Linux: source .venv/bin/activate)
pip install -r requirements.txt

python scripts/preprocess.py      # raw/ -> seeds/ (file-structure repair only)
python -m pytest tests_py -q      # unit tests for the Python scripts
dbt build --profiles-dir .        # seeds, Bronze, Silver, Gold + all data tests
python scripts/export_gold.py     # gold.* -> exports/*.parquet for Power BI
```

> Windows: keep the project in a short path. pip fails inside deeply nested folders because of the 260-character path limit.

CI (`.github/workflows/pipeline.yml`) runs the same steps on every push to `main` and every pull request, and uploads `exports/` as the `gold-parquet` artifact.

## Lineage

```
raw/*.csv --preprocess.py--> seeds/raw_*.csv --dbt seed--> raw.raw_*  -->  bronze.brz_*

bronze.brz_catalog     -> silver.stg_catalog      -> gold.dim_item
bronze.brz_customers   -> silver.stg_customers    -> gold.dim_customer  (+ stg_pos_orders for inferred customers)
bronze.brz_pos_system  -> silver.stg_pos_orders   -> gold.dim_store, gold.dim_date
bronze.brz_pos_system  -> silver.stg_pos_order_items

stg_pos_order_items + stg_pos_orders + dim_item -> gold.fct_order_items -> gold.fct_orders
```

## Layers

| Layer | Schema | Materialization | Responsibility |
|---|---|---|---|
| Pre-process | files | — | Quote the unquoted comma in `raw_customers`, LF line endings, final newline. No value changes. |
| Raw seeds | `raw` | table | Repaired CSVs loaded with every column as `varchar`. |
| Bronze | `bronze` | view | Seeds exposed as-is. |
| Silver | `silver` | view | Trim/case, strip `$`, split descriptions, cast types, parse two date formats, extract store JSON, split `items_sold` to line grain, flag latest customer record. |
| Gold | `gold` | table | Star schema: `dim_customer`, `dim_item`, `dim_store`, `dim_date`, `fct_orders`, `fct_order_items`. |

## Data quality rules

| Issue in the raw files | Rule |
|---|---|
| Duplicate customers by email (different casing) | Lower-case email; keep newest `updated_at` (tie-break `full_name`). |
| `Smith, Alice`, `wilson diana` | Swap `Last, First`; Title Case, word order otherwise kept → `Alice Smith`, `Wilson Diana`. |
| Tier `silver / GOLD / NONE / blank` | Title Case; `NONE` or blank → `None`. |
| Email `null` | Treated as missing; record excluded from the customer dimension. |
| Prices `$3.50`, `4.50`, `$3.00 ` | Strip `$` and whitespace, cast `DECIMAL(10,2)`, USD. |
| `drnk-002` vs `DRNK-002` | Item codes upper-cased everywhere. |
| `Beverage - Latte`, `Merch \| Ceramic Mug`, `Mystery Box` | Split on ` - ` or ` \| `; no separator → category `Unknown`. |
| Dates `08/01/2026 07:15` and `2026-08-01 08:22:00` | Parsed as `MM/DD/YYYY HH:MM` or ISO → `TIMESTAMP`. Unparseable → build fails. |
| Store data in JSON, `seattle` | Extracted; city Title Case, region upper-case. |
| `1x DRNK-001\|2x FOOD-001`, `-1x FOOD-002` | One row per item per transaction; signed quantity, `is_return` flag; repeated codes summed. |
| POS code not in catalog | Mapped to `UNKNOWN_ITEM`; `assert_pos_items_exist_in_catalog` warns. |
| Blank contact / `INVALID_EMAIL` / email not in loyalty list | `__guest__` / `__unknown__` / inferred customer (name `Unknown`, first purchase as `updated_at`). |

## Headline numbers (current raw files)

| Metric | Definition | Value |
|---|---|---|
| Net revenue | Σ `fct_orders.order_revenue` | 52.25 |
| Orders | count of `fct_orders` where not `is_return_order` | 7 |
| Average order value | revenue of non-return orders ÷ orders | 7.96 |

## Tests

- Generic: `unique` + `not_null` on every key, `relationships` on every foreign key, `accepted_values` on tier, contact type and customer type.
- Singular (`tests/`): quantity and order count reconcile Gold to Bronze; order revenue equals its lines; `order_fraction` sums to 1 per order; one latest record per email; POS codes exist in catalog (warn).
- Python (`tests_py/`): pre-processing repairs and export types.
````

- [ ] **Step 2: CLAUDE.md commands**

Replace the `## Commands` section of `CLAUDE.md` (from the heading to the end of the file) with:
```markdown
## Commands
- Activate venv: `.venv\Scripts\Activate.ps1`
- Pre-process: `python scripts/preprocess.py`
- Python tests: `python -m pytest tests_py -q`
- Build + test: `dbt build --profiles-dir .`
- Export for Power BI: `python scripts/export_gold.py`
```

- [ ] **Step 3: Project plan stack section**

In `docs/project_plan.md` §2, replace the line starting `- **Python:**` with:
```markdown
- **Python:** Anaconda Python 3.10.9 → project venv `.venv`; pinned in `requirements.txt`: dbt-core 1.12.4, dbt-duckdb 1.11.0, duckdb 1.5.5, pytest 9.1.1.
```
and replace the fenced layout block in §2 with:
```
raw/                     original vendor CSVs, never edited
scripts/preprocess.py    file-structure repair only  -> seeds/
scripts/export_gold.py   gold tables -> exports/*.parquet (Power BI)
seeds/                   generated, git-ignored (all columns loaded as varchar)
models/bronze/           brz_* views: seeds as-is, no casting
models/silver/           stg_* views: cleaning, casting, dedup, JSON parse, item split
models/gold/             dim_* and fct_* tables (star schema)
tests/                   singular dbt tests (reconciliation, business rules)
tests_py/                pytest for the Python scripts
.github/workflows/       CI: pre-process, pytest, dbt build, export
docs/                    project_plan.md, erd.md, rollout.md, ai_usage.md
CLAUDE.md                harness rules for all models
```

In `docs/project_plan.md` §4, replace the table row starting `| pos | Item code not in catalog` with (decision confirmed by Albert: no extra column, ERD unchanged):
```markdown
| pos | Item code not in catalog (none today) | Gold | Map to `UNKNOWN_ITEM`; original code stays visible in `stg_pos_order_items`; `assert_pos_items_exist_in_catalog` warns |
```

- [ ] **Step 4: Verify links and commit**

Run: `ls docs/project_plan.md docs/erd.md && grep -n "dbt-core 1.12.4" docs/project_plan.md && grep -n "export_gold" CLAUDE.md && grep -c "source_item_code" docs/project_plan.md`
Expected: both files listed; one match for each of the first two greps; the last prints `0`.

```bash
git add README.md CLAUDE.md docs/project_plan.md
git commit -m "docs: add README and update commands and stack for the pipeline

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

---

### Task 9: Clean-run verification and PR (Opus 5, orchestrator)

- [ ] **Step 1:** Delete generated state: `rm -rf daily_grind.duckdb seeds exports target/run target/compiled`.
- [ ] **Step 2:** Run the README commands in order; expect `7 passed`, `Done. PASS=78 WARN=0 ERROR=0 SKIP=0 NO-OP=0 REUSED=0 TOTAL=78`, six Parquet files.
- [ ] **Step 3:** `.venv/Scripts/python.exe scripts/check_erd_columns.py` → `PASS`; re-run Task 6 Step 7 → `ERD mismatches: none`.
- [ ] **Step 4:** `git status --short` clean; `git ls-files | grep -E "duckdb|^seeds/.*csv|^exports/|^.venv"` empty.
- [ ] **Step 5:** Push `feat/task2-pipeline`; confirm the CI run on the PR is green (Albert opens the PR; controller supplies the description: Why, How with lineage and grains, Tests with exact counts, Known differences).
