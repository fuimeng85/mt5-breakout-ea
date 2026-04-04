#property copyright ""
#property link      ""
#property version   "1.00"
#property indicator_chart_window
#property indicator_plots 8
#property indicator_buffers 8

#property indicator_type1   DRAW_LINE
#property indicator_color1  clrDodgerBlue
#property indicator_label1  "EXT 1.618"
#property indicator_style1  STYLE_DOT
#property indicator_width1  1

#property indicator_type2   DRAW_LINE
#property indicator_color2  clrDodgerBlue
#property indicator_label2  "EXT 1.788"
#property indicator_style2  STYLE_DOT
#property indicator_width2  1

#property indicator_type3   DRAW_LINE
#property indicator_color3  clrDodgerBlue
#property indicator_label3  "EXT 1.888"
#property indicator_style3  STYLE_DOT
#property indicator_width3  1

#property indicator_type4   DRAW_LINE
#property indicator_color4  clrOrangeRed
#property indicator_label4  "EXT 2.618"
#property indicator_style4  STYLE_DOT
#property indicator_width4  1

#property indicator_type5   DRAW_LINE
#property indicator_color5  clrOrangeRed
#property indicator_label5  "EXT 2.788"
#property indicator_style5  STYLE_DOT
#property indicator_width5  1

#property indicator_type6   DRAW_LINE
#property indicator_color6  clrOrangeRed
#property indicator_label6  "EXT 2.888"
#property indicator_style6  STYLE_DOT
#property indicator_width6  1

#property indicator_type7   DRAW_NONE
#property indicator_label7  "Direction"

#property indicator_type8   DRAW_NONE
#property indicator_label8  "Valid"

input int      InpLookbackBars    = 100;      // Donchian扫描根数
input int      InpBreakoutConfirm = 1;        // 突破确认K线数
input int      InpAtrPeriod       = 14;       // ATR周期
input double   InpMinRangeATR     = 1.2;      // 最小区间ATR倍数
input bool     InpOnlyOnNewBar    = true;     // 仅在新K线重算
input bool     InpDrawObjects     = true;     // 绘制水平线对象
input color    InpColorGroup1     = clrDodgerBlue;
input color    InpColorGroup2     = clrOrangeRed;
input int      InpLineWidth       = 1;
input bool     InpShowLabel       = true;

// 输出buffer
static double BufL1[];
static double BufL2[];
static double BufL3[];
static double BufL4[];
static double BufL5[];
static double BufL6[];
static double BufDir[];
static double BufValid[];

const double g_ratios[6] = {1.618, 1.788, 1.888, 2.618, 2.788, 2.888};
int g_atrHandle = INVALID_HANDLE;
datetime g_lastBarTime = 0;

string TfToString(const ENUM_TIMEFRAMES tf)
{
   switch(tf)
   {
      case PERIOD_M1:   return "M1";
      case PERIOD_M2:   return "M2";
      case PERIOD_M3:   return "M3";
      case PERIOD_M4:   return "M4";
      case PERIOD_M5:   return "M5";
      case PERIOD_M6:   return "M6";
      case PERIOD_M10:  return "M10";
      case PERIOD_M12:  return "M12";
      case PERIOD_M15:  return "M15";
      case PERIOD_M20:  return "M20";
      case PERIOD_M30:  return "M30";
      case PERIOD_H1:   return "H1";
      case PERIOD_H2:   return "H2";
      case PERIOD_H3:   return "H3";
      case PERIOD_H4:   return "H4";
      case PERIOD_H6:   return "H6";
      case PERIOD_H8:   return "H8";
      case PERIOD_H12:  return "H12";
      case PERIOD_D1:   return "D1";
      case PERIOD_W1:   return "W1";
      case PERIOD_MN1:  return "MN1";
      default:          return "TF";
   }
}

void ClearBuffers(const int rates_total)
{
   for(int i = 0; i < rates_total; i++)
   {
      BufL1[i] = EMPTY_VALUE;
      BufL2[i] = EMPTY_VALUE;
      BufL3[i] = EMPTY_VALUE;
      BufL4[i] = EMPTY_VALUE;
      BufL5[i] = EMPTY_VALUE;
      BufL6[i] = EMPTY_VALUE;
      BufDir[i] = 0.0;
      BufValid[i] = 0.0;
   }
}

string MakeObjName(const int idx, const int direction)
{
   string dir = direction > 0 ? "UP" : "DN";
   return StringFormat("FIBX_%s_%s_%s_%.3f", _Symbol, TfToString(_Period), dir, g_ratios[idx]);
}

void DrawOrUpdateLevelObject(const int idx, const int direction, const double price)
{
   if(!InpDrawObjects)
      return;

   string name = MakeObjName(idx, direction);
   if(ObjectFind(0, name) < 0)
      ObjectCreate(0, name, OBJ_HLINE, 0, 0, price);

   color c = idx <= 2 ? InpColorGroup1 : InpColorGroup2;
   ObjectSetDouble(0, name, OBJPROP_PRICE, price);
   ObjectSetInteger(0, name, OBJPROP_COLOR, c);
   ObjectSetInteger(0, name, OBJPROP_STYLE, STYLE_DOT);
   ObjectSetInteger(0, name, OBJPROP_WIDTH, InpLineWidth);
   if(InpShowLabel)
   {
      string txt = StringFormat("%s %s %.3f @ %s",
                                TfToString(_Period),
                                direction > 0 ? "UP" : "DN",
                                g_ratios[idx],
                                DoubleToString(price, _Digits));
      ObjectSetString(0, name, OBJPROP_TEXT, txt);
   }
}

