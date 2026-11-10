## 0.16.0

* `DrawingLabels`: the words drawings write on the chart — a position's
  target, stop, long / short, quantity and risk / reward, "bars" after a
  bar count and the units of a duration. Set `DrawingLabels.current` to
  your app's language.
* Breaking: `barsLabel` of `DateRangeDrawing`, `MeasureDrawing` and
  `InfoLineDrawing` is now `String?` (`null` follows
  `DrawingLabels.current`). `DrawingCodec` saves it only when set, and
  reads the "bars" 0.15.0 saved with every drawing back as `null`.

## 0.15.0

* `ProChartStrings`: every label, tooltip and message of `SwmProChart`,
  its sheets and dialogs, English by default — pass your app's words to
  `SwmProChart.strings` or a `ProChartStringsScope`. Function fields name
  the catalog's indicators, groups and inputs, the drawing tools, line
  styles and chart types; the indicator search matches translated names.
* `IndicatorCatalog.register` / `unregister`: an app's own indicators in
  the picker (new `IndicatorGroup.custom`), added, set and saved like the
  built-in ones; `IndicatorCatalog.available` and `registered`.
* `ProChartController.drawingKinds` and `SwmProChart.toolGroups`: your own
  drawing tools on the toolbar, saved, restored and duplicated.
* Display settings: `crosshairStyle`, `crosshairColor`, `crosshairWidth`,
  `showGrid`, `showWatermark` and `resetDisplay` on the controller, a
  Chart display sheet (`showChartDisplaySheet`, `ChartDisplaySettings`)
  in the settings menu, and a `display` part in `saveState`. Changing them
  keeps the price scale's mode.
* Fourteen more drawing tools, saved and restored by `DrawingCodec`:
  `TrendAngleDrawing`, `InfoLineDrawing`, `RangeVolumeProfileDrawing`
  (fixed range or anchored), `HarmonicDrawing` (XABCD, Cypher),
  `HeadAndShouldersDrawing`, `SineLineDrawing`, `CyclicLinesDrawing`,
  `TimeCyclesDrawing`, `FibFanDrawing`, `FibArcDrawing`, `IconMarkDrawing`
  (flags and emoji, saved by key through `DrawingCodec.icons`) and
  `PriceLabelDrawing`.
* `DrawingTools.groups`: 51 tools in seven groups — lines, channels and
  pitchforks, Fibonacci and Gann, patterns and cycles (ABCD, triangle,
  three drives and the Elliott waves too), forecasting and measuring
  (volume profiles too), shapes (highlighter too) and annotations (price
  label, flag, emoji too).
* `SwmProChart.toolbarMode`: the drawing toolbar docked down the left (as
  before), or `DrawingToolbarMode.floating` — behind a pencil button over
  the chart, which keeps the full width. New string
  `ProChartStrings.drawingTools`.

## 0.14.0

* `SwmProChart`: a ready-made trading screen around a `ProChartController`
  — a top bar (symbol, interval, chart type, indicator picker, undo /
  redo, log / percent scale, volume), a drawing toolbar with the tools in
  groups (magnet, keep drawing, hide / remove all) and a style bar for the
  selected drawing (color, width, line style, text, lock, duplicate,
  delete). The parts are public widgets: `ProChartTopBar`,
  `DrawingToolbar`, `DrawingStyleBar`, `IndicatorPicker` /
  `showIndicatorSheet`, `showIndicatorSettings`.
* `ProChartController`: the price series in seven styles (candles, hollow
  candles, bars, line, area, baseline, Heikin-Ashi), volume, indicators,
  drawings, trading lines and a legend; `saveState` / `restoreState` the
  whole chart as JSON, `saveIndicators` / `restoreIndicators` templates.
* `IndicatorCatalog`: all 73 indicators by id, with their inputs
  (`IndicatorSpec`, `IndicatorParam`) and groups — for pickers, settings
  and saved charts.
* New drawings: `PositionDrawing` (long / short with target, stop, R:R and
  amounts), `FibExtensionDrawing`, `FibTimeZoneDrawing`,
  `PitchforkDrawing` (Andrews, Schiff, modified Schiff), `GannFanDrawing`,
  `AnchoredVwapDrawing` (with bands), `RegressionTrendDrawing`,
  `CalloutDrawing`, `DateRangeDrawing`, `PriceRangeDrawing`; all saved by
  `DrawingCodec` (`source` / `volume` for those that read the data).
* `DrawingEditor.update` (a change as one undo step) and `duplicate`;
  `Drawing.completed` and `selectedAxisPrices`; `DrawingContext.timeOf`.
