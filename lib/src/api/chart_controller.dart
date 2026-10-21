import 'dart:ui' as ui;
import 'dart:ui' show Offset, Size;

import 'package:meta/meta.dart';

import '../data.dart';
import '../model/chart_model.dart';
import '../model/pane.dart';
import '../model/price_line.dart';
import '../model/price_scale.dart';
import '../model/series.dart';
import '../model/time_scale.dart';
import '../options.dart';
import '../plugins/primitive.dart';
import '../series_options.dart';

/// Payload of crosshair-move and click events, like `MouseEventParams`.
class ChartEventParams {
  const ChartEventParams({this.time, this.logical, this.point, this.paneIndex, this.seriesData = const {}});

  /// UTC seconds of the bar under the pointer, `null` outside the data.
  final int? time;

  /// Logical index of the bar under the pointer.
  final int? logical;

  /// Pane coordinates in logical pixels; `null` when the crosshair was hidden.
  final Offset? point;

  /// Index of the pane under the pointer.
  final int? paneIndex;

  /// Data of every series at [time].
  final Map<SeriesApi, SeriesData> seriesData;
}

typedef ChartEventHandler = void Function(ChartEventParams params);
typedef LogicalRangeChangeHandler = void Function(LogicalRange? range);
typedef TimeRangeChangeHandler = void Function(({int from, int to})? range);
typedef SizeChangeHandler = void Function(double width, double height);

typedef CandlestickSeriesApi = SeriesApi<CandlestickData, CandlestickSeriesOptions>;
typedef BarSeriesApi = SeriesApi<BarData, BarSeriesOptions>;
typedef LineSeriesApi = SeriesApi<LineData, LineSeriesOptions>;
typedef AreaSeriesApi = SeriesApi<AreaData, AreaSeriesOptions>;
typedef BaselineSeriesApi = SeriesApi<BaselineData, BaselineSeriesOptions>;
typedef HistogramSeriesApi = SeriesApi<HistogramData, HistogramSeriesOptions>;

/// Entry point of the library, the equivalent of `IChartApi`.
///
/// ```dart
/// final chart = ChartController();
/// final candles = chart.addCandlestickSeries();
/// candles.setData(bars);
/// // ...
/// SwmChart(controller: chart);
/// ```
class ChartController {
  ChartController({ChartOptions options = const ChartOptions()}) : _model = ChartModel(options) {
    _model.crosshairMoveListeners.add((p) => _dispatch(_crosshairMoveHandlers, p));
    _model.clickListeners.add((p) => _dispatch(_clickHandlers, p));
    _model.dblClickListeners.add((p) => _dispatch(_dblClickHandlers, p));
  }

  final ChartModel _model;
  final Map<SeriesModel, SeriesApi> _seriesApis = {};
  final Map<Pane, PaneApi> _paneApis = {};
  final List<ChartEventHandler> _crosshairMoveHandlers = [];
  final List<ChartEventHandler> _clickHandlers = [];
  final List<ChartEventHandler> _dblClickHandlers = [];
  late final TimeScaleApi _timeScaleApi = TimeScaleApi._(_model);
  late final _Host _host = _Host(_model);

  /// Set by the widget so [takeScreenshot] can render it.
  @internal
  Future<ui.Image> Function()? screenshotDelegate;

  @internal
  ChartModel get model => _model;

  ChartOptions get options => _model.options;

  void applyOptions(ChartOptions options) => _model.applyOptions(options);

  // ---- series ----

  CandlestickSeriesApi addCandlestickSeries([
    CandlestickSeriesOptions options = const CandlestickSeriesOptions(),
    int paneIndex = 0,
  ]) =>
      _add(CandlestickSeriesModel(options), paneIndex);

  BarSeriesApi addBarSeries([BarSeriesOptions options = const BarSeriesOptions(), int paneIndex = 0]) =>
      _add(BarSeriesModel(options), paneIndex);

  LineSeriesApi addLineSeries([LineSeriesOptions options = const LineSeriesOptions(), int paneIndex = 0]) =>
      _add(LineSeriesModel(options), paneIndex);

  AreaSeriesApi addAreaSeries([AreaSeriesOptions options = const AreaSeriesOptions(), int paneIndex = 0]) =>
      _add(AreaSeriesModel(options), paneIndex);

