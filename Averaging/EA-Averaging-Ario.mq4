//+-------------------------------------------------------------------------+
//|                                                      Ario Averaging.mq4 |
//|                                            Copyright 2020, Ario Gunawan |
//|                                             https://www.ariogunawan.com |
//+-------------------------------------------------------------------------+
#define VERSION "1.7" // always update this one upon modification
/*

TODO:
* Max Layers to be determined by:
- Risk Percentage
- Dollar Amount

IN PROGRESS:
* Simple Auto Trade for backtesting
- Crossing MA & Price under/over MA

DONE:
* Definition of 1 dollar:
- Calculate based on Price, Points, Digits, Leverage
- EURUSD is the simplest, USDJPY is medium, EURCHF is the hardest, need to pull conversion rate from external API
* Validating stopl level before deciding price to enter the order (to avoid ERROR 130)
* Create function to pull all debugging information
* Create dynamic magic number
* Emergency Switch:
- Place a Pending Order: BUY STOP with Price > 50% of the current Price
- For example current Price = 1.23456, then place a BUY STOP at 2.0000
- It will then CLOSE ALL orders
* Alternate Orders Mode: Set buy & sell alternatively to halve the risk
* Allow any currency for trading, at the moment EA only works on the applied chart
* Minor modification of inputs labelling
* MAJOR BUG FIXED!! Switched BUY STOP & BUY LIMIT, SELL STOP & SELL LIMIT
* Cut Loss Switch
- Close all - based on loss dollar amount
- Close all - based on loss percentage
* When to TP:
- Based on dollar amount
- Based on growth percentage
* Basic shit & stuff

*/
#property copyright "Copyright 2020, Ario Gunawan"
#property link      "https://www.ariogunawan.com"
#property version   VERSION
#property strict
// -- ENUM parameters
enum ENUM_SET_CUT_LOSS_TAKE_PROFIT
  {
   None = 0,//Disable
   Percentage = 1,//Remaining Balance (Percentage)
   Amount = 2//Remaining Balance (Dollar Amount)
  };
enum ENUM_SET_LAYERS
  {
   Manual = 0,//Manual - Based on input: Maximum number of layers
   Automatic = 1//Automatic - Based on Account Balance
  };
// -- input parameters
sinput string separator1 = "*******************************";//======[ BASIC SETTINGS ]=======
input bool AlternateOrdersMode = false;//Open new layers alternatively on buy and sell
input int FirstStepInPips = 50;//First step in pips
input int NextStepInPips = 20;//Next step in pips
input int MaxSlippage = 5;//Maximum slippage tolerant in pips
input int MaxNumberOfOrders = 11;//Maximum number of layers (pending orders)
sinput string separator2 = "*******************************";//======[ CUT LOSS SETTINGS ]======
input ENUM_SET_CUT_LOSS_TAKE_PROFIT CutLossMode = None;//Cut Loss Mode
input double CutLossPercent = 20;//Cut loss when balance shrinks to this percentage(%)
input double CutLossAmount = 400;//Cut loss when balance shrinks to this amount($)
sinput string separator3 = "*******************************";//======[ TAKE PROFIT SETTINGS ]======
input ENUM_SET_CUT_LOSS_TAKE_PROFIT TakeProfitMode = None;//Take Profit Mode
input double TakeProfitPercent = 20;//Take profit when balance grows by this percentage(%)
input double TakeProfitAmount = 400;//Take profit when balance grows by this amount($)
sinput string separator4 = "KALO JALAN GUA PINDAHIN KE ATAS";//======[ DIBAWAH INI BLOM JALAN SEMUA ]======
input ENUM_SET_LAYERS LayersMode = Manual;//Layers (Pending Orders) Mode
input double LayersBalancePercent = 20;//Open new layers up to this percentage of balance(%)
input double LayersBalanceAmount = 400;//Open new layers up to this balance amount($)

//--- struct initialization
struct DistanceInformation
  {
   int               order_no;
   int               rel_distance_pips;
   int               abs_distance_pips;
  };