* Example: a Pro tab with `SwmProChart`, live ticks, intervals and save /
  restore; screenshots of it.

## 0.13.1

* `CrosshairSync` across intervals: a time between the other chart's bars
  (02:00 on a 4h chart) now lands on the bar holding it; before, that
  chart's crosshair didn't move.
* Tooltip legend: the box stays inside the pane when it fits on neither
  side of the crosshair.
* Example: Pro tools adds Trend (Supertrend, HMA, ADX, Stoch RSI with a
  tooltip), Analysis (ZigZag, Elliott count, auto trendlines, support /
  resistance, candlestick patterns), Sessions (session volume profiles),
  Forecast (fan) and Sync (1h / 4h charts) — with screenshots.
* README: reorganized — captioned gallery, contents, installation, quick
  start, then the guide by topic.

## 0.13.0

* 47 more chart indicators — 73 built in — each one line to add, each
  over a new `Ta` function:
  * Moving averages: `Hma`, `Dema`, `Tema`, `Rma`, `Vwma`, `Alma`,
    `Lsma`, `Zlema`, `T3`, `McGinley`, `Envelope`, `Alligator`,
    `ChandelierExit`.
  * Oscillators: `StochRsi`, `Trix`, `UltimateOscillator`,
    `AwesomeOscillator`, `AcceleratorOscillator`, `Ppo`, `Dpo`,
    `Momentum`, `Cmo`, `Tsi`, `Coppock`, `Kst`, `FisherTransform`,
    `ConnorsRsi`, `Rvi`, `Smi`, `Choppiness`, `Vortex`, `ElderRay`,
    `BalanceOfPower`, `MassIndex`.
  * Volume: `AccumulationDistribution`, `ChaikinOscillator`,
    `PriceVolumeTrend`, `VolumeIndexes` (NVI / PVI), `Klinger`,
    `ForceIndex`, `EaseOfMovement`, `VolumeOscillator`.
  * Volatility: `StandardDeviation`, `HistoricalVolatility`,
    `BollingerPercentB`, `BollingerWidth`, `UlcerIndex`.
* `Ta`: the functions above, plus `Ta.trueRange`, `Ta.wma`, `Ta.rma`,
  `Ta.fractals` (Williams fractals) and `Ta.opens`. Multi-line results
  are records, e.g. `Ta.stochRsi(bars).k`.

## 0.12.0

* Value area: `VolumeProfileResult.valueAreaLow` / `valueAreaHigh` (VAL /
  VAH), the range around the point of control holding 70% of the volume,
  and `Ta.valueArea` to compute it for any profile.
* `Ta.sessionVolumeProfiles`: a volume profile per session — by default
  each calendar day of intraday bars, or any key via `sessionOf`.
* `VolumeProfileOptions.valueArea`: marks the value area — bins outside
  it dimmed (`outsideOpacity`), VAH and VAL as dashed lines
  (`valueAreaLineColor`).
* `SessionVolumeProfilePrimitive`: each session's profile drawn over its
  own bars, growing right from the session's first bar, with its point of
  control and value area.

## 0.11.0

* Faster crosshair and animations: the chart paints in two layers. The
  content (grid, series, axes) sits in its own repaint boundary; the
  overlay (crosshair and its axis labels, legend, trading lines,
  drawings, the last price pulse) paints over it. A crosshair move or a
  pulse frame repaints only the overlay — no layout, no series. About
  3× less paint work per crosshair move on 5,000 bars with 6 lines.
  `ChartModel.overlay` notifies overlay-only changes.
* `FanPrimitive`: a forecast fan (cone) — nested ranges (e.g. 80% and
  95%) and a center line drawn forward from a bar into the future, on
  logical indices past the last bar. Takes part in autoscale; smooth or
  straight edges.
