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
