#property strict
#property version   "1.00"
#property description "Manual grid EA with left dashboard, X trigger start, and TP line close"

#include <Trade/Trade.mqh>

input long   InpMagicNumber            = 20260331;
input double InpBaseLot                = 0.01;
input int    InpGridStepPoints         = 285;
input int    InpMaxOrders              = 20;
input double InpMaxLotPerOrder         = 0.10;
input bool   InpUseLotExponential      = true;
input double InpLotFactor              = 1.20;
input bool   InpUseProfitTarget        = true;
input double InpProfitTargetPct        = 30.0;
input bool   InpUseDrawdownStopAdd     = false;
input double InpDrawdownStopAddPct     = 30.0;
input int    InpSlippagePoints         = 30;
input bool   InpUseTpLineOnStart       = false;
input int    InpDefaultTolerancePoints = 10;
input int    InpMinTolerancePoints     = 5;
input int    InpMaxTolerancePoints     = 25;

enum CycleState
{
   STATE_IDLE = 0,
   STATE_RUNNING_BUY = 1,
   STATE_RUNNING_SELL = 2,
   STATE_ARMED_BUY = 3,
   STATE_ARMED_SELL = 4
};

CTrade g_trade;
CycleState g_state = STATE_IDLE;
double g_start_equity = 0.0;
double g_cycle_realized = 0.0;
datetime g_cycle_started_at = 0;

double g_trigger_price = 0.0;
int    g_trigger_tolerance_points = 10;

double g_last_open_price = 0.0;
bool   g_allow_add = true;

string PREFIX = "MGD_";
string TP_LINE_NAME = "MGD_TP_LINE";

//---------------- UI helpers ----------------
void CreateButton(const string name, const string text, int x, int y, int w=118, int h=20)
{
   if(ObjectFind(0, name) < 0)
      ObjectCreate(0, name, OBJ_BUTTON, 0, 0, 0);

   ObjectSetInteger(0, name, OBJPROP_XDISTANCE, x);
   ObjectSetInteger(0, name, OBJPROP_YDISTANCE, y);
   ObjectSetInteger(0, name, OBJPROP_XSIZE, w);
   ObjectSetInteger(0, name, OBJPROP_YSIZE, h);
   ObjectSetInteger(0, name, OBJPROP_CORNER, CORNER_LEFT_UPPER);
   ObjectSetInteger(0, name, OBJPROP_BGCOLOR, clrGainsboro);
   ObjectSetInteger(0, name, OBJPROP_COLOR, clrBlack);
   ObjectSetString(0, name, OBJPROP_TEXT, text);
   ObjectSetInteger(0, name, OBJPROP_HIDDEN, false);
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
}

void CreateLabel(const string name, const string text, int x, int y, int size=9, color clr=clrWhite)
{
   if(ObjectFind(0, name) < 0)
      ObjectCreate(0, name, OBJ_LABEL, 0, 0, 0);

   ObjectSetInteger(0, name, OBJPROP_XDISTANCE, x);
   ObjectSetInteger(0, name, OBJPROP_YDISTANCE, y);
   ObjectSetInteger(0, name, OBJPROP_CORNER, CORNER_LEFT_UPPER);
   ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
   ObjectSetInteger(0, name, OBJPROP_FONTSIZE, size);
   ObjectSetString(0, name, OBJPROP_FONT, "Consolas");
   ObjectSetString(0, name, OBJPROP_TEXT, text);
   ObjectSetInteger(0, name, OBJPROP_HIDDEN, false);
}

void CreateEdit(const string name, const string text, int x, int y, int w=118, int h=20)
{
   if(ObjectFind(0, name) < 0)
      ObjectCreate(0, name, OBJ_EDIT, 0, 0, 0);

   ObjectSetInteger(0, name, OBJPROP_XDISTANCE, x);
   ObjectSetInteger(0, name, OBJPROP_YDISTANCE, y);
   ObjectSetInteger(0, name, OBJPROP_XSIZE, w);
   ObjectSetInteger(0, name, OBJPROP_YSIZE, h);
   ObjectSetInteger(0, name, OBJPROP_CORNER, CORNER_LEFT_UPPER);
   ObjectSetInteger(0, name, OBJPROP_COLOR, clrBlack);
   ObjectSetInteger(0, name, OBJPROP_BGCOLOR, clrWhite);
   ObjectSetString(0, name, OBJPROP_TEXT, text);
   ObjectSetInteger(0, name, OBJPROP_HIDDEN, false);
}

