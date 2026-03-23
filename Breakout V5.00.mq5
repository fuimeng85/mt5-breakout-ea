//+------------------------------------------------------------------+
//| Donchian_MACD_Breakout_PerTF_Full.mq5                            |
//| Per TF Max Orders + 友好Comment标识 (5min/15min/1H等)            |
//| v4.98:                                                          |
//| 1) Added Per-TimeFrame Trailing Stop inputs (Start, Dist, Step)  |
//| 2) Fix trade request flood: trailing throttle + step             |
//| 3) EMA Profit Exit: shift=0 + buffer (configurable)              |
//| 4) After ProfitPts>=InpEMAExitProfitPts: use EMAx as SL (config) |
//| 5) Cleanup MAX_TRACK ticket table (avoid trailing stop disabled after long run) |
//| 6) Trade retcode checks + INVALID_STOPS auto-adjust/retry           |
//+------------------------------------------------------------------+
#property strict
#property version   "5.00"

#include <Trade/Trade.mqh>
CTrade trade;

//============================== INPUTS ==============================

input group "=== 1) HTF Donchian Breakout (State) ==="
input ENUM_TIMEFRAMES InpHTF            = PERIOD_H4;
input int             InpDonchianPer    = 20;
input int             InpMinChRangePts  = 300;
input bool            InpUseATRFilter   = false;
input int             InpATRPeriod      = 14;
input double          InpATRMult        = 1.5;

input group "=== 1b) HTF Breakout Continuation (Trend Memory) ==="
input bool            InpUseTrendMemory       = false;   // 启用“突破后趋势记忆/延续”模式（允许回踩后继续做）
input bool            InpMem_BreakCandleLevel = true;    // A) 突破K低/高保护：BUY用突破K低点，SELL用突破K高点
input bool            InpMem_XBarsLevel       = true;    // B) X根HTF结构位保护：BUY用最近X根HTF最低，SELL用最近X根HTF最高
input int             InpMem_XBarsLookback    = 3;       // X=几根HTF（含突破K）
input bool            InpMem_PctRetraceLevel  = true;    // C) 百分比回撤保护：基于突破后最高/最低与breakLevel的回撤百分比
input double          InpMem_RetracePercent   = 50.0;    // 允许回撤百分比(0-100)，例如50=回撤到(突破幅度的一半)仍保持趋势

input group "=== 1c) Trend Memory Lines on Chart (Visual) ==="
input bool            InpShowTM_Lines         = true;    // 画出 Donchian / XBars / Memory 水平线
input bool            InpShowTM_History       = false;   // 是否保留历史线(开启后每次突破都保留；否则只保留当前)
input int             InpShowTM_MaxHistory    = 50;      // 历史线最大保留数量(每种线各自计算)
input bool            InpShowTM_DonchianLine  = true;    // 显示 Donchian Break 线
input bool            InpShowTM_XBarsLine     = true;    // 显示 XBars Protect 线
input bool            InpShowTM_MemoryLine    = true;    // 显示 Trend Memory Active 线
input int             InpShowTM_LabelFontSize = 9;       // 标签字体大小

input group "=== 2) LTF MACD Entry TF Switches ==="
input bool            InpUseH4          = true;
input bool            InpUseH1          = true;
input bool            InpUseM30         = true;
input bool            InpUseM15         = true;
input bool            InpUseM5          = true;

input group "=== 2B) Per-TF Ignore Donchian (MACD-only Entry) ==="
input bool            InpH4_IgnoreDonchian  = false;
input bool            InpH1_IgnoreDonchian  = false;
input bool            InpM30_IgnoreDonchian = false;
input bool            InpM15_IgnoreDonchian = false;
input bool            InpM5_IgnoreDonchian  = false;

input group "=== 2C) Per-TF Breakout Candle Scan Entry ==="
enum EMacdScanMode { MACD_SCAN_CROSS=0, MACD_SCAN_FADE=1 };
input bool          InpH4_UseBreakScan     = false;
input int           InpH4_BreakScanBars    = 5;
input EMacdScanMode InpH4_BreakScanMode    = MACD_SCAN_CROSS;
input bool          InpH1_UseBreakScan     = false;
input int           InpH1_BreakScanBars    = 5;
input EMacdScanMode InpH1_BreakScanMode    = MACD_SCAN_CROSS;
input bool          InpM30_UseBreakScan    = false;
input int           InpM30_BreakScanBars   = 5;
input EMacdScanMode InpM30_BreakScanMode   = MACD_SCAN_CROSS;
input bool          InpM15_UseBreakScan    = false;
input int           InpM15_BreakScanBars   = 5;
input EMacdScanMode InpM15_BreakScanMode   = MACD_SCAN_CROSS;
input bool          InpM5_UseBreakScan     = false;
input int           InpM5_BreakScanBars    = 5;
input EMacdScanMode InpM5_BreakScanMode    = MACD_SCAN_CROSS;

input group "=== 2D) MODE2(BreakScan) Per-TF SL/TP ==="
input int           InpH4_SLLookbackBars   = 5;
input int           InpH1_SLLookbackBars   = 5;
input int           InpM30_SLLookbackBars  = 5;
input int           InpM15_SLLookbackBars  = 5;
input int           InpM5_SLLookbackBars   = 5;
input int           InpH4_Mode2TPValue     = 50000;
input int           InpH1_Mode2TPValue     = 50000;
input int           InpM30_Mode2TPValue    = 50000;
input int           InpM15_Mode2TPValue    = 50000;
input int           InpM5_Mode2TPValue     = 50000;

input group "=== 3) Filters & Order Management (Per TF) ==="
input int             InpMaxSpreadPts   = 30;
input bool            InpUseNewsFilter  = false;
input int             InpNewsBeforeMin  = 30;
input int             InpNewsAfterMin   = 30;
input bool            InpFOMCOnly       = true;
input bool            InpNewsNoPosOnly  = true;
input int             InpMaxOrdersPerTF = 2;
input int             InpMaxOrdersPerTF_Mode1 = 2;
input int             InpMaxOrdersPerTF_Mode2 = 2;

input group "=== 4) TV Style MACD (Custom) ==="
input int             InpFastEMA        = 12;
input int             InpSlowEMA        = 26;
input int             InpSignalSMA      = 9;
input int             InpEMAFilterPer   = 26;

input group "=== 5) SL / TP / EMA Exit ==="
input int             InpSLBufferPts      = 0;
input int             InpHardTP           = 50000;

input bool            InpUseEMAProfitExit = true;
input int             InpEMAExitProfitPts = 2500;
input int             InpEMAExitPeriod    = 26;      // EMA Exit 周期（可输入）
input int             InpEMAExitBufferPts = 200;     // EMA Exit 缓冲(点)：价格需穿过EMA±Buffer才出

// --- Flood protection for modify
input int             InpTrailMinInterval = 2;       // 同一张单最短多少秒才能Modify一次（建议 1~5）

// --- NEW: After Profit>=EMAExitProfitPts use EMA as SL (instead of distance trailing)
input bool            InpUseEMATrailAfterProfit = true;  // >=2500点后用EMA当止损
input int             InpEMATrailPeriod         = 26;    // EMA 止损周期（可输入）
input int             InpEMATrailBufferPts      = 200;   // EMA 止损缓冲(点)
input bool            InpEMATrailUseEntryTF     = true;  // true=用入场TF的EMA；false=用当前图表TF

input group "=== 5B) Per-TF Bollinger Exit (Optional) ==="
// 每个入场TF可独立设置：是否启用BB止盈、参考哪个TF的布林带、参数
// M5
input bool            InpM5_UseBBExit       = false;
input ENUM_TIMEFRAMES InpM5_BB_TF           = PERIOD_M15;
input int             InpM5_BB_Period       = 20;
input double          InpM5_BB_Deviation    = 2.0;
// M15
input bool            InpM15_UseBBExit      = false;
input ENUM_TIMEFRAMES InpM15_BB_TF          = PERIOD_M30;
input int             InpM15_BB_Period      = 20;
input double          InpM15_BB_Deviation   = 2.0;
// M30
input bool            InpM30_UseBBExit      = false;
input ENUM_TIMEFRAMES InpM30_BB_TF          = PERIOD_H1;
input int             InpM30_BB_Period      = 20;
input double          InpM30_BB_Deviation   = 2.0;
// H1
input bool            InpH1_UseBBExit       = false;
input ENUM_TIMEFRAMES InpH1_BB_TF           = PERIOD_H4;
input int             InpH1_BB_Period       = 20;
input double          InpH1_BB_Deviation    = 2.0;
// H4
input bool            InpH4_UseBBExit       = false;
input ENUM_TIMEFRAMES InpH4_BB_TF           = PERIOD_D1;
input int             InpH4_BB_Period       = 20;
input double          InpH4_BB_Deviation    = 2.0;

input group "=== 5C) Per-TF Distance Trailing ==="
// M5 Trailing
input int InpM5_TrailStartPts  = 1500;
input int InpM5_TrailDistPts   = 500;
input int InpM5_TrailStepPts   = 50;
// M15 Trailing
input int InpM15_TrailStartPts = 1500;
input int InpM15_TrailDistPts  = 500;
input int InpM15_TrailStepPts  = 50;
// M30 Trailing
input int InpM30_TrailStartPts = 1500;
input int InpM30_TrailDistPts  = 500;
input int InpM30_TrailStepPts  = 50;
// H1 Trailing
input int InpH1_TrailStartPts  = 1500;
input int InpH1_TrailDistPts   = 500;
input int InpH1_TrailStepPts   = 50;
// H4 Trailing
input int InpH4_TrailStartPts  = 1500;
input int InpH4_TrailDistPts   = 500;
input int InpH4_TrailStepPts   = 50;

input group "=== 5D) Per-TF Cooldown After TP (Bars) ==="
input int InpM5_TPCoolBars  = 0;
input int InpM15_TPCoolBars = 0;
input int InpM30_TPCoolBars = 0;
input int InpH1_TPCoolBars  = 0;
input int InpH4_TPCoolBars  = 0;

input group "=== 6) Money Management ==="
input bool            InpUseAutoLot     = false;
input double          InpRiskPercent    = 1.0;
input double          InpFixedLot       = 0.01;
input ulong           InpMagic          = 88888;

input group "=== 6B) Per-TF Manual Lot (Optional) ==="
input bool            InpM5_UseManualLot  = false;
input double          InpM5_ManualLot     = 0.01;
input bool            InpM15_UseManualLot = false;
input double          InpM15_ManualLot    = 0.01;
input bool            InpM30_UseManualLot = false;
input double          InpM30_ManualLot    = 0.01;
input bool            InpH1_UseManualLot  = false;
input double          InpH1_ManualLot     = 0.01;
input bool            InpH4_UseManualLot  = false;
input double          InpH4_ManualLot     = 0.01;

input group "=== 7) Time Filter (交易时间控制) ==="
input bool            InpUseTimeFilter  = false;
input int             InpStartHour      = 9;
input int             InpStartMin       = 0;
input int             InpEndHour        = 17;
input int             InpEndMin         = 0;

input group "=== 8) Debug ==="
input bool            InpPrintHTF       = true;
input bool            InpPrintBlocks    = true;
input bool            InpPrintSignals   = true;
input bool            InpPrintExits     = true;

input group "=== 8B) Visual Debug: EA MACD Panel ==="
input bool            InpShowEAMACDPanel = false;
input ENUM_TIMEFRAMES InpShowEAMACD_TF   = PERIOD_H1;

input group "=== 8C) UI: TF Toggle Buttons ==="
input bool            InpShowTFButtons   = true;

//============================== ENUMS ===============================
enum EDir { DIR_NONE=0, DIR_BUY=1, DIR_SELL=-1 };

