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