void BuildDashboard()
{
   int x=10, y=15;
   CreateLabel(PREFIX+"title", "Manual Grid Dashboard (MT5)", x, y, 10, clrAqua); y += 22;

   CreateButton(PREFIX+"start_buy", "Start BUY Now", x, y); y += 24;
   CreateButton(PREFIX+"start_sell", "Start SELL Now", x, y); y += 24;
   CreateButton(PREFIX+"arm_buy", "Place BUY @X", x, y); y += 24;
   CreateButton(PREFIX+"arm_sell", "Place SELL @X", x, y); y += 24;
   CreateLabel(PREFIX+"hint_arm", "Arm=place pending at X", x, y, 8, clrSilver); y += 20;

   CreateLabel(PREFIX+"lbl_x", "Trigger X", x, y, 9, clrWhite);
   CreateEdit(PREFIX+"x", DoubleToString(SymbolInfoDouble(_Symbol, SYMBOL_BID), _Digits), x+70, y-3, 80, 20); y += 24;

   CreateLabel(PREFIX+"lbl_tol", "Tol(points)", x, y, 9, clrWhite);
   CreateEdit(PREFIX+"tol", IntegerToString(InpDefaultTolerancePoints), x+70, y-3, 80, 20); y += 24;

   CreateButton(PREFIX+"tp_on", "TP Line ON", x, y); y += 24;
   CreateButton(PREFIX+"tp_off", "TP Line OFF", x, y); y += 24;
   CreateButton(PREFIX+"stop_add", "Stop Add", x, y); y += 24;
   CreateButton(PREFIX+"close_all", "Close All", x, y); y += 24;
   CreateButton(PREFIX+"reset", "Reset Cycle", x, y); y += 26;

   CreateLabel(PREFIX+"stats", "", x, y, 9, clrYellow);
}

void RemoveDashboard()
{
   string names[] = {
      PREFIX+"title",PREFIX+"start_buy",PREFIX+"start_sell",PREFIX+"arm_buy",PREFIX+"arm_sell",
      PREFIX+"hint_arm",
      PREFIX+"lbl_x",PREFIX+"x",PREFIX+"lbl_tol",PREFIX+"tol",PREFIX+"tp_on",PREFIX+"tp_off",
      PREFIX+"stop_add",PREFIX+"close_all",PREFIX+"reset",PREFIX+"stats"
   };
   for(int i=0;i<ArraySize(names);i++)
      ObjectDelete(0, names[i]);
}

//---------------- trading helpers ----------------
int CountPositions(double &total_lot, double &floating_pnl)
{
   total_lot = 0.0;
   floating_pnl = 0.0;
   int count = 0;

   for(int i=PositionsTotal()-1;i>=0;i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0 || !PositionSelectByTicket(ticket))
         continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol)
         continue;
      if((long)PositionGetInteger(POSITION_MAGIC) != InpMagicNumber)
         continue;

      count++;
      total_lot += PositionGetDouble(POSITION_VOLUME);
      floating_pnl += PositionGetDouble(POSITION_PROFIT);
   }
   return count;
}

bool CloseAllPositions()
{
   bool ok = true;
   for(int i=PositionsTotal()-1;i>=0;i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0 || !PositionSelectByTicket(ticket))
         continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol)
         continue;
      if((long)PositionGetInteger(POSITION_MAGIC) != InpMagicNumber)
         continue;

      if(!g_trade.PositionClose(ticket, InpSlippagePoints))
         ok = false;
   }
   return ok;
}

bool OpenOrder(ENUM_ORDER_TYPE type, double lots)
{
   g_trade.SetExpertMagicNumber(InpMagicNumber);
   g_trade.SetDeviationInPoints(InpSlippagePoints);
   lots = MathMin(lots, InpMaxLotPerOrder);

   bool result = false;
   if(type == ORDER_TYPE_BUY)
      result = g_trade.Buy(lots, _Symbol, 0.0, 0.0, 0.0, "MGD");
   else if(type == ORDER_TYPE_SELL)
      result = g_trade.Sell(lots, _Symbol, 0.0, 0.0, 0.0, "MGD");

   if(result)
   {
      if(type == ORDER_TYPE_BUY)
         g_last_open_price = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
      else
         g_last_open_price = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   }
   return result;
}

