#!/usr/bin/env python3
"""Validation-only smoke test for the packaged repository."""
from pathlib import Path
import argparse, json, re, subprocess, sys, pandas as pd
from data_io import read_csv

ROOT=Path(__file__).resolve().parents[1]
ap=argparse.ArgumentParser(); ap.add_argument('--build', action='store_true'); args=ap.parse_args()
if args.build:
    subprocess.run([sys.executable, str(ROOT/'pipeline'/'run_all.py'), '--repo-root', str(ROOT)], check=True)

required_dirs=['architecture','dashboard','golden_dataset','notebook','pipeline','raw','reports','sql']
required_files=[ROOT/'README.md',ROOT/'pipeline/run_all.py',ROOT/'pipeline/run_pipeline.py',ROOT/'pipeline/build_account_month.py',ROOT/'pipeline/analysis_reproduce.py',ROOT/'pipeline/supplementary_metrics.py',ROOT/'pipeline/requirements.txt']
for name in required_dirs: assert (ROOT/name).exists(), f'Missing required path: {name}'
for p in required_files:
    txt=p.read_text(encoding='utf-8'); assert '/mnt/data/' not in txt, f'Machine-specific path remains in {p}'
    assert '../raw_data' not in txt, f'Old raw-data path remains in {p}'
nb=json.loads((ROOT/'notebook/collections_forensics.ipynb').read_text(encoding='utf-8')); code='\n'.join(''.join(c.get('source',[])) for c in nb.get('cells',[]) if c.get('cell_type')=='code'); assert '/mnt/data/' not in code; assert '../raw_data' not in code

summary=json.loads((ROOT/'reports/results/summary.json').read_text())
assert summary['audited_success_cash']>0
assert summary['complete_months']=='2026-01 through 2026-07' and summary['partial_month']=='2026-08'
assert summary['historical_signal_target_day_excluded'] is True
assert abs(summary['break_even_lift_pp']-1.9138201330488014)<1e-6
assert summary['annualized_target_account_opportunities']==67104.0
exp=pd.read_csv(ROOT/'reports/results/experiment_power.csv'); n10=int(exp.loc[exp.holdout_fraction.eq(.10),'min_total_n'].iloc[0]); assert n10==3464

gp=pd.read_csv(ROOT/'golden_dataset/golden_payments.csv'); assert gp.payment_id.is_unique
am=read_csv(ROOT/'golden_dataset', 'golden_account_month.csv');
for c in ['principal_amount_extract','outstanding_amount_extract','dpd_extract','risk_segment_extract','status_extract']:
    assert c in am.columns
for c in ['principal_amount','outstanding_amount','dpd','risk_segment','status']:
    assert c not in am.columns

ops=pd.read_csv(ROOT/'reports/results/operational_metrics_monthly.csv'); required_metrics={'contact_rate','rpc_rate','ptp_rate','ptp_kept_rate','recovery_rate','recovery_per_targeted_account','recovery_per_agent_hour'}; assert required_metrics.issubset(ops.columns); assert float(ops[['contact_rate','rpc_rate','ptp_rate','ptp_kept_rate']].max().max())<=1.000001
raw_attempts=read_csv(ROOT/'raw', 'call_attempts.csv'); raw_calls=read_csv(ROOT/'raw', 'calls.csv'); canon_calls=raw_calls.sort_values(['call_id','event_at']).drop_duplicates('call_id'); canon_attempts=raw_attempts.sort_values(['attempt_id','event_at']).drop_duplicates('attempt_id').merge(canon_calls[['call_id','call_status']],on='call_id',how='left'); j=canon_attempts[canon_attempts.event_at.str[:7].eq('2026-07')]; expected=float((j.call_status=='ANSWERED').sum()/len(j)); actual=float(ops.loc[ops.month.eq('2026-07'),'contact_rate'].iloc[0]); assert abs(actual-expected)<1e-12
ch=pd.read_csv(ROOT/'reports/results/channel_7d_conversion.csv'); assert 'mutually exclusive first targeting touch' in ch.attribution.iloc[0]; tq=read_csv(ROOT/'raw','daily_targeting.csv',parse_dates=['target_date']); tq['month']=tq.target_date.dt.to_period('M').astype(str); expected_first=len(tq.sort_values(['account_id','month','target_date','target_id']).drop_duplicates(['account_id','month'])); assert ch.unique_touches.sum()==expected_first
sel=pd.read_csv(ROOT/'reports/results/selection_balance_july.csv'); assert sel.interpretation.str.contains('pre-period').all()
co=pd.read_csv(ROOT/'reports/results/cohort_effects_common.csv'); assert set(co.month)=={'2026-01','2026-07'}
vc=(ROOT/'reports/results/vendor_disposition_finding.csv').read_text(); assert 'cannot be conclusively established' in vc

manifest=json.loads((ROOT/'reports/results/rebuild_manifest.json').read_text()); assert manifest['missing']==[]
for name in manifest['generated_files']:
    assert (ROOT/'reports/results'/name).exists(), name

# Stale methodology strings should not survive the final package.
texts=[]
for p in [ROOT/'README.md',ROOT/'reports/Metric_Dictionary.md',ROOT/'reports/Statistical_Investigation.md',ROOT/'reports/Data_Quality_Report.md',ROOT/'sql/05_counterfactual.sql']:
    texts.append(p.read_text(encoding='utf-8'))
joined='\n'.join(texts)
assert 'Primary outcome: 30-day audited cash per eligible account' not in joined
assert '0.053 pp' not in joined
assert '61,065' not in joined
assert '2,980' not in joined
print('QA SMOKE TEST PASSED')
print(f"audited_success_cash={summary['audited_success_cash']:.2f}")
print(f"targeting_signal_pp={summary['timing_aligned_pre_post_7d_payer_lift_pp']:.4f}")
print(f"break_even_lift_pp={summary['break_even_lift_pp']:.4f}")
