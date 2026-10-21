// Port of the parts of lightweight-charts src/model/chart-model.ts,
// pane.ts and crosshair.ts that a single-pane chart needs.
import 'dart:async';
import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';

import '../data.dart';
import '../options.dart';
import 'price_scale.dart';
import 'series.dart';
import 'time_scale.dart';
import 'time_utils.dart';

const String defaultPriceScaleId = 'right';

/// Crosshair state resolved for the current frame.
class CrosshairState {
  const CrosshairState({required this.index, required this.x, required this.y, required this.price});

  /// Time scale index the crosshair is snapped to.
  final int index;

  /// Pane coordinates in logical pixels.
  final double x;
  final double y;

  /// Price on the right price scale at [y].
  final double price;
}

/// Payload of crosshair-move and click events.
class ModelEventParams {
  const ModelEventParams({this.time, this.logical, this.point, this.seriesData = const {}});

  /// UTC seconds of the hovered bar, `null` outside the data.
  final int? time;

  /// Logical index of the hovered bar.
  final int? logical;

  /// Pane coordinates in logical pixels, `null` when the crosshair left the chart.
  final Offset? point;

  /// Data of each series at [time], keyed by the internal series model.
  final Map<SeriesModel, SeriesData> seriesData;
}

class ChartModel extends ChangeNotifier {
  ChartModel(this._options) : timeScale = TimeScale(_options.timeScale) {
    _priceScales[defaultPriceScaleId] = PriceScale(defaultPriceScaleId, _options.rightPriceScale);
  }

  ChartOptions _options;
  final TimeScale timeScale;
  final Map<String, PriceScale> _priceScales = {};
  final List<SeriesModel> _series = [];

  List<int> _times = [];
  List<int> _weights = [];

  Offset? _crosshairPoint;
  CrosshairState? _crosshair;

  Size _size = Size.zero;
  double _pixelRatio = 1;
  double _priceAxisWidth = 0;
  double _timeAxisHeight = 0;

  LogicalRange? _lastEmittedRange;
  bool _rangeCheckScheduled = false;
  bool _disposed = false;

  final List<void Function(LogicalRange?)> visibleLogicalRangeListeners = [];
  final List<void Function(ModelEventParams)> crosshairMoveListeners = [];
  final List<void Function(ModelEventParams)> clickListeners = [];

  ChartOptions get options => _options;

  List<SeriesModel> get series => List.unmodifiable(_series);

  PriceScale get rightPriceScale => _priceScales[defaultPriceScaleId]!;

  Iterable<PriceScale> get priceScales => _priceScales.values;

  Size get size => _size;

  double get pixelRatio => _pixelRatio;

  double get priceAxisWidth => _priceAxisWidth;

  double get timeAxisHeight => _timeAxisHeight;

  Size get paneSize => Size(math.max(0, _size.width - _priceAxisWidth), math.max(0, _size.height - _timeAxisHeight));

  CrosshairState? get crosshair => _crosshair;

  bool get hasCrosshair => _crosshairPoint != null;

  void applyOptions(ChartOptions options) {
    final fontChanged = options.layout.fontSize != _options.layout.fontSize ||
        options.layout.fontFamily != _options.layout.fontFamily;
    _options = options;
    timeScale.applyOptions(options.timeScale);
    rightPriceScale.options = options.rightPriceScale;
    if (fontChanged) _priceAxisWidth = 0;
    invalidate();
  }

  PriceScale priceScale(String id) {
    return _priceScales.putIfAbsent(
      id,
      () => PriceScale(id, _options.rightPriceScale.copyWith(visible: false, autoScale: true)),
    );
  }

  bool isOverlay(SeriesModel s) => s.priceScale.id != defaultPriceScaleId;

  // ---- series management ----

  void addSeries(SeriesModel s) {
    s.priceScale = priceScale(s.options.priceScaleId);
    _series.add(s);
    invalidate();
  }

  void removeSeries(SeriesModel s) {
    if (!_series.remove(s)) return;
    _rebuildTimeline();
    invalidate();
  }

  void seriesOptionsChanged(SeriesModel s) {
    s.priceScale = priceScale(s.options.priceScaleId);
    invalidate();
  }