  BaselineSeriesApi addBaselineSeries([
    BaselineSeriesOptions options = const BaselineSeriesOptions(),
    int paneIndex = 0,
  ]) =>
      _add(BaselineSeriesModel(options), paneIndex);

  HistogramSeriesApi addHistogramSeries([
    HistogramSeriesOptions options = const HistogramSeriesOptions(),
    int paneIndex = 0,
  ]) =>
      _add(HistogramSeriesModel(options), paneIndex);

  SeriesApi<T, O> _add<T extends SeriesData, O extends SeriesOptions>(SeriesModel<T, O> series, int paneIndex) {
    final api = SeriesApi<T, O>._(this, series);
    _seriesApis[series] = api;
    _model.addSeries(series, paneIndex: paneIndex);
    return api;
  }

  void removeSeries(SeriesApi series) {
    _seriesApis.remove(series._series);
    _model.removeSeries(series._series);
  }

  // ---- panes ----

  PaneApi _paneApi(Pane pane) => _paneApis.putIfAbsent(pane, () => PaneApi._(this, pane));

  List<PaneApi> panes() => [for (final p in _model.panes) _paneApi(p)];

  /// Adds an empty pane at the bottom. With [preserveEmptyPane] the pane is
  /// kept even without series.
  PaneApi addPane({bool preserveEmptyPane = false}) => _paneApi(_model.addPane(preserveEmpty: preserveEmptyPane));

  /// Removes the pane and its series.
  void removePane(int index) {
    if (index < 0 || index >= _model.panes.length || _model.panes.length < 2) return;
    final pane = _model.panes[index];
    for (final s in pane.series) {
      _seriesApis.remove(s);
    }
    _paneApis.remove(pane);
    _model.removePane(index);
  }

  void swapPanes(int first, int second) => _model.swapPanes(first, second);

  TimeScaleApi timeScale() => _timeScaleApi;

  /// The price scale [id] (`right`, `left` or an overlay id) of pane [paneIndex].
  PriceScaleApi priceScale([String id = rightPriceScaleId, int paneIndex = 0]) =>
      PriceScaleApi._(_model, _model.panes[paneIndex], id);

  // ---- events ----

  void subscribeCrosshairMove(ChartEventHandler handler) => _crosshairMoveHandlers.add(handler);

  void unsubscribeCrosshairMove(ChartEventHandler handler) => _crosshairMoveHandlers.remove(handler);

  void subscribeClick(ChartEventHandler handler) => _clickHandlers.add(handler);

  void unsubscribeClick(ChartEventHandler handler) => _clickHandlers.remove(handler);

  void subscribeDblClick(ChartEventHandler handler) => _dblClickHandlers.add(handler);

  void unsubscribeDblClick(ChartEventHandler handler) => _dblClickHandlers.remove(handler);

  /// Shows the crosshair at [price] / [time] of [series], e.g. to sync two charts.
  void setCrosshairPosition(double price, int time, SeriesApi series) {
    final s = series._series;
    final paneIndex = _model.paneIndexOf(s);
    final x = _timeScaleApi.timeToCoordinate(time);
    if (paneIndex < 0 || x == null || s.priceScale.isEmpty) return;
    _model.setCrosshairPosition(paneIndex, Offset(x, s.priceToCoordinate(price)), exact: true);
  }

  void clearCrosshairPosition() => _model.setCrosshairPosition(null, null);

  /// Renders the chart to an image. The chart must be on screen.
  Future<ui.Image> takeScreenshot() {
    final delegate = screenshotDelegate;
    if (delegate == null) throw StateError('The chart is not mounted');
    return delegate();
  }

  void _dispatch(List<ChartEventHandler> handlers, ModelEventParams p) {
    if (handlers.isEmpty) return;
    final params = ChartEventParams(
      time: p.time,
      logical: p.logical,
      point: p.point,
      paneIndex: p.paneIndex,
      seriesData: {
        for (final e in p.seriesData.entries)
          if (_seriesApis[e.key] != null) _seriesApis[e.key]!: e.value,
      },
    );
    for (final h in List.of(handlers)) {
      h(params);
    }
  }

  void dispose() {
    _crosshairMoveHandlers.clear();
    _clickHandlers.clear();
    _dblClickHandlers.clear();
    _model.dispose();
  }
}

