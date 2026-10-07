from __future__ import annotations

from dataclasses import dataclass
from typing import Dict

import MetaTrader5 as mt5
import pandas as pd


TF_MAP = {
    "H1": mt5.TIMEFRAME_H1,
    "M30": mt5.TIMEFRAME_M30,
    "M15": mt5.TIMEFRAME_M15,
    "M5": mt5.TIMEFRAME_M5,
}


@dataclass
class MarketSnapshot:
    symbol: str
    current_price: float
    frames: Dict[str, pd.DataFrame]


def connect_mt5() -> None:
    if not mt5.initialize():
        code, message = mt5.last_error()
        raise RuntimeError(f"MT5 initialize failed: {code} {message}")


def shutdown_mt5() -> None:
    mt5.shutdown()


def _ensure_symbol(symbol: str) -> None:
    info = mt5.symbol_info(symbol)
    if info is None:
        raise RuntimeError(
            f"MT5 cannot find symbol '{symbol}'. "
            "Your broker may use a suffix such as XAUUSDm/XAUUSD.a; set MT5_SYMBOL in .env."
        )
    if not info.visible and not mt5.symbol_select(symbol, True):
        raise RuntimeError(f"Could not select symbol '{symbol}' in Market Watch.")


def get_current_price(symbol: str) -> float:
    _ensure_symbol(symbol)
    tick = mt5.symbol_info_tick(symbol)
    if tick is None:
        raise RuntimeError(f"No live tick available for {symbol}.")
    if tick.bid > 0:
        return float(tick.bid)
    if tick.last > 0:
        return float(tick.last)
    raise RuntimeError(f"Invalid live price returned for {symbol}.")


def get_closed_bars(symbol: str, tf_name: str, count: int) -> pd.DataFrame:
    if tf_name not in TF_MAP:
        raise ValueError(f"Unsupported timeframe: {tf_name}")

    _ensure_symbol(symbol)

    # start_pos=1 deliberately skips bar 0, the still-forming candle.
    rates = mt5.copy_rates_from_pos(symbol, TF_MAP[tf_name], 1, count)
    if rates is None:
        code, message = mt5.last_error()
        raise RuntimeError(f"copy_rates_from_pos({tf_name}) failed: {code} {message}")
    if len(rates) < count:
        raise RuntimeError(
            f"{tf_name}: requested {count} closed bars but MT5 returned only {len(rates)}."
        )

    df = pd.DataFrame(rates)
    df["time"] = pd.to_datetime(df["time"], unit="s", utc=True)
    df = df.sort_values("time").reset_index(drop=True)
    return df[["time", "open", "high", "low", "close", "tick_volume"]]


def get_snapshot(symbol: str, tf_specs) -> MarketSnapshot:
    connect_mt5()
    try:
        price = get_current_price(symbol)
        frames = {
            tf_name: get_closed_bars(symbol, tf_name, count)
            for tf_name, count in tf_specs.items()
        }
        return MarketSnapshot(symbol=symbol, current_price=price, frames=frames)
    finally:
        shutdown_mt5()
