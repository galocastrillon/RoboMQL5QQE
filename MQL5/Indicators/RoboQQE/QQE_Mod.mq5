#property copyright "RoboQQE"
#property version   "1.10"
#property indicator_separate_window
#property indicator_buffers 2
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

double QQEBuffer[];   // Buffer 0: linea visible y gatillo que lee el EA.
double RsiBuffer[];   // Buffer 1: RSI copiado (calculo interno).
int    rsiHandle = INVALID_HANDLE;
int    firstValid = 0;

int OnInit()
{
   if(InpRSIPeriod < 2 || InpSmoothing < 1 || InpQQEFactor <= 0.0) return(INIT_PARAMETERS_INCORRECT);

   // Buffers en orden natural (0 = vela mas antigua); coincide con los arrays de OnCalculate.
   SetIndexBuffer(0, QQEBuffer, INDICATOR_DATA);
   SetIndexBuffer(1, RsiBuffer, INDICATOR_CALCULATIONS);

   rsiHandle = iRSI(_Symbol, _Period, InpRSIPeriod, PRICE_CLOSE);
   if(rsiHandle == INVALID_HANDLE) return(INIT_FAILED);

   firstValid = InpRSIPeriod;
   PlotIndexSetInteger(0, PLOT_DRAW_BEGIN, firstValid);
   PlotIndexSetDouble(0, PLOT_EMPTY_VALUE, EMPTY_VALUE);
   IndicatorSetInteger(INDICATOR_DIGITS, 2);
   IndicatorSetString(INDICATOR_SHORTNAME, "QQE Mod (" + (string)InpRSIPeriod + "," + (string)InpSmoothing + ")");
   return(INIT_SUCCEEDED);
}

void OnDeinit(const int reason)
{
   if(rsiHandle != INVALID_HANDLE) IndicatorRelease(rsiHandle);
}

int OnCalculate(const int rates_total, const int prev_calculated, const datetime &time[],
                const double &open[], const double &high[], const double &low[],
                const double &close[], const long &tick_volume[], const long &volume[], const int &spread[])
{
   if(rates_total < firstValid + InpSmoothing + 2) return(0);

   // Se espera a que el RSI tenga todo el historico calculado (evita pantalla en blanco al adjuntar).
   if(CopyBuffer(rsiHandle, 0, 0, rates_total, RsiBuffer) < rates_total)
      return(prev_calculated);

   // Primera vela con RSI realmente valido. Durante el calentamiento el RSI puede
   // devolver EMPTY_VALUE (~1.8e308); si esa cifra entra en la recursion se multiplica
   // por (SF-1) y desborda a 1.#INF, contaminando toda la linea. Por eso se localiza aqui.
   // El RSI esta acotado en [0,100]; cualquier valor fuera es un centinela de calentamiento.
   int seed = 0;
   while(seed < rates_total && (!MathIsValidNumber(RsiBuffer[seed]) || RsiBuffer[seed] < 0.0 || RsiBuffer[seed] > 100.0))
      seed++;
   if(seed >= rates_total - 1) return(prev_calculated);   // Aun no hay datos utiles.

   int start;
   if(prev_calculated == 0 || prev_calculated > rates_total)
   {
      for(int i = 0; i <= seed && i < rates_total; i++) QQEBuffer[i] = EMPTY_VALUE;
      QQEBuffer[seed] = RsiBuffer[seed] - 50.0;             // Semilla del suavizado.
      start = seed + 1;
   }
   else
   {
      start = prev_calculated - 1;                          // Recalcula la ultima vela (en formacion).
      if(start <= seed) { QQEBuffer[seed] = RsiBuffer[seed] - 50.0; start = seed + 1; }
   }

   for(int i = start; i < rates_total; i++)
   {
      double rsi = RsiBuffer[i];
      if(!MathIsValidNumber(rsi) || rsi < 0.0 || rsi > 100.0) { QQEBuffer[i] = QQEBuffer[i - 1]; continue; }
      QQEBuffer[i] = (QQEBuffer[i - 1] * (InpSmoothing - 1) + (rsi - 50.0)) / InpSmoothing;
   }

   return(rates_total);
}
