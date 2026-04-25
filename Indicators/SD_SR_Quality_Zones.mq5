#property strict
#property indicator_chart_window
#property indicator_plots 0

input int      InpScanBars            = 500;   // 扫描K线数量
input bool     InpUseScanDays         = true;  // 是否按天数扩展扫描，避免H1/H4显示差异过大
input int      InpScanDays            = 120;   // 扫描天数（启用时会取 max(ScanBars, ScanDays对应bar数)）
input int      InpPivotN              = 3;     // Pivot窗口N（左右各N根）
input int      InpBaseMin             = 2;     // Base最小根数
input int      InpBaseMax             = 6;     // Base最大根数
input int      InpAvgBodyPeriod       = 20;    // 平均实体计算窗口
input double   InpImpulseBodyFactor   = 2.0;   // 大蜡烛阈值：实体 >= factor * 平均实体
input int      InpATRPeriod           = 14;    // ATR周期
input double   InpMinQualityScore     = 70.0;  // 高质量最小分
input bool     InpAggressiveEntry     = true;  // 激进：触区即信号
input bool     InpFirstRetestOnly     = true;  // 仅首次回踩
input double   InpBreakBufferATR      = 0.1;   // 失效缓冲（ATR倍数）
input double   InpSRMergeATR          = 0.3;   // S/R聚类容差（ATR倍数）
input int      InpMaxDrawSR           = 8;     // 最多绘制S/R区域
input int      InpMaxDrawZones        = 10;    // 最多绘制供需区域
input bool     InpFilterSRByDistance  = false; // 中小级别想多看线时建议false；true则启用距离过滤
input double   InpMaxSRDistanceATR    = 25.0;  // 启用过滤时：仅显示距离当前价格<=N*ATR的S/R
input bool     InpShowSRLevelLabel    = true;  // 显示S/R级别标签（LOW/MID/HIGH + 周期）
input color    InpSRLowColor          = clrSilver;
input color    InpSRMidColor          = clrGold;
input color    InpSRHighColor         = clrMediumOrchid;
input bool     InpDebugShowStats      = true;  // 显示扫描统计（用于排查“图上无显示”）

string PREFIX = "SD_SR_QZ_";

struct SRCluster
{
   double top;
   double bottom;
   int    touches;
   bool   is_resistance;
   datetime first_t;
   datetime last_t;
};

struct SDZone
{
   bool     is_supply;
   double   top;
   double   bottom;
   int      base_start_shift;
   int      base_len;
   int      impulse_shift;
   double   score;
   int      retests;
   bool     invalid;
};

int atr_handle = INVALID_HANDLE;

//--- helpers
string ObjName(const string tag, const int idx)
{
   return PREFIX + tag + "_" + IntegerToString(idx);
}

void ClearObjects()
{
   ObjectsDeleteAll(0, PREFIX);
}

double CandleBody(const int shift, const double &open[], const double &close[])
{
   return MathAbs(close[shift] - open[shift]);
}

bool IsPivotHigh(const int shift, const int n, const int bars, const double &high[])
{
   if(shift - n < 0 || shift + n >= bars)
      return false;

   double v = high[shift];
   for(int k=1; k<=n; k++)
   {
      if(v <= high[shift-k] || v <= high[shift+k])
         return false;
   }
   return true;
}

bool IsPivotLow(const int shift, const int n, const int bars, const double &low[])
{
   if(shift - n < 0 || shift + n >= bars)
      return false;

   double v = low[shift];
   for(int k=1; k<=n; k++)
   {
      if(v >= low[shift-k] || v >= low[shift+k])
         return false;
   }
   return true;
}

double MeanBody(const int from_shift, const int count, const int bars, const double &open[], const double &close[])
{
   int valid = 0;
   double sum = 0.0;
   for(int i=0; i<count; i++)
   {
      int s = from_shift + i;
      if(s >= bars)
         break;
      sum += CandleBody(s, open, close);
      valid++;
   }
   if(valid <= 0)
      return 0.0;
   return sum / valid;
}