void DeleteAllLevelObjects()
{
   string prefix = StringFormat("FIBX_%s_%s_", _Symbol, TfToString(_Period));
   for(int i = ObjectsTotal(0) - 1; i >= 0; i--)
   {
      string n = ObjectName(0, i);
      if(StringFind(n, prefix) == 0)
         ObjectDelete(0, n);
   }
}

bool GetDonchianBreakout(int &direction, double &a, double &b, const int rates_total, const int shift)
{
   int barsNeeded = InpLookbackBars + InpBreakoutConfirm + 5;
   if(rates_total < barsNeeded)
      return false;

   int hhIndex = iHighest(_Symbol, PERIOD_CURRENT, MODE_HIGH, InpLookbackBars, shift + InpBreakoutConfirm);
   int llIndex = iLowest(_Symbol, PERIOD_CURRENT, MODE_LOW, InpLookbackBars, shift + InpBreakoutConfirm);
   if(hhIndex < 0 || llIndex < 0)
      return false;

   double hh = iHigh(_Symbol, PERIOD_CURRENT, hhIndex);
   double ll = iLow(_Symbol, PERIOD_CURRENT, llIndex);

   double atrVals[];
   ArraySetAsSeries(atrVals, true);
   if(CopyBuffer(g_atrHandle, 0, shift + InpBreakoutConfirm, 1, atrVals) < 1)
      return false;

   double atr = atrVals[0];
   if(atr <= 0.0)
      return false;

   if((hh - ll) < (atr * InpMinRangeATR))
      return false;

   bool up = true;
   bool down = true;
   for(int i = 0; i < InpBreakoutConfirm; i++)
   {
      double c = iClose(_Symbol, PERIOD_CURRENT, shift + i);
      if(c <= hh)
         up = false;
      if(c >= ll)
         down = false;
   }

   if(up)
   {
      direction = 1;
      a = ll;
      b = hh;
      return true;
   }

   if(down)
   {
      direction = -1;
      a = hh;
      b = ll;
      return true;
   }

   return false;
}

void FillLastBarBuffers(const int rates_total, const int direction, const double &levels[])
{
   int i = 0;
   BufL1[i] = levels[0];
   BufL2[i] = levels[1];
   BufL3[i] = levels[2];
   BufL4[i] = levels[3];
   BufL5[i] = levels[4];
   BufL6[i] = levels[5];
   BufDir[i] = (double)direction;
   BufValid[i] = 1.0;

   // 其他柱子置空，避免历史画满
   for(i = 1; i < rates_total; i++)
   {
      BufL1[i] = EMPTY_VALUE;
      BufL2[i] = EMPTY_VALUE;
      BufL3[i] = EMPTY_VALUE;
      BufL4[i] = EMPTY_VALUE;
      BufL5[i] = EMPTY_VALUE;
      BufL6[i] = EMPTY_VALUE;
      BufDir[i] = 0.0;
      BufValid[i] = 0.0;
   }
}

int OnInit()
{
   SetIndexBuffer(0, BufL1, INDICATOR_DATA);
   SetIndexBuffer(1, BufL2, INDICATOR_DATA);
   SetIndexBuffer(2, BufL3, INDICATOR_DATA);
   SetIndexBuffer(3, BufL4, INDICATOR_DATA);
   SetIndexBuffer(4, BufL5, INDICATOR_DATA);
   SetIndexBuffer(5, BufL6, INDICATOR_DATA);
   SetIndexBuffer(6, BufDir, INDICATOR_DATA);
   SetIndexBuffer(7, BufValid, INDICATOR_DATA);

   ArraySetAsSeries(BufL1, true);
   ArraySetAsSeries(BufL2, true);
   ArraySetAsSeries(BufL3, true);
   ArraySetAsSeries(BufL4, true);
   ArraySetAsSeries(BufL5, true);
   ArraySetAsSeries(BufL6, true);
   ArraySetAsSeries(BufDir, true);
   ArraySetAsSeries(BufValid, true);

   g_atrHandle = iATR(_Symbol, PERIOD_CURRENT, InpAtrPeriod);
   if(g_atrHandle == INVALID_HANDLE)
      return INIT_FAILED;

   IndicatorSetString(INDICATOR_SHORTNAME, "FIB Extension Donchian");
   return INIT_SUCCEEDED;
}

void OnDeinit(const int reason)
{
   if(g_atrHandle != INVALID_HANDLE)
      IndicatorRelease(g_atrHandle);

   DeleteAllLevelObjects();
}

int OnCalculate(const int rates_total,
                const int prev_calculated,
                const datetime &time[],
                const double &open[],
                const double &high[],
                const double &low[],
                const double &close[],
                const long &tick_volume[],
                const long &volume[],
                const int &spread[])
{
   if(rates_total <= InpLookbackBars + InpBreakoutConfirm + 5)
   {
      ClearBuffers(rates_total);
      return rates_total;
   }

   ArraySetAsSeries(time, true);

   if(InpOnlyOnNewBar && prev_calculated > 0 && g_lastBarTime == time[0])
      return rates_total;

   g_lastBarTime = time[0];

   int direction = 0;
   double a = 0.0, b = 0.0;
   double levels[6];
   ArrayInitialize(levels, 0.0);

   ClearBuffers(rates_total);

   if(!GetDonchianBreakout(direction, a, b, rates_total, 0))
   {
      DeleteAllLevelObjects();
      return rates_total;
   }

   double leg = MathAbs(b - a);
   if(leg <= 0)
      return rates_total;

   for(int i = 0; i < 6; i++)
   {
      if(direction > 0)
         levels[i] = b + (leg * g_ratios[i]);
      else
         levels[i] = b - (leg * g_ratios[i]);

      DrawOrUpdateLevelObject(i, direction, levels[i]);
   }

   FillLastBarBuffers(rates_total, direction, levels);
   return rates_total;
}
