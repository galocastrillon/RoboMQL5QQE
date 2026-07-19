#property copyright "RoboQQE"
#property version   "1.00"
#property strict

#include <Trade/Trade.mqh>

// El robot evalua exclusivamente velas cerradas; no abre operaciones dentro de una vela.
input ENUM_TIMEFRAMES InpTimeframe       = PERIOD_M5;
input bool            InpUsePercentRisk  = true;
input double          InpRiskPercent     = 1.0;
input double          InpFixedLots       = 0.01;
input ulong           InpMagicNumber     = 505200;
input int             InpMaxSignalLag    = 0;    // 0 = las tres condiciones en la misma vela; maximo recomendado: 1
input bool            InpUseFixedSL      = true;
input double          InpFixedSL_Pips    = 20.0;
input int             InpSwingLookback   = 5;
input bool            InpUseATRStops     = true;
input int             InpATRPeriod       = 14;
input double          InpATRStopMultiplier = 1.5;
input bool            InpUseTakeProfit   = false; // false: la salida en ganancia queda a decision del usuario/trailing
input double          InpRR_Ratio        = 1.5;   // Solo se utiliza si InpUseTakeProfit=true
input bool            InpUseTrailingStop = true;
input double          InpTrailingStartPips = 20.0; // Ganancia minima antes de proteger la posicion
input double          InpTrailingDistancePips = 15.0; // Distancia del SL respecto al precio actual
input double          InpTrailingStepPips = 1.0; // Movimiento minimo necesario para modificar el SL
input bool            InpUseATRTrailing  = true;
input double          InpTrailingStartATR = 1.0;
input double          InpTrailingDistanceATR = 1.5;
input bool            InpUseBreakEven    = true;
input double          InpBreakEvenAtR    = 1.0;
input double          InpBreakEvenOffsetPips = 0.0;
input int             InpMaxSpreadPoints = 20;
input double          InpDailyLossLimitPercent = 3.0;
input int             InpQQE_RSI_Period  = 14;
input int             InpQQE_SF          = 5;
input double          InpQQE_Factor      = 4.238;
input double          InpQQE_ExtLevel    = 20.0;
input int             InpQQE_LookbackTouched = 10;
input bool            InpCloseOnReverse  = true;
input int             InpDeviationPoints = 10;

input string InpQQEIndicator   = "RoboQQE\\QQE_Mod";
input string InpTrendIndicator = "RoboQQE\\Trend_Magic";
input string InpSSLIndicator   = "RoboQQE\\SSL_Hybrid_JMA";
input bool   InpShowIndicators = true; // Dibuja los 3 indicadores en el grafico al cargar el EA

CTrade trade;
int qqeHandle=INVALID_HANDLE, trendHandle=INVALID_HANDLE, sslHandle=INVALID_HANDLE, atrHandle=INVALID_HANDLE;
datetime lastProcessedBar=0;

enum Signal { SIGNAL_NONE=0, SIGNAL_BUY=1, SIGNAL_SELL=-1 };

int OnInit()
{
   if(InpFixedLots<=0 || InpRiskPercent<=0 || InpMaxSignalLag<0 || InpMaxSignalLag>2 || InpSwingLookback<1 || InpRR_Ratio<=0 || InpFixedSL_Pips<=0 || InpTrailingStartPips<0 || InpTrailingDistancePips<=0 || InpTrailingStepPips<=0 || InpQQE_RSI_Period<2 || InpQQE_SF<1 || InpQQE_Factor<=0 || InpQQE_ExtLevel<=0 || InpQQE_LookbackTouched<1)
      return(INIT_PARAMETERS_INCORRECT);
   qqeHandle=iCustom(_Symbol,InpTimeframe,InpQQEIndicator,InpQQE_RSI_Period,InpQQE_SF,InpQQE_Factor);
   trendHandle=iCustom(_Symbol,InpTimeframe,InpTrendIndicator,50,6,1.0);
   sslHandle=iCustom(_Symbol,InpTimeframe,InpSSLIndicator,200,0.0);
   atrHandle=iATR(_Symbol,InpTimeframe,InpATRPeriod);
   if(qqeHandle==INVALID_HANDLE || trendHandle==INVALID_HANDLE || sslHandle==INVALID_HANDLE || atrHandle==INVALID_HANDLE)
   {
      Print("No se pudieron cargar los indicadores. Instale los tres archivos en MQL5\\Indicators\\RoboQQE y compilelos.");
      return(INIT_FAILED);
   }
   trade.SetExpertMagicNumber(InpMagicNumber);
   trade.SetDeviationInPoints(InpDeviationPoints);

   if(InpShowIndicators && !MQLInfoInteger(MQL_OPTIMIZATION))
      ShowIndicatorsOnChart();
   return(INIT_SUCCEEDED);
}

