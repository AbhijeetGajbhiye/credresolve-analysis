#!/usr/bin/env python3
"""Standalone rebuild of golden_account_month.csv.gz for clean-clone reproducibility."""
from pathlib import Path
import argparse
from run_pipeline import rebuild_golden_account_month

ap=argparse.ArgumentParser(); ap.add_argument('--repo-root', default=Path(__file__).resolve().parents[1]); args=ap.parse_args()
repo=Path(args.repo_root).resolve(); print('ACCOUNT STAGE START', flush=True)
rebuild_golden_account_month(repo)
print('golden_account_month rebuild complete')
