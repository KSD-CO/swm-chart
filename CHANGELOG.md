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