double CalculateNextLot(const int existing_positions)
{
   double lot = InpBaseLot;
   if(InpUseLotExponential)
      lot = InpBaseLot * MathPow(InpLotFactor, existing_positions);
   lot = MathMin(lot, InpMaxLotPerOrder);

   double min_lot  = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double max_lot  = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   double lot_step = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   if(lot_step <= 0.0) lot_step = 0.01;

   lot = MathMax(lot, min_lot);
   lot = MathMin(lot, max_lot);
   lot = MathFloor(lot / lot_step) * lot_step;
   lot = NormalizeDouble(lot, 2);
   return lot;
}

int CountPendingOrders()
{
   int count = 0;
   for(int i=OrdersTotal()-1;i>=0;i--)
   {
      ulong ticket = OrderGetTicket(i);
      if(ticket == 0 || !OrderSelect(ticket))
         continue;
      if(OrderGetString(ORDER_SYMBOL) != _Symbol)
         continue;
      if((long)OrderGetInteger(ORDER_MAGIC) != InpMagicNumber)
         continue;

      ENUM_ORDER_TYPE t = (ENUM_ORDER_TYPE)OrderGetInteger(ORDER_TYPE);
      if(t == ORDER_TYPE_BUY_LIMIT || t == ORDER_TYPE_BUY_STOP || t == ORDER_TYPE_SELL_LIMIT || t == ORDER_TYPE_SELL_STOP)
         count++;
   }
   return count;
}

void CancelAllPendingOrders()
{
   for(int i=OrdersTotal()-1;i>=0;i--)
   {
      ulong ticket = OrderGetTicket(i);
      if(ticket == 0 || !OrderSelect(ticket))
         continue;
      if(OrderGetString(ORDER_SYMBOL) != _Symbol)
         continue;
      if((long)OrderGetInteger(ORDER_MAGIC) != InpMagicNumber)
         continue;

      ENUM_ORDER_TYPE t = (ENUM_ORDER_TYPE)OrderGetInteger(ORDER_TYPE);
      if(t == ORDER_TYPE_BUY_LIMIT || t == ORDER_TYPE_BUY_STOP || t == ORDER_TYPE_SELL_LIMIT || t == ORDER_TYPE_SELL_STOP)
         g_trade.OrderDelete(ticket);
   }
}

void StartCycle(const bool is_buy)
{
   g_cycle_realized = 0.0;
   g_start_equity = AccountInfoDouble(ACCOUNT_EQUITY);
   g_cycle_started_at = TimeCurrent();
   g_allow_add = true;
   g_state = is_buy ? STATE_RUNNING_BUY : STATE_RUNNING_SELL;
   CancelAllPendingOrders();
   OpenOrder(is_buy ? ORDER_TYPE_BUY : ORDER_TYPE_SELL, CalculateNextLot(0));
   if(g_last_open_price <= 0.0)
      Print("StartCycle failed to place first market order.");
}

void ArmCycle(const bool is_buy)
{
   string sx = ObjectGetString(0, PREFIX+"x", OBJPROP_TEXT);
   string stol = ObjectGetString(0, PREFIX+"tol", OBJPROP_TEXT);

   g_trigger_price = StringToDouble(sx);
   int t = (int)StringToInteger(stol);
   g_trigger_tolerance_points = (int)MathMax(InpMinTolerancePoints, MathMin(InpMaxTolerancePoints, t));

   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double price = NormalizeDouble(g_trigger_price, _Digits);
   double lots = CalculateNextLot(0);

   g_trade.SetExpertMagicNumber(InpMagicNumber);
   g_trade.SetDeviationInPoints(InpSlippagePoints);
   CancelAllPendingOrders();

   bool ok = false;
   if(is_buy)
   {
      if(price <= ask) ok = g_trade.BuyLimit(lots, price, _Symbol, 0.0, 0.0, ORDER_TIME_GTC, 0, "MGD_ARM_BUY");
      else             ok = g_trade.BuyStop(lots, price, _Symbol, 0.0, 0.0, ORDER_TIME_GTC, 0, "MGD_ARM_BUY");
   }
   else
   {
      if(price >= bid) ok = g_trade.SellLimit(lots, price, _Symbol, 0.0, 0.0, ORDER_TIME_GTC, 0, "MGD_ARM_SELL");
      else             ok = g_trade.SellStop(lots, price, _Symbol, 0.0, 0.0, ORDER_TIME_GTC, 0, "MGD_ARM_SELL");
   }

   if(ok)
   {
      g_state = is_buy ? STATE_ARMED_BUY : STATE_ARMED_SELL;
      g_cycle_realized = 0.0;
      g_start_equity = 0.0; // set when pending gets filled
      g_cycle_started_at = TimeCurrent();
      g_allow_add = true;
   }
   else
   {
      Print("ArmCycle failed to place pending order at X=", DoubleToString(price, _Digits),
            ". Check min distance/stops/filling mode. retcode=", g_trade.ResultRetcode(),
            " comment=", g_trade.ResultRetcodeDescription());
   }
}