class _Host implements PrimitiveHost {
  _Host(this._model);

  final ChartModel _model;

  @override
  void requestUpdate() => _model.invalidate();

  @override
  double get barSpacing => _model.timeScale.barSpacing;
}

/// Result of [SeriesApi.barsInLogicalRange].
class BarsInfo {
  const BarsInfo({required this.barsBefore, required this.barsAfter, this.from, this.to});

  /// Logical distance from the first bar to the start of the range
  /// (negative when the range starts before the first bar).
  final double barsBefore;

  /// Logical distance from the end of the range to the last bar.
  final double barsAfter;

  /// Time of the first/last series bar inside the range.
  final int? from;
  final int? to;
}

/// Handle of a custom price line.
class PriceLineApi {
  PriceLineApi._(this._model, this._line);

  final ChartModel _model;
  final PriceLine _line;

  PriceLineOptions get options => _line.options;

  void applyOptions(PriceLineOptions options) {
    _line.options = options;
    _model.invalidate();
  }
}

/// A series on the chart, the equivalent of `ISeriesApi`.
class SeriesApi<T extends SeriesData, O extends SeriesOptions> {
  SeriesApi._(this._chart, this._series);

  final ChartController _chart;
  final SeriesModel<T, O> _series;

  ChartModel get _model => _chart._model;

  O get options => _series.options;

  void applyOptions(O options) {
    _series.options = options;
    _model.seriesOptionsChanged(_series);
  }

  /// Replaces all data. [data] must be sorted by strictly ascending time.
  void setData(List<T> data) => _model.setSeriesData<T>(_series, data);

  /// Updates the last bar if [item] has the same time, appends it otherwise.
  /// Updating bars older than the last one is not supported, as upstream.
  void update(T item) => _model.updateSeries<T>(_series, item);

  /// A copy of the series data.
  List<T> data() => List.unmodifiable(_series.data);

  /// Data at a logical index, or `null` when this series has no bar there.
  T? dataByIndex(int logicalIndex) => _series.itemAt(logicalIndex);

  /// Y coordinate in pane logical pixels, `null` when the scale is empty.
  double? priceToCoordinate(double price) => _series.priceScale.isEmpty ? null : _series.priceToCoordinate(price);

  double? coordinateToPrice(double y) => _series.priceScale.isEmpty ? null : _series.coordinateToPrice(y);

  /// Formats a price as this series' axis label does.
  String formatPrice(double price) => _model.formatSeriesPrice(_series, price);

  /// The price scale this series is attached to.
  PriceScaleApi priceScale() {
    final pane = _model.panes[_model.paneIndexOf(_series)];
    return PriceScaleApi._(_model, pane, _series.priceScale.id);
  }

  /// How many bars of this series are before/after [range]; handy to decide
  /// when to load more history.
  BarsInfo? barsInLogicalRange(LogicalRange range) {
    if (_series.data.isEmpty) return null;
    final indices = _series.indices;
    final first = _series.lowerBound(range.from.ceil());
    final last = _series.lowerBound(range.to.floor() + 1) - 1;
    final inside = first <= last;
    return BarsInfo(
      barsBefore: range.from - indices.first,
      barsAfter: indices.last - range.to,
      from: inside ? _series.data[first].time : null,
      to: inside ? _series.data[last].time : null,
    );
  }

  // ---- price lines ----

  PriceLineApi createPriceLine(PriceLineOptions options) {
    final line = PriceLine(options);
    _series.priceLines.add(line);
    _model.invalidate();
    return PriceLineApi._(_model, line);
  }

  void removePriceLine(PriceLineApi line) {
    _series.priceLines.remove(line._line);
    _model.invalidate();
  }

  List<PriceLineApi> priceLines() => [for (final l in _series.priceLines) PriceLineApi._(_model, l)];

  // ---- primitives ----

  void attachPrimitive(ChartPrimitive primitive) {
    _series.primitives.add(primitive);
    primitive.attached(_chart._host);
    _model.invalidate();
  }

  void detachPrimitive(ChartPrimitive primitive) {
    if (_series.primitives.remove(primitive)) primitive.detached();
    _model.invalidate();
  }

  // ---- panes ----