//============================== GLOBALS =============================
EDir     g_dir             = DIR_NONE;
double   g_breakLevel      = 0.0;
double   g_breakCandleLow  = 0.0;   // 突破K低点（BUY保护）
double   g_breakCandleHigh = 0.0;   // 突破K高点（SELL保护）
double   g_xBarsLow        = 0.0;   // 最近X根HTF最低（BUY保护）
double   g_xBarsHigh       = 0.0;   // 最近X根HTF最高（SELL保护）
double   g_peakHigh        = 0.0;   // 突破后最高价（用于百分比回撤保护 BUY）
double   g_troughLow       = 0.0;   // 突破后最低价（用于百分比回撤保护 SELL）
datetime g_lastHTFClosedT1 = 0;
bool     g_newBreakoutSignal = false;
int      g_atrHTF  = INVALID_HANDLE;

// Entry filter handles (EMAFilterPer)
int g_fastH4  = INVALID_HANDLE, g_slowH4  = INVALID_HANDLE, g_emaH4  = INVALID_HANDLE;
int g_fastH1  = INVALID_HANDLE, g_slowH1  = INVALID_HANDLE, g_emaH1  = INVALID_HANDLE;
int g_fastM30 = INVALID_HANDLE, g_slowM30 = INVALID_HANDLE, g_emaM30 = INVALID_HANDLE;
int g_fastM15 = INVALID_HANDLE, g_slowM15 = INVALID_HANDLE, g_emaM15 = INVALID_HANDLE;
int g_fastM5  = INVALID_HANDLE, g_slowM5  = INVALID_HANDLE, g_emaM5  = INVALID_HANDLE;

// NEW: EMA Exit handles (InpEMAExitPeriod)
int g_exitEmaH4  = INVALID_HANDLE, g_exitEmaH1  = INVALID_HANDLE, g_exitEmaM30 = INVALID_HANDLE, g_exitEmaM15 = INVALID_HANDLE, g_exitEmaM5 = INVALID_HANDLE;

// NEW: EMA Trail SL handles (InpEMATrailPeriod)
int g_trailEmaH4 = INVALID_HANDLE, g_trailEmaH1 = INVALID_HANDLE, g_trailEmaM30 = INVALID_HANDLE, g_trailEmaM15 = INVALID_HANDLE, g_trailEmaM5 = INVALID_HANDLE;
int g_trailEmaChart = INVALID_HANDLE;

int g_dbgMacdPanelH = INVALID_HANDLE;

datetime g_lastBarH4  = 0, g_lastBarH1  = 0, g_lastBarM30 = 0, g_lastBarM15 = 0, g_lastBarM5  = 0;
datetime g_lastSigH4  = 0, g_lastSigH1  = 0, g_lastSigM30 = 0, g_lastSigM15 = 0, g_lastSigM5  = 0;
datetime g_lastSigMode2H4  = 0, g_lastSigMode2H1  = 0, g_lastSigMode2M30 = 0, g_lastSigMode2M15 = 0, g_lastSigMode2M5  = 0;

datetime g_lastTPCloseH4=0, g_lastTPCloseH1=0, g_lastTPCloseM30=0, g_lastTPCloseM15=0, g_lastTPCloseM5=0;

bool g_useH4=false, g_useH1=false, g_useM30=false, g_useM15=false, g_useM5=false;

// --- per ticket modify throttle
#define MAX_TRACK 200
ulong    g_trkTicket[MAX_TRACK];
datetime g_trkLastMod[MAX_TRACK];

int FindTrackIndex(ulong ticket)
{
   for(int k=0;k<MAX_TRACK;k++)
      if(g_trkTicket[k]==ticket) return k;
   return -1;
}

int AllocTrackIndex(ulong ticket)
{
   int empty=-1;
   for(int k=0;k<MAX_TRACK;k++)
   {
      if(g_trkTicket[k]==ticket) return k;
      if(g_trkTicket[k]==0 && empty==-1) empty=k;
   }
   if(empty!=-1)
   {
      g_trkTicket[empty]=ticket;
      g_trkLastMod[empty]=0;
      return empty;
   }
   return -1;
}

bool TrailAllowModify(ulong ticket,int minIntervalSec)
{
   int idx=FindTrackIndex(ticket);
   if(idx<0) idx=AllocTrackIndex(ticket);
   if(idx<0) return false; // table full -> skip to avoid flood

   datetime now=TimeCurrent();
   if((now - g_trkLastMod[idx]) < minIntervalSec) return false;
   g_trkLastMod[idx]=now;
   return true;
}


//====================== v4.98 FIXES: TRACK CLEANUP + SAFE TRADES ======================

// Cleanup throttle table: free slots for tickets that are no longer open positions
void TrailCleanupTable()
{
   for(int k=0;k<MAX_TRACK;k++)
   {
      ulong tk=g_trkTicket[k];
      if(tk==0) continue;
      // if ticket not found in current positions, free this slot
      if(!PositionSelectByTicket(tk))
      {
         g_trkTicket[k]=0;
         g_trkLastMod[k]=0;
      }
   }
}

// Return a SL adjusted to broker constraints (StopsLevel / FreezeLevel).
// Note: we only adjust if needed; caller should still validate direction logic.
double AdjustSLToBrokerRules(bool isBuy,double sl)
{
   double bid=SymbolInfoDouble(_Symbol,SYMBOL_BID);
   double ask=SymbolInfoDouble(_Symbol,SYMBOL_ASK);
   double point=_Point;

   int stopsLevel=(int)SymbolInfoInteger(_Symbol,SYMBOL_TRADE_STOPS_LEVEL);
   int freezeLevel=(int)SymbolInfoInteger(_Symbol,SYMBOL_TRADE_FREEZE_LEVEL);

   double minDistPts=(double)MathMax(stopsLevel,freezeLevel);
   double minDist=minDistPts*point;

   // Some brokers return 0 for stops/freeze. Use spread as a conservative baseline.
   if(minDist <= 0)
   {
      int sp=(int)SymbolInfoInteger(_Symbol,SYMBOL_SPREAD);
      if(sp>0) minDist = (double)sp*point;
      if(minDist <= 0) minDist = 1.0*point;
   }

   if(isBuy)
   {
      double maxSL=bid - minDist;
      if(sl>maxSL) sl=maxSL;
   }
   else
   {
      double minSL=ask + minDist;
      if(sl<minSL) sl=minSL;
   }

   // normalize
   sl=NormalizeDouble(sl,_Digits);
   return sl;
}

bool SafePositionModify(ulong ticket,bool isBuy,double sl,double tp,const string tag)
{
   // v4.98-A: 预防型（Pre-adjust）— 先按经纪商 Stops/Feeze 规则把SL修正到安全范围，再只发一次Modify
   double point = P();
   double bid   = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double ask   = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   if(bid<=0 || ask<=0) return false;

   // 取 StopsLevel 与 FreezeLevel 的最大值作为最小允许距离
   double stopsLevel  = (double)SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL)  * point;
   double freezeLevel = (double)SymbolInfoInteger(_Symbol, SYMBOL_TRADE_FREEZE_LEVEL) * point;
   double limitDist   = MathMax(stopsLevel, freezeLevel);

   // 若平台返回0（动态/未知限制），用当前点差做底线缓冲，避免INVALID_STOPS
   if(limitDist <= 0.0)
   {
      double spr = (double)SymbolInfoInteger(_Symbol, SYMBOL_SPREAD) * point;
      if(spr <= 0.0) spr = 1.0 * point;
      limitDist = spr;
   }

   double safeSL = sl;
   if(isBuy)
   {
      if((bid - safeSL) < limitDist) safeSL = bid - limitDist;
   }
   else
   {
      if((safeSL - ask) < limitDist) safeSL = ask + limitDist;
   }

   safeSL = NormalizeDouble(safeSL, _Digits);
   tp     = NormalizeDouble(tp, _Digits);

   if(!trade.PositionModify(ticket, safeSL, tp))
   {
      Print("PositionModify FAILED [",tag,"] ticket=",ticket,
            " rc=",trade.ResultRetcode()," ",trade.ResultRetcodeDescription(),
            " sl_req=",DoubleToString(sl,_Digits),
            " sl_safe=",DoubleToString(safeSL,_Digits),
            " tp=",DoubleToString(tp,_Digits));
      return false;
   }
   return true;
}


bool SafePositionClose(ulong ticket,const string tag)
{
   bool ok=trade.PositionClose(ticket);
   if(ok) return true;

   uint rc=trade.ResultRetcode();
   string desc=trade.ResultRetcodeDescription();
   Print("PositionClose FAILED [",tag,"] ticket=",ticket," rc=",rc," ",desc);
   return false;
}

//======================================================================================



//=========================== UTILITY FUNCTIONS ======================
double P() { return _Point; }

double SpreadPts()
{
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   if(ask <= 0 || bid <= 0) return 999999;
   return (ask - bid) / P();
}

string GetTFFriendlyName(ENUM_TIMEFRAMES tf)
{
   switch(tf)
   {
      case PERIOD_M1:  return "1min";
      case PERIOD_M5:  return "5min";
      case PERIOD_M15: return "15min";
      case PERIOD_M30: return "30min";
      case PERIOD_H1:  return "1H";
      case PERIOD_H2:  return "2H";
      case PERIOD_H4:  return "4H";
      case PERIOD_D1:  return "1D";
      case PERIOD_W1:  return "1W";
      default:         return EnumToString(tf);
   }
}


//=========================== TREND MEMORY VISUAL (HLINE + LABEL) ===========================
string TM_SanitizeObjName(string s)
{
   StringReplace(s, " ", "_");
   StringReplace(s, ":", "-");
   StringReplace(s, ".", "-");
   StringReplace(s, "/", "-");
   return s;
}

void TM_DeleteObjectSafe(string name)
{
   if(ObjectFind(0, name) >= 0) ObjectDelete(0, name);
}

void TM_DrawHLineAndLabel(string baseName, double price, color clr, string labelText, bool keepHistory, datetime stamp)
{
   if(!InpShowTM_Lines) return;

   string lineName = baseName;
   string lblName  = baseName + "_LBL";

   if(keepHistory)
   {
      string ts = TimeToString(stamp, TIME_DATE|TIME_MINUTES);
      ts = TM_SanitizeObjName(ts);
      lineName = baseName + "_" + ts;
      lblName  = lineName + "_LBL";
   }
   else
   {
      TM_DeleteObjectSafe(lineName);
      TM_DeleteObjectSafe(lblName);
   }

   // --- line ---
   if(ObjectCreate(0, lineName, OBJ_HLINE, 0, 0, price))
   {
      ObjectSetInteger(0, lineName, OBJPROP_COLOR, clr);
      ObjectSetInteger(0, lineName, OBJPROP_WIDTH, 2);
      ObjectSetInteger(0, lineName, OBJPROP_STYLE, STYLE_SOLID);
      ObjectSetInteger(0, lineName, OBJPROP_BACK, true);
      ObjectSetInteger(0, lineName, OBJPROP_SELECTABLE, true);
      ObjectSetInteger(0, lineName, OBJPROP_HIDDEN, false);
   }
   else
   {
      ObjectSetDouble(0, lineName, OBJPROP_PRICE, price);
      ObjectSetInteger(0, lineName, OBJPROP_COLOR, clr);
   }

   // --- label (OBJ_TEXT) ---
   datetime t = TimeCurrent() + PeriodSeconds(PERIOD_CURRENT) * 5;
   if(ObjectCreate(0, lblName, OBJ_TEXT, 0, t, price))
   {
      ObjectSetString(0, lblName, OBJPROP_TEXT, labelText);
      ObjectSetInteger(0, lblName, OBJPROP_COLOR, clr);
      ObjectSetInteger(0, lblName, OBJPROP_FONTSIZE, InpShowTM_LabelFontSize);
      ObjectSetInteger(0, lblName, OBJPROP_ANCHOR, ANCHOR_LEFT);
      ObjectSetInteger(0, lblName, OBJPROP_BACK, true);
      ObjectSetInteger(0, lblName, OBJPROP_SELECTABLE, true);
      ObjectSetInteger(0, lblName, OBJPROP_HIDDEN, false);
   }
   else
   {
      ObjectSetString(0, lblName, OBJPROP_TEXT, labelText);
      ObjectMove(0, lblName, 0, t, price);
      ObjectSetInteger(0, lblName, OBJPROP_COLOR, clr);
      ObjectSetInteger(0, lblName, OBJPROP_FONTSIZE, InpShowTM_LabelFontSize);
   }
}