void ResetCycleState()
{
   g_state = STATE_IDLE;
   g_trigger_price = 0.0;
   g_cycle_started_at = 0;
   g_start_equity = 0.0;
   g_cycle_realized = 0.0;
   g_last_open_price = 0.0;
   g_allow_add = true;
}

void EnsureTpLine(const bool create)
{
   if(create)
   {
      if(ObjectFind(0, TP_LINE_NAME) < 0)
      {
         double mid = (SymbolInfoDouble(_Symbol, SYMBOL_BID) + SymbolInfoDouble(_Symbol, SYMBOL_ASK))/2.0;
         ObjectCreate(0, TP_LINE_NAME, OBJ_HLINE, 0, 0, mid);
      }
      ObjectSetInteger(0, TP_LINE_NAME, OBJPROP_COLOR, clrRed);
      ObjectSetInteger(0, TP_LINE_NAME, OBJPROP_WIDTH, 2);
      ObjectSetInteger(0, TP_LINE_NAME, OBJPROP_SELECTABLE, true);
      ObjectSetInteger(0, TP_LINE_NAME, OBJPROP_HIDDEN, false);
      ObjectSetInteger(0, TP_LINE_NAME, OBJPROP_BACK, false);
      ObjectSetString(0, TP_LINE_NAME, OBJPROP_TEXT, "TP Line");
   }
   else
   {
      ObjectDelete(0, TP_LINE_NAME);
   }
}

void CheckArmedTrigger()
{
   if(g_state != STATE_ARMED_BUY && g_state != STATE_ARMED_SELL)
      return;

   double lots, floating;
   int pos_count = CountPositions(lots, floating);
   int pending_count = CountPendingOrders();

   if(pos_count > 0)
   {
      if(g_start_equity <= 0.0)
         g_start_equity = AccountInfoDouble(ACCOUNT_EQUITY);

      if(g_state == STATE_ARMED_BUY)
         g_state = STATE_RUNNING_BUY;
      else if(g_state == STATE_ARMED_SELL)
         g_state = STATE_RUNNING_SELL;

      // initialize last open price from current market side
      if(g_state == STATE_RUNNING_BUY)
         g_last_open_price = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
      else
         g_last_open_price = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   }
   else if(pending_count == 0)
   {
      // pending got removed manually
      ResetCycleState();
   }
}

void CheckGridAdd()
{
   if(g_state != STATE_RUNNING_BUY && g_state != STATE_RUNNING_SELL)
      return;
   if(!g_allow_add)
      return;

   double total_lot, floating;
   int count = CountPositions(total_lot, floating);
   if(count <= 0)
      return;
   if(count >= InpMaxOrders)
      return;

   double balance = AccountInfoDouble(ACCOUNT_BALANCE);
   double equity = AccountInfoDouble(ACCOUNT_EQUITY);
   double dd_pct = (balance > 0.0) ? ((balance - equity)/balance)*100.0 : 0.0;
   if(InpUseDrawdownStopAdd && dd_pct >= InpDrawdownStopAddPct)
      return;

   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double step = InpGridStepPoints * _Point;

   if(g_state == STATE_RUNNING_BUY)
   {
      if((g_last_open_price - bid) >= step)
         OpenOrder(ORDER_TYPE_BUY, CalculateNextLot(count));
   }
   else if(g_state == STATE_RUNNING_SELL)
   {
      if((ask - g_last_open_price) >= step)
         OpenOrder(ORDER_TYPE_SELL, CalculateNextLot(count));
   }
}