  void setSeriesData<T extends SeriesData>(SeriesModel<T, SeriesOptions> s, List<T> data) {
    s.setData(data);
    _rebuildTimeline();
    invalidate();
  }

  void updateSeries<T extends SeriesData>(SeriesModel<T, SeriesOptions> s, T item) {
    final appended = s.update(item);
    if (appended) {
      final time = item.time;
      if (_times.isEmpty || time > _times.last) {
        // Fast path: a new bar to the right of everything.
        final times = List<int>.of(_times)..add(time);
        final weights = List<int>.of(_weights)..add(0);
        fillWeightsForPoints(times, weights, times.length - 1);
        if (times.length == 1) weights[0] = TickMarkWeight.day;
        s.setIndices(List<int>.of(s.indices)..add(times.length - 1));
        _applyTimeline(times, weights, times.length - 1);
      } else {
        final index = timeScale.timeToIndex(time);
        if (index != null && (s.indices.isEmpty || index > s.indices.last)) {
          // Another series already has this time; only this series' indices grow.
          s.setIndices(List<int>.of(s.indices)..add(index));
        } else {
          _rebuildTimeline();
        }
      }
    }
    invalidate();
  }

  void _rebuildTimeline() {
    final all = <int>{};
    for (final s in _series) {
      for (final d in s.data) {
        all.add(d.time);
      }
    }
    final times = all.toList()..sort();
    final weights = List<int>.filled(times.length, 0);
    fillWeightsForPoints(times, weights);

    for (final s in _series) {
      final indices = List<int>.filled(s.data.length, 0);
      var j = 0;
      for (var i = 0; i < s.data.length; i++) {
        final t = s.data[i].time;
        while (times[j] < t) {
          j++;
        }
        indices[i] = j;
      }
      s.setIndices(indices);
    }

    var firstChanged = 0;
    final common = math.min(times.length, _times.length);
    while (firstChanged < common && times[firstChanged] == _times[firstChanged]) {
      firstChanged++;
    }
    // A weight depends only on the point and its predecessor, so the common
    // prefix can be kept, except the first point's weight, which is guessed
    // from the average interval of the whole data set.
    if (weights.isEmpty || _weights.isEmpty || weights[0] != _weights[0]) firstChanged = 0;

    _applyTimeline(times, weights, firstChanged);
  }

  /// Mirrors `ChartModel.updateTimeScale`: keeps the visible range stable when
  /// bars are added, unless the last bar is visible and
  /// `shiftVisibleRangeOnNewBar` is on.
  void _applyTimeline(List<int> times, List<int> weights, int firstChanged) {
    final oldFirstTime = timeScale.indexToTime(0);
    final visibleBars = timeScale.visibleStrictRange();
    final currentBaseIndex = timeScale.baseIndex;

    _times = times;
    _weights = weights;
    timeScale.update(times, weights, firstChanged);

    final newFirstTime = times.isEmpty ? null : times.first;
    final newBaseIndex = times.isEmpty ? null : times.length - 1;

    if (visibleBars != null && oldFirstTime != null && newFirstTime != null) {
      final isLastSeriesBarVisible = visibleBars.contains(currentBaseIndex);
      final isLeftBarShiftToLeft = oldFirstTime > newFirstTime;
      final isSeriesPointsAdded = newBaseIndex != null && newBaseIndex > currentBaseIndex;
      final isSeriesPointsAddedToRight = isSeriesPointsAdded && !isLeftBarShiftToLeft;
      final needShift = isLastSeriesBarVisible && timeScale.options.shiftVisibleRangeOnNewBar;
      if (isSeriesPointsAddedToRight && !needShift) {
        timeScale.setRightOffset(timeScale.rightOffset - (newBaseIndex - currentBaseIndex));
      }
    }
    timeScale.setBaseIndex(newBaseIndex);
  }

  // ---- layout (called by the painter every frame) ----

