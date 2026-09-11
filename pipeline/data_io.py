from pathlib import Path
import pandas as pd


def resolve_data_path(base: Path, name: str) -> Path:
    """Resolve an ordinary CSV or its GitHub-friendly gzip-compressed sibling."""
    base = Path(base)
    p = base / name
    if p.exists():
        return p
    gz = base / f"{name}.gz"
    if gz.exists():
        return gz
    raise FileNotFoundError(f"Neither {p} nor {gz} exists")


def read_csv(base: Path, name: str, **kwargs) -> pd.DataFrame:
    return pd.read_csv(resolve_data_path(base, name), **kwargs)
