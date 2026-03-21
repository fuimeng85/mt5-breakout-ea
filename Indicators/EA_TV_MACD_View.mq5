#property strict
#property indicator_separate_window
#property indicator_buffers 3
#property indicator_plots   3

#property indicator_label1  "MACD Main"
#property indicator_type1   DRAW_LINE
#property indicator_color1  clrDodgerBlue
#property indicator_width1  1

#property indicator_label2  "MACD Signal(SMA)"
#property indicator_type2   DRAW_LINE
#property indicator_color2  clrOrange
#property indicator_width2  1

#property indicator_label3  "MACD Hist"
#property indicator_type3   DRAW_HISTOGRAM
#property indicator_color3  clrSilver
#property indicator_width3  2

input int InpFastEMA   = 12;
input int InpSlowEMA   = 26;
input int InpSignalSMA = 9;

double g_mainBuf[];
double g_sigBuf[];
double g_histBuf[];

int g_fastH = INVALID_HANDLE;
int g_slowH = INVALID_HANDLE;

int OnInit()
{
   SetIndexBuffer(0, g_mainBuf, INDICATOR_DATA);
   SetIndexBuffer(1, g_sigBuf, INDICATOR_DATA);
   SetIndexBuffer(2, g_histBuf, INDICATOR_DATA);

   ArraySetAsSeries(g_mainBuf, true);
   ArraySetAsSeries(g_sigBuf, true);
   ArraySetAsSeries(g_histBuf, true);

   g_fastH = iMA(_Symbol, _Period, InpFastEMA, 0, MODE_EMA, PRICE_CLOSE);
   g_slowH = iMA(_Symbol, _Period, InpSlowEMA, 0, MODE_EMA, PRICE_CLOSE);
   if(g_fastH==INVALID_HANDLE || g_slowH==INVALID_HANDLE)
      return INIT_FAILED;

   IndicatorSetString(INDICATOR_SHORTNAME,
      "EA_TV_MACD_View(" + IntegerToString(InpFastEMA) + "," +
      IntegerToString(InpSlowEMA) + "," + IntegerToString(InpSignalSMA) + ")");

   return INIT_SUCCEEDED;
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
   if(rates_total <= InpSignalSMA + 2) return 0;

   double fast[], slow[];
   ArraySetAsSeries(fast, true);
   ArraySetAsSeries(slow, true);

   if(CopyBuffer(g_fastH, 0, 0, rates_total, fast) < rates_total) return prev_calculated;
   if(CopyBuffer(g_slowH, 0, 0, rates_total, slow) < rates_total) return prev_calculated;

   for(int i=0;i<rates_total;i++)
      g_mainBuf[i] = fast[i] - slow[i];

   for(int i=0;i<rates_total;i++)
   {
      if(i + InpSignalSMA - 1 < rates_total)
      {
         double sum = 0.0;
         for(int k=i; k<i+InpSignalSMA; k++) sum += g_mainBuf[k];
         g_sigBuf[i] = sum / InpSignalSMA;
         g_histBuf[i] = g_mainBuf[i] - g_sigBuf[i];
      }
      else
      {
         g_sigBuf[i] = EMPTY_VALUE;
         g_histBuf[i] = EMPTY_VALUE;
      }
   }

   return rates_total;
}

void OnDeinit(const int reason)
{
   if(g_fastH!=INVALID_HANDLE) IndicatorRelease(g_fastH);
   if(g_slowH!=INVALID_HANDLE) IndicatorRelease(g_slowH);
}