  void layout(Size size, double pixelRatio, double Function(String text) measureText) {
    _size = size;
    _pixelRatio = pixelRatio;
    final fontSize = _options.layout.fontSize;

    _timeAxisHeight = _options.timeScale.visible ? _optimalTimeAxisHeight(fontSize) : 0;
    final paneHeight = math.max(0.0, size.height - _timeAxisHeight);

    for (final ps in _priceScales.values) {
      ps.setHeight(paneHeight, fontSize);
    }
    _updateFormatters();

    // Axis width depends on labels, labels on the price range, the price
    // range on visible bars and visible bars on the axis width. Like
    // upstream, iterate and never shrink the axis to avoid jitter.
    for (var pass = 0; pass < 3; pass++) {
      timeScale.setWidth(math.max(1, size.width - _priceAxisWidth));
      _recalculateAutoScale();
      final width = rightPriceScale.options.visible ? _optimalPriceAxisWidth(fontSize, measureText) : 0.0;
      if (width <= _priceAxisWidth) break;
      _priceAxisWidth = width;
    }
    if (!rightPriceScale.options.visible) _priceAxisWidth = 0;

    _resolveCrosshair();
    _scheduleRangeCheck();
  }

  double _optimalTimeAxisHeight(double fontSize) {
    const borderSize = 1.0;
    const tickLength = 5.0;
    final paddingTop = 3 * fontSize / 12;
    final paddingBottom = 3 * fontSize / 12;
    final labelBottomOffset = 4 * fontSize / 12;
    return (borderSize + tickLength + fontSize + paddingTop + paddingBottom + labelBottomOffset).ceilToDouble();
  }

  double _optimalPriceAxisWidth(double fontSize, double Function(String) measureText) {
    final ps = rightPriceScale;
    var maxWidth = 0.0;
    final marks = ps.marks();
    if (marks.isNotEmpty) {
      maxWidth = math.max(measureText(marks.first.label), measureText(marks.last.label));
    }
    for (final s in _series) {
      final last = s.lastItem;
      if (!s.visible || !s.options.lastValueVisible || last == null) continue;
      maxWidth = math.max(maxWidth, measureText(formatSeriesPrice(s, s.closeValue(last))));
    }
    if (!ps.isEmpty && _options.crosshair.horzLine.labelVisible) {
      final top = ps.coordinateToPrice(1);
      final bottom = ps.coordinateToPrice(ps.height - 2);
      maxWidth = math.max(maxWidth, measureText(ps.formatPrice(math.min(top, bottom).floorToDouble() + 0.11111111111111)));
      maxWidth = math.max(maxWidth, measureText(ps.formatPrice(math.max(top, bottom).ceilToDouble() - 0.11111111111111)));
    }
    if (maxWidth == 0) maxWidth = 34; // DefaultOptimalWidth

    final padding = fontSize / 12 * 5;
    var res = (1 + 5 + padding + padding + 5 + maxWidth).ceil();
    if (res.isOdd) res++; // make it even, like `suggestPriceScaleWidth`
    return math.max(res.toDouble(), ps.options.minimumWidth);
  }

  void _updateFormatters() {
    final override = _options.localization.priceFormatter;
    for (final ps in _priceScales.values) {
      final main = _series.where((s) => s.priceScale == ps).firstOrNull;
      if (main != null) ps.setFormatter(main.formatter, override);
    }
  }

  void _recalculateAutoScale() {
    final visible = timeScale.visibleStrictRange();
    if (visible == null) return;
    for (final ps in _priceScales.values) {
      if (!ps.isAutoScale) continue;
      PriceRange? range;
      for (final s in _series) {
        if (s.priceScale != ps) continue;
        final r = s.autoscaleRange(visible);
        range = range == null ? r : range.merge(r);
      }
      ps.updateAutoScaleRange(range);
    }
  }

  String formatSeriesPrice(SeriesModel s, double price) =>
      (_options.localization.priceFormatter ?? s.formatter.call)(price);

  String formatTime(int time) {
    final custom = _options.localization.timeFormatter;
    if (custom != null) return custom(time);
    return defaultTimeFormatter(
      time,
      timeVisible: _options.timeScale.timeVisible,
      secondsVisible: _options.timeScale.secondsVisible,
    );
  }

  // ---- crosshair ----

  void setCrosshairPosition(Offset? point) {
    _crosshairPoint = point;
    _resolveCrosshair();
    notifyListeners();
    _emit(crosshairMoveListeners, _eventParams(point == null ? null : _crosshair));
  }

