from __future__ import annotations

import os
from collections import OrderedDict
from pathlib import Path

BASE_DIR = Path(__file__).resolve().parent
OUTPUT_DIR = BASE_DIR / "output"
STATE_DIR = BASE_DIR / "state"

OUTPUT_DIR.mkdir(parents=True, exist_ok=True)
STATE_DIR.mkdir(parents=True, exist_ok=True)

SYMBOL = os.getenv("MT5_SYMBOL", "XAUUSD")
DEEPSEEK_MODEL = os.getenv("DEEPSEEK_MODEL", "deepseek-flash")
DEEPSEEK_BASE_URL = "https://api.deepseek.com"

# Locked V1 visual windows agreed for the first blind test.
TF_SPECS = OrderedDict(
    [
        ("H1", 80),
        ("M30", 100),
        ("M15", 120),
        ("M5", 150),
    ]
)

CHART_WIDTH_PX = 1280
CHART_HEIGHT_PX = 720
CHART_DPI = 100
IMAGE_DETAIL = "high"

# V1 is observation-only. No trading/order execution is implemented here.