int TM_CollectObjectsByPrefix(string prefix, string &names[])
{
   ArrayResize(names, 0);
   int total = ObjectsTotal(0, 0, -1);
   for(int i=0;i<total;i++)
   {
      string n = ObjectName(0, i, 0, -1);
      if(StringFind(n, prefix) == 0) // starts with prefix
      {
         int k = ArraySize(names);
         ArrayResize(names, k+1);
         names[k] = n;
      }
   }
   return ArraySize(names);
}

void TM_CleanupHistory(string basePrefix, int maxCount)
{
   if(maxCount <= 0) return;

   string arr[];
   int n = TM_CollectObjectsByPrefix(basePrefix + "_", arr);
   if(n <= maxCount) return;

   ArraySort(arr);
   int toDelete = n - maxCount;
   for(int i=0;i<toDelete;i++)
   {
      string obj = arr[i];
      TM_DeleteObjectSafe(obj);
      TM_DeleteObjectSafe(obj + "_LBL");
   }
}

void TM_ClearCurrentLines()
{
   TM_DeleteObjectSafe("TM_DONCHIAN");
   TM_DeleteObjectSafe("TM_DONCHIAN_LBL");
   TM_DeleteObjectSafe("TM_XBARS");
   TM_DeleteObjectSafe("TM_XBARS_LBL");
   TM_DeleteObjectSafe("TM_MEMORY");
   TM_DeleteObjectSafe("TM_MEMORY_LBL");
}

void TM_UpdateVisual(datetime stamp)
{
   if(!InpShowTM_Lines) { TM_ClearCurrentLines(); return; }

   if(g_dir == DIR_NONE)
   {
      if(!InpShowTM_History) TM_ClearCurrentLines();
      return;
   }

   bool keepHist = InpShowTM_History;

   // 1) Donchian break line
   if(InpShowTM_DonchianLine && g_breakLevel > 0.0)
   {
      string txt = (g_dir==DIR_BUY ? "Donchian Break (BUY) " : "Donchian Break (SELL) ");
      txt += GetTFFriendlyName(InpHTF) + " @ " + DoubleToString(g_breakLevel, _Digits);
      TM_DrawHLineAndLabel("TM_DONCHIAN", g_breakLevel, clrDodgerBlue, txt, keepHist, stamp);
      if(keepHist) TM_CleanupHistory("TM_DONCHIAN", InpShowTM_MaxHistory);
   }

   // 2) XBars protect line
   if(InpShowTM_XBarsLine)
   {
      double lvl = 0.0;
      if(g_dir==DIR_BUY) lvl = g_xBarsLow;
      else if(g_dir==DIR_SELL) lvl = g_xBarsHigh;

      if(lvl > 0.0)
      {
         string txt = "XBars Protect (X=" + IntegerToString(InpMem_XBarsLookback) + ") @ " + DoubleToString(lvl, _Digits);
         TM_DrawHLineAndLabel("TM_XBARS", lvl, clrLimeGreen, txt, keepHist, stamp);
         if(keepHist) TM_CleanupHistory("TM_XBARS", InpShowTM_MaxHistory);
      }
   }

   // 3) Effective Trend Memory line (active protect)
   if(InpShowTM_MemoryLine)
   {
      double mem = 0.0;
      if(g_dir==DIR_BUY)  mem = GetProtectLevelBuy();
      if(g_dir==DIR_SELL) mem = GetProtectLevelSell();

      if(mem > 0.0)
      {
         string txt = "Trend Memory Active @ " + DoubleToString(mem, _Digits);
         TM_DrawHLineAndLabel("TM_MEMORY", mem, clrOrange, txt, keepHist, stamp);
         if(keepHist) TM_CleanupHistory("TM_MEMORY", InpShowTM_MaxHistory);
      }
   }
}

void TM_DeleteAllObjects()
{
   int total = ObjectsTotal(0,0,-1);
   for(int i=total-1;i>=0;i--)
   {
      string n = ObjectName(0,i,0,-1);
      if(StringFind(n, "TM_") == 0) ObjectDelete(0,n);
   }
}

//==========================================================================================
string TFButtonName(ENUM_TIMEFRAMES tf)
{
   return "EA_TF_BTN_" + EnumToString(tf);
}

bool TFEnabled(ENUM_TIMEFRAMES tf)
{
   if(tf==PERIOD_H4)  return g_useH4;
   if(tf==PERIOD_H1)  return g_useH1;
   if(tf==PERIOD_M30) return g_useM30;
   if(tf==PERIOD_M15) return g_useM15;
   if(tf==PERIOD_M5)  return g_useM5;
   return false;
}

void SetTFEnabled(ENUM_TIMEFRAMES tf, bool enabled)
{
   if(tf==PERIOD_H4)  g_useH4=enabled;
   if(tf==PERIOD_H1)  g_useH1=enabled;
   if(tf==PERIOD_M30) g_useM30=enabled;
   if(tf==PERIOD_M15) g_useM15=enabled;
   if(tf==PERIOD_M5)  g_useM5=enabled;
}

void TFButtonUpdate(ENUM_TIMEFRAMES tf)
{
   string name = TFButtonName(tf);
   bool on = TFEnabled(tf);
   string txt = GetTFFriendlyName(tf) + (on ? " ON" : " OFF");
   ObjectSetString(0, name, OBJPROP_TEXT, txt);
   ObjectSetInteger(0, name, OBJPROP_BGCOLOR, on ? clrLimeGreen : clrTomato);
   ObjectSetInteger(0, name, OBJPROP_COLOR, clrBlack);
}

void TFButtonsCreate()
{
   if(!InpShowTFButtons) return;

   ENUM_TIMEFRAMES arr[5] = {PERIOD_H4, PERIOD_H1, PERIOD_M30, PERIOD_M15, PERIOD_M5};
   int x=10, y=20, w=80, h=20, gap=4;

   for(int i=0;i<5;i++)
   {
      string name = TFButtonName(arr[i]);
      if(ObjectFind(0, name) < 0)
      {
         ObjectCreate(0, name, OBJ_BUTTON, 0, 0, 0);
         ObjectSetInteger(0, name, OBJPROP_CORNER, CORNER_LEFT_UPPER);
         ObjectSetInteger(0, name, OBJPROP_XDISTANCE, x);
         ObjectSetInteger(0, name, OBJPROP_YDISTANCE, y + i*(h+gap));
         ObjectSetInteger(0, name, OBJPROP_XSIZE, w);
         ObjectSetInteger(0, name, OBJPROP_YSIZE, h);
         ObjectSetInteger(0, name, OBJPROP_BORDER_TYPE, BORDER_FLAT);
         ObjectSetInteger(0, name, OBJPROP_FONTSIZE, 9);
         ObjectSetInteger(0, name, OBJPROP_HIDDEN, false);
         ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
      }
      TFButtonUpdate(arr[i]);
   }
}

void TFButtonsDelete()
{
   ENUM_TIMEFRAMES arr[5] = {PERIOD_H4, PERIOD_H1, PERIOD_M30, PERIOD_M15, PERIOD_M5};
   for(int i=0;i<5;i++)
   {
      string name = TFButtonName(arr[i]);
      if(ObjectFind(0, name) >= 0) ObjectDelete(0, name);
   }
}

bool TFButtonTryToggle(const string obj)
{
   ENUM_TIMEFRAMES arr[5] = {PERIOD_H4, PERIOD_H1, PERIOD_M30, PERIOD_M15, PERIOD_M5};
   for(int i=0;i<5;i++)
   {
      if(obj == TFButtonName(arr[i]))
      {
         SetTFEnabled(arr[i], !TFEnabled(arr[i]));
         TFButtonUpdate(arr[i]);
         if(InpPrintSignals)
            Print("TF Toggle: ", EnumToString(arr[i]), " -> ", (TFEnabled(arr[i])?"ON":"OFF"));
         return true;
      }
   }
   return false;
}

bool IsInTradingTime()
{
   if(!InpUseTimeFilter) return true;

   MqlDateTime dt;
   TimeToStruct(TimeCurrent(), dt);

   int currentTime = dt.hour * 60 + dt.min;
   int startTime = InpStartHour * 60 + InpStartMin;
   int endTime = InpEndHour * 60 + InpEndMin;
   if(startTime < endTime)
      return (currentTime >= startTime && currentTime < endTime);
   else if(startTime > endTime)
      return (currentTime >= startTime || currentTime < endTime);
   return true;
}

// Parse entry TF from comment
ENUM_TIMEFRAMES ParseEntryTF(const string comment, ENUM_TIMEFRAMES defTF)
{
   if(StringFind(comment, "TF_PERIOD_H4") >= 0) return PERIOD_H4;
   if(StringFind(comment, "TF_PERIOD_H1") >= 0) return PERIOD_H1;
   if(StringFind(comment, "TF_PERIOD_M30") >= 0) return PERIOD_M30;
   if(StringFind(comment, "TF_PERIOD_M15") >= 0) return PERIOD_M15;
   if(StringFind(comment, "TF_PERIOD_M5") >= 0) return PERIOD_M5;
   return defTF;
}

bool ParseEntryTFStrict(const string comment, ENUM_TIMEFRAMES &tf)
{
   if(StringFind(comment, "TF_PERIOD_H4") >= 0)  { tf = PERIOD_H4;  return true; }
   if(StringFind(comment, "TF_PERIOD_H1") >= 0)  { tf = PERIOD_H1;  return true; }
   if(StringFind(comment, "TF_PERIOD_M30") >= 0) { tf = PERIOD_M30; return true; }
   if(StringFind(comment, "TF_PERIOD_M15") >= 0) { tf = PERIOD_M15; return true; }
   if(StringFind(comment, "TF_PERIOD_M5") >= 0)  { tf = PERIOD_M5;  return true; }
   return false;
}

//=========================== PER-TF BB EXIT GETTERS ==================
bool TF_UseBBExit(ENUM_TIMEFRAMES tf)
{
   if(tf==PERIOD_H4)  return InpH4_UseBBExit;
   if(tf==PERIOD_H1)  return InpH1_UseBBExit;
   if(tf==PERIOD_M30) return InpM30_UseBBExit;
   if(tf==PERIOD_M15) return InpM15_UseBBExit;
   if(tf==PERIOD_M5)  return InpM5_UseBBExit;
   return false;
}

ENUM_TIMEFRAMES TF_BB_TF(ENUM_TIMEFRAMES tf)
{
   if(tf==PERIOD_H4)  return InpH4_BB_TF;
   if(tf==PERIOD_H1)  return InpH1_BB_TF;
   if(tf==PERIOD_M30) return InpM30_BB_TF;
   if(tf==PERIOD_M15) return InpM15_BB_TF;
   if(tf==PERIOD_M5)  return InpM5_BB_TF;
   return PERIOD_M15;
}

int TF_BB_Period(ENUM_TIMEFRAMES tf)
{
   if(tf==PERIOD_H4)  return InpH4_BB_Period;
   if(tf==PERIOD_H1)  return InpH1_BB_Period;
   if(tf==PERIOD_M30) return InpM30_BB_Period;
   if(tf==PERIOD_M15) return InpM15_BB_Period;
   if(tf==PERIOD_M5)  return InpM5_BB_Period;
   return 20;
}