// Adjunta un handle al grafico solo si aun no hay un indicador con ese nombre visible.
bool ChartHasIndicator(const long chartId,const string namePart)
{
   int windows=(int)ChartGetInteger(chartId,CHART_WINDOWS_TOTAL);
   for(int w=0;w<windows;w++)
   {
      int total=ChartIndicatorsTotal(chartId,w);
      for(int k=0;k<total;k++)
         if(StringFind(ChartIndicatorName(chartId,w,k),namePart)>=0) return(true);
   }
   return(false);
}

void ShowIndicatorsOnChart()
{
   long chartId=ChartID();
   if(trendHandle!=INVALID_HANDLE && !ChartHasIndicator(chartId,"Trend Magic"))
      ChartIndicatorAdd(chartId,0,trendHandle);
   if(sslHandle!=INVALID_HANDLE && !ChartHasIndicator(chartId,"SSL Hybrid"))
      ChartIndicatorAdd(chartId,0,sslHandle);
   // El QQE es un oscilador: va en su propia subventana (nuevo indice = total de ventanas actual).
   if(qqeHandle!=INVALID_HANDLE && !ChartHasIndicator(chartId,"QQE Mod"))
   {
      int sub=(int)ChartGetInteger(chartId,CHART_WINDOWS_TOTAL);
      ChartIndicatorAdd(chartId,sub,qqeHandle);
   }
   ChartRedraw(chartId);
}

void OnDeinit(const int reason)
{
   if(qqeHandle!=INVALID_HANDLE) IndicatorRelease(qqeHandle);
   if(trendHandle!=INVALID_HANDLE) IndicatorRelease(trendHandle);
   if(sslHandle!=INVALID_HANDLE) IndicatorRelease(sslHandle);
   if(atrHandle!=INVALID_HANDLE) IndicatorRelease(atrHandle);
}

bool IsNewClosedBar()
{
   datetime current=iTime(_Symbol,InpTimeframe,0);
   if(current==0 || current==lastProcessedBar) return(false);
   lastProcessedBar=current;
   return(true);
}

bool QQEVisitedExtreme(const int direction,const double &qqe[])
{
   // El cruce es shift 1; las velas que lo preceden comienzan en shift 2.
   int available=ArraySize(qqe);
   for(int shift=2; shift<=InpQQE_LookbackTouched+1 && shift<available; shift++)
   {
      if(direction==SIGNAL_BUY && qqe[shift]<=-InpQQE_ExtLevel) return(true);
      if(direction==SIGNAL_SELL && qqe[shift]>=InpQQE_ExtLevel) return(true);
   }
   return(false);
}

Signal GetSignal()
{
   int need=MathMax(InpQQE_LookbackTouched+3,8);
   double qqe[], trend[], ssl[];
   ArraySetAsSeries(qqe,true); ArraySetAsSeries(trend,true); ArraySetAsSeries(ssl,true);
   if(CopyBuffer(qqeHandle,0,0,need,qqe)!=need || CopyBuffer(trendHandle,2,0,need,trend)!=need || CopyBuffer(sslHandle,2,0,need,ssl)!=need)
      return(SIGNAL_NONE);
   bool crossUp=(qqe[1]>0.0 && qqe[2]<=0.0);
   bool crossDown=(qqe[1]<0.0 && qqe[2]>=0.0);
   if(!crossUp && !crossDown) return(SIGNAL_NONE);
   if(crossUp && !QQEVisitedExtreme(SIGNAL_BUY,qqe)) return(SIGNAL_NONE);
   if(crossDown && !QQEVisitedExtreme(SIGNAL_SELL,qqe)) return(SIGNAL_NONE);

   // El QQE es el gatillo. Tendencia y baseline pueden haber quedado alineados hasta N velas antes.
   for(int shift=1; shift<=InpMaxSignalLag+1; shift++)
   {
      if(crossUp && trend[shift]>0.0 && ssl[shift]>0.0) return(SIGNAL_BUY);
      if(crossDown && trend[shift]<0.0 && ssl[shift]<0.0) return(SIGNAL_SELL);
   }
   return(SIGNAL_NONE);
}

