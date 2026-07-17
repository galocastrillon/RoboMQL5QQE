#property copyright "RoboQQE"
#property version   "1.10"
#property indicator_chart_window
#property indicator_buffers 5
#property indicator_plots   1
#property indicator_label1  "Trend Magic"
#property indicator_type1   DRAW_COLOR_LINE
#property indicator_color1  clrLimeGreen,clrTomato
#property indicator_width1  2

input int    InpCCIPeriod     = 50;
input int    InpATRPeriod     = 6;
input double InpATRMultiplier = 1.0;

double TrendBuffer[];     // Buffer 0: linea escalonada.
double ColorBuffer[];     // Buffer 1: indice de color (0 alcista / 1 bajista).
double DirectionBuffer[]; // Buffer 2: +1 / -1, lo lee el EA.
double CciBuffer[];       // Buffer 3: calculo interno.
double AtrBuffer[];       // Buffer 4: calculo interno.
int cciHandle = INVALID_HANDLE, atrHandle = INVALID_HANDLE;
int firstValid = 0;

int OnInit()
{
   if(InpCCIPeriod < 2 || InpATRPeriod < 1 || InpATRMultiplier <= 0) return(INIT_PARAMETERS_INCORRECT);

   SetIndexBuffer(0, TrendBuffer, INDICATOR_DATA);
   SetIndexBuffer(1, ColorBuffer, INDICATOR_COLOR_INDEX);
   SetIndexBuffer(2, DirectionBuffer, INDICATOR_CALCULATIONS);
   SetIndexBuffer(3, CciBuffer, INDICATOR_CALCULATIONS);
   SetIndexBuffer(4, AtrBuffer, INDICATOR_CALCULATIONS);

   cciHandle = iCCI(_Symbol, _Period, InpCCIPeriod, PRICE_TYPICAL);
   atrHandle = iATR(_Symbol, _Period, InpATRPeriod);
   if(cciHandle == INVALID_HANDLE || atrHandle == INVALID_HANDLE) return(INIT_FAILED);

   firstValid = (int)MathMax(InpCCIPeriod, InpATRPeriod) + 1;
   PlotIndexSetInteger(0, PLOT_DRAW_BEGIN, firstValid);
   PlotIndexSetDouble(0, PLOT_EMPTY_VALUE, EMPTY_VALUE);
   IndicatorSetString(INDICATOR_SHORTNAME, "Trend Magic (CCI " + (string)InpCCIPeriod + ", ATR " + (string)InpATRPeriod + ")");
   return(INIT_SUCCEEDED);
}

void OnDeinit(const int reason)
{
   if(cciHandle != INVALID_HANDLE) IndicatorRelease(cciHandle);
   if(atrHandle != INVALID_HANDLE) IndicatorRelease(atrHandle);
}

int OnCalculate(const int rates_total, const int prev_calculated, const datetime &time[], const double &open[],
                const double &high[], const double &low[], const double &close[], const long &tick_volume[], const long &volume[], const int &spread[])
{
   if(rates_total < firstValid + 2) return(0);

   if(CopyBuffer(cciHandle, 0, 0, rates_total, CciBuffer) < rates_total) return(prev_calculated);
   if(CopyBuffer(atrHandle, 0, 0, rates_total, AtrBuffer) < rates_total) return(prev_calculated);

   int start;
   if(prev_calculated == 0)
   {
      for(int i = 0; i < firstValid && i < rates_total; i++)
      {
         TrendBuffer[i]     = EMPTY_VALUE;
         ColorBuffer[i]     = 0.0;
         DirectionBuffer[i] = 0.0;
      }
      double up0   = low[firstValid]  - AtrBuffer[firstValid] * InpATRMultiplier;
      double down0 = high[firstValid] + AtrBuffer[firstValid] * InpATRMultiplier;
      TrendBuffer[firstValid]     = (CciBuffer[firstValid] >= 0.0 ? up0 : down0);
      DirectionBuffer[firstValid] = (CciBuffer[firstValid] >= 0.0 ? 1.0 : -1.0);
      ColorBuffer[firstValid]     = (DirectionBuffer[firstValid] > 0.0 ? 0.0 : 1.0);
      start = firstValid + 1;
   }
   else
      start = prev_calculated - 1;

   if(start < firstValid + 1) start = firstValid + 1;

   for(int i = start; i < rates_total; i++)
   {
      double up   = low[i]  - AtrBuffer[i] * InpATRMultiplier;
      double down = high[i] + AtrBuffer[i] * InpATRMultiplier;
      if(CciBuffer[i] >= 0.0) TrendBuffer[i] = MathMax(up, TrendBuffer[i - 1]);
      else                    TrendBuffer[i] = MathMin(down, TrendBuffer[i - 1]);
      DirectionBuffer[i] = (CciBuffer[i] >= 0.0 ? 1.0 : -1.0);
      ColorBuffer[i]     = (DirectionBuffer[i] > 0.0 ? 0.0 : 1.0);
   }

   return(rates_total);
}
