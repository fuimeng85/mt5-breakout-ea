# Breakout EA 使用说明（MT5）

> 适用文件：`Experts/Breakout.mq5`  
> 可视化指标（可选）：`Indicators/EA_TV_MACD_View.mq5`

---

## 1. EA 核心逻辑（先看这个）

1. **HTF Donchian** 决定大方向（BUY/SELL）。
2. 再按你启用的入场 TF（H4/H1/M30/M15/M5）做 **MACD 条件入场**。
3. 出场优先级：
   - BB Exit（可选）
   - EMA Profit Exit（可选）
   - Trailing（距离或EMA止损）
4. 手数支持：
   - AutoLot（风险百分比）
   - FixedLot
   - 每TF手动覆盖（可选）

---

## 2. 安装与运行

### 2.1 文件放置
- EA：`MQL5/Experts/Breakout.mq5`
- 指标（可选）：`MQL5/Indicators/EA_TV_MACD_View.mq5`

### 2.2 编译
- 在 MetaEditor 编译 EA。
- 若要用“EA MACD可视化面板”，也要编译 `EA_TV_MACD_View.mq5`。

### 2.3 挂载
- 任意图表挂 EA（一个图可以多TF扫描，不要求每TF单独开图）。
- 勾选“允许自动交易”。

---

## 3. 参数说明（完整）

## 3.1 `=== 1) HTF Donchian Breakout (State) ===`
- `InpHTF`：方向判定主周期（默认H4）
- `InpDonchianPer`：Donchian周期
- `InpMinChRangePts`：最小通道宽度（点）
- `InpUseATRFilter`：是否启用 ATR 过滤
- `InpATRPeriod`：ATR周期
- `InpATRMult`：通道宽度与ATR倍率阈值

## 3.2 `=== 1b) HTF Breakout Continuation (Trend Memory) ===`
- `InpUseTrendMemory`：开启突破后趋势记忆
- `InpMem_BreakCandleLevel`：用突破K高/低保护
- `InpMem_XBarsLevel`：用最近X根HTF结构位保护
- `InpMem_XBarsLookback`：X根数量
- `InpMem_PctRetraceLevel`：按回撤百分比保护
- `InpMem_RetracePercent`：允许回撤百分比

## 3.3 `=== 1c) Trend Memory Lines on Chart (Visual) ===`
- `InpShowTM_Lines`：显示趋势记忆线总开关
- `InpShowTM_History`：保留历史线
- `InpShowTM_MaxHistory`：历史线最大保留
- `InpShowTM_DonchianLine`：显示Donchian线
- `InpShowTM_XBarsLine`：显示XBars线
- `InpShowTM_MemoryLine`：显示Memory线
- `InpShowTM_LabelFontSize`：标签字号

## 3.4 `=== 2) LTF MACD Entry TF Switches ===`
- `InpUseH4 / InpUseH1 / InpUseM30 / InpUseM15 / InpUseM5`
  - 启用/禁用对应TF入场扫描

## 3.5 `=== 2B) Per-TF Ignore Donchian (MACD-only Entry) ===`
- `InpH4_IgnoreDonchian`
- `InpH1_IgnoreDonchian`
- `InpM30_IgnoreDonchian`
- `InpM15_IgnoreDonchian`
- `InpM5_IgnoreDonchian`

> 开启后：该TF入场不依赖 Donchian 方向，只看 MACD 条件。

## 3.6 `=== 2C) Per-TF Breakout Candle Scan Entry ===`
- `Inp*_UseBreakScan`：是否启用“突破后回看X根信号即入场”
- `Inp*_BreakScanBars`：回看根数 X
- `Inp*_BreakScanMode`：模式
  - `MACD_SCAN_CROSS`（金叉/死叉）
  - `MACD_SCAN_FADE`（fade）

## 3.7 `=== 3) Filters & Order Management (Per TF) ===`
- `InpMaxSpreadPts`：最大点差
- `InpUseNewsFilter`：新闻过滤开关
- `InpNewsBeforeMin`：新闻前禁开分钟
- `InpNewsAfterMin`：新闻后禁开分钟
- `InpFOMCOnly`：仅过滤FOMC
- `InpNewsNoPosOnly`：仅无仓位时启用新闻过滤
- `InpMaxOrdersPerTF`：每TF最大持仓数

## 3.8 `=== 4) TV Style MACD (Custom) ===`
- `InpFastEMA`：快线EMA
- `InpSlowEMA`：慢线EMA
- `InpSignalSMA`：信号SMA周期
- `InpEMAFilterPer`：EMA趋势过滤周期

## 3.9 `=== 5) SL / TP / EMA Exit ===`
- `InpSLBufferPts`：初始SL缓冲点
- `InpHardTP`：硬TP点数
- `InpUseEMAProfitExit`：EMA利润退出开关
- `InpEMAExitProfitPts`：达到该利润后才启用EMA退出
- `InpEMAExitPeriod`：EMA退出周期
- `InpEMAExitBufferPts`：EMA退出缓冲点
- `InpTrailMinInterval`：同票最短修改间隔（秒）
- `InpUseEMATrailAfterProfit`：达到利润后改用EMA止损
- `InpEMATrailPeriod`：EMA止损周期
- `InpEMATrailBufferPts`：EMA止损缓冲
- `InpEMATrailUseEntryTF`：EMA止损使用入场TF