  PaneApi getPane() => _chart._paneApi(_model.panes[_model.paneIndexOf(_series)]);

  /// Moves the series to pane [paneIndex], creating it if needed.
  void moveToPane(int paneIndex) => _model.moveSeriesToPane(_series, paneIndex);
}

/// A pane, the equivalent of `IPaneApi`.
class PaneApi {
  PaneApi._(this._chart, this._pane);

  final ChartController _chart;
  final Pane _pane;

  ChartModel get _model => _chart._model;

  /// Current index, or -1 once removed.
  int paneIndex() => _model.panes.indexOf(_pane);

  double getHeight() => _pane.height;

  void setHeight(double height) {
    final index = paneIndex();
    if (index >= 0) _model.setPaneHeight(index, height);
  }

  double getStretchFactor() => _pane.stretchFactor;

  void setStretchFactor(double factor) {
    _pane.stretchFactor = factor;
    _model.invalidate();
  }

  bool get preserveEmptyPane => _pane.preserveEmpty;

  set preserveEmptyPane(bool value) => _pane.preserveEmpty = value;

  List<SeriesApi> getSeries() => [
        for (final s in _pane.series)
          if (_chart._seriesApis[s] != null) _chart._seriesApis[s]!,
      ];

  PriceScaleApi priceScale(String id) => PriceScaleApi._(_model, _pane, id);

  /// Moves this pane to [index].
  void moveTo(int index) {
    final from = paneIndex();
    if (from < 0 || index < 0 || index >= _model.panes.length || from == index) return;
    _model.panes
      ..removeAt(from)
      ..insert(index, _pane);
    _model.invalidate();
  }

  void attachPrimitive(ChartPrimitive primitive) {
    _pane.primitives.add(primitive);
    primitive.attached(_chart._host);
    _model.invalidate();
  }

  void detachPrimitive(ChartPrimitive primitive) {
    if (_pane.primitives.remove(primitive)) primitive.detached();
    _model.invalidate();
  }
}

/// The equivalent of `ITimeScaleApi`.
class TimeScaleApi {
  TimeScaleApi._(this._model);

  final ChartModel _model;
  final Map<Object, Object> _handlers = {};

  TimeScale get _ts => _model.timeScale;

  TimeScaleOptions get options => _ts.options;

  void applyOptions(TimeScaleOptions options) => _model.applyOptions(_model.options.copyWith(timeScale: options));

  /// Shows all data.
  void fitContent() {
    _model.cancelAnimations();
    _ts.fitContent();
    _model.invalidate();
  }

  /// Scrolls to the most recent bar.
  void scrollToRealTime({bool animated = true}) => scrollToPosition(_ts.options.rightOffset, animated: animated);

  /// Scrolls so the last bar is [position] bars from the right edge.
  void scrollToPosition(double position, {bool animated = false}) {
    if (animated) {
      _model.animateRightOffset(position);
      return;
    }
    _model.cancelAnimations();
    _ts.setRightOffset(position);
    _model.invalidate();
  }

  /// Distance of the last bar from the right edge, in bars.
  double scrollPosition() => _ts.rightOffset;

  /// Restores default bar spacing and right offset.
  void resetTimeScale() {
    _ts.restoreDefault();
    _model.invalidate();
  }

  LogicalRange? getVisibleLogicalRange() => _ts.visibleLogicalRange();

  void setVisibleLogicalRange(LogicalRange range) {
    _model.cancelAnimations();
    _ts.setLogicalRange(range);
    _model.invalidate();
  }

  /// Visible range as UTC seconds, clamped to the data.
  ({int from, int to})? getVisibleRange() {
    final range = _ts.visibleStrictRange();
    if (range == null || _ts.pointsCount == 0) return null;
    final last = _ts.pointsCount - 1;
    final from = range.left.clamp(0, last);
    final to = range.right.clamp(0, last);
    return (from: _ts.times[from], to: _ts.times[to]);
  }

  /// Shows the bars between [from] and [to] (UTC seconds).
  void setVisibleRange(int from, int to) {
    final a = _ts.timeToIndex(from, findNearest: true);
    final b = _ts.timeToIndex(to, findNearest: true);
    if (a == null || b == null) return;
    setVisibleLogicalRange(LogicalRange(a.toDouble(), b.toDouble()));
  }