struct TradeInformation
  {
   int               order_no;
   int               order_ticket_no;
   string            order_symbol;
   int               order_type;
   double            order_volume;
   double            order_price;
   double            order_sl;
   double            order_tp;
   int               order_magic_no;
   string            order_comment;
   double            order_next_price;
  };
struct EntryInformation
  {
   int               entry_ticket_no;
   string            entry_symbol;
   int               entry_order_type;
   double            entry_volume;
   double            entry_price;
   int               entry_slippage;
   double            entry_stop_loss;
   double            entry_take_profit;
   string            entry_comment;
   int               entry_magic_no;
   datetime          entry_expiration;
   color             entry_color;
  };

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
  {
//---
   string message = WindowExpertName() + " " + VERSION + " - Started";
//SendNotification(message);
//---
   return(INIT_SUCCEEDED);
  }
//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
  {
   string message = WindowExpertName() + " " + VERSION + " - Shutdown";
//SendNotification(message);

//---

  }
//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
  {
//---

// 1. Initialize variables
   int number_of_orders = 0;
   DistanceInformation starr_distance_information[];
   ZeroMemory(starr_distance_information);
   TradeInformation starr_trade_information[];
   ZeroMemory(starr_trade_information);

// 2. Get Number of Orders
   number_of_orders = getMaxNumberOfOrders();
   ArrayResize(starr_distance_information,number_of_orders,5);
   ArrayResize(starr_trade_information,OrdersTotal(),5);

// 3. Set Distance Information
   setDistanceInformation(starr_distance_information, number_of_orders);

// 4. Get Trades Information
   getTradesInformation(starr_trade_information);

// 5. Set Pending Orders
   setAveragingOrders(starr_trade_information, number_of_orders);

// 6. Check for TP
   setTakeProfitMode();

// 7. Check for Cutloss
   setCutLossMode();

// 8. Set for Autotrade

// 9. Check for emergency switch
   getEmergencySwitch();

// 99. Show information
   getInformation();

  }

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
void getEmergencySwitch()
  {
   bool res;
   for(int i = OrdersTotal()-1; i >= 0; i--)
     {
      res = OrderSelect(i, SELECT_BY_POS, MODE_TRADES);
      if(res)
        {
         double price_diff_percent = 0;
         price_diff_percent = MathAbs((OrderOpenPrice() - MarketInfo(OrderSymbol(), MODE_ASK))/MarketInfo(OrderSymbol(), MODE_ASK) * 100);
         if(OrderType() == OP_BUYSTOP && price_diff_percent > 50)
            setCloseAllOrders();
        }

     }
  }
//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
void setTakeProfitMode()
  {
   RefreshRates();
   bool is_profitable = false;
   if(TakeProfitMode > 0)
     {
      if(TakeProfitMode == Percentage)
         is_profitable = (AccountProfit()/AccountBalance()*100 > TakeProfitPercent) ? true : false;
      else
         if(TakeProfitMode == Amount)
            is_profitable = (AccountProfit() > 0 && MathAbs(AccountProfit()) > TakeProfitAmount) ? true : false;
     }
   if(is_profitable == true)
     {
      Print("Profit/Loss = ", AccountProfit());
      setCloseAllOrders();
      Sleep(10000);
     }
  }
//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
void setCutLossMode()
  {
   RefreshRates();
   bool is_margin_breached = false;
   if(CutLossMode > 0)
     {
      if(CutLossMode == Percentage)
         is_margin_breached = (AccountProfit()/AccountBalance()*100 < -CutLossPercent) ? true : false;
      else
         if(CutLossMode == Amount)
            is_margin_breached = (AccountProfit() < 0 && MathAbs(AccountProfit()) > CutLossAmount) ? true : false;
     }
   if(is_margin_breached == true)
     {
      Print("Profit/Loss = ", AccountProfit());
      setCloseAllOrders();
      Sleep(10000);
     }
  }