bool HasPosition(int &positionType)
{
   positionType=-1;
   for(int i=PositionsTotal()-1;i>=0;i--)
   {
      ulong ticket=PositionGetTicket(i);
      if(ticket==0 || !PositionSelectByTicket(ticket)) continue;
      if(PositionGetString(POSITION_SYMBOL)==_Symbol && (ulong)PositionGetInteger(POSITION_MAGIC)==InpMagicNumber)
      {
         positionType=(int)PositionGetInteger(POSITION_TYPE);
         return(true);
      }
   }
   return(false);
}

string RiskKey(const ulong ticket) { return("RoboQQE.InitialRisk."+(string)ticket); }

bool GetATR(double &atr)
{
   double data[];
   ArraySetAsSeries(data,true);
   if(CopyBuffer(atrHandle,0,1,1,data)!=1 || data[0]<=0.0) return(false);
   atr=data[0];
   return(true);
}

bool SpreadIsAcceptable()
{
   if(InpMaxSpreadPoints==0) return(true);
   MqlTick tick;
   return(SymbolInfoTick(_Symbol,tick) && (tick.ask-tick.bid)/_Point<=InpMaxSpreadPoints);
}

bool DailyLossLimitReached()
{
   if(InpDailyLossLimitPercent<=0.0) return(false);
   MqlDateTime d; TimeToStruct(TimeCurrent(),d); d.hour=0; d.min=0; d.sec=0;
   if(!HistorySelect(StructToTime(d),TimeCurrent())) return(false);
   double net=0.0;
   for(int i=0;i<HistoryDealsTotal();i++)
   {
      ulong deal=HistoryDealGetTicket(i);
      if(deal==0 || HistoryDealGetString(deal,DEAL_SYMBOL)!=_Symbol || (ulong)HistoryDealGetInteger(deal,DEAL_MAGIC)!=InpMagicNumber) continue;
      if(HistoryDealGetInteger(deal,DEAL_ENTRY)==DEAL_ENTRY_OUT)
         net+=HistoryDealGetDouble(deal,DEAL_PROFIT)+HistoryDealGetDouble(deal,DEAL_COMMISSION)+HistoryDealGetDouble(deal,DEAL_SWAP);
   }
   double openingBalance=AccountInfoDouble(ACCOUNT_BALANCE)-net;
   return(net<=-openingBalance*InpDailyLossLimitPercent/100.0);
}

double NormalizeVolume(double volume)
{
   double minLot=SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_MIN), maxLot=SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_MAX), step=SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_STEP);
   volume=MathMax(minLot,MathMin(maxLot,volume));
   return(NormalizeDouble(MathFloor(volume/step)*step,2));
}

