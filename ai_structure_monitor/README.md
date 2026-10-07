# XAUUSD AI Structure Monitor — V1

This folder is an isolated prototype. It does **not** modify or depend on the existing
`Experts/Breakout.mq5` trading modes.

## Goal

Test one question before any automatic trading is added:

> Can a vision model inspect H1 / M30 / M15 / M5 XAUUSD charts and classify nested
> market structure/BOS in a way that is close to the trader's manual judgement?

V1 intentionally runs in **Blind Mode**. The charts do not contain pre-drawn BOS levels,
pivot labels, ATR, volume, EMA, RSI or MACD. The AI must infer structure from price action.

Locked chart windows:

- H1: 80 closed candles
- M30: 100 closed candles
- M15: 120 closed candles
- M5: 150 closed candles
- Volume: hidden
- Current live price: shown as a dashed line
- Price/time scales: shown
- Only closed candles are rendered; MT5 bar 0 is excluded

## Architecture

```text
MT5
  -> closed OHLC H1/M30/M15/M5
  -> deterministic Python chart renderer
  -> 4 PNG images
  -> DeepSeek Flash Vision
  -> strict JSON structure classification
  -> saved previous structure state
  -> human review

M1 MACD and order execution are NOT connected in V1.
```

## Requirements

Windows machine with:

1. MetaTrader 5 desktop installed and logged in.
2. XAUUSD visible/available from the broker.
3. Python 3.10+ (64-bit recommended).
4. A DeepSeek API key.

Broker symbols are not always exactly `XAUUSD`. Examples include `XAUUSDm`,
`XAUUSD.a`, etc. Set the actual broker symbol in `.env`.

## Install

Open PowerShell in this folder:

```powershell
python -m venv .venv
.\.venv\Scripts\Activate.ps1
pip install -r requirements.txt
Copy-Item .env.example .env
```

Edit `.env`:

```text
DEEPSEEK_API_KEY=your_real_key
MT5_SYMBOL=XAUUSD
DEEPSEEK_MODEL=deepseek-flash
```

Never commit the real API key.

## Run

Keep the MT5 terminal open and logged in, then:

```powershell
streamlit run app.py
```

The dashboard:

- renders the four fixed TF views;
- shows the current price line;
- sends all four images to DeepSeek in one request;
- requests JSON only;
- stores the latest AI structure state in `state/latest_structure.json`;
- supplies that prior state on the next analysis so the model can update rather than
  blindly restart every time.

## Structure states

- **ACTIVE** — selected BOS is still usable as continuation context.
- **SUSPENDED** — BOS occurred, but price has moved deeply back into the prior structure.
  M1 continuation entries in that BOS direction should pause.
- **INVALID** — evidence shows the selected structure itself failed.
- **NONE** — no sufficiently clear structure is selected.

This state is an AI classification in V1. It is not yet allowed to place orders.

## Why no BOS line in the input charts?

If we draw a BOS line first and then ask the AI whether a BOS exists, the test is partly
giving away the answer. In Blind Mode the AI sees raw candles and price/time scales only.

After enough blind tests we can compare a second Assisted Mode where a mechanical
algorithm supplies unlabeled candidate swing levels and the AI decides which ones matter.

## First validation target

Do not judge V1 by profit.

Build a labelled set of historical snapshots and compare the AI judgement with the
trader's judgement for:

- primary structure timeframe;
- BOS direction;
- BOS level;
- ACTIVE / SUSPENDED / INVALID;
- M5 pullback vs deep re-entry vs re-break;
- M1 long/short structure permission.

Only after this is acceptably consistent should M1 MACD execution be connected.
