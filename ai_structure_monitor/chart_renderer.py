from __future__ import annotations

from pathlib import Path

import matplotlib.pyplot as plt
from matplotlib.patches import Rectangle
import pandas as pd

from config import CHART_DPI, CHART_HEIGHT_PX, CHART_WIDTH_PX


def render_candles(
    df: pd.DataFrame,
    symbol: str,
    tf_name: str,
    current_price: float,
    output_path: Path,
) -> Path:
    if df.empty:
        raise ValueError(f"{tf_name}: no candles to render")

    width_in = CHART_WIDTH_PX / CHART_DPI
    height_in = CHART_HEIGHT_PX / CHART_DPI
    fig, ax = plt.subplots(figsize=(width_in, height_in), dpi=CHART_DPI)

    candle_width = 0.64
    for i, row in df.iterrows():
        bullish = row["close"] >= row["open"]
        body_color = "#16884a" if bullish else "#c83f49"
        ax.vlines(i, row["low"], row["high"], linewidth=0.8, color="#252525", zorder=1)

        lower = min(row["open"], row["close"])
        body_h = abs(row["close"] - row["open"])
        if body_h == 0:
            ax.hlines(row["close"], i - candle_width / 2, i + candle_width / 2,
                      linewidth=1.1, color=body_color, zorder=2)
        else:
            ax.add_patch(
                Rectangle(
                    (i - candle_width / 2, lower),
                    candle_width,
                    body_h,
                    facecolor=body_color,
                    edgecolor=body_color,
                    linewidth=0.6,
                    zorder=2,
                )
            )

    ax.axhline(current_price, color="#2f6db3", linewidth=1.0, linestyle="--")
    ax.text(
        len(df) - 0.3,
        current_price,
        f"  Current {current_price:.2f}",
        va="center",
        ha="left",
        fontsize=9,
        color="#2f6db3",
    )

    visible_low = min(float(df["low"].min()), current_price)
    visible_high = max(float(df["high"].max()), current_price)
    span = max(visible_high - visible_low, max(abs(current_price) * 0.0005, 0.01))
    pad = span * 0.05
    ax.set_ylim(visible_low - pad, visible_high + pad)

    n = len(df)
    tick_count = min(8, n)
    tick_positions = sorted(set(int(round(x)) for x in
                                [i * (n - 1) / max(tick_count - 1, 1) for i in range(tick_count)]))
    labels = [df.iloc[i]["time"].strftime("%m-%d\n%H:%M") for i in tick_positions]
    ax.set_xticks(tick_positions)
    ax.set_xticklabels(labels, fontsize=8)

    ax.yaxis.tick_right()
    ax.yaxis.set_label_position("right")
    ax.grid(True, axis="both", linewidth=0.35, alpha=0.25)
    ax.set_xlim(-1, n + 7)
    ax.set_title(
        f"{symbol}  {tf_name}  |  {len(df)} CLOSED candles",
        loc="left",
        fontsize=13,
        fontweight="bold",
    )
    ax.set_xlabel("UTC")
    ax.set_ylabel("Price")

    fig.tight_layout()
    output_path.parent.mkdir(parents=True, exist_ok=True)
    fig.savefig(output_path, bbox_inches="tight")
    plt.close(fig)
    return output_path
