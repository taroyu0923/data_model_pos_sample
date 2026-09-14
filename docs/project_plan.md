# Project Plan — The Daily Grind POS Analytics Pipeline

Status: **Draft for review** (2026-09-14). Nothing below is built yet.

## 1. Goal and deliverables

| Task | Deliverable | Owner of final output |
|---|---|---|
| 1. Blueprint | Conceptual/logical model + physical star schema as Mermaid ER (`docs/erd.md`) with PKs, FKs, data types | Claude (reviewed by Albert) |
| 2. Pipeline | dbt project on DuckDB, Bronze / Silver / Gold layers, tests, docs — pushed to GitHub | Claude (reviewed by Albert) |
| 3. Dashboard | One-page Store Manager dashboard in Power BI on the Gold tables | Albert (Claude supplies KPI definitions / DAX list) |
| 4. Roll-out | Change-management strategy (1–2 paragraphs or slides) | Claude draft, Albert edits |
| AI usage note | How AI was prompted and how it helped (required by the brief) | Claude draft, Albert edits |

## 2. Stack and repository

- **Database:** DuckDB file `daily_grind.duckdb` (git-ignored).
- **Python:** Anaconda Python 3.10.9 → project venv `.venv`; pinned in `requirements.txt`: dbt-core 1.12.4, dbt-duckdb 1.11.0, duckdb 1.5.5, pytest 9.1.1.
- **Repo:** `github.com/taroyu0923/data_model_pos_sample`. Work on feature branches off `main`; Albert merges.
- **Line endings:** `.gitattributes` marks `*.csv -text` so `core.autocrlf=true` never rewrites raw bytes.

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

## 3. Confirmed decisions

| # | Topic | Decision |
|---|---|---|
| 1 | Customer history | `dim_customer` keeps **latest record per email only** (row_number over lower(email) by `updated_at` desc). History stays visible in Silver. |
| 2 | Fact grain | **Two facts**: `fct_orders` (PK `tx_id`) and `fct_order_items` (PK `tx_id, item_code`). |
| 3 | Returns | Signed `quantity` (-1) **plus** `is_return = true`. |
| 4 | Unmatched contacts | Valid email not in customers → **inferred customer**; empty contact → **Guest** row; invalid email → **Unknown** row. |
| 5 | Price | `unit_price` from current catalog stored on the fact line; `line_revenue = quantity * unit_price`. Assumption: catalog price was valid on the sale dates. |
| 6 | Date dimension | `dim_date` included. |
| 7 | Currency | All prices USD, including Vancouver (S-3). |
| 8 | Dates | Source `MM/DD/YYYY HH:MM` and ISO both cast to `TIMESTAMP` (`YYYY-MM-DD HH:MM:SS`). No time zone; treated as store-local time. |
| 9 | Catalog | Upper-case codes; strip `$` and spaces; split description on ` - ` or ` \| `; `UNKNOWN_ITEM` → category `Unknown`, sub-category `Mystery Box`, price 0.00. |
| 10 | Customer names | Title Case. `Last, First` → `First Last` (`Smith, Alice` → `Alice Smith`); otherwise keep word order (`wilson diana` → `Wilson Diana`). |
| A | Return-only orders | `is_return_order = true`; excluded from order count and AOV; revenue still counts in net revenue. |
| B | `order_fraction` | By line: `1 / number of lines in tx`. |
| C | Duplicate item in one tx | Aggregated into one line (quantities summed) so `(tx_id, item_code)` stays unique. |
| D | Inferred customer `updated_at` | First purchase timestamp. |
| E | Alice | Latest record wins → `Alice S.`. |
| F | `wilson diana` | `Wilson Diana`. |
| G | Pre-processing | Python fixes **file structure only** (quote broken field, CRLF→LF, final newline). All value cleaning in dbt Silver. |
| 11 | Diagram | Mermaid ER. |
| 12 | Database | DuckDB. |

## 4. Data quality issues and where each is fixed