  void _resolveCrosshair() {
    final point = _crosshairPoint;
    if (point == null || timeScale.isEmpty || _options.crosshair.mode == CrosshairMode.hidden) {
      _crosshair = null;
      return;
    }
    final pane = paneSize;
    final x = point.dx.clamp(0.0, pane.width - 1);
    final y = point.dy.clamp(0.0, pane.height - 1);
    final index = timeScale.coordinateToIndex(x);
    final snappedX = timeScale.indexToCoordinate(index);
    final ps = rightPriceScale;
    var price = ps.coordinateToPrice(y);
    var resolvedY = y;

    final mode = _options.crosshair.mode;
    if ((mode == CrosshairMode.magnet || mode == CrosshairMode.magnetOhlc) && !ps.isEmpty) {
      double? best;
      for (final s in _series) {
        if (isOverlay(s) || !s.visible) continue;
        final item = s.itemAt(index);
        if (item == null) continue;
        for (final v in s.magnetValues(item, ohlc: mode == CrosshairMode.magnetOhlc)) {
          final cy = ps.priceToCoordinate(v);
          if (best == null || (cy - y).abs() < (best - y).abs()) best = cy;
        }
      }
      if (best != null) {
        resolvedY = best;
        price = ps.coordinateToPrice(best);
      }
    }
    _crosshair = CrosshairState(index: index, x: snappedX, y: resolvedY, price: price);
  }

  ModelEventParams _eventParams(CrosshairState? c) {
    if (c == null) return const ModelEventParams();
    final data = <SeriesModel, SeriesData>{};
    for (final s in _series) {
      final item = s.itemAt(c.index);
      if (item != null) data[s] = item;
    }
    return ModelEventParams(
      time: timeScale.indexToTime(c.index),
      logical: c.index,
      point: Offset(c.x, c.y),
      seriesData: data,
    );
  }

  void click(Offset point) {
    final index = timeScale.coordinateToIndex(point.dx);
    final data = <SeriesModel, SeriesData>{};
    for (final s in _series) {
      final item = s.itemAt(index);
      if (item != null) data[s] = item;
    }
    _emit(
      clickListeners,
      ModelEventParams(time: timeScale.indexToTime(index), logical: index, point: point, seriesData: data),
    );
  }

  // ---- notifications ----

  void invalidate() {
    if (_disposed) return;
    notifyListeners();
  }

  void _scheduleRangeCheck() {
    if (_rangeCheckScheduled) return;
    _rangeCheckScheduled = true;
    // Never call user code from inside paint.
    scheduleMicrotask(() {
      _rangeCheckScheduled = false;
      if (_disposed) return;
      final range = timeScale.visibleLogicalRange();
      if (range != _lastEmittedRange) {
        _lastEmittedRange = range;
        for (final l in List.of(visibleLogicalRangeListeners)) {
          l(range);
        }
      }
    });
  }

  void _emit(List<void Function(ModelEventParams)> listeners, ModelEventParams params) {
    for (final l in List.of(listeners)) {
      l(params);
    }
  }

  // ---- animations ----

  int _animationId = 0;

  /// Animates the right offset to [target], like `scrollToPosition(pos, true)`.
  void animateRightOffset(double target, {Duration duration = const Duration(milliseconds: 400)}) {
    final id = ++_animationId;
    final start = timeScale.rightOffset;
    Duration? startTime;
    void tick(Duration now) {
      if (_disposed || id != _animationId) return;
      startTime ??= now;
      final t = ((now - startTime!).inMicroseconds / duration.inMicroseconds).clamp(0.0, 1.0);
      // Same easing as lightweight-charts' cubic ease-out.
      final eased = 1 - math.pow(1 - t, 3).toDouble();
      timeScale.setRightOffset(start + (target - start) * eased);
      invalidate();
      if (t < 1) SchedulerBinding.instance.scheduleFrameCallback(tick);
    }

    SchedulerBinding.instance.scheduleFrameCallback(tick);
    SchedulerBinding.instance.scheduleFrame();
  }

  void cancelAnimations() => _animationId++;

  @override
  void dispose() {
    _disposed = true;
    _animationId++;
    super.dispose();
  }
}