void CheckProfitTargetAndTpLine()
{
   if(g_state != STATE_RUNNING_BUY && g_state != STATE_RUNNING_SELL)
      return;

   double total_lot, floating;
   int count = CountPositions(total_lot, floating);
   if(count <= 0)
   {
      ResetCycleState();
      return;
   }

   if(InpUseProfitTarget && g_start_equity > 0.0)
   {
      double target = g_start_equity * (InpProfitTargetPct / 100.0);
      if(floating >= target)
      {
         if(CloseAllPositions())
            ResetCycleState();
         return;
      }
   }

   if(ObjectFind(0, TP_LINE_NAME) >= 0)
   {
      double line_price = ObjectGetDouble(0, TP_LINE_NAME, OBJPROP_PRICE);
      double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
      double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);

      bool hit = false;
      if(g_state == STATE_RUNNING_BUY && bid >= line_price)
         hit = true;
      if(g_state == STATE_RUNNING_SELL && ask <= line_price)
         hit = true;

      if(hit)
      {
         if(CloseAllPositions())
            ResetCycleState();
      }
   }
}

string StateToText()
{
   switch(g_state)
   {
      case STATE_IDLE: return "IDLE";
      case STATE_RUNNING_BUY: return "RUNNING_BUY";
      case STATE_RUNNING_SELL: return "RUNNING_SELL";
      case STATE_ARMED_BUY: return "PENDING_BUY_AT_X";
      case STATE_ARMED_SELL: return "PENDING_SELL_AT_X";
   }
   return "UNKNOWN";
}

void UpdateStats()
{
   double lots, floating;
   int count = CountPositions(lots, floating);
   int pending = CountPendingOrders();
   double target = (g_start_equity > 0.0) ? g_start_equity * (InpProfitTargetPct/100.0) : 0.0;
   double to_target = target - floating;
   if(to_target < 0) to_target = 0;

   double line_price = 0.0;
   if(ObjectFind(0, TP_LINE_NAME) >= 0)
      line_price = ObjectGetDouble(0, TP_LINE_NAME, OBJPROP_PRICE);

   string s = StringFormat(
      "State: %s\nAddEnabled: %s\nOpenOrders: %d/%d\nPending: %d\nLots: %.2f\nFloating: %.2f\nStartEquity: %.2f\nProfitTarget(%.1f%%): %.2f\nToTarget: %.2f\nLotMode: %s (factor=%.2f)\nTriggerX: %s (tol=%d)\nTPLine: %s",
      StateToText(), (g_allow_add ? "YES" : "NO"), count, InpMaxOrders, pending, lots, floating, g_start_equity, InpProfitTargetPct, target,
      to_target,
      (InpUseLotExponential ? "EXP" : "FIXED"), InpLotFactor,
      (g_trigger_price > 0 ? DoubleToString(g_trigger_price, _Digits) : "-"), g_trigger_tolerance_points,
      (line_price > 0 ? DoubleToString(line_price, _Digits) : "OFF")
   );

   ObjectSetString(0, PREFIX+"stats", OBJPROP_TEXT, s);
}

int OnInit()
{
   BuildDashboard();
   if(InpUseTpLineOnStart)
      EnsureTpLine(true);

   g_trigger_tolerance_points = InpDefaultTolerancePoints;
   return(INIT_SUCCEEDED);
}

void OnDeinit(const int reason)
{
   RemoveDashboard();
}

void OnTick()
{
   CheckArmedTrigger();
   CheckGridAdd();
   CheckProfitTargetAndTpLine();
   UpdateStats();
}

void OnChartEvent(const int id, const long &lparam, const double &dparam, const string &sparam)
{
   if(id != CHARTEVENT_OBJECT_CLICK)
      return;

   if(sparam == PREFIX+"start_buy")
      StartCycle(true);
   else if(sparam == PREFIX+"start_sell")
      StartCycle(false);
   else if(sparam == PREFIX+"arm_buy")
      ArmCycle(true);
   else if(sparam == PREFIX+"arm_sell")
      ArmCycle(false);
   else if(sparam == PREFIX+"tp_on")
      EnsureTpLine(true);
   else if(sparam == PREFIX+"tp_off")
      EnsureTpLine(false);
   else if(sparam == PREFIX+"stop_add")
   {
      g_allow_add = false;
   }
   else if(sparam == PREFIX+"close_all")
   {
      CancelAllPendingOrders();
      CloseAllPositions();
      ResetCycleState();
   }
   else if(sparam == PREFIX+"reset")
   {
      CancelAllPendingOrders();
      ResetCycleState();
   }
}