| Source | Issue | Layer | Fix |
|---|---|---|---|
| customers | Unquoted comma in `Smith, Alice` (row parses as 5 fields) | preprocess.py | Quote the name field |
| customers | CRLF line endings | preprocess.py | Normalise to LF |
| customers | Email casing duplicates (`Alice.Smith@Example.com` vs `alice.smith@…`) | Silver | `lower(trim())` before dedup |
| customers | Tier `Gold/silver/GOLD/NONE/blank` | Silver | Title Case; `NONE`/blank → `None` |
| customers | Email literal `"null"` (Guest User) | Silver | Dropped from customer list |
| catalog | Missing final newline | preprocess.py | Add newline |
| catalog | `$`, trailing space, no-symbol prices | Silver | Strip, cast `DECIMAL(10,2)` |
| catalog | Lower-case `drnk-002` | Silver | `upper(trim())` |
| catalog | Mixed separators ` - ` / ` \| `, no separator for Mystery Box | Silver | regex split; fallback `Unknown` |
| pos | Mixed date formats | Silver | `coalesce(try_strptime(…, '%m/%d/%Y %H:%M'), try_strptime(…, '%Y-%m-%d %H:%M:%S'))`; test not null |
| pos | Store data in JSON, `seattle` casing | Silver | `json_extract_string`; Title Case city, upper region |
| pos | Multi-item delimited string, `-1x` returns, lower-case codes | Silver | split on `\|`, regex `^(-?\d+)x\s+(.+)$`, unnest to line grain |
| pos | Empty / invalid / unknown contact | Gold | Guest / Unknown / inferred rows in `dim_customer` |
| pos | Item code not in catalog (none today) | Gold | Map to `UNKNOWN_ITEM`; original code stays visible in `stg_pos_order_items`; `assert_pos_items_exist_in_catalog` warns |

## 5. Conceptual model

Customer **places** Order (0..n; an order has 0..1 identified customer → Guest/Unknown otherwise). Store **records** Order (1..n). Order **contains** Order Item (1..n). Product **appears in** Order Item (0..n).

## 6. Physical star schema (Gold) — DuckDB types

**dim_customer** — grain: one row per customer email (+ Guest, Unknown)
| column | type | note |
|---|---|---|
| customer_id | VARCHAR PK | lower-case email; `__guest__`, `__unknown__` sentinels |
| cust_email | VARCHAR | null for sentinels |
| full_name | VARCHAR | Title Case; `Unknown` for inferred, `Guest` / `Unknown` for sentinels |
| tier | VARCHAR | `Gold`, `Silver`, `None` |
| updated_at | TIMESTAMP | latest record; first purchase for inferred |
| customer_type | VARCHAR | `member`, `inferred`, `guest`, `unknown` |

**dim_item** — grain: one row per item code
| column | type |
|---|---|
| item_code | VARCHAR PK |
| item_category | VARCHAR |
| item_category_sub | VARCHAR |
| unit_price | DECIMAL(10,2) |

**dim_store** — grain: one row per store
| column | type |
|---|---|
| store_id | VARCHAR PK |
| city | VARCHAR |
| region | VARCHAR |

**dim_date** — grain: one row per calendar day from min to max sale date
| column | type |
|---|---|
| date_day | DATE PK |
| year | INTEGER |
| month | INTEGER |
| month_name | VARCHAR |
| week_start_date | DATE (Monday) |
| day_of_week | INTEGER (ISO, 1 = Mon) |
| day_name | VARCHAR |
| is_weekend | BOOLEAN |

**fct_orders** — grain: one row per transaction
| column | type | note |
|---|---|---|
| tx_id | VARCHAR PK | |
| sale_timestamp | TIMESTAMP | |
| date_day | DATE FK → dim_date | |
| customer_id | VARCHAR FK → dim_customer | |
| store_id | VARCHAR FK → dim_store | |
| line_count | INTEGER | lines in the order |
| unit_count | INTEGER | signed sum of quantity |
| order_revenue | DECIMAL(10,2) | signed sum of line_revenue |
| is_return_order | BOOLEAN | true when **every** line is a return |

**fct_order_items** — grain: one row per item per transaction
| column | type | note |
|---|---|---|
| tx_id | VARCHAR PK (1/2) FK → fct_orders | |
| item_code | VARCHAR PK (2/2) FK → dim_item | |
| sale_timestamp | TIMESTAMP | repeated for direct filtering |
| date_day | DATE FK → dim_date | |
| customer_id | VARCHAR FK → dim_customer | |
| store_id | VARCHAR FK → dim_store | |
| quantity | INTEGER | signed |
| is_return | BOOLEAN | quantity < 0 |
| unit_price | DECIMAL(10,2) | |
| line_revenue | DECIMAL(10,2) | quantity × unit_price |
| order_fraction | DECIMAL(10,4) | 1 / line_count of the tx |

Headline KPI definitions (for Task 3):
- Net Revenue = Σ `fct_orders.order_revenue`
- Orders = count of `tx_id` where `is_return_order = false`
- AOV = Σ `order_revenue` (non-return orders) ÷ Orders
- Units Sold = Σ `quantity` where `is_return = false`; Units Returned = −Σ `quantity` where `is_return = true`
- Orders attributed to a product = Σ `order_fraction`

## 7. Silver models

