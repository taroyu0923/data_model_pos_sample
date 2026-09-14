# CLAUDE.md — The Daily Grind dbt project harness

Plan and all confirmed decisions: `docs/project_plan.md`. Do not change a confirmed decision without asking Albert.

## Working style (applies to every model in every role)
- If a task is ambiguous or missing details, ask clarifying questions and explain why each matters. Do not work blindly.
- "I don't know — stopping to ask" is always acceptable and preferred over guessing.
- Before finishing: verify, report edge-case or logic flaws, then give a **verification status**: what was verified and by what means, what is unverified and the check that would confirm it.
- Only a tool call in this session counts as verification. Reasoning and recall do not.

## Contract first (from migrate-bi-sql-to-dbt)
- Every model states in its yml description: grain, uniqueness key, null behaviour.
- Put logic in the lowest layer that owns it: file structure → `scripts/preprocess.py`; value cleaning, casting, dedup, JSON, splitting → Silver; star schema, sentinel rows, business measures → Gold.
- Use `ref()` / `source()` only; no hard-coded relation names.
- Normalise case and whitespace deliberately and document it.
- Every window function has a complete, deterministic `order by` (tie-breaker included).
- Descriptions live next to the SQL in the same PR.

## Layers
- `raw/` is read-only. Never edit vendor files.
- Seeds load every column as `varchar`; casting happens in Silver.
- Bronze `brz_*`: select seeds as-is. Silver `stg_*`. Gold `dim_*`, `fct_*`.
- Use DuckDB `try_strptime` / `try_cast` for untrusted values, then test for nulls.

## Validation (from validate-dbt-report-migration, adapted)
- Validate in layers: structure (types, grain, uniqueness) → totals (Gold reconciles to Bronze) → rows.
- Every PK: `unique` + `not_null`. Every FK: `relationships`.
- Business invariants become singular tests in `tests/`.
- Do not "fix" numbers to match an expectation; trace the cause and report it.

## Git and PRs (from prepare-data-platform-pr / check-dataplatform-pr, light)
- Feature branch off `main`; Albert merges. Never commit to `main` directly.
- Never commit `.venv/`, `*.duckdb`, `target/`, `logs/`, or credentials.
- One focused change per commit. PR description: Why, How (lineage, grain), Tests (exact command + pass/warn/error counts), Known differences.
- Never mark a test as done unless it ran in this session.

## File naming
- Never put a date or time in a file name (e.g. `task1-blueprint.md`, not `2026-09-14-task1-blueprint.md`). This overrides any skill default.

## Commands
- Activate venv: `.venv\Scripts\Activate.ps1`
- Pre-process: `python scripts/preprocess.py`
- Python tests: `python -m pytest tests_py -q`
- Build + test: `dbt build --profiles-dir .`
- Export for Power BI: `python scripts/export_gold.py`
