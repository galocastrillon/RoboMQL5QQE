#property copyright "RoboQQE"
#property version   "1.10"
#property indicator_chart_window
#property indicator_buffers 3
#property indicator_plots   1
#property indicator_label1  "MA Baseline (JMA)"
#property indicator_type1   DRAW_COLOR_LINE
#property indicator_color1  clrDodgerBlue,clrTomato
#property indicator_width1  2

// JMA es una formula propietaria. Esta implementacion usa una aproximacion adaptativa,
// suave y de bajo retardo, para mantener una alternativa reproducible en MT5.
input int    InpBaselineLength = 200;
input double InpPhase          = 0.0; // -100..100; mayor valor reduce el retraso

double BaselineBuffer[];  // Buffer 0: baseline.
double ColorBuffer[];     // Buffer 1: indice de color (0 alcista / 1 bajista).
double DirectionBuffer[]; // Buffer 2: +1 / -1, lo lee el EA.
int firstValid = 0;

int OnInit()
{
   if(InpBaselineLength < 2 || InpPhase < -100.0 || InpPhase > 100.0) return(INIT_PARAMETERS_INCORRECT);

   SetIndexBuffer(0, BaselineBuffer, INDICATOR_DATA);
   SetIndexBuffer(1, ColorBuffer, INDICATOR_COLOR_INDEX);
   SetIndexBuffer(2, DirectionBuffer, INDICATOR_CALCULATIONS);

   firstValid = InpBaselineLength;
   PlotIndexSetInteger(0, PLOT_DRAW_BEGIN, firstValid);
   PlotIndexSetDouble(0, PLOT_EMPTY_VALUE, EMPTY_VALUE);
   IndicatorSetString(INDICATOR_SHORTNAME, "SSL Hybrid - JMA Baseline (" + (string)InpBaselineLength + ")");
   return(INIT_SUCCEEDED);
}

int OnCalculate(const int rates_total, const int prev_calculated, const datetime &time[], const double &open[],
                const double &high[], const double &low[], const double &close[], const long &tick_volume[], const long &volume[], const int &spread[])
{
   if(rates_total < InpBaselineLength + 2) return(0);

   double baseAlpha = 2.0 / (InpBaselineLength + 1.0);
   double phaseAdj  = 1.0 + InpPhase / 100.0;

   int start;
   if(prev_calculated == 0)
   {
      BaselineBuffer[0]  = close[0];   // Semilla del suavizado recursivo.
      DirectionBuffer[0] = 0.0;
      ColorBuffer[0]     = 0.0;
      start = 1;
   }
   else
      start = prev_calculated - 1;

   if(start < 1) start = 1;

   for(int i = start; i < rates_total; i++)
   {
      double volatility = MathAbs(close[i] - close[i - 1]);
      double reference  = MathMax(MathAbs(close[i - 1] - BaselineBuffer[i - 1]), _Point);
      double efficiency = MathMin(1.0, volatility / reference);
      double alpha      = MathMin(1.0, baseAlpha * (0.5 + efficiency) * phaseAdj);
      BaselineBuffer[i] = BaselineBuffer[i - 1] + alpha * (close[i] - BaselineBuffer[i - 1]);

      DirectionBuffer[i] = (close[i] >= BaselineBuffer[i] ? 1.0 : -1.0);
      ColorBuffer[i]     = (DirectionBuffer[i] > 0.0 ? 0.0 : 1.0);
   }

   return(rates_total);
}