bool BuildStops(const Signal signal,double &sl,double &tp)
{
   MqlTick tick;
   if(!SymbolInfoTick(_Symbol,tick)) return(false);
   double point=_Point, entry=(signal==SIGNAL_BUY ? tick.ask : tick.bid);
   double pip=((int)SymbolInfoInteger(_Symbol,SYMBOL_DIGITS)==3 || (int)SymbolInfoInteger(_Symbol,SYMBOL_DIGITS)==5 ? 10.0*point : point);
   if(InpUseATRStops)
   {
      double atr;
      if(!GetATR(atr)) return(false);
      double distance=atr*InpATRStopMultiplier;
      sl=(signal==SIGNAL_BUY ? entry-distance : entry+distance);
      tp=(InpUseTakeProfit ? (signal==SIGNAL_BUY ? entry+distance*InpRR_Ratio : entry-distance*InpRR_Ratio) : 0.0);
      int decimals=(int)SymbolInfoInteger(_Symbol,SYMBOL_DIGITS);
      sl=NormalizeDouble(sl,decimals); tp=NormalizeDouble(tp,decimals);
      int minStops=(int)SymbolInfoInteger(_Symbol,SYMBOL_TRADE_STOPS_LEVEL);
      return(MathAbs(entry-sl)>=minStops*point && (!InpUseTakeProfit || MathAbs(tp-entry)>=minStops*point));
   }
   if(InpUseFixedSL)
   {
      double distance=InpFixedSL_Pips*pip;
      sl=(signal==SIGNAL_BUY ? entry-distance : entry+distance);
      tp=(InpUseTakeProfit ? (signal==SIGNAL_BUY ? entry+distance*InpRR_Ratio : entry-distance*InpRR_Ratio) : 0.0);
      int fixedDigits=(int)SymbolInfoInteger(_Symbol,SYMBOL_DIGITS);
      sl=NormalizeDouble(sl,fixedDigits); tp=NormalizeDouble(tp,fixedDigits);
      int fixedStops=(int)SymbolInfoInteger(_Symbol,SYMBOL_TRADE_STOPS_LEVEL);
      return(MathAbs(entry-sl)>=fixedStops*point && (!InpUseTakeProfit || MathAbs(tp-entry)>=fixedStops*point));
   }
   double extreme=(signal==SIGNAL_BUY ? DBL_MAX : -DBL_MAX);
   for(int shift=1;shift<=InpSwingLookback;shift++)
   {
      double value=(signal==SIGNAL_BUY ? iLow(_Symbol,InpTimeframe,shift) : iHigh(_Symbol,InpTimeframe,shift));
      if(value==0.0) return(false);
      if(signal==SIGNAL_BUY) extreme=MathMin(extreme,value); else extreme=MathMax(extreme,value);
   }
   sl=extreme;
   double risk=(signal==SIGNAL_BUY ? entry-sl : sl-entry);
   if(risk<=0.0) return(false);
   tp=(InpUseTakeProfit ? (signal==SIGNAL_BUY ? entry+risk*InpRR_Ratio : entry-risk*InpRR_Ratio) : 0.0);
   int digits=(int)SymbolInfoInteger(_Symbol,SYMBOL_DIGITS);
   sl=NormalizeDouble(sl,digits); tp=NormalizeDouble(tp,digits);
   int stops=(int)SymbolInfoInteger(_Symbol,SYMBOL_TRADE_STOPS_LEVEL);
   if(MathAbs(entry-sl)<stops*point || (InpUseTakeProfit && MathAbs(tp-entry)<stops*point)) return(false);
   return(true);
}

void ManageTrailingStop()
{
   if(!InpUseTrailingStop) return;
   MqlTick tick;
   if(!SymbolInfoTick(_Symbol,tick)) return;
   double point=_Point;
   int digits=(int)SymbolInfoInteger(_Symbol,SYMBOL_DIGITS);
   double pip=(digits==3 || digits==5 ? 10.0*point : point);
   double start=InpTrailingStartPips*pip;
   double distance=InpTrailingDistancePips*pip;
   if(InpUseATRTrailing)
   {
      double atr;
      if(!GetATR(atr)) return;
      start=atr*InpTrailingStartATR;
      distance=atr*InpTrailingDistanceATR;
   }
   double step=InpTrailingStepPips*pip;
   double minDistance=(double)SymbolInfoInteger(_Symbol,SYMBOL_TRADE_STOPS_LEVEL)*point;

   for(int i=PositionsTotal()-1;i>=0;i--)
   {
      ulong ticket=PositionGetTicket(i);
      if(ticket==0 || !PositionSelectByTicket(ticket)) continue;
      if(PositionGetString(POSITION_SYMBOL)!=_Symbol || (ulong)PositionGetInteger(POSITION_MAGIC)!=InpMagicNumber) continue;
      ENUM_POSITION_TYPE type=(ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
      double openPrice=PositionGetDouble(POSITION_PRICE_OPEN);
      double oldSL=PositionGetDouble(POSITION_SL);
      double tp=PositionGetDouble(POSITION_TP);
      double candidate=0.0;
      double initialRisk=0.0;
      string key=RiskKey(ticket);
      if(GlobalVariableCheck(key)) initialRisk=GlobalVariableGet(key);
      if(InpUseBreakEven && initialRisk>0.0)
      {
         double offset=InpBreakEvenOffsetPips*pip;
         if(type==POSITION_TYPE_BUY && tick.bid-openPrice>=initialRisk*InpBreakEvenAtR)
         {
            candidate=NormalizeDouble(openPrice+offset,digits);
            if((oldSL==0.0 || candidate>oldSL) && candidate<=tick.bid-minDistance && trade.PositionModify(ticket,candidate,tp)) oldSL=candidate;
         }
         else if(type==POSITION_TYPE_SELL && openPrice-tick.ask>=initialRisk*InpBreakEvenAtR)
         {
            candidate=NormalizeDouble(openPrice-offset,digits);
            if((oldSL==0.0 || candidate<oldSL) && candidate>=tick.ask+minDistance && trade.PositionModify(ticket,candidate,tp)) oldSL=candidate;
         }
      }
      if(type==POSITION_TYPE_BUY && tick.bid-openPrice>=start)
      {
         candidate=MathMin(tick.bid-distance,tick.bid-minDistance);
         candidate=NormalizeDouble(candidate,digits);
         if((oldSL==0.0 || candidate-oldSL>=step) && candidate>openPrice)
         {
            if(!trade.PositionModify(ticket,candidate,tp)) Print("No se pudo actualizar trailing stop: ",trade.ResultRetcodeDescription());
         }
      }
      else if(type==POSITION_TYPE_SELL && openPrice-tick.ask>=start)
      {
         candidate=MathMax(tick.ask+distance,tick.ask+minDistance);
         candidate=NormalizeDouble(candidate,digits);
         if((oldSL==0.0 || oldSL-candidate>=step) && candidate<openPrice)
         {
            if(!trade.PositionModify(ticket,candidate,tp)) Print("No se pudo actualizar trailing stop: ",trade.ResultRetcodeDescription());
         }
      }
   }
}

double CalculateLots(const double entry,const double sl)
{
   if(!InpUsePercentRisk) return(NormalizeVolume(InpFixedLots));
   double tickSize=SymbolInfoDouble(_Symbol,SYMBOL_TRADE_TICK_SIZE);
   double tickValue=SymbolInfoDouble(_Symbol,SYMBOL_TRADE_TICK_VALUE);
   if(tickSize<=0.0 || tickValue<=0.0) return(0.0);
   double riskMoney=AccountInfoDouble(ACCOUNT_BALANCE)*InpRiskPercent/100.0;
   double lossPerLot=MathAbs(entry-sl)/tickSize*tickValue;
   if(lossPerLot<=0.0) return(0.0);
   double requestedLots=riskMoney/lossPerLot;
   if(requestedLots<SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_MIN)) return(0.0);
   return(NormalizeVolume(requestedLots));
}