  /// Fires when the visible logical range changes (scroll, zoom, new data).
  /// Handy for loading more history when `range.from` gets close to 0.
  void subscribeVisibleLogicalRangeChange(LogicalRangeChangeHandler handler) {
    void listener(LogicalRange? r) => handler(r);
    _handlers[handler] = listener;
    _model.visibleLogicalRangeListeners.add(listener);
  }

  void unsubscribeVisibleLogicalRangeChange(LogicalRangeChangeHandler handler) {
    final listener = _handlers.remove(handler);
    _model.visibleLogicalRangeListeners.remove(listener);
  }

  /// Fires when the visible time range changes.
  void subscribeVisibleTimeRangeChange(TimeRangeChangeHandler handler) {
    void listener(LogicalRange? _) => handler(getVisibleRange());
    _handlers[handler] = listener;
    _model.visibleLogicalRangeListeners.add(listener);
  }

  void unsubscribeVisibleTimeRangeChange(TimeRangeChangeHandler handler) {
    final listener = _handlers.remove(handler);
    _model.visibleLogicalRangeListeners.remove(listener);
  }

  /// Fires when the chart size changes.
  void subscribeSizeChange(SizeChangeHandler handler) {
    void listener(Size s) => handler(s.width, s.height);
    _handlers[handler] = listener;
    _model.sizeListeners.add(listener);
  }

  void unsubscribeSizeChange(SizeChangeHandler handler) {
    final listener = _handlers.remove(handler);
    _model.sizeListeners.remove(listener);
  }

  double? timeToCoordinate(int time) {
    final index = _ts.timeToIndex(time);
    return index == null ? null : _ts.indexToCoordinate(index);
  }

  double logicalToCoordinate(double logical) => _ts.indexToCoordinate(logical);

  double coordinateToLogical(double x) => _ts.coordinateToFloatIndex(x);

  int? coordinateToTime(double x) => _ts.indexToTime(_ts.coordinateToIndex(x));

  /// Width of the time scale (pane width) in logical pixels.
  double width() => _ts.width;

  /// Height of the time axis in logical pixels.
  double height() => _model.timeAxisHeight;
}

/// The equivalent of `IPriceScaleApi`.
class PriceScaleApi {
  PriceScaleApi._(this._model, this._pane, this.id);

  final ChartModel _model;
  final Pane _pane;
  final String id;

  PriceScale get _ps => _pane.priceScale(id, _model.options);

  bool get _isSide => id == rightPriceScaleId || id == leftPriceScaleId;

  PriceScaleOptions get options => _ps.options;

  /// Applies to this pane's scale. `visible` of the left/right scales is
  /// chart-wide, as the axes are shared by all panes.
  void applyOptions(PriceScaleOptions options) {
    if (!_isSide) {
      _ps.options = options.copyWith(visible: false);
    } else {
      _ps.options = options;
      final chart = _model.options;
      final current = id == rightPriceScaleId ? chart.rightPriceScale : chart.leftPriceScale;
      if (current.visible != options.visible) {
        // Changing visibility rebuilds every pane's scale from chart options.
        final updated = current.copyWith(visible: options.visible);
        _model.applyOptions(id == rightPriceScaleId
            ? chart.copyWith(rightPriceScale: updated)
            : chart.copyWith(leftPriceScale: updated));
        _ps.options = options;
      }
    }
    _model.invalidate();
  }

  /// Width of the price axis in logical pixels (0 for overlay scales).
  double width() => id == rightPriceScaleId
      ? _model.rightAxisWidth
      : id == leftPriceScaleId
          ? _model.leftAxisWidth
          : 0;

  /// Visible range in prices (percent in the percentage modes), `null` until
  /// the chart has been laid out.
  PriceRange? getVisibleRange() => _ps.priceRange;

  /// Sets the visible range and turns autoscale off.
  void setVisibleRange(PriceRange range) {
    _ps.options = _ps.options.copyWith(autoScale: false);
    _ps.setInternalRange(_ps.isLog ? _ps.toInternalRange(range, 0) : range);
    _model.invalidate();
  }

  void setAutoScale(bool on) {
    _ps.options = _ps.options.copyWith(autoScale: on);
    _model.invalidate();
  }
}