void AddOrMergeSR(SRCluster &arr[], const double price, const bool is_res, const double tol, const datetime t)
{
   int n = ArraySize(arr);
   for(int i=0; i<n; i++)
   {
      if(arr[i].is_resistance != is_res)
         continue;

      double center = (arr[i].top + arr[i].bottom) * 0.5;
      if(MathAbs(price - center) <= tol)
      {
         arr[i].top = MathMax(arr[i].top, price);
         arr[i].bottom = MathMin(arr[i].bottom, price);
         arr[i].touches++;
         arr[i].last_t = t;
         return;
      }
   }

   ArrayResize(arr, n+1);
   arr[n].top = price;
   arr[n].bottom = price;
   arr[n].touches = 1;
   arr[n].is_resistance = is_res;
   arr[n].first_t = t;
   arr[n].last_t = t;
}

int CompareSR(const SRCluster &a, const SRCluster &b)
{
   if(a.touches > b.touches) return -1;
   if(a.touches < b.touches) return 1;
   if(a.last_t > b.last_t) return -1;
   if(a.last_t < b.last_t) return 1;
   return 0;
}

void SortSR(SRCluster &arr[])
{
   int n = ArraySize(arr);
   for(int i=0; i<n-1; i++)
   {
      int best = i;
      for(int j=i+1; j<n; j++)
      {
         if(CompareSR(arr[j], arr[best]) < 0)
            best = j;
      }
      if(best != i)
      {
         SRCluster tmp = arr[i];
         arr[i] = arr[best];
         arr[best] = tmp;
      }
   }
}

bool IntersectsZone(const double low_v, const double high_v, const double z_low, const double z_high)
{
   return (low_v <= z_high && high_v >= z_low);
}

double ClampScore(const double v)
{
   if(v < 0.0) return 0.0;
   if(v > 100.0) return 100.0;
   return v;
}

string SRLevelName(const int touches)
{
   if(touches >= 5) return "HIGH";
   if(touches >= 3) return "MID";
   return "LOW";
}

color SRLevelColor(const int touches)
{
   if(touches >= 5) return InpSRHighColor;
   if(touches >= 3) return InpSRMidColor;
   return InpSRLowColor;
}

void DrawSR(const SRCluster &sr, const int idx, const datetime &time[])
{
   string nm = ObjName(sr.is_resistance ? "RES" : "SUP", idx);
   double center = (sr.top + sr.bottom) * 0.5;
   if(!ObjectCreate(0, nm, OBJ_HLINE, 0, 0, center))
      return;

   color c = SRLevelColor(sr.touches);
   ObjectSetInteger(0, nm, OBJPROP_COLOR, c);
   ObjectSetInteger(0, nm, OBJPROP_STYLE, STYLE_DOT);
   ObjectSetInteger(0, nm, OBJPROP_WIDTH, 2);

   if(InpShowSRLevelLabel)
   {
      string lb = nm + "_LBL";
      if(ObjectCreate(0, lb, OBJ_TEXT, 0, time[0], center))
      {
         string side = sr.is_resistance ? "RES" : "SUP";
         string txt = StringFormat("%s-%s %s", side, SRLevelName(sr.touches), EnumToString(_Period));
         ObjectSetString(0, lb, OBJPROP_TEXT, txt);
         ObjectSetInteger(0, lb, OBJPROP_COLOR, c);
         ObjectSetInteger(0, lb, OBJPROP_FONTSIZE, 8);
         ObjectSetString(0, lb, OBJPROP_FONT, "Arial");
         ObjectSetInteger(0, lb, OBJPROP_ANCHOR, ANCHOR_RIGHT);
      }
   }
}

