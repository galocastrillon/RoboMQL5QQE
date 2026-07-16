#property copyright "RoboQQE"
#property version   "1.00"
#property indicator_separate_window
#property indicator_buffers 4
#property indicator_plots   1
#property indicator_label1  "QQE"
#property indicator_type1   DRAW_LINE
#property indicator_color1  clrYellow
#property indicator_width1  2
#property indicator_level1  0.0
#property indicator_level2  20.0
#property indicator_level3  -20.0
#property indicator_levelcolor clrDimGray
#property indicator_levelstyle STYLE_DOT

// QQE Mod: RSI suavizado y centrado en cero. Los niveles +/-20 son el filtro de extremos.
input int    InpRSIPeriod     = 14;
input int    InpSmoothing     = 5;
input double InpQQEFactor     = 4.238;

double QQEBuffer[];
double RsiBuffer[], AtrRsiBuffer[], DarBuffer[];
int    rsiHandle = INVALID_HANDLE;

int OnInit()
{
   if(InpRSIPeriod < 2 || InpSmoothing < 1 || InpQQEFactor<=0.0) return(INIT_PARAMETERS_INCORRECT);
   SetIndexBuffer(0,QQEBuffer,INDICATOR_DATA);
   SetIndexBuffer(1,RsiBuffer,INDICATOR_CALCULATIONS);
   SetIndexBuffer(2,AtrRsiBuffer,INDICATOR_CALCULATIONS);
   SetIndexBuffer(3,DarBuffer,INDICATOR_CALCULATIONS);
   ArraySetAsSeries(QQEBuffer,true);
   ArraySetAsSeries(RsiBuffer,true);
   ArraySetAsSeries(AtrRsiBuffer,true);
   ArraySetAsSeries(DarBuffer,true);
   rsiHandle=iRSI(_Symbol,_Period,InpRSIPeriod,PRICE_CLOSE);
   if(rsiHandle==INVALID_HANDLE) return(INIT_FAILED);
   IndicatorSetString(INDICATOR_SHORTNAME,"QQE Mod ("+(string)InpRSIPeriod+","+(string)InpSmoothing+")");
   return(INIT_SUCCEEDED);
}

void OnDeinit(const int reason)
{
   if(rsiHandle!=INVALID_HANDLE) IndicatorRelease(rsiHandle);
}

int OnCalculate(const int rates_total,const int prev_calculated,const datetime &time[],
                const double &open[],const double &high[],const double &low[],
                const double &close[],const long &tick_volume[],const long &volume[],const int &spread[])
{
   if(rates_total < InpRSIPeriod+InpSmoothing+2) return(0);
   if(CopyBuffer(rsiHandle,0,0,rates_total,RsiBuffer) != rates_total) return(0);
   // Se calcula del pasado al presente: los arrays de precio están en serie (0 = vela actual).
   for(int i=rates_total-1;i>=0;i--)
   {
      if(i==rates_total-1) QQEBuffer[i]=RsiBuffer[i]-50.0;
      else QQEBuffer[i]=(QQEBuffer[i+1]*(InpSmoothing-1)+(RsiBuffer[i]-50.0))/InpSmoothing;

      // Rango dinámico QQE clásico: suavizado Wilder doble de los cambios del RSI.
      // Se conserva como cálculo interno; la línea visual/trigger es el RSI suavizado centrado en cero.
      if(i==rates_total-1) { AtrRsiBuffer[i]=0.0; DarBuffer[i]=0.0; }
      else
      {
         int wilders=2*InpRSIPeriod-1;
         AtrRsiBuffer[i]=(AtrRsiBuffer[i+1]*(wilders-1)+MathAbs(QQEBuffer[i]-QQEBuffer[i+1]))/wilders;
         DarBuffer[i]=(DarBuffer[i+1]*(wilders-1)+AtrRsiBuffer[i])/wilders*InpQQEFactor;
      }
   }
   return(rates_total);
}