double TF_BB_Deviation(ENUM_TIMEFRAMES tf)
{
   if(tf==PERIOD_H4)  return InpH4_BB_Deviation;
   if(tf==PERIOD_H1)  return InpH1_BB_Deviation;
   if(tf==PERIOD_M30) return InpM30_BB_Deviation;
   if(tf==PERIOD_M15) return InpM15_BB_Deviation;
   if(tf==PERIOD_M5)  return InpM5_BB_Deviation;
   return 2.0;
}

//=========================== PER-TF TRAILING GETTERS =================
int TF_TrailStart(ENUM_TIMEFRAMES tf)
{
   if(tf==PERIOD_H4)  return InpH4_TrailStartPts;
   if(tf==PERIOD_H1)  return InpH1_TrailStartPts;
   if(tf==PERIOD_M30) return InpM30_TrailStartPts;
   if(tf==PERIOD_M15) return InpM15_TrailStartPts;
   if(tf==PERIOD_M5)  return InpM5_TrailStartPts;
   return 1500;
}

int TF_TrailDist(ENUM_TIMEFRAMES tf)
{
   if(tf==PERIOD_H4)  return InpH4_TrailDistPts;
   if(tf==PERIOD_H1)  return InpH1_TrailDistPts;
   if(tf==PERIOD_M30) return InpM30_TrailDistPts;
   if(tf==PERIOD_M15) return InpM15_TrailDistPts;
   if(tf==PERIOD_M5)  return InpM5_TrailDistPts;
   return 500;
}

int TF_TrailStep(ENUM_TIMEFRAMES tf)
{
   if(tf==PERIOD_H4)  return InpH4_TrailStepPts;
   if(tf==PERIOD_H1)  return InpH1_TrailStepPts;
   if(tf==PERIOD_M30) return InpM30_TrailStepPts;
   if(tf==PERIOD_M15) return InpM15_TrailStepPts;
   if(tf==PERIOD_M5)  return InpM5_TrailStepPts;
   return 50;
}

bool TF_UseManualLot(ENUM_TIMEFRAMES tf)
{
   if(tf==PERIOD_H4)  return InpH4_UseManualLot;
   if(tf==PERIOD_H1)  return InpH1_UseManualLot;
   if(tf==PERIOD_M30) return InpM30_UseManualLot;
   if(tf==PERIOD_M15) return InpM15_UseManualLot;
   if(tf==PERIOD_M5)  return InpM5_UseManualLot;
   return false;
}

double TF_ManualLot(ENUM_TIMEFRAMES tf)
{
   if(tf==PERIOD_H4)  return InpH4_ManualLot;
   if(tf==PERIOD_H1)  return InpH1_ManualLot;
   if(tf==PERIOD_M30) return InpM30_ManualLot;
   if(tf==PERIOD_M15) return InpM15_ManualLot;
   if(tf==PERIOD_M5)  return InpM5_ManualLot;
   return InpFixedLot;
}

bool TF_IgnoreDonchian(ENUM_TIMEFRAMES tf)
{
   if(tf==PERIOD_H4)  return InpH4_IgnoreDonchian;
   if(tf==PERIOD_H1)  return InpH1_IgnoreDonchian;
   if(tf==PERIOD_M30) return InpM30_IgnoreDonchian;
   if(tf==PERIOD_M15) return InpM15_IgnoreDonchian;
   if(tf==PERIOD_M5)  return InpM5_IgnoreDonchian;
   return false;
}

bool TF_UseBreakScan(ENUM_TIMEFRAMES tf)
{
   if(tf==PERIOD_H4)  return InpH4_UseBreakScan;
   if(tf==PERIOD_H1)  return InpH1_UseBreakScan;
   if(tf==PERIOD_M30) return InpM30_UseBreakScan;
   if(tf==PERIOD_M15) return InpM15_UseBreakScan;
   if(tf==PERIOD_M5)  return InpM5_UseBreakScan;
   return false;
}

int TF_BreakScanBars(ENUM_TIMEFRAMES tf)
{
   if(tf==PERIOD_H4)  return InpH4_BreakScanBars;
   if(tf==PERIOD_H1)  return InpH1_BreakScanBars;
   if(tf==PERIOD_M30) return InpM30_BreakScanBars;
   if(tf==PERIOD_M15) return InpM15_BreakScanBars;
   if(tf==PERIOD_M5)  return InpM5_BreakScanBars;
   return 5;
}

EMacdScanMode TF_BreakScanMode(ENUM_TIMEFRAMES tf)
{
   if(tf==PERIOD_H4)  return InpH4_BreakScanMode;
   if(tf==PERIOD_H1)  return InpH1_BreakScanMode;
   if(tf==PERIOD_M30) return InpM30_BreakScanMode;
   if(tf==PERIOD_M15) return InpM15_BreakScanMode;
   if(tf==PERIOD_M5)  return InpM5_BreakScanMode;
   return MACD_SCAN_CROSS;
}

int TF_SLLookbackBars(ENUM_TIMEFRAMES tf)
{
   if(tf==PERIOD_H4)  return InpH4_SLLookbackBars;
   if(tf==PERIOD_H1)  return InpH1_SLLookbackBars;
   if(tf==PERIOD_M30) return InpM30_SLLookbackBars;
   if(tf==PERIOD_M15) return InpM15_SLLookbackBars;
   if(tf==PERIOD_M5)  return InpM5_SLLookbackBars;
   return 5;
}

int TF_Mode2TPValue(ENUM_TIMEFRAMES tf)
{
   if(tf==PERIOD_H4)  return InpH4_Mode2TPValue;
   if(tf==PERIOD_H1)  return InpH1_Mode2TPValue;
   if(tf==PERIOD_M30) return InpM30_Mode2TPValue;
   if(tf==PERIOD_M15) return InpM15_Mode2TPValue;
   if(tf==PERIOD_M5)  return InpM5_Mode2TPValue;
   return InpHardTP;
}

int TF_TPCoolBars(ENUM_TIMEFRAMES tf)
{
   if(tf==PERIOD_H4)  return InpH4_TPCoolBars;
   if(tf==PERIOD_H1)  return InpH1_TPCoolBars;
   if(tf==PERIOD_M30) return InpM30_TPCoolBars;
   if(tf==PERIOD_M15) return InpM15_TPCoolBars;
   if(tf==PERIOD_M5)  return InpM5_TPCoolBars;
   return 0;
}

datetime TF_LastTPCloseTime(ENUM_TIMEFRAMES tf)
{
   if(tf==PERIOD_H4)  return g_lastTPCloseH4;
   if(tf==PERIOD_H1)  return g_lastTPCloseH1;
   if(tf==PERIOD_M30) return g_lastTPCloseM30;
   if(tf==PERIOD_M15) return g_lastTPCloseM15;
   if(tf==PERIOD_M5)  return g_lastTPCloseM5;
   return 0;
}

void TF_SetLastTPCloseTime(ENUM_TIMEFRAMES tf, datetime t)
{
   if(tf==PERIOD_H4)  g_lastTPCloseH4=t;
   if(tf==PERIOD_H1)  g_lastTPCloseH1=t;
   if(tf==PERIOD_M30) g_lastTPCloseM30=t;
   if(tf==PERIOD_M15) g_lastTPCloseM15=t;
   if(tf==PERIOD_M5)  g_lastTPCloseM5=t;
}

bool TF_PassTPCooldown(ENUM_TIMEFRAMES tf)
{
   int cool=TF_TPCoolBars(tf);
   if(cool<=0) return true;

   datetime tpT=TF_LastTPCloseTime(tf);
   if(tpT<=0) return true;

   int sh=iBarShift(_Symbol, tf, tpT, false);
   if(sh<0) return true;

   return (sh >= cool);
}


// Support old & friendly
bool IsMode2Comment(const string comment)
{
   return (StringFind(comment, "MODE 2 ") == 0);
}

int MaxOrdersPerTFByMode(const int mode)
{
   // mode: 1=MODE1, 2=MODE2, else fallback to legacy limit
   if(mode == 1) return MathMax(0, InpMaxOrdersPerTF_Mode1);
   if(mode == 2) return MathMax(0, InpMaxOrdersPerTF_Mode2);
   return MathMax(0, InpMaxOrdersPerTF);
}

int CountOrdersPerTF(ENUM_TIMEFRAMES tf, int mode=0)
{
   int count = 0;
   string tfStr = EnumToString(tf);
   string tfToken = "_TF_" + tfStr;
   string friendlyName = GetTFFriendlyName(tf);

   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      if(PositionGetSymbol(i) != _Symbol) continue;
      if((ulong)PositionGetInteger(POSITION_MAGIC) != InpMagic) continue;

      string comment = PositionGetString(POSITION_COMMENT);
      bool isMode2 = IsMode2Comment(comment);

      if(mode == 1 && isMode2)  continue;
      if(mode == 2 && !isMode2) continue;

      // Primary (strict) path: EA standard comment token
      if(StringFind(comment, tfToken) >= 0)
      {
         count++;
         continue;
      }

      // Legacy fallback: only accept comments shaped like EA orders
      bool legacyShape = (StringFind(comment, "Buy_") == 0 || StringFind(comment, "Sell_") == 0);
      if(!legacyShape) continue;
      if(mode == 2) continue; // legacy comments are MODE1 only
      if(StringFind(comment, friendlyName) < 0) continue;

      // Ambiguity guard for old 1H/15min style comments
      if(tf == PERIOD_H1 && StringFind(comment, "15min") >= 0) continue;

      count++;
   }
   return count;
}

bool HasMaxOrdersForTF(ENUM_TIMEFRAMES tf, int mode=0)
{
   return CountOrdersPerTF(tf, mode) >= MaxOrdersPerTFByMode(mode);
}

bool HasAnyPosition()
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
      if(PositionGetSymbol(i) == _Symbol && (ulong)PositionGetInteger(POSITION_MAGIC) == InpMagic)
         return true;
   return false;
}

double NormalizeLot(double lot)
{
   double minLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double maxLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   double step   = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   if(lot < minLot) lot = minLot;
   if(lot > maxLot) lot = maxLot;
   lot = MathFloor(lot / step) * step;
   return MathMax(lot, minLot);
}

double CalcAutoLotByRisk(double entryPrice, double slPrice)
{
   if(!InpUseAutoLot) return NormalizeLot(InpFixedLot);
   double equity = AccountInfoDouble(ACCOUNT_EQUITY);
   double riskMoney = equity * (InpRiskPercent / 100.0);
   double dist = MathAbs(entryPrice - slPrice);
   if(dist <= 0) dist = 10 * P();
   double tickValue = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   double tickSize  = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   if(tickValue <= 0 || tickSize <= 0) return NormalizeLot(InpFixedLot);
   double riskPerLot = dist * (tickValue / tickSize);
   if(riskPerLot <= 0) return NormalizeLot(InpFixedLot);
   return NormalizeLot(riskMoney / riskPerLot);
}

string ToUpperStr(string s) { StringToUpper(s); return s; }

bool IsInNewsWindow()
{
   if(!InpUseNewsFilter) return false;
   if(InpNewsNoPosOnly && HasAnyPosition()) return false;

   datetime now = TimeCurrent();
   datetime fromTime = now - (InpNewsAfterMin * 60);
   datetime toTime   = now + (InpNewsBeforeMin * 60);

   MqlCalendarValue values[];
   if(!CalendarValueHistory(values, fromTime, toTime)) return false;

   for(int i = 0; i < ArraySize(values); i++)
   {
      MqlCalendarEvent event;
      if(!CalendarEventById(values[i].event_id, event)) continue;
      if(event.importance != CALENDAR_IMPORTANCE_HIGH) continue;
      if(InpFOMCOnly && StringFind(ToUpperStr(event.name), "FOMC") < 0) continue;

      MqlCalendarCountry country;
      if(!CalendarCountryById(event.country_id, country)) continue;
      string currency = country.currency;
      string baseCurr = SymbolInfoString(_Symbol, SYMBOL_CURRENCY_BASE);
      string profCurr = SymbolInfoString(_Symbol, SYMBOL_CURRENCY_PROFIT);
      if(currency == baseCurr || currency == profCurr || currency == "USD")
      {
         if(InpPrintBlocks) Print("Blocked by News: ", event.name);
         return true;
      }
   }
   return false;
}