## 3.10 `=== 5B) Per-TF Bollinger Exit (Optional) ===`
每个TF都可设置：
- `Inp*_UseBBExit`
- `Inp*_BB_TF`
- `Inp*_BB_Period`
- `Inp*_BB_Deviation`

## 3.11 `=== 5C) Per-TF Distance Trailing ===`
每个TF都可设置：
- `Inp*_TrailStartPts`
- `Inp*_TrailDistPts`
- `Inp*_TrailStepPts`

## 3.12 `=== 6) Money Management ===`
- `InpUseAutoLot`：自动手数开关
- `InpRiskPercent`：风险百分比
- `InpFixedLot`：固定手数
- `InpMagic`：策略Magic Number

## 3.13 `=== 6B) Per-TF Manual Lot (Optional) ===`
每个TF：
- `Inp*_UseManualLot`
- `Inp*_ManualLot`

> 若启用该TF手动手数，会覆盖默认 Auto/Fix 结果。

## 3.14 `=== 7) Time Filter (交易时间控制) ===`
- `InpUseTimeFilter`
- `InpStartHour / InpStartMin`
- `InpEndHour / InpEndMin`

## 3.15 `=== 8) Debug ===`
- `InpPrintHTF`
- `InpPrintBlocks`
- `InpPrintSignals`
- `InpPrintExits`

## 3.16 `=== 8B) Visual Debug: EA MACD Panel ===`
- `InpShowEAMACDPanel`：显示EA同算法MACD面板
- `InpShowEAMACD_TF`：面板显示TF

## 3.17 `=== 8C) UI: TF Toggle Buttons ===`
- `InpShowTFButtons`：图左侧TF按钮开关
- 运行时按钮可切换：M5/M15/M30/H1/H4

---

## 4. 常见配置模板

## 4.1 保守
- 开 `InpUseH1=true`, `InpUseH4=true`
- 关 M5/M15/M30
- 保持 `IgnoreDonchian=false`
- 点差与新闻过滤开启

## 4.2 均衡
- 开 H1/M30/M15
- M5 视点差再开
- BreakScan 只在 M15/M30 开

## 4.3 激进
- 全TF开启
- 可开启部分TF IgnoreDonchian
- 手动每TF lot 管理风险

---

## 5. 常见问题

1. **为什么有信号不下单？**
   - 可能被 spread/news/time/max-orders/非新K 过滤。
2. **为什么不同账号行为不同？**
   - 点差、报价、执行环境、历史数据与时间不同。
3. **MACD面板没显示？**
   - 检查 `InpShowEAMACDPanel=true`；
   - 检查 indicator 文件是否放在 `MQL5/Indicators` 且已编译。

---

## 6. 操作建议（实盘前）

- 先单账号、小手数、短周期回测 + 可视化测试。
- 先关复杂开关（BreakScan/IgnoreDonchian），逐项开启。
- 固定 Magic，避免多个EA实例混淆管理。

---

## 7. 新增可视化工具：高质量供需 + 支撑阻力扫描器

文件：`Indicators/SD_SR_Quality_Zones.mq5`

用途：
- 扫描最近500根K线（可调）
- 用 Pivot 方式绘制支撑/阻力区域
- 识别高质量 Supply / Demand 区域（Base + 大实体离开）
- 支持“激进触区即提示”与“仅首次回踩”

关键参数（默认值）：
- `InpScanBars=500`
- `InpUseScanDays=true`
- `InpScanDays=120`（跨周期对齐扫描时间范围，减少“H1无、H4有”）
- `InpPivotN=3`
- `InpBaseMin=2`
- `InpBaseMax=6`
- `InpImpulseBodyFactor=2.0`
- `InpMinQualityScore=70`
- `InpAggressiveEntry=true`
- `InpFirstRetestOnly=true`
- `InpFilterSRByDistance=false`（中小级别可见性优先建议关闭）
- `InpMaxSRDistanceATR=25.0`（过滤离现价过远的S/R，避免远古高点线占满名额）
- `InpShowSRLevelLabel=true`（在线上显示级别和周期）
- `InpSRLowColor / InpSRMidColor / InpSRHighColor`（不同级别线颜色）
- `InpDebugShowStats=true`（左上角显示扫描统计，便于排查“图上无任何显示”）

排查建议（如果加载后看不到区域）：
- 先把图表切到流动性较高的品种/周期（如 EURUSD M15/H1）。
- 保持 `InpScanBars=500`，并确认图表历史K线数量足够。
- 看左上角统计是否出现 `SR` 与 `ZonesDrawn`；若 `ZonesDrawn=0`，可先把 `InpMinQualityScore` 临时下调到 60 做验证。
- 如果出现“H1几乎没线、H4有很多旧线”：开启 `InpUseScanDays=true` 并提高 `InpScanDays`，同时设置 `InpMaxSRDistanceATR` 过滤远离当前价格的历史线。
- 如果你希望在 M15/M30/H1 看见更多线：把 `InpFilterSRByDistance=false`（关闭距离过滤）。
