import 'dart:ui' show Offset;

import 'package:meta/meta.dart';

import '../data.dart';
import '../model/chart_model.dart';
import '../model/price_scale.dart';
import '../model/series.dart';
import '../model/time_scale.dart';
import '../options.dart';

/// Payload of crosshair-move and click events, like `MouseEventParams`.
class ChartEventParams {
  const ChartEventParams({this.time, this.logical, this.point, this.seriesData = const {}});

  /// UTC seconds of the bar under the pointer, `null` outside the data.
  final int? time;

  /// Logical index of the bar under the pointer.
  final int? logical;

  /// Pane coordinates in logical pixels; `null` when the crosshair was hidden.
  final Offset? point;

  /// Data of every series at [time].
  final Map<SeriesApi, SeriesData> seriesData;
}

typedef ChartEventHandler = void Function(ChartEventParams params);
typedef LogicalRangeChangeHandler = void Function(LogicalRange? range);

typedef CandlestickSeriesApi = SeriesApi<CandlestickData, CandlestickSeriesOptions>;
typedef LineSeriesApi = SeriesApi<LineData, LineSeriesOptions>;
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
  }

  final ChartModel _model;
  final Map<SeriesModel, SeriesApi> _seriesApis = {};
  final List<ChartEventHandler> _crosshairMoveHandlers = [];
  final List<ChartEventHandler> _clickHandlers = [];
  late final TimeScaleApi _timeScaleApi = TimeScaleApi._(_model);

  @internal
  ChartModel get model => _model;

  ChartOptions get options => _model.options;

  void applyOptions(ChartOptions options) => _model.applyOptions(options);

  CandlestickSeriesApi addCandlestickSeries([CandlestickSeriesOptions options = const CandlestickSeriesOptions()]) =>
      _add(CandlestickSeriesModel(options));

  LineSeriesApi addLineSeries([LineSeriesOptions options = const LineSeriesOptions()]) => _add(LineSeriesModel(options));

  HistogramSeriesApi addHistogramSeries([HistogramSeriesOptions options = const HistogramSeriesOptions()]) =>
      _add(HistogramSeriesModel(options));

  SeriesApi<T, O> _add<T extends SeriesData, O extends SeriesOptions>(SeriesModel<T, O> series) {
    final api = SeriesApi<T, O>._(_model, series);
    _seriesApis[series] = api;
    _model.addSeries(series);
    return api;
  }

  void removeSeries(SeriesApi series) {
    _seriesApis.remove(series._series);
    _model.removeSeries(series._series);
  }

  TimeScaleApi timeScale() => _timeScaleApi;

  /// The price scale with [id]: `right`, or the id of an overlay scale used by
  /// a series' `priceScaleId`.
  PriceScaleApi priceScale([String id = defaultPriceScaleId]) => PriceScaleApi._(_model, id);

  void subscribeCrosshairMove(ChartEventHandler handler) => _crosshairMoveHandlers.add(handler);

  void unsubscribeCrosshairMove(ChartEventHandler handler) => _crosshairMoveHandlers.remove(handler);

  void subscribeClick(ChartEventHandler handler) => _clickHandlers.add(handler);

  void unsubscribeClick(ChartEventHandler handler) => _clickHandlers.remove(handler);

  void clearCrosshairPosition() => _model.setCrosshairPosition(null);

  void _dispatch(List<ChartEventHandler> handlers, ModelEventParams p) {
    if (handlers.isEmpty) return;
    final params = ChartEventParams(
      time: p.time,
      logical: p.logical,
      point: p.point,
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
    _model.dispose();
  }
}

/// A series on the chart, the equivalent of `ISeriesApi`.
class SeriesApi<T extends SeriesData, O extends SeriesOptions> {
  SeriesApi._(this._model, this._series);

  final ChartModel _model;
  final SeriesModel<T, O> _series;

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
  double? priceToCoordinate(double price) =>
      _series.priceScale.isEmpty ? null : _series.priceScale.priceToCoordinate(price);

  double? coordinateToPrice(double y) => _series.priceScale.isEmpty ? null : _series.priceScale.coordinateToPrice(y);

  /// The price scale this series is attached to.
  PriceScaleApi priceScale() => PriceScaleApi._(_model, _series.priceScale.id);
}

/// The equivalent of `ITimeScaleApi`.
class TimeScaleApi {
  TimeScaleApi._(this._model);

  final ChartModel _model;
  final Map<LogicalRangeChangeHandler, void Function(LogicalRange?)> _rangeHandlers = {};

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

  /// Fires when the visible logical range changes (scroll, zoom, new data).
  /// Handy for loading more history when `range.from` gets close to 0.
  void subscribeVisibleLogicalRangeChange(LogicalRangeChangeHandler handler) {
    void listener(LogicalRange? r) => handler(r);
    _rangeHandlers[handler] = listener;
    _model.visibleLogicalRangeListeners.add(listener);
  }

  void unsubscribeVisibleLogicalRangeChange(LogicalRangeChangeHandler handler) {
    final listener = _rangeHandlers.remove(handler);
    if (listener != null) _model.visibleLogicalRangeListeners.remove(listener);
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
}

/// The equivalent of `IPriceScaleApi`.
class PriceScaleApi {
  PriceScaleApi._(this._model, this.id);

  final ChartModel _model;
  final String id;

  PriceScale get _ps => _model.priceScale(id);

  PriceScaleOptions get options => _ps.options;

  void applyOptions(PriceScaleOptions options) {
    if (id == defaultPriceScaleId) {
      _model.applyOptions(_model.options.copyWith(rightPriceScale: options));
    } else {
      _ps.options = options.copyWith(visible: false);
      _model.invalidate();
    }
  }

  /// Width of the price axis in logical pixels (0 for overlay scales).
  double width() => id == defaultPriceScaleId ? _model.priceAxisWidth : 0;

  /// Current price range, `null` until the chart has been laid out.
  PriceRange? priceRange() => _ps.priceRange;
}