//=========================== DONCHIAN & EMA HELPERS =================

double ClampPercent(double p)
{
   if(p < 0.0) return 0.0;
   if(p > 100.0) return 100.0;
   return p;
}

double GetProtectLevelBuy()
{
   if(!InpUseTrendMemory) return g_breakLevel;

   double levels[];
   ArrayResize(levels, 0);
   if(InpMem_BreakCandleLevel && g_breakCandleLow > 0.0)
   {
      int n = ArraySize(levels);
      ArrayResize(levels, n+1);
      levels[n] = g_breakCandleLow;
   }
   if(InpMem_XBarsLevel && g_xBarsLow > 0.0)
   {
      int n = ArraySize(levels);
      ArrayResize(levels, n+1);
      levels[n] = g_xBarsLow;
   }
   if(InpMem_PctRetraceLevel && g_peakHigh > 0.0 && g_breakLevel > 0.0)
   {
      double pct = ClampPercent(InpMem_RetracePercent) / 100.0;
      double lvl = g_breakLevel + (1.0 - pct) * (g_peakHigh - g_breakLevel);
      int n = ArraySize(levels);
      ArrayResize(levels, n+1);
      levels[n] = lvl;
   }

   if(ArraySize(levels) == 0) return g_breakLevel;

   double minv = levels[0];
   for(int i=1;i<ArraySize(levels);i++) if(levels[i] < minv) minv = levels[i];
   return minv;
}

double GetProtectLevelSell()
{
   if(!InpUseTrendMemory) return g_breakLevel;

   double levels[];
   ArrayResize(levels, 0);
   if(InpMem_BreakCandleLevel && g_breakCandleHigh > 0.0)
   {
      int n = ArraySize(levels);
      ArrayResize(levels, n+1);
      levels[n] = g_breakCandleHigh;
   }
   if(InpMem_XBarsLevel && g_xBarsHigh > 0.0)
   {
      int n = ArraySize(levels);
      ArrayResize(levels, n+1);
      levels[n] = g_xBarsHigh;
   }
   if(InpMem_PctRetraceLevel && g_troughLow > 0.0 && g_breakLevel > 0.0)
   {
      double pct = ClampPercent(InpMem_RetracePercent) / 100.0;
      double lvl = g_breakLevel - (1.0 - pct) * (g_breakLevel - g_troughLow);
      int n = ArraySize(levels);
      ArrayResize(levels, n+1);
      levels[n] = lvl;
   }

   if(ArraySize(levels) == 0) return g_breakLevel;

   double maxv = levels[0];
   for(int i=1;i<ArraySize(levels);i++) if(levels[i] > maxv) maxv = levels[i];
   return maxv;
}

bool ComputeDonchianHTF(double &upper, double &lower, double &close1)
{
   upper = -DBL_MAX; lower = DBL_MAX; close1 = 0.0;
   int need = InpDonchianPer + 2;
   MqlRates rates[];
   int copied = CopyRates(_Symbol, InpHTF, 0, need, rates);
   if(copied < need) return false;

   ArraySetAsSeries(rates, true);
   close1 = rates[1].close;
   for(int i = 2; i <= InpDonchianPer + 1; i++)
   {
      if(rates[i].high > upper) upper = rates[i].high;
      if(rates[i].low  < lower) lower = rates[i].low;
   }
   return (upper > lower);
}


bool ComputeDonchianHTFEx(double &upper, double &lower, double &close1, double &high1, double &low1, double &xLow, double &xHigh)
{
   upper = -DBL_MAX;
   lower = DBL_MAX; close1 = 0.0; high1 = 0.0; low1 = 0.0;
   xLow = 0.0; xHigh = 0.0;
   int x = InpMem_XBarsLookback;
   if(x < 1) x = 1;

   int need = MathMax(InpDonchianPer + 2, x + 2);
   MqlRates rates[];
   int copied = CopyRates(_Symbol, InpHTF, 0, need, rates);
   if(copied < need) return false;

   ArraySetAsSeries(rates, true);

   close1 = rates[1].close;
   high1  = rates[1].high;
   low1   = rates[1].low;

   for(int i = 2; i <= InpDonchianPer + 1; i++)
   {
      if(rates[i].high > upper) upper = rates[i].high;
      if(rates[i].low  < lower) lower = rates[i].low;
   }

   double xl = rates[1].low;
   double xh = rates[1].high;
   for(int i=2; i<=x && i < need; i++)
   {
      if(rates[i].low  < xl) xl = rates[i].low;
      if(rates[i].high > xh) xh = rates[i].high;
   }
   xLow = xl;
   xHigh = xh;

   return (upper > lower);
}



int UpdateHTFState()
{
   g_newBreakoutSignal = false;

   datetime t1 = iTime(_Symbol, InpHTF, 1);
   if(t1 <= 0) return (int)g_dir;
   if(t1 == g_lastHTFClosedT1) return (int)g_dir;
   g_lastHTFClosedT1 = t1;

   double up, lo, close1, high1, low1, xLow, xHigh;
   if(!ComputeDonchianHTFEx(up, lo, close1, high1, low1, xLow, xHigh))
   {
      g_dir = DIR_NONE;
      g_breakLevel = 0.0;
      g_breakCandleLow = 0.0; g_breakCandleHigh = 0.0;
      g_xBarsLow = 0.0; g_xBarsHigh = 0.0;
      g_peakHigh = 0.0;
      g_troughLow = 0.0;
      return 0;
   }

   double width = up - lo;
   double minW  = InpMinChRangePts * P();
   if(width < minW)
   {
      g_dir = DIR_NONE;
      g_breakLevel = 0.0;
      g_breakCandleLow = 0.0; g_breakCandleHigh = 0.0;
      g_xBarsLow = 0.0; g_xBarsHigh = 0.0;
      g_peakHigh = 0.0;
      g_troughLow = 0.0;
      return 0;
   }

   if(InpUseATRFilter)
   {
      double atr[];
      ArraySetAsSeries(atr, true);
      if(CopyBuffer(g_atrHTF, 0, 1, 1, atr) < 1 || width < atr[0] * InpATRMult)
      {
         g_dir = DIR_NONE;
         g_breakLevel = 0.0;
         g_breakCandleLow = 0.0; g_breakCandleHigh = 0.0;
         g_xBarsLow = 0.0; g_xBarsHigh = 0.0;
         g_peakHigh = 0.0;
         g_troughLow = 0.0;
         return 0;
      }
   }

   if(g_dir == DIR_NONE)
   {
      if(close1 > up)
      {
         g_dir        = DIR_BUY;
         g_breakLevel = up;
         g_newBreakoutSignal = true;

         g_breakCandleLow  = low1;
         g_breakCandleHigh = high1;

         g_xBarsLow  = xLow;
         g_xBarsHigh = xHigh;

         g_peakHigh  = high1;
         g_troughLow = low1;
      }
      else if(close1 < lo)
      {
         g_dir        = DIR_SELL;
         g_breakLevel = lo;
         g_newBreakoutSignal = true;

         g_breakCandleLow  = low1;
         g_breakCandleHigh = high1;

         g_xBarsLow  = xLow;
         g_xBarsHigh = xHigh;
         g_peakHigh  = high1;
         g_troughLow = low1;
      }
   }
   else
   {
      if(g_dir == DIR_BUY)
      {
         if(high1 > g_peakHigh) g_peakHigh = high1;
      }
      else if(g_dir == DIR_SELL)
      {
         if(g_troughLow == 0.0 || low1 < g_troughLow) g_troughLow = low1;
      }

      if(g_dir == DIR_BUY)
      {
         double protect = GetProtectLevelBuy();
         if(close1 <= protect)
         {
            g_dir = DIR_NONE;
            g_breakLevel = 0.0;
            g_breakCandleLow = 0.0; g_breakCandleHigh = 0.0;
            g_xBarsLow = 0.0; g_xBarsHigh = 0.0;
            g_peakHigh = 0.0;
            g_troughLow = 0.0;
         }
      }
      else if(g_dir == DIR_SELL)
      {
         double protect = GetProtectLevelSell();
         if(close1 >= protect)
         {
            g_dir = DIR_NONE;
            g_breakLevel = 0.0;
            g_breakCandleLow = 0.0; g_breakCandleHigh = 0.0;
            g_xBarsLow = 0.0; g_xBarsHigh = 0.0;
            g_peakHigh = 0.0;
            g_troughLow = 0.0;
         }
      }
   }

   if(InpPrintHTF)
   {
      if(g_dir == DIR_BUY)
      {
         double pb = GetProtectLevelBuy();
         Print(TimeToString(t1),
               " HTF BUY",
               " breakLevel=", DoubleToString(g_breakLevel,_Digits),
               " protect=", DoubleToString(pb,_Digits),
               " peak=", DoubleToString(g_peakHigh,_Digits));
      }
      else if(g_dir == DIR_SELL)
      {
         double ps = GetProtectLevelSell();
         Print(TimeToString(t1),
               " HTF SELL",
               " breakLevel=", DoubleToString(g_breakLevel,_Digits),
               " protect=", DoubleToString(ps,_Digits),
               " trough=", DoubleToString(g_troughLow,_Digits));
      }
      else
      {
         Print(TimeToString(t1), " HTF dir=0");
      }
   }

   TM_UpdateVisual(t1);
   return (int)g_dir;
}


int FastH(ENUM_TIMEFRAMES tf)
{
   switch(tf)
   {
      case PERIOD_H4:  return g_fastH4;
      case PERIOD_H1:  return g_fastH1;
      case PERIOD_M30: return g_fastM30;
      case PERIOD_M15: return g_fastM15;
      case PERIOD_M5:  return g_fastM5;
      default: return INVALID_HANDLE;
   }
}

int SlowH(ENUM_TIMEFRAMES tf)
{
   switch(tf)
   {
      case PERIOD_H4:  return g_slowH4;
      case PERIOD_H1:  return g_slowH1;
      case PERIOD_M30: return g_slowM30;
      case PERIOD_M15: return g_slowM15;
      case PERIOD_M5:  return g_slowM5;
      default: return INVALID_HANDLE;
   }
}

int EmaH(ENUM_TIMEFRAMES tf)
{
   switch(tf)
   {
      case PERIOD_H4:  return g_emaH4;
      case PERIOD_H1:  return g_emaH1;
      case PERIOD_M30: return g_emaM30;
      case PERIOD_M15: return g_emaM15;
      case PERIOD_M5:  return g_emaM5;
      default: return INVALID_HANDLE;
   }
}

int ExitEmaH(ENUM_TIMEFRAMES tf)
{
   switch(tf)
   {
      case PERIOD_H4:  return g_exitEmaH4;
      case PERIOD_H1:  return g_exitEmaH1;
      case PERIOD_M30: return g_exitEmaM30;
      case PERIOD_M15: return g_exitEmaM15;
      case PERIOD_M5:  return g_exitEmaM5;
      default: return INVALID_HANDLE;
   }
}

int TrailEmaH(ENUM_TIMEFRAMES tf)
{
   switch(tf)
   {
      case PERIOD_H4:  return g_trailEmaH4;
      case PERIOD_H1:  return g_trailEmaH1;
      case PERIOD_M30: return g_trailEmaM30;
      case PERIOD_M15: return g_trailEmaM15;
      case PERIOD_M5:  return g_trailEmaM5;
      default: return g_trailEmaChart;
   }
}