void DrawZone(const SDZone &z, const int idx, const datetime &time[])
{
   string nm = ObjName(z.is_supply ? "SUPPLY" : "DEMAND", idx);
   datetime t1 = time[z.base_start_shift];
   datetime t2 = time[0];

   if(!ObjectCreate(0, nm, OBJ_RECTANGLE, 0, t1, z.top, t2, z.bottom))
      return;

   color c = z.is_supply ? clrTomato : clrDodgerBlue;
   if(z.invalid)
      c = clrGray;

   ObjectSetInteger(0, nm, OBJPROP_COLOR, c);
   ObjectSetInteger(0, nm, OBJPROP_BACK, true);
   ObjectSetInteger(0, nm, OBJPROP_FILL, true);
   ObjectSetInteger(0, nm, OBJPROP_WIDTH, 1);

   string lb = ObjName(z.is_supply ? "S_TXT" : "D_TXT", idx);
   double y = z.is_supply ? z.top : z.bottom;
   if(ObjectCreate(0, lb, OBJ_TEXT, 0, time[MathMax(z.impulse_shift, 0)], y))
   {
      string txt = StringFormat("%s Q=%.1f R=%d%s",
                                (z.is_supply ? "SUPPLY" : "DEMAND"),
                                z.score,
                                z.retests,
                                z.invalid ? " INVALID" : "");
      ObjectSetString(0, lb, OBJPROP_TEXT, txt);
      ObjectSetInteger(0, lb, OBJPROP_COLOR, c);
      ObjectSetInteger(0, lb, OBJPROP_FONTSIZE, 8);
      ObjectSetString(0, lb, OBJPROP_FONT, "Arial");
      ObjectSetInteger(0, lb, OBJPROP_ANCHOR, ANCHOR_LEFT_UPPER);
   }
}

void DrawSignalArrow(const bool is_supply, const double price, const datetime t)
{
   string nm = ObjName(is_supply ? "SELL" : "BUY", (int)t);
   int arrow = is_supply ? 234 : 233;
   color c = is_supply ? clrTomato : clrDeepSkyBlue;

   if(ObjectCreate(0, nm, OBJ_ARROW, 0, t, price))
   {
      ObjectSetInteger(0, nm, OBJPROP_ARROWCODE, arrow);
      ObjectSetInteger(0, nm, OBJPROP_COLOR, c);
      ObjectSetInteger(0, nm, OBJPROP_WIDTH, 2);
   }
}

int OnInit()
{
   IndicatorSetString(INDICATOR_SHORTNAME, "SD/SR Quality Zones");
   atr_handle = iATR(_Symbol, _Period, InpATRPeriod);
   if(atr_handle == INVALID_HANDLE)
      return(INIT_FAILED);
   return(INIT_SUCCEEDED);
}