void ExecuteSignal(const Signal signal)
{
   double sl,tp;
   if(!BuildStops(signal,sl,tp)) { Print("Operacion omitida: el SL estructural no es valido para el precio actual."); return; }
   MqlTick tick;
   if(!SymbolInfoTick(_Symbol,tick)) return;
   double lots=CalculateLots(signal==SIGNAL_BUY ? tick.ask : tick.bid,sl);
   if(lots<=0.0) { Print("Operacion omitida: no fue posible calcular el volumen por riesgo."); return; }
   bool sent=(signal==SIGNAL_BUY ? trade.Buy(lots,_Symbol,0.0,sl,tp,"RoboQQE long") : trade.Sell(lots,_Symbol,0.0,sl,tp,"RoboQQE short"));
   if(!sent) Print("Error al enviar orden: ",trade.ResultRetcode()," - ",trade.ResultRetcodeDescription());
   else
   {
      int type;
      if(HasPosition(type))
      {
         ulong ticket=(ulong)PositionGetInteger(POSITION_TICKET);
         GlobalVariableSet(RiskKey(ticket),MathAbs(PositionGetDouble(POSITION_PRICE_OPEN)-sl));
      }
   }
}

void OnTick()
{
   ManageTrailingStop();
   if(!IsNewClosedBar()) return;
   if(DailyLossLimitReached()) { Print("Limite de perdida diaria alcanzado."); return; }
   if(!SpreadIsAcceptable()) { Print("Operacion omitida: spread excesivo."); return; }
   Signal signal=GetSignal();
   int positionType;
   if(HasPosition(positionType))
   {
      bool opposite=(signal==SIGNAL_BUY && positionType==POSITION_TYPE_SELL) || (signal==SIGNAL_SELL && positionType==POSITION_TYPE_BUY);
      if(opposite && InpCloseOnReverse && !trade.PositionClose(_Symbol))
         Print("No se pudo cerrar la posicion inversa: ",trade.ResultRetcodeDescription());
      return; // nunca abre mas de una operacion en la misma vela
   }
   if(signal!=SIGNAL_NONE) ExecuteSignal(signal);
}
