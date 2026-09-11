# Submission checklist

## Primary deliverables

- `architecture/Architecture_Diagram.png` and `.svg`
- `dashboard/Executive_Dashboard_DQ.xlsx`
- `golden_dataset/golden_account_month.csv.gz`
- `golden_dataset/golden_payments.csv`
- `golden_dataset/rejected_payments.csv`
- `notebook/collections_forensics.ipynb`
- `reports/Executive_Memo.docx`
- `reports/Executive_Memo.pdf`
- `reports/Data_Quality_Report.md`
- `reports/Metric_Dictionary.md`
- `reports/Statistical_Investigation.md`
- `reports/assignment_coverage.md`
- `reports/Data_Contracts_and_Lineage.md`
- `reports/results/`
- `sql/`
- `pipeline/`

## Clean-clone validation

From the repository root:

```bash
pip install -r pipeline/requirements.txt
python pipeline/run_pipeline.py
python pipeline/qa_smoke_test.py
```

The notebook can be executed either from the repository root or from inside `notebook/`.

## Decision-safe interpretation

- The reported 11% month-on-month improvement does not hold for audited all-account recovery cash.
- The 11.8% targeted-account yield movement is a narrower metric, not proof of causal improvement.
- The legacy July full-month targeting association is retained as a diagnostic only because its outcome window can include pre-target payments.
- The corrected first-target 7-day pre/post movement is +0.05 pp and is descriptive, not causal.
- The ₹10 Cr decision therefore uses a randomized pilot and a ~1.91 pp break-even payer-lift hurdle.

## Data window limitation
The supplied extracts cover 8 observed calendar months (Jan-Jul complete and Aug partial). The assignment requests approximately 12 months, but the raw data supplied does not contain a full 12-month history. The submission explicitly states this limitation and does not claim annual seasonality.
