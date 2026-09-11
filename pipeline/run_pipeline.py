#!/usr/bin/env python3
"""Build the CredResolve SQLite pipeline from the repository's raw/ folder."""
from __future__ import annotations
import argparse, os, sqlite3, json, subprocess, sys
from pathlib import Path
import pandas as pd
from data_io import read_csv, resolve_data_path

SQL_FILES = [
    '01_staging_clean.sql','02_golden_payments.sql','03_monthly_metrics.sql',
    '04_data_forensics.sql','05_counterfactual.sql','06_driver_analysis.sql','07_targeting_investment.sql',
    '08_metric_governance.sql','09_statistical_investigation.sql',
]

def find_repo_root() -> Path:
    here = Path(__file__).resolve().parents[1]
    if (here / 'raw').exists() and (here / 'sql').exists():
        return here
    return Path.cwd().resolve()



def rebuild_golden_account_month(repo: Path) -> None:
    """Rebuild the account-month analytical spine using only raw CSVs and canonical payments."""
    months = pd.DataFrame({'month': pd.period_range('2026-01','2026-08',freq='M').astype(str)})
    accounts = read_csv(repo/'raw', 'accounts.csv')
    accounts = accounts[['account_id','borrower_id','loan_type','principal_amount','outstanding_amount','dpd','risk_segment','timezone','status']].copy()
    accounts = accounts.rename(columns={
        'loan_type':'loan_type_extract','principal_amount':'principal_amount_extract',
        'outstanding_amount':'outstanding_amount_extract','dpd':'dpd_extract',
        'risk_segment':'risk_segment_extract','timezone':'timezone_extract','status':'status_extract'
    })
    months['key']=1; accounts['key']=1
    out=months.merge(accounts,on='key').drop(columns='key'); out['partial_month']=(out.month=='2026-08').astype(int)
    targets=read_csv(repo/'raw', 'daily_targeting.csv', parse_dates=['target_date']); targets['month']=targets.target_date.dt.to_period('M').astype(str)
    t=targets.groupby(['month','account_id']).agg(target_rows=('account_id','size'),max_priority=('priority','max'),avg_priority=('priority','mean')).reset_index()
    out=out.merge(t,on=['month','account_id'],how='left')
    for c in ['target_rows','max_priority','avg_priority']: out[c]=out[c].fillna(0)
    def add_event(path, specs):
        nonlocal out
        df=read_csv(repo/'raw', path, parse_dates=['event_at']); df['month']=df.event_at.dt.to_period('M').astype(str); df=df[df.month.between('2026-01','2026-08')]
        g=df.groupby(['month','account_id']).agg(**specs).reset_index(); out=out.merge(g,on=['month','account_id'],how='left')
    calls=read_csv(repo/'raw', 'calls.csv', parse_dates=['event_at']).sort_values(['call_id','event_at']).drop_duplicates('call_id'); calls['month']=calls.event_at.dt.to_period('M').astype(str); calls=calls[calls.month.between('2026-01','2026-08')]
    cg=calls.groupby(['month','account_id']).agg(calls=('call_id','nunique'),answered=('call_status',lambda s:(s=='ANSWERED').sum()),call_duration_sec=('duration_sec','sum')).reset_index(); out=out.merge(cg,on=['month','account_id'],how='left')
    attempts=read_csv(repo/'raw', 'call_attempts.csv', parse_dates=['event_at']); attempts['month']=attempts.event_at.dt.to_period('M').astype(str); ag=attempts.groupby(['month','account_id']).agg(attempts=('attempt_id','nunique'),connected=('attempt_status',lambda s:(s=='CONNECTED').sum())).reset_index(); out=out.merge(ag,on=['month','account_id'],how='left')
    add_event('whatsapp_events.csv', {'wa_events':('whatsapp_event_id','nunique'),'wa_replies':('event_type',lambda s:(s=='REPLIED').sum()),'wa_payment_clicks':('event_type',lambda s:(s=='PAYMENT_CLICK').sum())})
    add_event('sms_events.csv', {'sms_events':('sms_event_id','nunique'),'sms_clicks':('event_type',lambda s:(s=='CLICKED').sum())})
    add_event('field_visits.csv', {'field_visits':('visit_id','nunique'),'field_paid':('outcome',lambda s:(s=='PAID').sum()),'field_contacted':('outcome',lambda s:s.isin(['CONTACTED','PTP','PAID']).sum())})
    add_event('promises_to_pay.csv', {'ptps':('ptp_id','nunique'),'ptp_kept':('status',lambda s:(s=='KEPT').sum()),'ptp_broken':('status',lambda s:(s=='BROKEN').sum())})
    add_event('complaints.csv', {'complaints':('complaint_id','nunique'),'high_complaints':('severity',lambda s:s.isin(['HIGH','CRITICAL']).sum())})
    pay=read_csv(repo/'golden_dataset', 'golden_payments.csv', parse_dates=['event_at']); pay['month']=pay.event_at.dt.to_period('M').astype(str); pay=pay[(pay.month.between('2026-01','2026-08'))&(pay.audited_recovery.eq(1))&(pay.payment_status.eq('SUCCESS'))]
    pg=pay.groupby(['month','account_id']).agg(audited_success_payments=('payment_id','nunique'),audited_recovery=('amount','sum')).reset_index(); out=out.merge(pg,on=['month','account_id'],how='left')
    status_hist=read_csv(repo/'raw', 'account_status_history.csv', parse_dates=['event_at','recorded_at']).sort_values(['account_id','event_at']); status_hist['month']=status_hist.event_at.dt.to_period('M').astype(str); status_hist=status_hist[status_hist.month.between('2026-01','2026-08')]
    st=status_hist[['month','account_id','status','event_at']].sort_values(['account_id','month','event_at']).groupby(['month','account_id']).tail(1).drop(columns='event_at').rename(columns={'status':'status_hist'})
    out=out.merge(st,on=['month','account_id'],how='left'); out['status_extract']=out['status_hist'].fillna(out['status_extract']); out=out.drop(columns=['status_hist'])
    numeric=[c for c in out.columns if c not in ['month','account_id','borrower_id','loan_type_extract','risk_segment_extract','timezone_extract','status_extract']]
    for c in numeric: out[c]=out[c].fillna(0)
    cols=['month','account_id','borrower_id','loan_type_extract','principal_amount_extract','outstanding_amount_extract','dpd_extract','risk_segment_extract','status_extract','timezone_extract','target_rows','max_priority','avg_priority','calls','answered','call_duration_sec','attempts','connected','wa_events','wa_replies','wa_payment_clicks','sms_events','sms_clicks','field_visits','field_paid','field_contacted','ptps','ptp_kept','ptp_broken','complaints','high_complaints','audited_success_payments','audited_recovery','partial_month']
    out[cols].to_csv(repo/'golden_dataset/golden_account_month.csv.gz', index=False, compression='gzip')



