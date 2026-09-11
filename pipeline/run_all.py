#!/usr/bin/env python3
"""Compatibility wrapper for the canonical full pipeline."""
from pathlib import Path
import argparse, os, sys
ap=argparse.ArgumentParser(); ap.add_argument('--repo-root', default=Path(__file__).resolve().parents[1]); args=ap.parse_args()
repo=Path(args.repo_root).resolve()
os.execv(sys.executable, [sys.executable, str(repo/'pipeline'/'run_pipeline.py'), '--repo-root', str(repo)])
