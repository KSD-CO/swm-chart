# Stock World Monitor Charts

[![pub package](https://img.shields.io/pub/v/swm_chart.svg)](https://pub.dev/packages/swm_chart)

**Stock World Monitor Charts** (`swm_chart`), by
[Stock World Monitor](https://stockworldmonitor.com/), are high-performance financial
charts for Flutter. The package is a native Dart port of
[TradingView Lightweight Charts™](https://github.com/tradingview/lightweight-charts) (based on v5.2.1).

```yaml
dependencies:
  swm_chart: ^0.4.1
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
| Localization: locale, date format, month names, price/percentage/tick mark formatters | ✅ |
| Events: crosshair move, click, double click, visible logical/time range, size, data changed | ✅ |
| Gestures: pan + kinetic, pinch, long-press crosshair, axis drag, double-tap reset, mouse wheel — each switchable like `handleScroll` / `handleScale` | ✅ |
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

The API names follow upstream (`addCandlestickSeries`, `setData`, `update`,
`timeScale().fitContent()`, `scrollToRealTime()`, `subscribeCrosshairMove`, …),
so the upstream docs still apply.

The `example/` app has three tabs: a trading screen (switchable series types,
volume, SMA, an RSI pane with buy/sell markers, a watermark, live updates, an
OHLC legend, history lazy-loading, log/percentage scales, dark mode), a yield
curve and an options chain:

```sh
cd example && flutter run
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

## Notes

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
