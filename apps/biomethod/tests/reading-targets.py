"""Compatibility entry point for the current article and pathway-input regression."""
from pathlib import Path
import runpy

runpy.run_path(
    str(Path(__file__).resolve().parents[3] / "app/tests/annotation-review-ui.py"),
    run_name="__main__",
)