//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
void getTradesInformation(TradeInformation& starr_trade_information[])
  {
   bool res;
   int negative = 0, alt_negative = 0;
   for(int i = 0; i < OrdersTotal(); i++)
     {
      res = OrderSelect(i, SELECT_BY_POS, MODE_TRADES);
      negative = (OrderType() == 0 || OrderType() == 2 || OrderType() == 4) ? -1 : 1;
      if(res)
        {
         starr_trade_information[i].order_no = i+1;
         starr_trade_information[i].order_ticket_no = OrderTicket();
         starr_trade_information[i].order_symbol = OrderSymbol();
         starr_trade_information[i].order_type = OrderType();
         starr_trade_information[i].order_volume = OrderLots();
         starr_trade_information[i].order_price = OrderOpenPrice();
         starr_trade_information[i].order_sl = OrderStopLoss();
         starr_trade_information[i].order_tp = OrderTakeProfit();
         starr_trade_information[i].order_magic_no = OrderMagicNumber();
         starr_trade_information[i].order_comment = OrderComment();
         // if first order
         if(OrderComment() == "" && OrderMagicNumber() == 0 && OrderOpenPrice() > 0)
            starr_trade_information[i].order_next_price = starr_trade_information[i].order_price + negative * NormalizeDouble(FirstStepInPips * Point, Digits);
         else
           {
            if(AlternateOrdersMode)
              {
               if(i % 2 == 0)
                  alt_negative = -negative;
               else
                  alt_negative = negative;
               starr_trade_information[i].order_next_price = starr_trade_information[i].order_price + alt_negative * NormalizeDouble(NextStepInPips * Point, Digits);
              }
            else
               starr_trade_information[i].order_next_price = starr_trade_information[i].order_price + negative * NormalizeDouble(NextStepInPips * Point, Digits);
           }
        }
     }
  }
//+------------------------------------------------------------------+
void setAveragingOrders(TradeInformation& starr_trade_information[], int number_of_orders)
  {
   if(OrdersTotal() > 0 && OrdersTotal() < number_of_orders)
      setPendingOrders(starr_trade_information, number_of_orders);
  }

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
void setPendingOrders(TradeInformation& starr_trade_information[], int number_of_orders)
  {
   EntryInformation entry_information;
   int i = OrdersTotal();
   int cmd = -1;
   bool buy = (starr_trade_information[i-1].order_type == OP_BUY || starr_trade_information[i-1].order_type == OP_BUYLIMIT || starr_trade_information[i-1].order_type == OP_BUYSTOP) ? true : false;
   if(AlternateOrdersMode)
     {
      if(starr_trade_information[i-1].order_type == OP_BUY || starr_trade_information[i-1].order_type == OP_SELLSTOP)
         cmd = OP_BUYLIMIT;
      else
         if(starr_trade_information[i-1].order_type == OP_SELL || starr_trade_information[i-1].order_type == OP_BUYSTOP)
            cmd = OP_SELLLIMIT;
         else
            if(starr_trade_information[i-1].order_type == OP_BUYLIMIT)
               cmd = OP_SELLSTOP;
            else
               if(starr_trade_information[i-1].order_type == OP_SELLLIMIT)
                  cmd = OP_BUYSTOP;
     }
   else
      cmd = (buy == true) ? OP_BUYLIMIT:OP_SELLLIMIT;
//Build entry information
   entry_information.entry_symbol = starr_trade_information[i-1].order_symbol;
   entry_information.entry_order_type = cmd;
   entry_information.entry_volume = starr_trade_information[i-1].order_volume;
//Stop Level Validations
   double ask_bid_price = (buy == true) ? MarketInfo(entry_information.entry_symbol, MODE_ASK):MarketInfo(entry_information.entry_symbol, MODE_BID);
   double stop_level = MarketInfo(entry_information.entry_symbol, MODE_STOPLEVEL);
   entry_information.entry_price = starr_trade_information[i-1].order_next_price;
   if(buy && MathAbs(entry_information.entry_price - ask_bid_price) < stop_level)
      entry_information.entry_price -= stop_level;
   else
      if(!buy && MathAbs(entry_information.entry_price - ask_bid_price) < stop_level)
         entry_information.entry_price += stop_level;
      else
         entry_information.entry_price = starr_trade_information[i-1].order_next_price;
//-
   entry_information.entry_slippage = MaxSlippage;
   entry_information.entry_stop_loss = 0;
   entry_information.entry_take_profit = 0;
   entry_information.entry_comment = "Next Order";
   entry_information.entry_magic_no = setMagicNumber(entry_information.entry_symbol, entry_information.entry_order_type);
   entry_information.entry_expiration = 0;
   entry_information.entry_color = (entry_information.entry_order_type % 2 == 1) ? clrRed:clrGreen;
//-
   if(OrdersTotal() > 0)
     {
      entry_information.entry_ticket_no = OrderSend(entry_information.entry_symbol, entry_information.entry_order_type, entry_information.entry_volume, entry_information.entry_price, entry_information.entry_slippage, entry_information.entry_stop_loss, entry_information.entry_take_profit, entry_information.entry_comment, entry_information.entry_magic_no, entry_information.entry_expiration, entry_information.entry_color);
      if(entry_information.entry_ticket_no < 0)
         getDebugInformation("FAILED", entry_information, GetLastError());
      else
         getDebugInformation("SUCCESS", entry_information, GetLastError());
     }
  }
