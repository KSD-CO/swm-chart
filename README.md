# swm_chart

Financial charts for Flutter. This is a native Dart port of
[TradingView Lightweight Charts™](https://github.com/tradingview/lightweight-charts) (based on v5.2.1).

There is no WebView. Everything is drawn with `CustomPainter`, and the
model/renderer architecture mirrors upstream. Candles, columns and grid lines
are drawn in device pixels, the same way upstream draws in bitmap
coordinates, so they stay sharp.

## Status (MVP)

| Feature | Status |
|---|---|
| Candlestick, Line (simple/stepped, dashed), Histogram series | ✅ |
| Overlay price scales (e.g. volume in the bottom 20%) | ✅ |
| Time scale: bar spacing, right offset, tick marks by weight (year/month/day/time) | ✅ port of upstream |
| Price scale: autoscale, margins, tick marks | ✅ port of upstream |
| Crosshair: normal / magnet / magnet OHLC, axis labels | ✅ |
| Last value label + price line | ✅ |
| Gestures: pan + kinetic, pinch zoom, long-press crosshair, axis drag, double-tap reset | ✅ |
| `setData` / `update` realtime, prepend history while keeping the view | ✅ |
| Events: crosshair move, click, visible logical range change | ✅ |
| Area, Bar, Baseline series | ⏳ |
| Multiple panes, markers, custom price lines, log/percentage mode | ⏳ |
| Plugins / primitives API | ⏳ |

## Usage

```dart
final chart = ChartController(
  options: const ChartOptions(timeScale: TimeScaleOptions(timeVisible: true)),
);

final candles = chart.addCandlestickSeries();
candles.setData([
  CandlestickData(time: 1704067200, open: 100, high: 105, low: 98, close: 103),
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

The API names follow upstream (`addCandlestickSeries`, `setData`, `update`,
`timeScale().fitContent()`, `scrollToRealTime()`, `subscribeCrosshairMove`, …),
so the upstream docs still apply.

The `example/` app is a trading screen with candles, volume, live updates,
an OHLC legend, history lazy-loading and dark mode:

```sh
cd example && flutter run
```

## Known limitations

- A horizontal pan on the chart competes with a vertical `ListView` for the
  gesture. The chart works best on its own screen or with a fixed height.
- Labels use the UTC components of `time`. To show exchange-local time, shift
  the timestamps or pass `LocalizationOptions.timeFormatter` /
  `TimeScaleOptions.tickMarkFormatter`.

## License & attribution

Apache License 2.0 (see `LICENSE` and `NOTICE`). The code is derived from
TradingView Lightweight Charts™. Upstream's NOTICE requires apps that use it
to show attribution to TradingView with a link to
https://www.tradingview.com/ somewhere users can see it, for example an
"About" screen.
