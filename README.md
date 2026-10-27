# Stock World Monitor Charts

[![pub package](https://img.shields.io/pub/v/swm_chart.svg)](https://pub.dev/packages/swm_chart)

**Stock World Monitor Charts** (`swm_chart`), by
[Stock World Monitor](https://stockworldmonitor.com/), are high-performance financial
charts for Flutter. The package is a native Dart port of
[TradingView Lightweight Charts™](https://github.com/tradingview/lightweight-charts) (based on v5.2.1).

<p>
  <img src="https://raw.githubusercontent.com/KSD-CO/swm-chart/main/screenshots/trading_light.png" width="200" alt="Candlesticks with volume, SMA, RSI and markers">
  <img src="https://raw.githubusercontent.com/KSD-CO/swm-chart/main/screenshots/indicators.png" width="200" alt="Indicators with a legend">
  <img src="https://raw.githubusercontent.com/KSD-CO/swm-chart/main/screenshots/orders.png" width="200" alt="Orders, TP/SL and alerts">
  <img src="https://raw.githubusercontent.com/KSD-CO/swm-chart/main/screenshots/drawing_tools.png" width="200" alt="Drawing tools">
  <img src="https://raw.githubusercontent.com/KSD-CO/swm-chart/main/screenshots/overlays.png" width="200" alt="Bollinger, pivots and volume profile">
  <img src="https://raw.githubusercontent.com/KSD-CO/swm-chart/main/screenshots/compare.png" width="200" alt="Compare symbols">
  <img src="https://raw.githubusercontent.com/KSD-CO/swm-chart/main/screenshots/renko.png" width="200" alt="Renko">
  <img src="https://raw.githubusercontent.com/KSD-CO/swm-chart/main/screenshots/heikin_ashi.png" width="200" alt="Heikin-Ashi">
  <img src="https://raw.githubusercontent.com/KSD-CO/swm-chart/main/screenshots/trading_dark.png" width="200" alt="Dark theme">
  <img src="https://raw.githubusercontent.com/KSD-CO/swm-chart/main/screenshots/area_dark.png" width="200" alt="Area series">
  <img src="https://raw.githubusercontent.com/KSD-CO/swm-chart/main/screenshots/yield_curve.png" width="200" alt="Yield curve">
  <img src="https://raw.githubusercontent.com/KSD-CO/swm-chart/main/screenshots/options_chain.png" width="200" alt="Options chain">
  <img src="https://raw.githubusercontent.com/KSD-CO/swm-chart/main/screenshots/watchlist.png" width="200" alt="Sparklines and a donut">
</p>

```yaml
dependencies:
  swm_chart: ^0.9.0
```

There is no WebView. Everything is drawn with `CustomPainter`, and the
model/renderer architecture mirrors upstream. Candles, columns and grid lines
are drawn in device pixels, the same way upstream draws in bitmap
coordinates, so they stay sharp.

## Features

Everything in Lightweight Charts v5.2.1 that applies to Flutter is ported:

| Area | |
|---|---|
| Series: Candlestick, Bar, Line, Area, Baseline, Histogram, **custom series** | ✅ |
| Whitespace data, line types (simple, stepped, curved monotone) | ✅ |
| Chart types: time (`ChartController()`), **yield curve** (`.yieldCurve`), **options/price axis** (`.options`) | ✅ |
| Multiple panes: stretch factors, draggable separators, add/remove/swap/move, `addDefaultPane` | ✅ |
| Price scales: left, right, overlays (`overlayPriceScales`); normal, log, percentage, indexed-to-100; edge tick marks, ticks | ✅ |
| Time scale: bar spacing, right offset (bars or pixels), fix edges, lock range on resize, uniform distribution, ignore whitespace, conflation | ✅ |
| Crosshair: normal / magnet / magnet OHLC / hidden, per pane, `setCrosshairPosition`, tracking mode | ✅ |
| Last value labels, price line source, custom price lines, base line, last price animation | ✅ |
| Hit testing: `hoveredSeries` / `hoveredObjectId`, `hoveredSeriesOnTop` | ✅ |
| Plugins: primitives API, series markers, up/down markers, text & image watermarks | ✅ |
| Beyond upstream: **drawing tools** with an editor, band fill, price levels, volume profile, pointer capture, **sparklines**, **donut charts** | ✅ |
| **Indicators**: SMA, EMA, WMA, Bollinger, RSI, MACD, Stochastic, ATR, VWAP, Ichimoku — incremental, one line to add | ✅ |
| **Trading lines**: draggable orders, TP / SL, positions with P&L, price alerts | ✅ |
| **Legend & tooltip** following the crosshair | ✅ |
| **Chart types & timeframes**: Heikin-Ashi, Renko, line break, range bars; resample to minutes … months | ✅ |
| **Compare symbols** on a percentage scale | ✅ |
| Localization: locale, date format, month names, price/percentage/tick mark formatters | ✅ |
| Events: crosshair move, click, double click, visible logical/time range, size, data changed | ✅ |
| Gestures: pan + kinetic, pinch, long-press crosshair, axis drag, double-tap reset, mouse wheel — each switchable like `handleScroll` / `handleScale` | ✅ |
| Desktop / web: crosshair follows the mouse, resize cursors on axes and separators, primitive `cursor` | ✅ |
| Accessibility: `Semantics` label and a summary of the last values | ✅ |
| Attribution logo (opt-in), `takeScreenshot` | ✅ |

Not applicable in Flutter: `autoSize`/`resize`/`width`/`height` (the widget
takes its parent's size), `chartElement`, `colorSpace`, `colorParsers`.

## Usage

```dart
final chart = ChartController(
  options: const ChartOptions(timeScale: TimeScaleOptions(timeVisible: true)),
);

final candles = chart.addCandlestickSeries();
candles.setData([
  CandlestickData(time: 1704067200, open: 100, high: 105, low: 98, close: 103),
  WhitespaceData(time: 1704153600), // a gap
  // ... time is a UTC timestamp in seconds, strictly ascending
]);

final volume = chart.addHistogramSeries(const HistogramSeriesOptions(
  priceScaleId: 'volume',
  priceFormat: PriceFormat.volume(),
));
chart.priceScale('volume').applyOptions(
  const PriceScaleOptions(scaleMargins: ScaleMargins(top: 0.8, bottom: 0)),
);

// realtime
candles.update(CandlestickData(time: 1704153600, open: 103, high: 104, low: 101, close: 102));

// load more history when the user scrolls near the first bar
chart.timeScale().subscribeVisibleLogicalRangeChange((range) {
  if (range != null && range.from < 20) { /* fetch older bars, then setData */ }
});

// widget, needs bounded constraints
Expanded(child: SwmChart(controller: chart));
```

### Panes, indicators and plugins

```dart
// RSI in a second pane with 70/30 lines
final rsi = chart.addLineSeries(const LineSeriesOptions(color: Colors.purple), 1);
rsi.createPriceLine(const PriceLineOptions(price: 70, lineStyle: LineStyle.dashed));
rsi.createPriceLine(const PriceLineOptions(price: 30, lineStyle: LineStyle.dashed));
chart.panes()[0].setStretchFactor(3);

// markers
final markers = createSeriesMarkers(candles, [
  SeriesMarker(time: t, position: SeriesMarkerPosition.belowBar,
      shape: SeriesMarkerShape.arrowUp, color: Colors.green, text: 'Buy'),
]);

// watermark
createTextWatermark(chart.panes()[0],
    const TextWatermarkOptions(lines: [TextWatermarkLine(text: 'SWM Chart')]));

// log / percentage scale
chart.priceScale().applyOptions(const PriceScaleOptions(mode: PriceScaleMode.logarithmic));
```

Yield curves and options chains:

```dart
final yields = ChartController.yieldCurve(); // time = months
yields.addLineSeries().setData([LineData(time: 3, value: 5.4), LineData(time: 120, value: 4.3)]);

final chain = ChartController.options(precision: 0); // time = strike price
```

Custom series: implement `CustomSeriesView<T>` (`priceValues`, `draw`) and
add it with `chart.addCustomSeries(view)`.

Custom drawings: extend `ChartPrimitive` (override `paint`, `priceAxisLabels`,
`timeAxisLabels`, `autoscaleInfo`) and attach it with
`series.attachPrimitive(...)` or `pane.attachPrimitive(...)`.

Overlays beyond upstream: `BandFillPrimitive` (Bollinger, Keltner, an
Ichimoku cloud with a second colour where the lines cross),
`PriceLevelsPrimitive` (pivots, support / resistance, Fibonacci zones, with
optional axis labels and hit ids) and `VolumeProfilePrimitive` (horizontal
volume bins with a POC).

### Indicators

```dart
chart.addIndicator(Bollinger(), source: candles);          // over the candles
chart.addIndicator(Ema(50), source: candles);
final rsi = chart.addIndicator(Rsi(14), source: candles);   // its own pane, 70 / 30 levels
chart.addIndicator(Macd(), source: candles);
chart.addIndicator(Vwap(), source: candles, volume: volumeSeries);
rsi.remove();
```

Built in: `Sma`, `Ema`, `Wma`, `Bollinger`, `Rsi`, `Macd`, `Stochastic`,
`Atr`, `Vwap`, `Ichimoku` (cloud projected ahead). They follow the source
as it updates and only recompute the last bar on a tick. Extend `Indicator`
(`lines`, `compute(input, from, out)`) for your own, or call `computeAll`
to use the math without a chart.

### Legend and tooltip

```dart
createLegend(chart, const LegendOptions(title: 'BTC/USD · 1h'));
createLegend(chart, const LegendOptions(mode: LegendMode.tooltip));
```

Rows at the top-left of each pane (OHLC and change for candles, one row per
indicator) follow the crosshair, or show the last bar when it is hidden.

### Orders, positions and alerts

```dart
final trading = TradingLines(candles,
    onDragEnd: (line) => broker.modify(line.id, line.price),
    onAlert: (alert, price) => notify('${alert.id} at $price'));
trading
  ..add(TradingLine(id: 'pos', kind: TradingLineKind.position, price: 29730, quantity: 0.5))
  ..add(TradingLine(id: 'tp', kind: TradingLineKind.takeProfit, price: 30480, quantity: 0.5))
  ..add(TradingLine(id: 'sl', kind: TradingLineKind.stopLoss, price: 29340, quantity: 0.5))
  ..add(TradingLine(id: 'a1', kind: TradingLineKind.alert, price: 30240));
```

Orders, TP / SL and alerts can be dragged (rounded to the price step);
labels show the quantity and P&L against the position or the last price.
Alerts fire when the last price crosses them (`AlertCondition`).

### Chart types and timeframes

```dart
candles.setData(heikinAshi(bars));
candles.setData(renko(bars, boxSize: 50));   // also lineBreak, rangeBars
final hourly = resample(minuteBars, const Timeframe.hours(1));   // .weeks(), .months()
final live = Resampler(const Timeframe.minutes(15));
candles.update(live.add(tick));                  // streaming
```

### Compare symbols

```dart
chart.addComparison(ethBars, title: 'ETH');   // switches the scale to %
chart.addComparison(solBars, title: 'SOL');
```

### Drawing tools

`DrawingEditor` puts a drawing layer on a pane and edits it with the pointer:

```dart
final editor = DrawingEditor(chart,
    onCreated: (d) => save(d), onChanged: (d) => save(d));

// pick a tool: taps place the anchors, or drag out a two-point tool
editor.tool = (id, anchors) => TrendLineDrawing(id: id, anchors: anchors, extendRight: true);

// without a tool: tap selects, drag moves, drag a handle reshapes
editor.deleteSelected();
```

Built in: trend line / ray / extended line / arrow, horizontal line and ray,
vertical line, cross line, rectangle, ellipse, parallel channel, Fibonacci
retracement, text, price & date measurement, multi-point paths with labels
(Elliott waves, XABCD) and freehand. Anchors are a fractional logical index
and a price, so drawings can extend past the last bar. For anything else,
extend `Drawing` (`anchorCount`, `paint`, `hitDistance`). Set `snap` for a
magnet, `keepTool` to draw several in a row, and
`TrackingModeOptions(longPressCrosshair: false)` to edit with long presses.

Lower level: `chart.subscribePointer` offers each drag (and long press) in a
pane to your handler; return `true` on `down` to take it, and the chart
won't scroll. `PaneApi.priceToCoordinate` / `coordinateToPrice` and the
`price` on click events convert between pixels and prices.

The API names follow upstream (`addCandlestickSeries`, `setData`, `update`,
`timeScale().fitContent()`, `scrollToRealTime()`, `subscribeCrosshairMove`, …),
so the upstream docs still apply.

The `example/` app has five tabs: a trading screen (switchable series types,
volume, SMA, an RSI pane with buy/sell markers, a watermark, live updates, an
OHLC legend, history lazy-loading, log/percentage scales, dark mode), a yield
curve, an options chain, pro tools (drawings, overlays, indicators, orders,
Heikin-Ashi, Renko, compare) and a watchlist with sparklines and a donut:

```sh
cd example && flutter run
```

### Sparklines

For list rows and cards, `SwmSparkline` draws a small line without a chart
engine behind it — no axes, scales or gestures:

```dart
SwmSparkline(
  values: closes,          // oldest first; non-finite values are skipped
  width: 80,
  height: 32,
  baseline: previousClose, // optional dashed reference; decides green / red
  curved: true,
)
```

`SwmSparklinePainter` paints the same line onto any `Canvas`, e.g. into an
image with a `PictureRecorder`.

### Donut charts

`SwmDonut` shows shares of a whole, e.g. a portfolio's allocation:

```dart
SwmDonut(
  slices: [
    for (final h in holdings) SwmDonutSlice(value: h.value, color: h.color),
  ],
  size: 130,
  innerRadius: 38,
  thickness: 30,
  selected: touched,                       // drawn thicker
  onSelect: (i) => setState(() => touched = i), // null on release
  center: Text(touched == null ? 'Total' : holdings[touched!].symbol),
)
```

## Performance

Frame times in profile mode with 100k candles plus 100k volume columns
(`example/integration_test/perf_test.dart`):

| Scenario | iPhone build / raster (avg, ms) | macOS build / raster (avg, ms) |
|---|---|---|
| Scroll at normal zoom | 1.9 / 1.4 | 1.0 / 1.2 |
| Realtime update every frame | 2.1 / 1.9 | 1.3 / 1.7 |
| Crosshair moving | 1.9 / 2.3 | 0.6 / 0.9 |
| All 100k visible, conflation on | 2.4 / 2.1 | 1.1 / 1.2 |
| All 100k visible, conflation off | 28.7 / 16.9 | 16 / 8 |

When users can zoom out over tens of thousands of bars, turn on
`TimeScaleOptions(enableConflation: true)` (optionally with
`precomputeConflationOnInit`), as upstream recommends.

Run the benchmark yourself:

```sh
cd example
flutter drive --profile -d <device> \
  --driver=test_driver/perf_driver.dart --target=integration_test/perf_test.dart
```

## Interaction

| | Touch | Mouse |
|---|---|---|
| Crosshair | tap to show / hide, then drag to move it; or long-press and move | follows the pointer |
| Scroll / zoom | drag (locked to its main direction), pinch | drag, wheel |
| Scale an axis | drag it; double-tap resets | drag it; double-click resets |
| Resize panes | drag the separator | drag the separator (`resizeRow` cursor) |

## Notes

- `SwmChart(semanticsLabel: ...)` names the chart for screen readers; its
  value lists each series' last value.
- Inside a vertical `ListView`, vertical drags go to the list; set
  `handleScroll: HandleScrollOptions(vertTouchDrag: false)` so the chart never
  claims them.
- `time` is a `num`: UTC seconds on time charts, months on yield curves,
  prices on options charts. `series.data()` returns values and whitespace.
- `SeriesOptions` are generated by `tool/gen_series_options.py`; edit the
  script, not `lib/src/series_options.dart`.
- Labels use the UTC components of `time`. To show exchange-local time, shift
  the timestamps or pass `LocalizationOptions.timeFormatter` /
  `TimeScaleOptions.tickMarkFormatter`.

## License & attribution

Apache License 2.0 (see `LICENSE` and `NOTICE`). The code is derived from
TradingView Lightweight Charts™. Upstream's NOTICE requires apps that use it
to show attribution to TradingView with a link to
https://www.tradingview.com/, e.g. on an About screen. The chart can show
the TradingView logo for you (`layout.attributionLogo: true`, off by default;
pass `SwmChart(onAttributionLogoTap: ...)` to open the link).
