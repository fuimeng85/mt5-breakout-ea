from __future__ import annotations

import base64
import json
import os
from pathlib import Path
from typing import Any, Dict, Mapping, Optional

from dotenv import load_dotenv
from openai import OpenAI

from config import DEEPSEEK_BASE_URL, DEEPSEEK_MODEL, IMAGE_DETAIL

load_dotenv()


SYSTEM_PROMPT = r"""
You are a market-structure recognition engine for XAUUSD.
This is a BLIND visual test. No BOS/swing annotations are drawn for you.

You receive four chart images: H1, M30, M15 and M5.
All candles visible in the images are CLOSED candles. The dashed horizontal line is the
current live price and is not itself a structure level.

Your job is NOT to predict profit and NOT to invent an indicator signal.
Identify meaningful price structure visually across nested timeframes.

Rules:
1. Do not require all timeframes to agree.
2. A lower-timeframe BOS may remain inside a higher-timeframe structure.
3. Prefer a BOS confirmed by a CLOSED candle beyond a meaningful prior structural swing.
   A wick-only excursion is weaker and must not be called a clean confirmed BOS.
4. Do not use a fixed N-bar rule, ATR rule, RSI, MACD or volume. None is provided.
5. Distinguish:
   ACTIVE = the selected BOS remains usable for continuation.
   SUSPENDED = the BOS happened, but price has retraced deeply back into the prior structure;
               M1 continuation entries in that BOS direction should temporarily stop.
   INVALID = evidence shows the selected structure itself has failed, not merely a normal pullback.
6. If M15 has a clear BOS, it can be selected even if H1/M30 are still inside their own structures.
7. M5 is especially important for judging normal pullback vs deep re-entry vs re-break.
8. If evidence is ambiguous, say NONE/unclear instead of forcing a trade direction.
9. Return JSON only. Do not include markdown.

Required JSON shape:
{
  "per_tf": {
    "H1": {
      "structure": "bullish|bearish|range|unclear",
      "bos": "bullish|bearish|none|unclear",
      "bos_confirmed": true,
      "break_level": 0.0,
      "evidence": "short factual visual reason"
    },
    "M30": { "...": "same fields" },
    "M15": { "...": "same fields" },
    "M5": { "...": "same fields" }
  },
  "primary_structure_tf": "H1|M30|M15|M5|NONE",
  "primary_direction": "bullish|bearish|none",
  "primary_break_level": 0.0,
  "state": "ACTIVE|SUSPENDED|INVALID|NONE",
  "m5_condition": "continuation|normal_pullback|deep_reentry|rebreak|range|unclear",
  "inside_parent_structure": true,
  "higher_tf_obstruction": {
    "exists": true,
    "timeframe": "H1|M30|M15|NONE",
    "level": 0.0,
    "reason": "short factual visual reason"
  },
  "m1_permission": {
    "long": true,
    "short": false,
    "reason": "structure permission only; MACD is checked elsewhere"
  },
  "confidence": 0.0,
  "notes": "brief"
}

For unavailable/unknown numeric levels use null, not zero.
confidence is only your confidence in the structure classification, not probability of profit.
"""


def _image_data_url(path: Path) -> str:
    raw = path.read_bytes()
    encoded = base64.b64encode(raw).decode("ascii")
    return f"data:image/png;base64,{encoded}"


def analyze_structure(
    image_paths: Mapping[str, Path],
    previous_state: Optional[Dict[str, Any]] = None,
) -> Dict[str, Any]:
    api_key = os.getenv("DEEPSEEK_API_KEY", "").strip()
    if not api_key:
        raise RuntimeError(
            "DEEPSEEK_API_KEY is missing. Copy .env.example to .env and add your API key."
        )

    client = OpenAI(api_key=api_key, base_url=DEEPSEEK_BASE_URL)

    previous_text = (
        json.dumps(previous_state, ensure_ascii=False)
        if previous_state
        else "No previous structure state exists. Start a fresh assessment."
    )

    content = [
        {
            "type": "text",
            "text": (
                "Analyze these four XAUUSD charts as one nested multi-timeframe structure. "
                "Return the required json only.\n"
                f"Previous saved state (context only; override it when new visual evidence disagrees): "
                f"{previous_text}"
            ),
        }
    ]

    for tf_name in ("H1", "M30", "M15", "M5"):
        path = image_paths[tf_name]
        content.append(
            {
                "type": "text",
                "text": f"{tf_name} chart:",
            }
        )
        content.append(
            {
                "type": "image_url",
                "image_url": {
                    "url": _image_data_url(path),
                    "detail": IMAGE_DETAIL,
                },
            }
        )

    response = client.chat.completions.create(
        model=DEEPSEEK_MODEL,
        messages=[
            {"role": "system", "content": SYSTEM_PROMPT},
            {"role": "user", "content": content},
        ],
        response_format={"type": "json_object"},
        max_tokens=2500,
        extra_body={"thinking": {"type": "disabled"}},
    )

    raw = response.choices[0].message.content
    if not raw:
        raise RuntimeError("DeepSeek returned an empty JSON response.")
    return json.loads(raw)
