# RoboMQL5QQE

Sistema para MetaTrader 5 compuesto por un Expert Advisor y tres indicadores
personalizados que trabajan en conjunto:

| Archivo | Tipo | Ventana | Rol |
|---------|------|---------|-----|
| `MQL5/Indicators/RoboQQE/QQE_Mod.mq5` | Indicador | Separada | Oscilador QQE (RSI suavizado centrado en 0). Gatillo del sistema. |
| `MQL5/Indicators/RoboQQE/Trend_Magic.mq5` | Indicador | Principal | Filtro de tendencia (CCI + ATR). |
| `MQL5/Indicators/RoboQQE/SSL_Hybrid_JMA.mq5` | Indicador | Principal | Baseline adaptativa (aprox. JMA). |
| `MQL5/Experts/RoboQQE/RoboQQE_EA.mq5` | Expert Advisor | — | Lee los tres indicadores y opera. |

## Instalación (lo que resuelve el "no se adjuntan / no se muestran")

MT5 solo carga indicadores y EAs que estén dentro de la carpeta de datos **del
propio terminal**, no de cualquier carpeta del disco.

1. En MetaTrader 5: menú **Archivo → Abrir carpeta de datos**.
2. Copia respetando exactamente esta estructura (incluida la subcarpeta `RoboQQE`):
   ```
   <Carpeta de datos>/MQL5/Indicators/RoboQQE/QQE_Mod.mq5
   <Carpeta de datos>/MQL5/Indicators/RoboQQE/Trend_Magic.mq5
   <Carpeta de datos>/MQL5/Indicators/RoboQQE/SSL_Hybrid_JMA.mq5
   <Carpeta de datos>/MQL5/Experts/RoboQQE/RoboQQE_EA.mq5
   ```
3. Abre **MetaEditor** y compila (F7) los **tres indicadores primero** y luego el
   EA. Cada uno debe terminar con `0 errors, 0 warnings` y generar su `.ex5`.
   > El EA usa `iCustom` con la ruta `RoboQQE\QQE_Mod`, etc.; si los indicadores
   > no están compilados en esa subcarpeta, el EA falla al iniciar (`INIT_FAILED`)
   > y no se adjunta.
4. En el terminal, clic derecho sobre **Navegador → Actualizar**. Los archivos
   aparecerán bajo *Indicadores personalizados* y *Asesores expertos*.
5. Arrastra cada indicador al gráfico, o simplemente arrastra el EA: por defecto
   (`InpShowIndicators=true`) el EA dibuja los tres indicadores automáticamente.
6. Para operar, habilita **AutoTrading** (botón de la barra) y marca *"Permitir
   operaciones automáticas"* en la pestaña *Común* al adjuntar el EA.

## Correcciones aplicadas en esta versión

Los indicadores compilaban, pero fallaban en tiempo de ejecución:

- **Indexación cruzada (Trend_Magic y SSL_Hybrid_JMA):** los buffers se marcaban
  como serie (`ArraySetAsSeries`, 0 = vela actual) mientras que los arrays de
  precio de `OnCalculate` seguían en orden natural (0 = vela más antigua). Al
  usar el mismo índice para ambos, la recursión quedaba invertida y la línea
  salía errática o fuera de escala. Se reescribieron con el patrón estándar de
  MT5: buffers en orden natural e iteración hacia adelante con `prev_calculated`.
- **Warm-up frágil:** los indicadores exigían `CopyBuffer(...) == rates_total`
  del histórico completo en cada tick; en el primer tick el sub-indicador
  (RSI/CCI/ATR) aún no está listo y se devolvía `0`, dejando la pantalla en
  blanco. Ahora se devuelve `prev_calculated` y se reintenta hasta que los datos
  están disponibles.
- **Visibilidad:** el EA ahora adjunta los tres indicadores al gráfico al cargar
  (con protección contra duplicados), colocando el QQE en su subventana propia.
- Se eliminaron los binarios `.ex5` y los `.log` obsoletos del repositorio; se
  regeneran al compilar en MetaEditor.

## Lógica de trading (resumen)

- Opera solo en **velas cerradas** del timeframe `InpTimeframe` (M5 por defecto).
- **Compra:** el QQE cruza 0 al alza habiendo tocado antes el extremo `-20`, con
  Trend Magic y baseline SSL alineados al alza.
- **Venta:** condición simétrica.
- Gestión de riesgo: SL fijo / por ATR / estructural, trailing stop, break-even,
  límite de pérdida diaria y filtro de spread. Todo configurable por inputs.