//=========================== MACD SIGNAL ============================
bool CheckMACDSignal(ENUM_TIMEFRAMES tf, int dir)
{
   int fastH = FastH(tf), slowH = SlowH(tf), emaH = EmaH(tf);
   if(fastH == INVALID_HANDLE || slowH == INVALID_HANDLE || emaH == INVALID_HANDLE) return false;

   const int BARS = 30;
   double fast[], slow[], ema[];
   ArraySetAsSeries(fast, true); ArraySetAsSeries(slow, true); ArraySetAsSeries(ema, true);
   if(CopyBuffer(fastH, 0, 0, BARS, fast) < BARS ||
      CopyBuffer(slowH, 0, 0, BARS, slow) < BARS ||
      CopyBuffer(emaH, 0, 0, 2, ema) < 2) return false;
   double mainLine[];
   ArrayResize(mainLine, BARS);
   for(int i = 0; i < BARS; i++) mainLine[i] = fast[i] - slow[i];
   double signal1 = 0.0, signal2 = 0.0;
   int cnt1 = 0, cnt2 = 0;
   for(int i = 1; i < 1 + InpSignalSMA && i < BARS; i++) { signal1 += mainLine[i]; cnt1++; }
   for(int i = 2; i < 2 + InpSignalSMA && i < BARS; i++) { signal2 += mainLine[i]; cnt2++; }
   if(cnt1 <= 0 || cnt2 <= 0) return false;
   signal1 /= (double)cnt1;
   signal2 /= (double)cnt2;

   double main1 = mainLine[1];
   double hist1 = main1 - signal1;
   double hist2 = (mainLine[2]) - signal2;
   double close1 = iClose(_Symbol, tf, 1);
   double ema1   = ema[1];
   if(close1 == 0) return false;
   bool isLightPink  = (hist1 < 0) && (hist1 >= hist2);
   bool isLightGreen = (hist1 >= 0) && (hist1 <= hist2);
   if(dir == 1) return (main1 > 0 && signal1 > 0 && close1 > ema1 && isLightPink);
   else         return (main1 < 0 && signal1 < 0 && close1 < ema1 && isLightGreen);
}

//=========================== ORDER FUNCTIONS ========================

bool CheckMACDSignalAtShift(ENUM_TIMEFRAMES tf, int dir, int shift, EMacdScanMode mode)
{
   if(shift < 1) return false;

   int fastH = FastH(tf), slowH = SlowH(tf), emaH = EmaH(tf);
   if(fastH == INVALID_HANDLE || slowH == INVALID_HANDLE || emaH == INVALID_HANDLE) return false;

   int barsNeed = MathMax(shift + InpSignalSMA + 5, shift + 3);

   double fast[], slow[], ema[];
   ArraySetAsSeries(fast, true);
   ArraySetAsSeries(slow, true);
   ArraySetAsSeries(ema, true);
   if(CopyBuffer(fastH, 0, 0, barsNeed, fast) < barsNeed ||
      CopyBuffer(slowH, 0, 0, barsNeed, slow) < barsNeed ||
      CopyBuffer(emaH, 0, 0, shift + 2, ema) < shift + 2)
      return false;

   double mainLine[];
   ArrayResize(mainLine, barsNeed);
   for(int i=0;i<barsNeed;i++) mainLine[i]=fast[i]-slow[i];

   double sigNow=0.0, sigPrev=0.0;
   int cntNow=0, cntPrev=0;
   for(int i=shift; i<shift+InpSignalSMA && i<barsNeed; i++) { sigNow += mainLine[i]; cntNow++; }
   for(int i=shift+1; i<shift+1+InpSignalSMA && i<barsNeed; i++) { sigPrev += mainLine[i]; cntPrev++; }
   if(cntNow <= 0 || cntPrev <= 0) return false;
   sigNow  /= (double)cntNow;
   sigPrev /= (double)cntPrev;

   double mainNow  = mainLine[shift];
   double mainPrev = mainLine[shift+1];

   double closeNow = iClose(_Symbol, tf, shift);
   double emaNow   = ema[shift];
   if(closeNow==0.0) return false;

   if(mode == MACD_SCAN_CROSS)
   {
      if(dir==1)
         return (mainPrev <= sigPrev && mainNow > sigNow && closeNow > emaNow);
      return (mainPrev >= sigPrev && mainNow < sigNow && closeNow < emaNow);
   }

   double histNow  = mainNow - sigNow;
   double histPrev = mainPrev - sigPrev;
   bool isLightPink  = (histNow < 0 && histNow >= histPrev);
   bool isLightGreen = (histNow >= 0 && histNow <= histPrev);
   if(dir==1)
      return (mainNow > 0 && sigNow > 0 && closeNow > emaNow && isLightPink);
   return (mainNow < 0 && sigNow < 0 && closeNow < emaNow && isLightGreen);
}

bool HasMACDSignalInLookback(ENUM_TIMEFRAMES tf, int dir, int lookback, EMacdScanMode mode)
{
   if(lookback < 1) lookback = 1;
   for(int sh=1; sh<=lookback; sh++)
      if(CheckMACDSignalAtShift(tf, dir, sh, mode)) return true;
   return false;
}

double CalculateInitialSL(ENUM_TIMEFRAMES tf, int dir, int lookbackBars)
{
   if(lookbackBars < 1) lookbackBars = 1;

   MqlRates rates[]; ArraySetAsSeries(rates, true);
   if(CopyRates(_Symbol, tf, 1, lookbackBars, rates) < lookbackBars) return 0.0;

   if(dir == 1) {
      double lowest = rates[0].low;
      for(int i = 1; i < lookbackBars; i++) if(rates[i].low < lowest) lowest = rates[i].low;
      return lowest - InpSLBufferPts * P();
   } else {
      double highest = rates[0].high;
      for(int i = 1; i < lookbackBars; i++) if(rates[i].high > highest) highest = rates[i].high;
      return highest + InpSLBufferPts * P();
   }
}

bool IsNewBar(ENUM_TIMEFRAMES tf)
{
   datetime t0 = iTime(_Symbol, tf, 0);
   if(t0 <= 0) return false;
   switch(tf)
   {
      case PERIOD_H4:  if(t0 == g_lastBarH4) return false; g_lastBarH4 = t0; return true;
      case PERIOD_H1:  if(t0 == g_lastBarH1) return false; g_lastBarH1 = t0; return true;
      case PERIOD_M30: if(t0 == g_lastBarM30)return false; g_lastBarM30= t0; return true;
      case PERIOD_M15: if(t0 == g_lastBarM15)return false; g_lastBarM15= t0; return true;
      case PERIOD_M5:  if(t0 == g_lastBarM5) return false; g_lastBarM5 = t0; return true;
      default: return false;
   }
}

datetime GetLastSig(ENUM_TIMEFRAMES tf)
{
   switch(tf)
   {
      case PERIOD_H4:  return g_lastSigH4;
      case PERIOD_H1:  return g_lastSigH1;
      case PERIOD_M30: return g_lastSigM30;
      case PERIOD_M15: return g_lastSigM15;
      case PERIOD_M5:  return g_lastSigM5;
      default: return 0;
   }
}

void SetLastSig(ENUM_TIMEFRAMES tf, datetime val)
{
   switch(tf)
   {
      case PERIOD_H4:  g_lastSigH4 = val; break;
      case PERIOD_H1:  g_lastSigH1 = val; break;
      case PERIOD_M30: g_lastSigM30 = val; break;
      case PERIOD_M15: g_lastSigM15 = val; break;
      case PERIOD_M5:  g_lastSigM5 = val; break;
   }
}

datetime GetLastSigMode2(ENUM_TIMEFRAMES tf)
{
   switch(tf)
   {
      case PERIOD_H4:  return g_lastSigMode2H4;
      case PERIOD_H1:  return g_lastSigMode2H1;
      case PERIOD_M30: return g_lastSigMode2M30;
      case PERIOD_M15: return g_lastSigMode2M15;
      case PERIOD_M5:  return g_lastSigMode2M5;
      default: return 0;
   }
}

void SetLastSigMode2(ENUM_TIMEFRAMES tf, datetime val)
{
   switch(tf)
   {
      case PERIOD_H4:  g_lastSigMode2H4 = val; break;
      case PERIOD_H1:  g_lastSigMode2H1 = val; break;
      case PERIOD_M30: g_lastSigMode2M30 = val; break;
      case PERIOD_M15: g_lastSigMode2M15 = val; break;
      case PERIOD_M5:  g_lastSigMode2M5 = val; break;
   }
}

bool PlaceOrder(ENUM_TIMEFRAMES entryTF, int dir, bool isMode2=false)
{
   int mode = isMode2 ? 2 : 1;
   if(HasMaxOrdersForTF(entryTF, mode))
   {
      if(InpPrintBlocks)
         Print("Max orders for ", EnumToString(entryTF),
               " mode=", (isMode2 ? "MODE2" : "MODE1"),
               ": ", CountOrdersPerTF(entryTF, mode), "/", MaxOrdersPerTFByMode(mode));
      return false;
   }

   if(SpreadPts() > InpMaxSpreadPts || IsInNewsWindow()) return false;

   trade.SetExpertMagicNumber((int)InpMagic);
   trade.SetDeviationInPoints(20);

   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   if(ask <= 0 || bid <= 0) return false;

   bool isBuy = (dir == 1);
   double entryPrice = isBuy ? ask : bid;
   int slLookback = TF_SLLookbackBars(entryTF);
   double sl = CalculateInitialSL(entryTF, dir, slLookback);
   if(sl == 0.0) return false;
   int tpPts = InpHardTP;
   if(isMode2)
      tpPts = TF_Mode2TPValue(entryTF);
   double tp = isBuy ? entryPrice + tpPts * P() : entryPrice - tpPts * P();
   double lot = CalcAutoLotByRisk(entryPrice, sl);
   if(TF_UseManualLot(entryTF))
      lot = NormalizeLot(TF_ManualLot(entryTF));

   if(isBuy) { if(sl >= entryPrice || tp <= entryPrice) return false; }
   else      { if(sl <= entryPrice || tp >= entryPrice) return false; }

   string tfFriendly = GetTFFriendlyName(entryTF);
   string tfInternal = EnumToString(entryTF);
   string comment = "";
   if(isMode2)
      comment = "MODE 2 " + tfFriendly + " " + (isBuy ? "buy" : "sell") + "_TF_" + tfInternal;
   else
      comment = (isBuy ? "Buy_" : "Sell_") + tfFriendly + "_TF_" + tfInternal;

   bool ok = isBuy ? trade.Buy(lot, _Symbol, entryPrice, sl, tp, comment)
                   : trade.Sell(lot, _Symbol, entryPrice, sl, tp, comment);
   if(ok && InpPrintSignals)
      Print("Order: ", comment, " Lot=", lot);

   return ok;
}

//=========================== EXIT MANAGEMENT ========================

// Priority: BB Exit BEFORE EMA Profit Exit / Trailing
void CheckBBExit()
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      if(PositionGetSymbol(i) != _Symbol) continue;
      if((ulong)PositionGetInteger(POSITION_MAGIC) != InpMagic) continue;

      ulong ticket = (ulong)PositionGetInteger(POSITION_TICKET);
      long type = PositionGetInteger(POSITION_TYPE);
      bool isBuy = (type == POSITION_TYPE_BUY);
      double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
      double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
      if(bid <= 0 || ask <= 0) continue;
      string comment = PositionGetString(POSITION_COMMENT);
      ENUM_TIMEFRAMES entryTF = ParseEntryTF(comment, (ENUM_TIMEFRAMES)_Period);

      if(!TF_UseBBExit(entryTF)) continue;

      ENUM_TIMEFRAMES bbTF = TF_BB_TF(entryTF);
      int period = TF_BB_Period(entryTF);
      double dev = TF_BB_Deviation(entryTF);

      int hBB = iBands(_Symbol, bbTF, period, 0, dev, PRICE_CLOSE);
      if(hBB == INVALID_HANDLE) continue;

      double upper[], lower[];
      ArraySetAsSeries(upper, true);
      ArraySetAsSeries(lower, true);

      bool ok1 = (CopyBuffer(hBB, 1, 0, 1, upper) == 1);
      bool ok2 = (CopyBuffer(hBB, 2, 0, 1, lower) == 1);

      bool exit = false;
      if(ok1 && ok2)
      {
         if(isBuy) { if(bid >= upper[0]) exit = true; }
         else      { if(ask <= lower[0]) exit = true; }
      }

      IndicatorRelease(hBB);
      if(exit)
      {
         if(InpPrintExits)
            Print("BB Exit: ", comment,
                  " EntryTF=", EnumToString(entryTF),
                  " BBTF=", EnumToString(bbTF),
                  " Per=", period,
                  " Dev=", DoubleToString(dev,2));

         SafePositionClose(ticket,"BB_EXIT");
      }
   }
}

