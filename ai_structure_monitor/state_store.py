from __future__ import annotations

import json
from datetime import datetime, timezone
from pathlib import Path
from typing import Any, Dict, Optional

from config import STATE_DIR

STATE_FILE = STATE_DIR / "latest_structure.json"


def load_previous_state() -> Optional[Dict[str, Any]]:
    if not STATE_FILE.exists():
        return None
    try:
        return json.loads(STATE_FILE.read_text(encoding="utf-8"))
    except (json.JSONDecodeError, OSError):
        return None


def save_state(payload: Dict[str, Any]) -> Path:
    wrapped = {
        "saved_at_utc": datetime.now(timezone.utc).isoformat(),
        "analysis": payload,
    }
    STATE_FILE.write_text(
        json.dumps(wrapped, ensure_ascii=False, indent=2),
        encoding="utf-8",
    )
    return STATE_FILE