def main() -> None:
    repo = find_repo_root()
    ap = argparse.ArgumentParser(description='Build the CredResolve SQLite analytical pipeline')
    ap.add_argument('--repo-root', default=os.getenv('CREDRESOLVE_REPO_ROOT', str(repo)))
    ap.add_argument('--raw-dir', default=os.getenv('CREDRESOLVE_RAW_DIR', str(repo / 'raw')))
    ap.add_argument('--build-dir', default=os.getenv('CREDRESOLVE_BUILD_DIR', str(repo / 'pipeline' / 'build')))
    args = ap.parse_args()
    repo = Path(args.repo_root).resolve()
    raw = Path(args.raw_dir).resolve()
    build = Path(args.build_dir).resolve()
    golden_dir = repo / 'golden_dataset'
    results_dir = repo / 'reports' / 'results'
    sql_dir = repo / 'sql'
    for required in [raw, sql_dir, golden_dir, results_dir]:
        if not required.exists():
            raise SystemExit(f'Required directory not found: {required}')
    build.mkdir(parents=True, exist_ok=True)
    db = build / 'credresolve.sqlite'
    if db.exists(): db.unlink()
    conn = sqlite3.connect(db)
    try:
        for csv in sorted(raw.iterdir()):
            if csv.name.endswith('.csv'):
                table_name = csv.stem
            elif csv.name.endswith('.csv.gz'):
                table_name = csv.name[:-7]
            else:
                continue
            pd.read_csv(csv).to_sql(table_name, conn, index=False, if_exists='replace')
        for name in SQL_FILES:
            conn.executescript((sql_dir / name).read_text(encoding='utf-8'))
        gp = pd.read_sql_query('SELECT * FROM golden_payments', conn)
        rp = pd.read_sql_query('SELECT * FROM rejected_payments', conn)
        jt = pd.read_sql_query('SELECT * FROM july_first_target', conn)
        audit = pd.read_sql_query('SELECT * FROM july_target_timing_audit', conn)
        gp.to_csv(golden_dir / 'golden_payments.csv', index=False)
        rp.to_csv(golden_dir / 'rejected_payments.csv', index=False)
        jt.to_csv(results_dir / 'july_first_target.csv', index=False)
        audit.to_csv(results_dir / 'targeting_timing_audit_sql.csv', index=False)
        monthly_sql = pd.read_sql_query('''
            WITH gp AS (
              SELECT account_id, substr(event_at,1,7) AS month, SUM(amount) AS cash
              FROM golden_payments WHERE audited_recovery=1 GROUP BY account_id, month
            ), targets AS (
              SELECT DISTINCT account_id, substr(target_date,1,7) AS month FROM daily_targeting
            ), target_principal AS (
              SELECT t.month, SUM(a.principal_amount) AS principal,
                     COUNT(DISTINCT t.account_id) AS targeted_accounts
              FROM targets t JOIN accounts a USING(account_id) GROUP BY t.month
            ), monthly AS (
              SELECT month, SUM(cash) AS audited_cash,
                     SUM(CASE WHEN (account_id,month) IN
                       (SELECT account_id,month FROM targets) THEN cash ELSE 0 END) AS targeted_cash
              FROM gp GROUP BY month
            )
            SELECT m.month, m.audited_cash, m.targeted_cash,
                   p.principal AS targeted_principal, p.targeted_accounts,
                   CASE WHEN p.principal>0 THEN m.targeted_cash/p.principal ELSE NULL END AS targeted_recovery_yield
            FROM monthly m LEFT JOIN target_principal p USING(month) ORDER BY m.month
        ''', conn)
        monthly_sql.to_csv(results_dir / 'monthly_metrics_sql.csv', index=False)
        for table, filename in [('operational_metrics_monthly','operational_metrics_sql.csv'),('denominator_audit','denominator_audit_sql.csv'),('cohort_effects','cohort_effects_sql.csv')]:
            pd.read_sql_query(f'SELECT * FROM {table}', conn).to_csv(results_dir / filename, index=False)
        manifest = {
            'repo_root': '.', 'raw_dir': 'raw', 'sqlite_db': 'pipeline/build/credresolve.sqlite',
            'sql_files': SQL_FILES, 'golden_payment_rows': int(len(gp)), 'rejected_payment_rows': int(len(rp))
        }
        (build / 'pipeline_manifest.json').write_text(json.dumps(manifest, indent=2), encoding='utf-8')
    finally:
        conn.close()
    print(f'SQL build complete: {db}', flush=True)
    # Replace the process before the analytical stages so each stage starts with a clean memory state.
    os.execv(sys.executable, [sys.executable, str(repo / 'pipeline' / 'analysis_reproduce.py'), '--repo-root', str(repo), '--raw-dir', str(raw)])

if __name__ == '__main__':
    main()
