#property copyright "RoboQQE"
#property version   "1.00"
#property indicator_chart_window
#property indicator_buffers 3
#property indicator_plots   1
#property indicator_label1  "MA Baseline (JMA)"
#property indicator_type1   DRAW_COLOR_LINE
#property indicator_color1  clrDodgerBlue,clrTomato
#property indicator_width1  2

// JMA es una fórmula propietaria. Esta implementación usa una aproximación adaptativa,
// suave y de bajo retardo, para mantener una alternativa reproducible en MT5.
input int    InpBaselineLength = 200;
input double InpPhase          = 0.0; // -100..100; mayor valor reduce el retraso

double BaselineBuffer[], ColorBuffer[], DirectionBuffer[];

int OnInit()
{
   if(InpBaselineLength<2 || InpPhase < -100.0 || InpPhase > 100.0) return(INIT_PARAMETERS_INCORRECT);
   SetIndexBuffer(0,BaselineBuffer,INDICATOR_DATA);
   SetIndexBuffer(1,ColorBuffer,INDICATOR_COLOR_INDEX);
   SetIndexBuffer(2,DirectionBuffer,INDICATOR_DATA);
   ArraySetAsSeries(BaselineBuffer,true); ArraySetAsSeries(ColorBuffer,true); ArraySetAsSeries(DirectionBuffer,true);
   IndicatorSetString(INDICATOR_SHORTNAME,"SSL Hybrid - JMA Baseline ("+(string)InpBaselineLength+")");
   return(INIT_SUCCEEDED);
}

int OnCalculate(const int rates_total,const int prev_calculated,const datetime &time[],const double &open[],
                const double &high[],const double &low[],const double &close[],const long &tick_volume[],const long &volume[],const int &spread[])
{
   if(rates_total<InpBaselineLength+2) return(0);
   double baseAlpha=2.0/(InpBaselineLength+1.0);
   double phaseAdj=1.0+InpPhase/100.0;
   for(int i=rates_total-1;i>=0;i--)
   {
      if(i==rates_total-1) BaselineBuffer[i]=close[i];
      else
      {
         double volatility=MathAbs(close[i]-close[i+1]);
         double reference=MathMax(MathAbs(close[i+1]-BaselineBuffer[i+1]),_Point);
         double efficiency=MathMin(1.0,volatility/reference);
         double alpha=MathMin(1.0,baseAlpha*(0.5+efficiency)*phaseAdj);
         BaselineBuffer[i]=BaselineBuffer[i+1]+alpha*(close[i]-BaselineBuffer[i+1]);
      }
      DirectionBuffer[i]=(close[i]>=BaselineBuffer[i] ? 1.0 : -1.0);
      ColorBuffer[i]=(DirectionBuffer[i]>0.0 ? 0.0 : 1.0);
   }
   return(rates_total);
}