* `DrawingCodec`: save drawings as JSON-ready maps and load them back,
  with anchors stored by time (they don't shift when history is paged in).
  All built-in drawings are known; `DrawingKind` adds custom ones.
* `DrawingEditor`: undo / redo (`undo`, `redo`, `canUndo`, `canRedo`,
  `onHistoryChanged`, `checkpoint` for changes made outside the editor)
  over creating, moving, reshaping, removing and clearing.
* `Drawing.pricesAt(logical)` and `DrawingEditor.pricesAt(time)`: a
  drawing's line prices at a bar — trend line, horizontal line, channel
  rails, rectangle — for alerts.
* `CrosshairSync`: keeps the crosshair of several charts on the same time.
* `TimeScaleApi.timeToLogical` / `logicalToTime` (and `logicalOfTime` /
  `timeOfLogical`): fractional logical index ↔ time, interpolated between
  bars and extrapolated past them.
* `Drawing.kind`: the name a drawing is saved under.

## 0.10.1

* `Ta.volumeProfile`: each `VolumeBucket` has `upVolume`, the part traded
  on up bars, to colour the profile by buyers and sellers
  (`VolumeProfileBin.upVolume`).

## 0.10.0

* 16 more chart indicators: `WilliamsR`, `Adx` (+DI / −DI), `Obv`, `Cci`,
  `Mfi`, `Cmf`, `Aroon`, `Roc`, `ParabolicSar`, `Kama`, `Keltner`,
  `Donchian`, `Supertrend`, `VolumeSma`, `SineWave`, `EvenBetterSinewave`
  (26 in all). Built on `TaIndicator`: recomputed over the series on each
  update.
* `Ta`: technical analysis as plain functions over OHLCV bars (`TaBar`,
  implement it on your own bar type, or use `TaPoint`) — every indicator
  above plus the analysis tools: ZigZag, automatic Elliott wave counts,
  support / resistance, chart patterns (head & shoulders, double tops,
  triangles, wedges, flags, cup & handle…), candlestick patterns, automatic
  trendlines, RSI divergences, Fibonacci levels, pivot points, regression
  channel and volume profile. Moved from Stock World Monitor, so the app,
  its screener, alerts and backtests use the same math.

## 0.9.0

* Indicators: `Sma`, `Ema`, `Wma`, `Bollinger`, `Rsi`, `Macd`,
  `Stochastic`, `Atr`, `Vwap`, `Ichimoku`, added with
  `chart.addIndicator(indicator, source:)`. Incremental on ticks and new
  bars; oscillators get their own pane with levels.
* `TradingLines`: draggable orders, take profit / stop loss, positions with
  P&L, and price alerts (crossing / up / down) with `onAlert`.
* `createLegend`: legend rows or a tooltip following the crosshair.
* Chart types and timeframes: `heikinAshi` / `HeikinAshi`, `renko`,
  `lineBreak`, `rangeBars`, `resample` / `resampleSum` / `Resampler`
  (`Timeframe` minutes … months).
* `chart.addComparison`: compare symbols on a percentage scale.
* `PrimitiveContext.crosshairIndex` / `crosshairPosition`.
* Example: Pro tools tab with all of the above; new screenshots.

## 0.8.1

* Screenshots of the drawing tools, overlays, sparklines and donut.
* Example: Tools tab (drawings / overlays) and Watchlist tab.

## 0.8.0

* `SwmDonut`: a donut (ring) chart for shares of a whole. Slices clockwise
  from 12 o'clock with a gap between them; touch to select one (reported
  through `onSelect`, drawn thicker), any widget in the hole.
  `SwmDonut.sliceAt` hit-tests a point; `SwmDonutPainter` paints one onto
  any canvas.

## 0.7.0

* `SwmSparkline`: a small, non-interactive line for list rows, cards and
  tiles — one `CustomPainter`, no axes or gestures, so a list of dozens
  stays light. Green / red by direction (or against a `baseline`, drawn
  dashed), optional gradient area, curved line and last-point dot.
  `SwmSparklinePainter` paints one onto any canvas (e.g. into an image).

## 0.6.1

* Touch: with the crosshair shown (after a tap or a long press), a
  one-finger drag moves it across the bars instead of scrolling, like
  TradingView's mobile app; a tap hides it and drags scroll again. Pointer
  handlers (drawing tools) still get the drag first.

## 0.6.0

* Drawing tools (`DrawingEditor`, `DrawingsPrimitive`, `Drawing`): trend
  lines, rays and arrows, horizontal / vertical / cross lines, rectangles,
  ellipses, parallel channels, Fibonacci retracements, text, price & date
  measurements, labelled multi-point paths (Elliott, XABCD) and freehand.
  Create by taps or a drag, select, move, reshape by handles, delete; snap
  hook for magnets; extend `Drawing` for custom tools.
* Overlays: `BandFillPrimitive`, `PriceLevelsPrimitive`,
  `VolumeProfilePrimitive`.
* Pointer capture: `ChartController.subscribePointer` / `ChartPointerEvent`
  lets a handler take a drag or long press in a pane instead of the chart.
* `TrackingModeOptions.longPressCrosshair` to hand long presses to pointer
  handlers.
