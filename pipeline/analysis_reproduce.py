#!/usr/bin/env python3
"""Reproduce the canonical payment audit, timing-aligned targeting analysis, and investment hurdle."""
from pathlib import Path
import argparse, os, json
import numpy as np
import pandas as pd

def reproduce(repo_root, raw_dir=None):
    root = Path(repo_root).resolve()
    raw = Path(raw_dir).resolve() if raw_dir else Path(os.getenv('CREDRESOLVE_RAW_DIR', str(root / 'raw'))).resolve()
    data = root / 'golden_dataset'
    results = root / 'reports' / 'results'
    data.mkdir(parents=True, exist_ok=True)
    results.mkdir(parents=True, exist_ok=True)

    pay = pd.read_csv(raw / 'payments.csv')
    sp = pay.sort_values(['event_at', 'payment_id']).copy()
    sp['_rn'] = sp.groupby('payment_id').cumcount()
    d = sp[sp['_rn'].eq(0)].drop(columns='_rn')
    ref = d[d.payment_reference.fillna('').str.strip().ne('')].groupby('payment_reference').agg(
        ref_accounts=('account_id','nunique'), ref_amounts=('amount','nunique')
    ).reset_index()
    g = d.merge(ref, on='payment_reference', how='left')
    g['audited_recovery'] = (
        g.payment_status.eq('SUCCESS') & (
            g.payment_reference.fillna('').str.strip().eq('') |
            (g.ref_accounts.fillna(0).eq(1) & g.ref_amounts.fillna(0).eq(1))
        )
    ).astype(int)
    golden = g[['payment_id','account_id','borrower_id','event_at','payment_reference','amount',
                'payment_status','payment_method','provider_id','audited_recovery']]
    golden.to_csv(data / 'golden_payments.csv', index=False)
    rejected = golden[golden.audited_recovery.eq(0)].copy()
    rejected['rejection_reason'] = np.where(
        rejected.payment_status.ne('SUCCESS'), 'NON_SUCCESS_STATUS',
        np.where(rejected.payment_reference.fillna('').str.strip().eq(''),
                 'SUCCESS_WITH_BLANK_REFERENCE', 'AMBIGUOUS_REFERENCE')
    )
    rejected.to_csv(data / 'rejected_payments.csv', index=False)

    accounts = pd.read_csv(raw / 'accounts.csv')
    target = pd.read_csv(raw / 'daily_targeting.csv', parse_dates=['target_date'])
    gold = golden.copy(); gold['event_at'] = pd.to_datetime(gold['event_at'])
    gold = gold[gold.audited_recovery.eq(1) & gold.payment_status.eq('SUCCESS')].copy()
    gold['month'] = gold.event_at.dt.to_period('M').astype(str)
    tgt = target[['account_id','target_date']].copy()
    tgt['month'] = tgt.target_date.dt.to_period('M').astype(str)
    tgt = tgt[['month','account_id']].drop_duplicates()
    principal = (tgt.merge(accounts[['account_id','principal_amount']], on='account_id', how='inner')
                    .groupby('month').agg(targeted_accounts=('account_id','nunique'),
                                          targeted_principal=('principal_amount','sum')).reset_index())
    per_acct = gold.groupby(['month','account_id'], as_index=False)['amount'].sum()
    monthly = per_acct.groupby('month', as_index=False).agg(
        audited_recovery_cash_all_accounts=('amount','sum'),
        audited_paying_accounts_all_accounts=('account_id','nunique')
    )
    per_target = per_acct.merge(tgt, on=['month','account_id'], how='inner')
    targeted_cash = per_target.groupby('month', as_index=False).agg(
        audited_recovery_cash_on_targeted_accounts=('amount','sum')
    )
    monthly = monthly.merge(targeted_cash,on='month',how='left').merge(principal,on='month',how='left')
    monthly['audited_recovery_cash_on_targeted_accounts'] = monthly['audited_recovery_cash_on_targeted_accounts'].fillna(0)
    monthly['targeted_accounts'] = monthly['targeted_accounts'].fillna(0)
    monthly['targeted_principal'] = monthly['targeted_principal'].fillna(0)
    monthly['target_account_recovery_yield'] = np.where(
        monthly.targeted_principal.gt(0), monthly.audited_recovery_cash_on_targeted_accounts / monthly.targeted_principal, np.nan
    )
    raw_month = pay.assign(month=pd.to_datetime(pay.event_at).dt.to_period('M').astype(str)).query("payment_status=='SUCCESS'").groupby('month').amount.sum()
    monthly['raw_success_cash'] = monthly.month.map(raw_month)
    monthly['audited_success_cash'] = monthly.audited_recovery_cash_all_accounts
    monthly.to_csv(results / 'monthly_metrics.csv', index=False)

    july = target[target.target_date.dt.to_period('M').astype(str).eq('2026-07')]
    first = july.groupby('account_id', as_index=False).target_date.min().rename(columns={'target_date':'first_target_date'})
    x = first.merge(gold[['account_id','event_at','amount']], on='account_id', how='left')
    # target_date is date-only; exclude the entire treatment day to avoid classifying
    # pre-target payments as post-treatment. Compare seven full prior calendar days
    # with seven full subsequent calendar days.
    x['pre7'] = x.event_at.ge(x.first_target_date - pd.Timedelta(days=7)) & x.event_at.lt(x.first_target_date)
    x['post7'] = x.event_at.ge(x.first_target_date + pd.Timedelta(days=1)) & x.event_at.lt(x.first_target_date + pd.Timedelta(days=8))
    pp = x.groupby('account_id').agg(
        pre7_payer=('pre7','max'), post7_payer=('post7','max'),
        pre7_cash=('amount', lambda s: s[x.loc[s.index,'pre7']].sum()),
        post7_cash=('amount', lambda s: s[x.loc[s.index,'post7']].sum())
    ).reset_index()
    pp.to_csv(results / 'targeting_pre_post_7d_account_level.csv', index=False)
    pre_payer, post_payer = float(pp.pre7_payer.mean()), float(pp.post7_payer.mean())
    pre_cash, post_cash = float(pp.pre7_cash.mean()), float(pp.post7_cash.mean())
    lift_pp = (post_payer - pre_payer) * 100

    july_pay = gold[gold.event_at.dt.to_period('M').astype(str).eq('2026-07')]
    july_targeted_pay = july_pay.merge(first[['account_id']], on='account_id', how='inner')
    leak = first.merge(july_pay[['account_id','event_at']], on='account_id', how='left')
    leak['pre_target_payment'] = leak.event_at.le(leak.first_target_date)
    pre_target_accounts = int(leak.groupby('account_id').pre_target_payment.max().sum())
    association = pd.DataFrame([
        ['july_first_targeted_accounts', len(first), 'count'],
        ['july_untargeted_accounts', int(len(accounts) - len(first)), 'count'],
        ['pre7_payer_rate', pre_payer, 'rate'], ['post7_payer_rate', post_payer, 'rate'],
        ['timing_aligned_pre_post_lift_pp', lift_pp, 'percentage_points'],
        ['pre7_avg_cash_per_targeted_account', pre_cash, 'INR'],
        ['post7_avg_cash_per_targeted_account', post_cash, 'INR'],
        ['timing_aligned_cash_change_per_account', post_cash - pre_cash, 'INR'],
        ['treated_accounts_with_pre_target_july_payment', pre_target_accounts, 'count'],
        ['treated_accounts_with_pre_target_july_payment_pct', pre_target_accounts / len(first), 'rate'],
    ], columns=['metric','value','unit'])
    association.to_csv(results / 'targeting_association.csv', index=False)

    monthly_targeted = target[target.target_date.dt.to_period('M').astype(str).le('2026-07')].groupby(target.target_date.dt.to_period('M').astype(str)).account_id.nunique()
    annual_ops = float(monthly_targeted.mean() * 12)
    avg_recovery_per_targeted_payer_july = float(july_targeted_pay.amount.sum() / july_targeted_pay.account_id.nunique())
    budget = 100_000_000.0
    annual_recovery_base = annual_ops * avg_recovery_per_targeted_payer_july
    break_even_pp = 100 * budget / annual_recovery_base
    historical_benchmark = annual_recovery_base * lift_pp / 100
    inv = pd.DataFrame([
        ['annualized_target_account_opportunities', annual_ops],
        ['avg_recovery_per_targeted_payer_july', avg_recovery_per_targeted_payer_july],
        ['historical_timing_aligned_lift_pp', lift_pp],
        ['historical_benchmark_incremental_recovery', historical_benchmark],
        ['historical_benchmark_roi', (historical_benchmark-budget)/budget],
        ['break_even_lift_pp', break_even_pp],
        ['pilot_0_5pp_recovery', annual_recovery_base*0.005],
        ['pilot_0_5pp_roi', (annual_recovery_base*0.005-budget)/budget],
        ['pilot_1_0pp_recovery', annual_recovery_base*0.01],
        ['pilot_1_0pp_roi', (annual_recovery_base*0.01-budget)/budget],
        ['stretch_2_5pp_recovery', annual_recovery_base*0.025],
        ['stretch_2_5pp_roi', (annual_recovery_base*0.025-budget)/budget],
        ['budget', budget], ['recommendation', 'randomized targeting pilot before scale'],
    ], columns=['metric','value'])
    inv.to_csv(results / 'investment_scenario.csv', index=False)

    m = monthly.set_index('month')
    summary = {
        'observation_start':'2026-01-01', 'observation_end_events':'2026-08-12',
        'complete_months':'2026-01 through 2026-07', 'partial_month':'2026-08',
        'raw_success_cash':float(pay.query("payment_status=='SUCCESS'").amount.sum()),
        'audited_success_cash':float(golden.query("payment_status=='SUCCESS' and audited_recovery==1").amount.sum()),
        'raw_to_audited_pct_change':float(golden.query("payment_status=='SUCCESS' and audited_recovery==1").amount.sum()/pay.query("payment_status=='SUCCESS'").amount.sum()-1),
        'june_july_audited_cash_mom_all_accounts':float(m.loc['2026-07','audited_recovery_cash_all_accounts']/m.loc['2026-06','audited_recovery_cash_all_accounts']-1),
        'june_july_target_account_yield_mom':float(m.loc['2026-07','target_account_recovery_yield']/m.loc['2026-06','target_account_recovery_yield']-1),
        'jan_july_audited_cash_change':float(m.loc['2026-07','audited_recovery_cash_all_accounts']/m.loc['2026-01','audited_recovery_cash_all_accounts']-1),
        'timing_aligned_pre_post_7d_payer_lift_pp':lift_pp,
        'pre_target_july_payment_accounts_pct':pre_target_accounts/len(first)*100,
        'annualized_target_account_opportunities':annual_ops, 'break_even_lift_pp':break_even_pp,
        'historical_benchmark_incremental_recovery':historical_benchmark,
        'historical_benchmark_roi':(historical_benchmark-budget)/budget,
        'recommendation':'Better borrower targeting pilot with randomized 5-10% holdout',
        'recommendation_confidence':'Medium-Low for causal impact; High for payment-forensics findings'
    }
    (results/'summary.json').write_text(json.dumps(summary, indent=2, ensure_ascii=False), encoding='utf-8')
    print('audited cash =', summary['audited_success_cash'], flush=True)
    print('timing-aligned payer lift pp =', lift_pp, flush=True)
    print('break-even lift pp =', break_even_pp, flush=True)
    import os, sys
    os.execv(sys.executable, [sys.executable, str(root / 'pipeline' / 'supplementary_metrics.py'), '--repo-root', str(root)])

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--repo-root', default=Path(__file__).resolve().parents[1])
    ap.add_argument('--raw-dir', default=None)
    args = ap.parse_args()
    reproduce(args.repo_root, args.raw_dir)

if __name__ == '__main__':
    main()