//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
void getDebugInformation(string message, EntryInformation& entry_information, int get_last_error)
  {
   string full_debug_message;
   full_debug_message = "[DEBUG]: "+ message+ " | Ticket No = "+ IntegerToString(entry_information.entry_ticket_no)+ " | "+
                        "Currency = "+ entry_information.entry_symbol+ " | "+
                        "Lots = "+ DoubleToString(entry_information.entry_volume)+ " | "+
                        "Price = "+ DoubleToString(entry_information.entry_price)+ " | "+
                        "SL Pos = "+ DoubleToString(entry_information.entry_stop_loss)+ " | "+
                        "TP Pos = "+ DoubleToString(entry_information.entry_take_profit)+ " | "+
                        "SL Points = "+ DoubleToString(NormalizeDouble(MathAbs((entry_information.entry_price-entry_information.entry_stop_loss)/MarketInfo(entry_information.entry_symbol, MODE_POINT)), 0))+ " | "+
                        "TP Points = "+ DoubleToString(NormalizeDouble(MathAbs((entry_information.entry_price-entry_information.entry_take_profit)/MarketInfo(entry_information.entry_symbol, MODE_POINT)), 0))+ " | "+
                        "Spread Points = "+ DoubleToString(MarketInfo(entry_information.entry_symbol, MODE_SPREAD))+ " | "+
                        "Stop Level Points = "+ DoubleToString(MarketInfo(entry_information.entry_symbol, MODE_STOPLEVEL))+ " | "+
                        "Error No = "+ IntegerToString(get_last_error);
   Print(full_debug_message);
  }
//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
int getMaxNumberOfOrders()
  {
   if(LayersMode == Manual)
      return MaxNumberOfOrders;
   else
     {
      /* PLACEHOLDER - Set logic to count max number of orders based on balance */
      return MaxNumberOfOrders;
     }
  }