* `PaneApi.priceToCoordinate` / `coordinateToPrice`; `ChartEventParams.price`.

## 0.5.1

* Screenshots on pub.dev and in the README (`tool/screenshots.sh`).
* Example: yield curve with fixed edges so the axis end labels stay inside.

## 0.5.0

* Desktop / web: the crosshair follows the mouse and hides when it leaves;
  mouse clicks no longer toggle it. Cursors like upstream: `resizeRow` on
  separators, `resizeUpDown` on price axes, `resizeLeftRight` on the time
  axis; primitives and custom series can set `cursor` from `hitTest`.
  Separators highlight on hover. Long-press is touch-only.
* `alignLabels` is a port of upstream's overlap algorithm (verified against
  it on 300 random label sets).
* Time axis labels are clipped like upstream, and only aligned inside the
  axis at fixed edges (`needAlignCoordinate`).
* Last price animation reproduces upstream's three stages.
* `PriceScaleOptions.textColor`.
* Price axes can't be drag-scaled in percentage / indexed-to-100 modes,
  like upstream.
* Accessibility: `SwmChart.semanticsLabel` and a last-values summary.
* CI and tag-based publishing workflows.

## 0.4.1

* Homepage: https://stockworldmonitor.com/
* Example: "SWM Chart" watermark.

## 0.4.0

* Renamed to **Stock World Monitor Charts** (package name stays `swm_chart`).
* Conflation now matches upstream's DataConflater: pairwise power-of-two
  levels with incremental updates, custom series `conflationReducer`,
  per-series `conflationThresholdFactor`, `precomputeConflationOnInit` and
  `precomputeConflationPriority`.
* `hoveredInfo` matches upstream: `type`, `sourceKind`, `objectKind`
  (incl. `seriesMarker`, `customObject`); primitive `itemType` and
  `hitTestPriority`; custom series `hitTest`.
* New bars no longer rebuild all time scale tick marks (only the tail,
  with identical results): realtime p99 frame build 6-14 ms -> ~2 ms.

* Performance: candles, bars and histograms are drawn in one vertex batch;
  autoscale uses a chunked min/max cache; prices and indices are converted
  with precomputed linear transforms; new bars are appended in place.
  Zooming out to 100k candles without conflation went from ~1.3 s to ~12 ms
  of raster time per frame (macOS, profile). Rendering is pixel-identical.
* Touch pans lock to their dominant direction, so horizontal swipes no
  longer drift a manual price scale.
* The TradingView attribution logo is now opt-in (`layout.attributionLogo`).
* Example: macOS target and a frame-timing benchmark
  (`example/integration_test/perf_test.dart`).

## 0.3.0

* Yield curve (`ChartController.yieldCurve`) and options
  (`ChartController.options`) charts; `SeriesData.time` is now `num`.
* Whitespace data, custom series, conflation, up/down markers plugin.
* Hit testing (`hoveredSeries`, `hoveredObjectId`), `hoveredSeriesOnTop`.
* All remaining upstream options: time scale (`rightOffsetPixels`,
  `lockVisibleTimeRangeOnResize`, `uniformDistribution`,
  `ignoreWhitespaceIndices`, ...), price scale (`ticksVisible`,
  `ensureEdgeTickMarksVisible`, `overlayPriceScales`), localization
  (`dateFormat`, `locale`, formatters), `handleScroll`/`handleScale`/
  `kineticScroll`/`trackingMode`, background gradient, attribution logo,
  `addDefaultPane`, `defaultVisiblePriceScaleId`.
* API: `pop`, `priceFormatter`, `lastValueData`, `seriesOrder`,
  `subscribeDataChanged`, `dataByIndex` mismatch direction, `paneSize`,
  `timeToIndex`, `pane.addSeries`.
* `fitContent()` before the first layout is applied once laid out.

## 0.2.0

* Multiple panes with draggable separators; pane API (add/remove/swap/move,
  height, stretch factor).
* Area, Bar and Baseline series; curved line type.
* Left price scale; logarithmic, percentage and indexed-to-100 modes.
* Custom price lines, price line source, base line, last price animation.
* Primitives (plugin) API, series markers, text and image watermarks.
* `autoscaleInfoProvider`, `setCrosshairPosition`, `takeScreenshot`,
  `barsInLogicalRange`, double-click, size and visible time range events.

## 0.1.0

* MVP port of TradingView Lightweight Charts v5.2.1: candlestick, line and
  histogram series, overlay price scales, time/price scale, crosshair,
  touch gestures, realtime updates and events.