void OnDeinit(const int reason)
{
   ClearObjects();
   if(atr_handle != INVALID_HANDLE)
      IndicatorRelease(atr_handle);
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
   if(rates_total < 100)
      return rates_total;

   int scan = MathMin(InpScanBars, rates_total - 1);
   if(InpUseScanDays && InpScanDays > 0)
   {
      datetime cutoff = time[0] - (datetime)(InpScanDays * 86400);
      int bars_by_days = 0;
      while((bars_by_days + 1) < rates_total && time[bars_by_days] >= cutoff)
         bars_by_days++;
      scan = MathMin(rates_total - 1, MathMax(scan, bars_by_days));
   }
   if(scan <= InpPivotN*2 + 10)
      return rates_total;

   double atr[];
   ArraySetAsSeries(atr, true);
   if(CopyBuffer(atr_handle, 0, 0, scan + 50, atr) <= 0)
      return rates_total;

   ClearObjects();

   // 1) S/R
   SRCluster sr_list[];
   for(int s=scan-1-InpPivotN; s>=InpPivotN; s--)
   {
      double tol = atr[s] * InpSRMergeATR;
      if(IsPivotHigh(s, InpPivotN, rates_total, high))
         AddOrMergeSR(sr_list, high[s], true, tol, time[s]);
      if(IsPivotLow(s, InpPivotN, rates_total, low))
         AddOrMergeSR(sr_list, low[s], false, tol, time[s]);
   }
   SortSR(sr_list);

   int draw_sr = 0;
   double atr0 = atr[0];
   for(int i=0; i<ArraySize(sr_list) && draw_sr < InpMaxDrawSR; i++)
   {
      double center = (sr_list[i].top + sr_list[i].bottom) * 0.5;
      if(InpFilterSRByDistance && atr0 > 0.0 && MathAbs(center - close[0]) > InpMaxSRDistanceATR * atr0)
         continue;
      DrawSR(sr_list[i], draw_sr, time);
      draw_sr++;
   }

   // 2) Supply / Demand
   SDZone zones[];
   for(int start=scan-1-InpBaseMin-2; start>=InpBaseMax+2; start--)
   {
      for(int base_len=InpBaseMin; base_len<=InpBaseMax; base_len++)
      {
         int base_last = start - (base_len - 1);
         int imp = base_last - 1;
         if(imp < 2)
            continue;

         double b_top = -DBL_MAX;
         double b_low = DBL_MAX;
         for(int k=0; k<base_len; k++)
         {
            int sh = start - k;
            b_top = MathMax(b_top, high[sh]);
            b_low = MathMin(b_low, low[sh]);
         }

         double base_range = b_top - b_low;
         double atr_v = atr[imp];
         if(atr_v <= 0.0)
            continue;

         // 放宽base限制，避免有效区被过度过滤
         if(base_range > 2.0 * atr_v)
            continue;

         double body_imp = CandleBody(imp, open, close);
         double mean_body = MeanBody(imp+1, InpAvgBodyPeriod, rates_total, open, close);
         if(mean_body <= 0.0)
            continue;

         bool up_imp = (close[imp] > open[imp]);
         bool dn_imp = (close[imp] < open[imp]);
         double impulse_need = MathMax(InpImpulseBodyFactor * mean_body, 0.8 * atr_v);
         bool big_imp = (body_imp >= impulse_need);
         if(!big_imp || (!up_imp && !dn_imp))
            continue;

         bool is_supply = dn_imp;
         // 评分
         double score = 0.0;

         // A. 离开强度 0~45
         double impulse_ratio = body_imp / mean_body;
         score += MathMin(35.0, (impulse_ratio / InpImpulseBodyFactor) * 35.0);
         // 连续动量加分
         int cont = 0;
         for(int p=imp-1; p>=MathMax(0, imp-3); p--)
         {
            if((is_supply && close[p] < open[p]) || (!is_supply && close[p] > open[p]))
               cont++;
         }
         score += MathMin(10.0, cont * 5.0);

         // B. Base干净度 0~15
         double compact = 1.0 - MathMin(1.0, base_range / (2.0 * atr_v));
         score += compact * 15.0;

         // C. 新鲜度 0~15, 噪音惩罚 0~-10
         int retests = 0;
         int noise_breaks = 0;
         bool invalid = false;
         double break_buf = atr_v * InpBreakBufferATR;

         for(int p=imp-1; p>=0; p--)
         {
            bool hit = IntersectsZone(low[p], high[p], b_low, b_top);
            if(hit)
               retests++;

            if(is_supply)
            {
               if(close[p] > (b_top + break_buf))
               {
                  invalid = true;
                  break;
               }
               if(high[p] > b_top && close[p] <= b_top)
                  noise_breaks++;
            }
            else
            {
               if(close[p] < (b_low - break_buf))
               {
                  invalid = true;
                  break;
               }
               if(low[p] < b_low && close[p] >= b_low)
                  noise_breaks++;
            }
         }

         if(retests == 0) score += 15.0;
         else if(retests == 1) score += 10.0;
         else if(retests == 2) score += 5.0;

         score -= MathMin(10.0, noise_breaks * 2.0);

         // D. 结构位置 0~15（简单版：靠近强S/R加分）
         double center = (b_top + b_low) * 0.5;
         int best_touch = 0;
         for(int m=0; m<ArraySize(sr_list); m++)
         {
            double sr_center = (sr_list[m].top + sr_list[m].bottom) * 0.5;
            if(MathAbs(center - sr_center) <= atr_v * 0.5)
               best_touch = MathMax(best_touch, sr_list[m].touches);
         }
         score += MathMin(15.0, best_touch * 2.0);

         score = ClampScore(score);

         if(score < InpMinQualityScore)
            continue;

         int nz = ArraySize(zones);
         ArrayResize(zones, nz+1);
         zones[nz].is_supply = is_supply;
         zones[nz].top = b_top;
         zones[nz].bottom = b_low;
         zones[nz].base_start_shift = start;
         zones[nz].base_len = base_len;
         zones[nz].impulse_shift = imp;
         zones[nz].score = score;
         zones[nz].retests = retests;
         zones[nz].invalid = invalid;
      }
   }

   // 简单去重：同类型且中心接近时保留分高者
   for(int i=0; i<ArraySize(zones); i++)
   {
      if(zones[i].score < 0.0)
         continue;
      double ci = (zones[i].top + zones[i].bottom) * 0.5;
      for(int j=i+1; j<ArraySize(zones); j++)
      {
         if(zones[j].score < 0.0) continue;
         if(zones[i].is_supply != zones[j].is_supply) continue;
         double cj = (zones[j].top + zones[j].bottom) * 0.5;
         double tol = atr[MathMax(zones[i].impulse_shift, zones[j].impulse_shift)] * InpSRMergeATR;
         if(MathAbs(ci - cj) <= tol)
         {
            if(zones[i].score >= zones[j].score) zones[j].score = -1.0;
            else zones[i].score = -1.0;
         }
      }
   }

   // 按分数选择绘制
   int draw_z = 0;
   for(int step=0; step<InpMaxDrawZones; step++)
   {
      int best = -1;
      double best_score = -1.0;
      for(int i=0; i<ArraySize(zones); i++)
      {
         if(zones[i].score > best_score)
         {
            best_score = zones[i].score;
            best = i;
         }
      }
      if(best < 0 || best_score < 0.0)
         break;

      DrawZone(zones[best], draw_z, time);

      // 激进触发 + 首次回踩
      if(InpAggressiveEntry && !zones[best].invalid)
      {
         bool hit_now = IntersectsZone(low[0], high[0], zones[best].bottom, zones[best].top);
         bool hit_prev = IntersectsZone(low[1], high[1], zones[best].bottom, zones[best].top);
         bool first_ok = (!InpFirstRetestOnly || zones[best].retests <= 1);
         if(hit_now && !hit_prev && first_ok)
         {
            double p = zones[best].is_supply ? high[0] : low[0];
            DrawSignalArrow(zones[best].is_supply, p, time[0]);
         }
      }

      zones[best].score = -1.0;
      draw_z++;
   }

   if(InpDebugShowStats)
   {
      string dbg = ObjName("DBG", 1);
      if(ObjectCreate(0, dbg, OBJ_LABEL, 0, 0, 0))
      {
         string text = StringFormat("SD/SR %s Scan=%d  SR=%d  Zones=%d DistFilter=%s",
                                    EnumToString(_Period),
                                    scan,
                                    draw_sr,
                                    draw_z,
                                    (InpFilterSRByDistance ? "ON" : "OFF"));
         ObjectSetString(0, dbg, OBJPROP_TEXT, text);
         ObjectSetInteger(0, dbg, OBJPROP_COLOR, clrWhite);
         ObjectSetInteger(0, dbg, OBJPROP_FONTSIZE, 9);
         ObjectSetInteger(0, dbg, OBJPROP_CORNER, CORNER_LEFT_UPPER);
         ObjectSetInteger(0, dbg, OBJPROP_XDISTANCE, 10);
         ObjectSetInteger(0, dbg, OBJPROP_YDISTANCE, 20);
      }
   }

   return rates_total;
}
