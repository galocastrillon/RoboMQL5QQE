#property copyright "RoboQQE"
#property version   "1.00"
#property indicator_chart_window
#property indicator_buffers 5
#property indicator_plots   1
#property indicator_label1  "Trend Magic"
#property indicator_type1   DRAW_COLOR_LINE
#property indicator_color1  clrLimeGreen,clrTomato
#property indicator_width1  2

input int    InpCCIPeriod  = 50;
input int    InpATRPeriod  = 6;
input double InpATRMultiplier = 1.0;

double TrendBuffer[], ColorBuffer[], DirectionBuffer[], CciBuffer[], AtrBuffer[];
int cciHandle=INVALID_HANDLE, atrHandle=INVALID_HANDLE;

int OnInit()
{
   if(InpCCIPeriod<2 || InpATRPeriod<1 || InpATRMultiplier<=0) return(INIT_PARAMETERS_INCORRECT);
   SetIndexBuffer(0,TrendBuffer,INDICATOR_DATA);
   SetIndexBuffer(1,ColorBuffer,INDICATOR_COLOR_INDEX);
   SetIndexBuffer(2,DirectionBuffer,INDICATOR_DATA);
   SetIndexBuffer(3,CciBuffer,INDICATOR_CALCULATIONS);
   SetIndexBuffer(4,AtrBuffer,INDICATOR_CALCULATIONS);
   ArraySetAsSeries(TrendBuffer,true); ArraySetAsSeries(ColorBuffer,true); ArraySetAsSeries(DirectionBuffer,true);
   ArraySetAsSeries(CciBuffer,true); ArraySetAsSeries(AtrBuffer,true);
   cciHandle=iCCI(_Symbol,_Period,InpCCIPeriod,PRICE_TYPICAL);
   atrHandle=iATR(_Symbol,_Period,InpATRPeriod);
   if(cciHandle==INVALID_HANDLE || atrHandle==INVALID_HANDLE) return(INIT_FAILED);
   IndicatorSetString(INDICATOR_SHORTNAME,"Trend Magic (CCI "+(string)InpCCIPeriod+", ATR "+(string)InpATRPeriod+")");
   return(INIT_SUCCEEDED);
}
void OnDeinit(const int reason) { if(cciHandle!=INVALID_HANDLE) IndicatorRelease(cciHandle); if(atrHandle!=INVALID_HANDLE) IndicatorRelease(atrHandle); }

int OnCalculate(const int rates_total,const int prev_calculated,const datetime &time[],const double &open[],
                const double &high[],const double &low[],const double &close[],const long &tick_volume[],const long &volume[],const int &spread[])
{
   int minbars=(int)MathMax(InpCCIPeriod,InpATRPeriod)+2;
   if(rates_total<minbars) return(0);
   if(CopyBuffer(cciHandle,0,0,rates_total,CciBuffer)!=rates_total || CopyBuffer(atrHandle,0,0,rates_total,AtrBuffer)!=rates_total) return(0);
   for(int i=rates_total-1;i>=0;i--)
   {
      double up=low[i]-AtrBuffer[i]*InpATRMultiplier;
      double down=high[i]+AtrBuffer[i]*InpATRMultiplier;
      if(i==rates_total-1) TrendBuffer[i]=(CciBuffer[i]>=0.0 ? up : down);
      else if(CciBuffer[i]>=0.0) TrendBuffer[i]=MathMax(up,TrendBuffer[i+1]);
      else TrendBuffer[i]=MathMin(down,TrendBuffer[i+1]);
      DirectionBuffer[i]=(CciBuffer[i]>=0.0 ? 1.0 : -1.0);
      ColorBuffer[i]=(DirectionBuffer[i]>0.0 ? 0.0 : 1.0);
   }
   return(rates_total);
}