//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
void setDistanceInformation(DistanceInformation& starr_distance_information[], int number_of_orders)
  {
   for(int i = 0; i< number_of_orders; i++)
     {
      if(i == 0)
        {
         starr_distance_information[i].order_no = 1;
         starr_distance_information[i].rel_distance_pips = 0;
         starr_distance_information[i].abs_distance_pips = 0;
        }
      else
         if(i == 1)
           {
            starr_distance_information[i].order_no = 2;
            starr_distance_information[i].rel_distance_pips = FirstStepInPips;
            starr_distance_information[i].abs_distance_pips = FirstStepInPips;
           }
         else
           {
            starr_distance_information[i].order_no = i + 1;
            starr_distance_information[i].rel_distance_pips = starr_distance_information[i-1].rel_distance_pips + NextStepInPips;
            starr_distance_information[i].abs_distance_pips = starr_distance_information[i].rel_distance_pips + starr_distance_information[i-1].abs_distance_pips;
           }
     }
  }

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
void getInformation()
  {
   ENUM_ACCOUNT_TRADE_MODE account_type=(ENUM_ACCOUNT_TRADE_MODE)AccountInfoInteger(ACCOUNT_TRADE_MODE);
   string trade_mode;
   switch(account_type)
     {
      case  ACCOUNT_TRADE_MODE_DEMO:
         trade_mode="demo";
         break;
      case  ACCOUNT_TRADE_MODE_CONTEST:
         trade_mode="contest";
         break;
      default:
         trade_mode="real";
         break;
     }
   long login=AccountInfoInteger(ACCOUNT_LOGIN);

   Comment("\n\n", WindowExpertName(), " ", VERSION, ""+
           "\n", "Account (", trade_mode, ") No: ", login, ""+
           "\n", "-------------------------------------------", ""+
           "");
  }
//+------------------------------------------------------------------+
void setCloseAllOrders()
  {
   int is_order_closed = 0;
   for(int i = OrdersTotal()-1; i>=0; i--)
     {
      is_order_closed = 0;
      RefreshRates();
      if(OrderSelect(i, SELECT_BY_POS, MODE_TRADES))
         if(OrderType() == OP_BUY)
           {
            is_order_closed = OrderClose(OrderTicket(), OrderLots(), MarketInfo(OrderSymbol(), MODE_BID), MaxSlippage, clrNONE);
            if(is_order_closed < 0)
               Print("[DEBUG] - Error in closing BUY order, error no: ", GetLastError(), " | Ticket: ", OrderTicket());
            else
               Print("[DEBUG] - Closing BUY order, ticket no: ", OrderTicket());
           }
         else
            if(OrderType() == OP_SELL)
              {
               is_order_closed = OrderClose(OrderTicket(), OrderLots(), MarketInfo(OrderSymbol(), MODE_ASK), MaxSlippage, clrNONE);
               if(is_order_closed < 0)
                  Print("[DEBUG] - Error in closing SELL order, error no: ", GetLastError(), " | Ticket: ", OrderTicket());
               else
                  Print("[DEBUG] - Closing SELL order, ticket no: ", OrderTicket());
              }
            else
               if(OrderType()== OP_BUYLIMIT || OrderType()== OP_BUYSTOP || OrderType()== OP_SELLLIMIT || OrderType()== OP_SELLSTOP)
                 {
                  is_order_closed = OrderDelete(OrderTicket(), clrNONE);
                  if(is_order_closed < 0)
                     Print("[DEBUG] - Error in deleting pending order, error no: ", GetLastError(), " | Ticket: ", OrderTicket());
                  else
                     Print("[DEBUG] - Deleting pending order, ticket no: ", OrderTicket());
                 }
     }
  }
//+------------------------------------------------------------------+
int setMagicNumber(string pair, int op_type)
  {
   int weight = 0;
   string whole_weight;
   for(int i = 0; i<StringLen(pair); i++)
      weight = weight + StringGetChar(pair, i);
   whole_weight = IntegerToString(weight) + IntegerToString(op_type);
   return (int) whole_weight;
  }
//+------------------------------------------------------------------+
double getOnePipPerLotValue(string pair="")
  {
   if(pair == "")
      pair = Symbol();
   int multiply_ten = ((int)MarketInfo(pair, MODE_DIGITS) % 2 == 1) ? 10:1;
   return getOnePointPerLotValue(pair) * multiply_ten;
  }
//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
double getOnePointPerLotValue(string pair="")
  {
   if(pair == "")
      pair = Symbol();
   return MarketInfo(pair, MODE_TICKVALUE)/MarketInfo(pair, MODE_TICKSIZE) * MarketInfo(pair, MODE_POINT);
  }