void CheckEMAProfitExit()
{
   if(!InpUseEMAProfitExit) return;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      if(PositionGetSymbol(i) != _Symbol) continue;
      if((ulong)PositionGetInteger(POSITION_MAGIC) != InpMagic) continue;

      ulong ticket = (ulong)PositionGetInteger(POSITION_TICKET);

      long type = PositionGetInteger(POSITION_TYPE);
      bool isBuy = (type == POSITION_TYPE_BUY);
      double openPrice = PositionGetDouble(POSITION_PRICE_OPEN);
      double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
      double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
      double point = P();
      if(bid <= 0 || ask <= 0) continue;

      double profitPts = isBuy ? (bid - openPrice) / point : (openPrice - ask) / point;
      if(profitPts < InpEMAExitProfitPts) continue;

      string comment = PositionGetString(POSITION_COMMENT);
      ENUM_TIMEFRAMES entryTF = ParseEntryTF(comment, (ENUM_TIMEFRAMES)_Period);

      int emaHandle = ExitEmaH(entryTF);
      if(emaHandle == INVALID_HANDLE) continue;

      double emaVal[];
      ArraySetAsSeries(emaVal, true);
      if(CopyBuffer(emaHandle, 0, 0, 1, emaVal) != 1) continue;
      double ema = emaVal[0];
      double bufferPrice = InpEMAExitBufferPts * point;
      double priceNow = isBuy ? bid : ask;
      bool exit = false;

      if(isBuy) { if(priceNow <= (ema - bufferPrice)) exit = true; }
      else      { if(priceNow >= (ema + bufferPrice)) exit = true; }

      if(exit)
      {
         if(InpPrintExits)
            Print("EMA Profit Exit(shift0+buf): ", comment,
                  " Profit:", (int)profitPts, "pts",
                  " PriceNow:", DoubleToString(priceNow,_Digits),
                  " EMA:", DoubleToString(ema,_Digits),
                  " BufPts:", InpEMAExitBufferPts,
                  " TF:", EnumToString(entryTF));
         SafePositionClose(ticket,"EMA_EXIT");
      }
   }
}

// Trailing management: Use Per-TF inputs dynamically
void ManageTrailingStop()
{
   TrailCleanupTable(); // v4.98: prevent MAX_TRACK table overflow
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      if(PositionGetSymbol(i) != _Symbol) continue;
      if((ulong)PositionGetInteger(POSITION_MAGIC) != InpMagic) continue;

      ulong  ticket    = (ulong)PositionGetInteger(POSITION_TICKET);
      long   type      = PositionGetInteger(POSITION_TYPE);
      bool   isBuy     = (type == POSITION_TYPE_BUY);

      double openPrice = PositionGetDouble(POSITION_PRICE_OPEN);
      double currentSL = PositionGetDouble(POSITION_SL);
      double currentTP = PositionGetDouble(POSITION_TP);

      double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
      double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
      double point = P();
      if(bid <= 0 || ask <= 0) continue;

      // Extract entry TF to apply corresponding trailing inputs
      string comment = PositionGetString(POSITION_COMMENT);
      ENUM_TIMEFRAMES entryTF = ParseEntryTF(comment, (ENUM_TIMEFRAMES)_Period);

      int trailStartPts = TF_TrailStart(entryTF);
      int trailDistPts  = TF_TrailDist(entryTF);
      int trailStepPts  = TF_TrailStep(entryTF);

      double profitPts = isBuy ? (bid - openPrice) / point : (openPrice - ask) / point;
      if(profitPts < trailStartPts) continue;

      // --- AFTER PROFIT THRESHOLD: EMA as SL
      if(InpUseEMATrailAfterProfit && profitPts >= InpEMAExitProfitPts)
      {
         ENUM_TIMEFRAMES emaTF = (ENUM_TIMEFRAMES)_Period;
         if(InpEMATrailUseEntryTF)
         {
            emaTF = entryTF;
         }

         int h = TrailEmaH(emaTF);
         if(h == INVALID_HANDLE) continue;

         double emaVal[];
         ArraySetAsSeries(emaVal, true);
         if(CopyBuffer(h, 0, 0, 1, emaVal) != 1) continue;

         double ema = emaVal[0];
         double buf = InpEMATrailBufferPts * point;

         double newSL = isBuy ? (ema - buf) : (ema + buf);
         newSL = NormalizeDouble(newSL, _Digits);

         if(isBuy && newSL >= bid) continue;
         if(!isBuy && newSL <= ask) continue;

         double stepPrice = trailStepPts * point;
         if(currentSL != 0 && MathAbs(newSL - currentSL) < stepPrice)
            continue;

         if(isBuy) { if(currentSL != 0 && newSL <= currentSL) continue; }
         else      { if(currentSL != 0 && newSL >= currentSL) continue; }

         if(!TrailAllowModify(ticket, InpTrailMinInterval))
            continue;

         SafePositionModify(ticket,isBuy,newSL,currentTP,"TRAIL");
         continue;
      }

      // --- NORMAL DISTANCE TRAIL (before profit threshold)
      double newSL = isBuy ? (bid - trailDistPts * point) : (ask + trailDistPts * point);
      newSL = NormalizeDouble(newSL, _Digits);

      double stepPrice = trailStepPts * point;
      if(currentSL != 0 && MathAbs(newSL - currentSL) < stepPrice)
         continue;

      if(isBuy) { if(currentSL != 0 && newSL <= currentSL) continue; }
      else      { if(currentSL != 0 && newSL >= currentSL) continue; }

      if(!TrailAllowModify(ticket, InpTrailMinInterval))
         continue;

      SafePositionModify(ticket,isBuy,newSL,currentTP,"TRAIL");
   }
}

void ManagePosition()
{
   TrailCleanupTable(); // v4.98: free closed tickets in throttle table
CheckBBExit();
   CheckEMAProfitExit();
   ManageTrailingStop();
}

//=========================== ENTRY SCAN =============================
void TryEntryOnTF(ENUM_TIMEFRAMES tf, int dir)
{
   if(!IsInTradingTime())
   {
      static datetime lastPrintTime = 0;
      if(TimeCurrent() - lastPrintTime > 300)
      {
         if(InpPrintBlocks) Print("Outside trading hours: ", InpStartHour, ":", InpStartMin, "-", InpEndHour, ":", InpEndMin);
         lastPrintTime = TimeCurrent();
      }
      return;
   }

   if(HasMaxOrdersForTF(tf, 1))
   {
      if(InpPrintBlocks && IsNewBar(tf))
         Print("Max orders for ", EnumToString(tf), " mode=MODE1: ",
               CountOrdersPerTF(tf, 1), "/", MaxOrdersPerTFByMode(1));
      return;
   }

   if(!TF_PassTPCooldown(tf))
   {
      if(InpPrintBlocks && IsNewBar(tf))
         Print("Blocked by TP cooldown: ", EnumToString(tf), " coolBars=", TF_TPCoolBars(tf));
      return;
   }

   if(!IsNewBar(tf)) return;

   datetime sigT = iTime(_Symbol, tf, 1);
   if(sigT <= 0 || sigT == GetLastSig(tf)) return;

   if(CheckMACDSignal(tf, dir))
   {
      SetLastSig(tf, sigT);
      PlaceOrder(tf, dir);
      return;
   }
}

void TryEntryOnTF_IgnoreDonchian(ENUM_TIMEFRAMES tf)
{
   if(!IsInTradingTime())
   {
      static datetime lastPrintTime2 = 0;
      if(TimeCurrent() - lastPrintTime2 > 300)
      {
         if(InpPrintBlocks) Print("Outside trading hours: ", InpStartHour, ":", InpStartMin, "-", InpEndHour, ":", InpEndMin);
         lastPrintTime2 = TimeCurrent();
      }
      return;
   }

   if(HasMaxOrdersForTF(tf, 1))
   {
      if(InpPrintBlocks && IsNewBar(tf))
         Print("Max orders for ", EnumToString(tf), " mode=MODE1: ",
               CountOrdersPerTF(tf, 1), "/", MaxOrdersPerTFByMode(1));
      return;
   }

   if(!TF_PassTPCooldown(tf))
   {
      if(InpPrintBlocks && IsNewBar(tf))
         Print("Blocked by TP cooldown: ", EnumToString(tf), " coolBars=", TF_TPCoolBars(tf));
      return;
   }

   if(!IsNewBar(tf)) return;

   datetime sigT = iTime(_Symbol, tf, 1);
   if(sigT <= 0 || sigT == GetLastSig(tf)) return;

   int dir = 0;
   if(CheckMACDSignal(tf, 1)) dir = 1;
   else if(CheckMACDSignal(tf, -1)) dir = -1;
   if(dir == 0) return;

   SetLastSig(tf, sigT);
   PlaceOrder(tf, dir);
   return;
}

bool TryEntryOnTF_BreakoutScan(ENUM_TIMEFRAMES tf, int dir)
{
   if(!g_newBreakoutSignal) return false;
   if(!TF_UseBreakScan(tf)) return false;
   if(!IsInTradingTime()) return false;
   if(HasMaxOrdersForTF(tf, 2)) return false;
   if(!TF_PassTPCooldown(tf)) return false;

   datetime sigT = iTime(_Symbol, tf, 1);
   if(sigT <= 0 || sigT == GetLastSigMode2(tf)) return false;

   int lookback = TF_BreakScanBars(tf);
   EMacdScanMode mode = TF_BreakScanMode(tf);
   if(!HasMACDSignalInLookback(tf, dir, lookback, mode)) return false;

   SetLastSigMode2(tf, sigT);

   if(InpPrintSignals)
      Print("BreakoutScan Entry: ", EnumToString(tf),
            " mode=", EnumToString(mode),
            " lookback=", lookback,
            " dir=", (dir==1?"BUY":"SELL"));

   return PlaceOrder(tf, dir, true);
}