| Model | Grain | Purpose |
|---|---|---|
| stg_catalog | item_code | clean codes, split description, cast price |
| stg_customers | source row | normalise email/name/tier, cast `updated_at`, `is_latest` flag (deterministic tie-break: `updated_at desc, full_name`) |
| stg_pos_orders | tx_id | parse timestamp, normalise contact, extract store JSON |
| stg_pos_order_items | tx_id, item_code | split + unnest items, parse qty/code, aggregate duplicates |

## 8. Testing and validation (from `validate-dbt-report-migration`, adapted)

- **Generic tests:** `unique` + `not_null` on every PK; `relationships` on every FK; `accepted_values` on tier, customer_type.
- **Singular reconciliation tests:**
  - Σ raw item quantities (parsed from Bronze) = Σ `fct_order_items.quantity`
  - count distinct raw `tx_id` = rows in `fct_orders`
  - `fct_orders.order_revenue` = Σ its lines
  - Σ `order_fraction` per tx = 1
  - every raw timestamp parses (no null `sale_timestamp`)
  - one `dim_customer` row per lower-case email
- **preprocess.py:** pytest checking the repaired customers file parses to exactly 4 columns on every row.
- **Evidence:** exact `dbt build` command and pass/warn/error counts recorded in the PR description.

## 9. Model orchestration — task list

Orchestrator: **Opus 5** (design, task split, prompt writing, review of every diff, running `dbt build`, final verification). Every subagent prompt includes the working-style rules: "I don't know — stopping to ask" is acceptable; end with a tool-verified verification status. Opus re-verifies subagent claims with tool calls before accepting them.

| ID | Task | Model | Effort | Depends on | Parallel group |
|---|---|---|---|---|---|
| T1.1 | Conceptual + logical model text | Opus 5 | high | — | — |
| T1.2 | Mermaid ER `docs/erd.md` from §6 | Sonnet 5 | low | T1.1 | — |
| T1.3 | Review ER vs §6 and brief | Opus 5 | medium | T1.2 | — |
| T2.0 | venv, `dbt-duckdb` install, `dbt_project.yml`, `profiles.yml`, `.gitignore`, `.gitattributes`, move raw CSVs to `raw/` | Sonnet 5 | low | plan approved | — |
| T2.1 | `scripts/preprocess.py` + pytest | Sonnet 5 | medium | T2.0 | A |
| T2.2 | Seeds config (varchar) + Bronze `brz_*` views + `sources`/schema yml | Haiku 4.5 | low | T2.1 | — |
| T2.3a | `stg_catalog` | Sonnet 5 | medium | T2.2 | B |
| T2.3b | `stg_customers` (dedup, name rules) | Sonnet 5 | medium | T2.2 | B |
| T2.3c | `stg_pos_orders` + `stg_pos_order_items` (JSON, dates, unnest) | Sonnet 5 | high | T2.2 | B |
| T2.4 | `dim_item`, `dim_store`, `dim_date`, `dim_customer` (inferred/guest/unknown) | Sonnet 5 | medium | T2.3 | — |
| T2.5 | `fct_orders`, `fct_order_items` | Sonnet 5 | high | T2.4 | — |
| T2.6 | Generic + singular tests (§8) | Sonnet 5 | medium | T2.5 | — |
| T2.7 | Model/column descriptions, README data dictionary | Haiku 4.5 | low | T2.6 | — |
| T2.8 | Full `dbt build`, review lineage, PR description, readiness gate | Opus 5 | high | T2.7 | — |
| T3.1 | KPI definitions + DAX measure list; Gold export/connection guide for Power BI | Opus 5 | medium | T2.8 | — |
| T3.2 | Build dashboard in Power BI | Albert | — | T3.1 | — |
| T4.1 | Roll-out strategy draft `docs/rollout.md` | Opus 5 | medium | T2.8 | C |
| T5.1 | AI usage write-up `docs/ai_usage.md` | Opus 5 | medium | all | — |

Effort guidance: **low** = mechanical, spec fully given; **medium** = spec given but SQL logic needed; **high** = tricky parsing or grain/key correctness where errors silently corrupt numbers.

Branches: `docs/project-plan` (this), `feat/task1-erd`, `feat/task2-pipeline`, `docs/task3-kpis`, `docs/task4-rollout`. Each merged by Albert.

## 10. Known risks / assumptions

- Catalog price is current-only; historic price changes would misstate revenue (decision 5).
- `is_return_order` is true only when all lines are returns; a mixed order counts as a normal order with reduced revenue.
- Sale timestamps have no time zone; all three stores are in Pacific time, so no conversion is applied.
- Only 8 transactions over 4 days — trends in the dashboard are illustrative.
