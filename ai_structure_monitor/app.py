from __future__ import annotations

from datetime import datetime, timezone
from pathlib import Path
import json

import streamlit as st
from dotenv import load_dotenv

from chart_renderer import render_candles
from config import OUTPUT_DIR, SYMBOL, TF_SPECS
from deepseek_client import analyze_structure
from market_data import get_snapshot
from state_store import load_previous_state, save_state

load_dotenv()

st.set_page_config(page_title="XAUUSD AI Structure Monitor", layout="wide")
st.title("XAUUSD AI Structure Monitor — V1 Blind Test")
st.caption(
    "Observation only. H1/M30/M15/M5 structure recognition; no automatic trading and no M1 MACD execution yet."
)

with st.sidebar:
    symbol = st.text_input("MT5 symbol", value=SYMBOL)
    st.write("Locked V1 windows")
    for tf, bars in TF_SPECS.items():
        st.write(f"{tf}: {bars} closed candles")
    st.info("Volume/ATR/EMA/MACD are intentionally hidden in V1.")
    fetch = st.button("Refresh charts", use_container_width=True)
    analyze = st.button("Ask DeepSeek to analyze", type="primary", use_container_width=True)

if "snapshot" not in st.session_state:
    st.session_state.snapshot = None
if "image_paths" not in st.session_state:
    st.session_state.image_paths = None
if "analysis" not in st.session_state:
    st.session_state.analysis = None


def refresh_snapshot():
    snap = get_snapshot(symbol, TF_SPECS)
    stamp = datetime.now(timezone.utc).strftime("%Y%m%d_%H%M%S")
    paths = {}
    for tf_name, df in snap.frames.items():
        path = OUTPUT_DIR / f"{symbol}_{tf_name}_{stamp}.png"
        render_candles(
            df=df,
            symbol=symbol,
            tf_name=tf_name,
            current_price=snap.current_price,
            output_path=path,
        )
        paths[tf_name] = path
    st.session_state.snapshot = snap
    st.session_state.image_paths = paths


if fetch or st.session_state.snapshot is None:
    try:
        refresh_snapshot()
    except Exception as exc:
        st.error(str(exc))
        st.stop()

snap = st.session_state.snapshot
paths = st.session_state.image_paths

st.subheader(f"{snap.symbol} | live price {snap.current_price:.2f}")
left, right = st.columns(2)
with left:
    st.image(str(paths["H1"]), caption="H1 — 80 closed candles", use_container_width=True)
    st.image(str(paths["M15"]), caption="M15 — 120 closed candles", use_container_width=True)
with right:
    st.image(str(paths["M30"]), caption="M30 — 100 closed candles", use_container_width=True)
    st.image(str(paths["M5"]), caption="M5 — 150 closed candles", use_container_width=True)

if analyze:
    try:
        previous = load_previous_state()
        result = analyze_structure(paths, previous_state=previous)
        save_state(result)
        st.session_state.analysis = result
    except Exception as exc:
        st.error(f"AI analysis failed: {exc}")

st.divider()
st.subheader("AI Structure JSON")

if st.session_state.analysis:
    result = st.session_state.analysis

    c1, c2, c3, c4 = st.columns(4)
    c1.metric("Primary TF", result.get("primary_structure_tf", "—"))
    c2.metric("Direction", result.get("primary_direction", "—"))
    c3.metric("State", result.get("state", "—"))
    c4.metric("M5", result.get("m5_condition", "—"))

    perm = result.get("m1_permission", {})
    p1, p2 = st.columns(2)
    p1.metric("M1 LONG permission", "YES" if perm.get("long") else "NO")
    p2.metric("M1 SHORT permission", "YES" if perm.get("short") else "NO")

    st.json(result)
else:
    previous = load_previous_state()
    if previous:
        st.caption("No analysis in this UI session yet. Latest saved state is shown below.")
        st.json(previous)
    else:
        st.caption("Press 'Ask DeepSeek to analyze' after checking the four charts.")