//=========================== INIT / TICK ============================
int OnInit()
{
   bool badHandle = false;

   if(InpSignalSMA < 1)
   {
      Print("Invalid InpSignalSMA: ", InpSignalSMA, ", must be >= 1");
      return INIT_FAILED;
   }

   if(InpH4_SLLookbackBars < 1 || InpH1_SLLookbackBars < 1 || InpM30_SLLookbackBars < 1 ||
      InpM15_SLLookbackBars < 1 || InpM5_SLLookbackBars < 1)
   {
      Print("Invalid SLLookbackBars: all TF values must be >= 1");
      return INIT_FAILED;
   }

   if(InpH4_Mode2TPValue <= 0 || InpH1_Mode2TPValue <= 0 || InpM30_Mode2TPValue <= 0 ||
      InpM15_Mode2TPValue <= 0 || InpM5_Mode2TPValue <= 0)
   {
      Print("Invalid Mode2TPValue: all TF values must be > 0");
      return INIT_FAILED;
   }

   if(InpMaxOrdersPerTF_Mode1 < 0 || InpMaxOrdersPerTF_Mode2 < 0)
   {
      Print("Invalid max-orders: Mode1/Mode2 limits must be >= 0");
      return INIT_FAILED;
   }

   trade.SetExpertMagicNumber((int)InpMagic);

   g_useH4  = InpUseH4;
   g_useH1  = InpUseH1;
   g_useM30 = InpUseM30;
   g_useM15 = InpUseM15;
   g_useM5  = InpUseM5;

   TFButtonsCreate();

   if(InpUseATRFilter) g_atrHTF = iATR(_Symbol, InpHTF, InpATRPeriod);
   if(InpUseATRFilter && g_atrHTF==INVALID_HANDLE) badHandle = true;

   // Entry filter handles (EMAFilterPer)
   g_fastH4=iMA(_Symbol,PERIOD_H4,InpFastEMA,0,MODE_EMA,PRICE_CLOSE);
   g_slowH4=iMA(_Symbol,PERIOD_H4,InpSlowEMA,0,MODE_EMA,PRICE_CLOSE);
   g_emaH4 =iMA(_Symbol,PERIOD_H4,InpEMAFilterPer,0,MODE_EMA,PRICE_CLOSE);
   if(g_fastH4==INVALID_HANDLE || g_slowH4==INVALID_HANDLE || g_emaH4==INVALID_HANDLE) badHandle = true;

   g_fastH1=iMA(_Symbol,PERIOD_H1,InpFastEMA,0,MODE_EMA,PRICE_CLOSE);
   g_slowH1=iMA(_Symbol,PERIOD_H1,InpSlowEMA,0,MODE_EMA,PRICE_CLOSE);
   g_emaH1 =iMA(_Symbol,PERIOD_H1,InpEMAFilterPer,0,MODE_EMA,PRICE_CLOSE);
   if(g_fastH1==INVALID_HANDLE || g_slowH1==INVALID_HANDLE || g_emaH1==INVALID_HANDLE) badHandle = true;

   g_fastM30=iMA(_Symbol,PERIOD_M30,InpFastEMA,0,MODE_EMA,PRICE_CLOSE);
   g_slowM30=iMA(_Symbol,PERIOD_M30,InpSlowEMA,0,MODE_EMA,PRICE_CLOSE);
   g_emaM30 =iMA(_Symbol,PERIOD_M30,InpEMAFilterPer,0,MODE_EMA,PRICE_CLOSE);
   if(g_fastM30==INVALID_HANDLE || g_slowM30==INVALID_HANDLE || g_emaM30==INVALID_HANDLE) badHandle = true;

   g_fastM15=iMA(_Symbol,PERIOD_M15,InpFastEMA,0,MODE_EMA,PRICE_CLOSE);
   g_slowM15=iMA(_Symbol,PERIOD_M15,InpSlowEMA,0,MODE_EMA,PRICE_CLOSE);
   g_emaM15 =iMA(_Symbol,PERIOD_M15,InpEMAFilterPer,0,MODE_EMA,PRICE_CLOSE);
   if(g_fastM15==INVALID_HANDLE || g_slowM15==INVALID_HANDLE || g_emaM15==INVALID_HANDLE) badHandle = true;

   g_fastM5=iMA(_Symbol,PERIOD_M5,InpFastEMA,0,MODE_EMA,PRICE_CLOSE);
   g_slowM5=iMA(_Symbol,PERIOD_M5,InpSlowEMA,0,MODE_EMA,PRICE_CLOSE);
   g_emaM5 =iMA(_Symbol,PERIOD_M5,InpEMAFilterPer,0,MODE_EMA,PRICE_CLOSE);
   if(g_fastM5==INVALID_HANDLE || g_slowM5==INVALID_HANDLE || g_emaM5==INVALID_HANDLE) badHandle = true;

   // EMA Exit handles (InpEMAExitPeriod)
   g_exitEmaH4  = iMA(_Symbol, PERIOD_H4,  InpEMAExitPeriod, 0, MODE_EMA, PRICE_CLOSE);
   g_exitEmaH1  = iMA(_Symbol, PERIOD_H1,  InpEMAExitPeriod, 0, MODE_EMA, PRICE_CLOSE);
   g_exitEmaM30 = iMA(_Symbol, PERIOD_M30, InpEMAExitPeriod, 0, MODE_EMA, PRICE_CLOSE);
   g_exitEmaM15 = iMA(_Symbol, PERIOD_M15, InpEMAExitPeriod, 0, MODE_EMA, PRICE_CLOSE);
   g_exitEmaM5  = iMA(_Symbol, PERIOD_M5,  InpEMAExitPeriod, 0, MODE_EMA, PRICE_CLOSE);
   if(g_exitEmaH4==INVALID_HANDLE || g_exitEmaH1==INVALID_HANDLE ||
      g_exitEmaM30==INVALID_HANDLE || g_exitEmaM15==INVALID_HANDLE || g_exitEmaM5==INVALID_HANDLE) badHandle = true;

   // EMA Trail SL handles (InpEMATrailPeriod)
   g_trailEmaH4  = iMA(_Symbol, PERIOD_H4,  InpEMATrailPeriod, 0, MODE_EMA, PRICE_CLOSE);
   g_trailEmaH1  = iMA(_Symbol, PERIOD_H1,  InpEMATrailPeriod, 0, MODE_EMA, PRICE_CLOSE);
   g_trailEmaM30 = iMA(_Symbol, PERIOD_M30, InpEMATrailPeriod, 0, MODE_EMA, PRICE_CLOSE);
   g_trailEmaM15 = iMA(_Symbol, PERIOD_M15, InpEMATrailPeriod, 0, MODE_EMA, PRICE_CLOSE);
   g_trailEmaM5  = iMA(_Symbol, PERIOD_M5,  InpEMATrailPeriod, 0, MODE_EMA, PRICE_CLOSE);
   g_trailEmaChart = iMA(_Symbol, (ENUM_TIMEFRAMES)_Period, InpEMATrailPeriod, 0, MODE_EMA, PRICE_CLOSE);
   if(g_trailEmaH4==INVALID_HANDLE || g_trailEmaH1==INVALID_HANDLE ||
      g_trailEmaM30==INVALID_HANDLE || g_trailEmaM15==INVALID_HANDLE ||
      g_trailEmaM5==INVALID_HANDLE || g_trailEmaChart==INVALID_HANDLE) badHandle = true;

   if(InpShowEAMACDPanel)
   {
      g_dbgMacdPanelH = iCustom(_Symbol, InpShowEAMACD_TF, "EA_TV_MACD_View", InpFastEMA, InpSlowEMA, InpSignalSMA);
      if(g_dbgMacdPanelH==INVALID_HANDLE)
      {
         Print("EA MACD panel disabled: indicator handle error");
      }
      else
      {
         int subw = (int)ChartGetInteger(0, CHART_WINDOWS_TOTAL);
         if(!ChartIndicatorAdd(0, subw, g_dbgMacdPanelH))
            Print("EA MACD panel add failed, err=", GetLastError());
      }
   }

   if(badHandle)
   {
      Print("Handle error");
      return INIT_FAILED;
   }

   Print("Donchian_MACD v4.97 - Per-TF Trailing enabled");
   return INIT_SUCCEEDED;
}

void OnTick()
{
   ManagePosition();

   if(SpreadPts() > InpMaxSpreadPts || IsInNewsWindow()) return;

   int dir = UpdateHTFState();

   if(g_useH4)
   {
      if(TF_IgnoreDonchian(PERIOD_H4)) TryEntryOnTF_IgnoreDonchian(PERIOD_H4);
      else if(dir != 0)
      {
         if(!TryEntryOnTF_BreakoutScan(PERIOD_H4, dir))
            TryEntryOnTF(PERIOD_H4, dir);
      }
   }
   if(g_useH1)
   {
      if(TF_IgnoreDonchian(PERIOD_H1)) TryEntryOnTF_IgnoreDonchian(PERIOD_H1);
      else if(dir != 0)
      {
         if(!TryEntryOnTF_BreakoutScan(PERIOD_H1, dir))
            TryEntryOnTF(PERIOD_H1, dir);
      }
   }
   if(g_useM30)
   {
      if(TF_IgnoreDonchian(PERIOD_M30)) TryEntryOnTF_IgnoreDonchian(PERIOD_M30);
      else if(dir != 0)
      {
         if(!TryEntryOnTF_BreakoutScan(PERIOD_M30, dir))
            TryEntryOnTF(PERIOD_M30, dir);
      }
   }
   if(g_useM15)
   {
      if(TF_IgnoreDonchian(PERIOD_M15)) TryEntryOnTF_IgnoreDonchian(PERIOD_M15);
      else if(dir != 0)
      {
         if(!TryEntryOnTF_BreakoutScan(PERIOD_M15, dir))
            TryEntryOnTF(PERIOD_M15, dir);
      }
   }
   if(g_useM5)
   {
      if(TF_IgnoreDonchian(PERIOD_M5)) TryEntryOnTF_IgnoreDonchian(PERIOD_M5);
      else if(dir != 0)
      {
         if(!TryEntryOnTF_BreakoutScan(PERIOD_M5, dir))
            TryEntryOnTF(PERIOD_M5, dir);
      }
   }
}

void OnTradeTransaction(const MqlTradeTransaction& trans,
                        const MqlTradeRequest& request,
                        const MqlTradeResult& result)
{
   if(trans.type != TRADE_TRANSACTION_DEAL_ADD) return;
   ulong dealTicket = trans.deal;
   if(dealTicket==0) return;
   if(!HistoryDealSelect(dealTicket)) return;

   string sym = HistoryDealGetString(dealTicket, DEAL_SYMBOL);
   if(sym != _Symbol) return;

   long mg = HistoryDealGetInteger(dealTicket, DEAL_MAGIC);
   if((ulong)mg != InpMagic) return;

   long entry = HistoryDealGetInteger(dealTicket, DEAL_ENTRY);
   if(entry != DEAL_ENTRY_OUT) return;

   long reason = HistoryDealGetInteger(dealTicket, DEAL_REASON);
   if(reason != DEAL_REASON_TP) return;

   ENUM_TIMEFRAMES tf = (ENUM_TIMEFRAMES)_Period;
   bool tfFound = false;

   string cmt = HistoryDealGetString(dealTicket, DEAL_COMMENT);
   tfFound = ParseEntryTFStrict(cmt, tf);

   if(!tfFound)
   {
      long posId = HistoryDealGetInteger(dealTicket, DEAL_POSITION_ID);
      if(posId > 0 && HistorySelect(TimeCurrent()-86400*365, TimeCurrent()+60))
      {
         int n = HistoryDealsTotal();
         for(int i=n-1; i>=0; i--)
         {
            ulong tk = HistoryDealGetTicket(i);
            if((long)HistoryDealGetInteger(tk, DEAL_POSITION_ID) != posId) continue;
            if((long)HistoryDealGetInteger(tk, DEAL_ENTRY) != DEAL_ENTRY_IN) continue;
            string inCmt = HistoryDealGetString(tk, DEAL_COMMENT);
            if(ParseEntryTFStrict(inCmt, tf)) { tfFound = true; break; }
         }
      }
   }

   if(!tfFound) return;

   datetime dt = (datetime)HistoryDealGetInteger(dealTicket, DEAL_TIME);
   TF_SetLastTPCloseTime(tf, dt);

   if(InpPrintExits)
      Print("TP Cooldown Start: ", EnumToString(tf), " at ", TimeToString(dt));
}

void OnChartEvent(const int id, const long &lparam, const double &dparam, const string &sparam)
{
   if(id == CHARTEVENT_OBJECT_CLICK)
   {
      TFButtonTryToggle(sparam);
   }
}

void OnDeinit(const int reason)
{
   TM_DeleteAllObjects();
   TFButtonsDelete();
   if(g_dbgMacdPanelH!=INVALID_HANDLE)
   {
      IndicatorRelease(g_dbgMacdPanelH);
      g_dbgMacdPanelH = INVALID_HANDLE;
   }
}
//+------------------------------------------------------------------+
