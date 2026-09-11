# CredResolve Analysis

A cleaned, reproducible submission for the collections forensics assignment.

## Folder structure

- `architecture/` - production architecture diagram.
- `dashboard/` - one-screen executive dashboard.
- `golden_dataset/` - canonical golden and rejected payment layers plus the account-month analytical dataset.
- `notebook/` - executed analysis notebook with repository-relative paths.
- `pipeline/` - reproducibility scripts and build outputs.
- `raw/` - source CSVs and raw SQLite database supplied for the analysis.
- `reports/` - executive memo, data-quality report, metric dictionary, statistical investigation, assignment coverage, investment assumptions, production contracts, and result tables.
- `sql/` - SQL staging, canonical payment audit, metrics, forensics, counterfactual design, driver analysis, and investment inputs.

## Key analytical corrections

1. Payment auditing uses one canonical order everywhere: deduplicate by `payment_id` first, then evaluate reused/ambiguous references.
2. The historical July targeting comparison is not presented as a causal ATT because full-month payment outcomes can precede treatment.
3. The timing-aligned 7-day pre/post signal is explicitly descriptive; the investment decision is based on a randomized pilot and a break-even hurdle rather than historical association.
4. Every material result CSV/JSON in `reports/results/` is rebuilt on every pipeline run; `rebuild_manifest.json` records the generated set and SHA-256 hashes.
5. Reproducibility paths are repository-relative; no machine-specific paths are required.
6. The historical first-target diagnostic excludes the entire target day because treatment timestamps are unavailable.
7. Channel conversion uses mutually exclusive first-target attribution at the account-month level to avoid double-counting one payment across multiple overlapping channel touches.

## Reproduce from a clean clone

From the repository root:

```bash
python -m venv .venv
source .venv/bin/activate
pip install -r pipeline/requirements.txt
python pipeline/run_pipeline.py
python pipeline/qa_smoke_test.py
```

The build creates a local SQLite build database under `pipeline/build/` (ignored from GitHub), refreshes the canonical payment outputs, and regenerates **all material analytical result tables** under `reports/results/`.

After the analytical build, materialize the account-month golden spine from the same raw/golden inputs:

```bash
python pipeline/build_account_month.py
```

This is intentionally a separate memory-heavy stage so the SQL/metrics process remains deterministic and reproducible. The golden spine labels current/extract-level account attributes explicitly; it does not fabricate historical monthly snapshots.

To execute the notebook from the same clean clone:

```bash
jupyter nbconvert --to notebook --execute notebook/collections_forensics.ipynb --output executed_check.ipynb
```

The notebook resolves `raw/`, `golden_dataset/`, and `reports/results/` relative to the repository root, whether it is launched from the repo root or from `notebook/`. The pipeline does not rely on packaged/stale result CSVs: material analytical outputs are regenerated before QA.

## Decision framing

The historical timing-aligned pre/post result is descriptive only. Because `target_date` is date-only, the entire target day is excluded; the comparison uses seven full calendar days before versus seven full days after. It is not treated as causal incremental recovery. The investment case therefore uses a randomized targeting pilot with a 5-10% holdout and a break-even payer-lift hurdle based on targeted-population payer economics. The experiment uses **30-day payer rate as the primary statistical endpoint** and **30-day cash per eligible account as the financial decision metric**; the SQL, power calculation and memo all use this same hierarchy. This preserves the assignment's requirement to separate fact, evidence, correlation, and hypothesis.
