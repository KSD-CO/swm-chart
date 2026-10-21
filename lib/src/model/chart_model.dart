// Port of lightweight-charts src/model/chart-model.ts, pane.ts and
// crosshair.ts, plus the layout done by gui/chart-widget.ts.
import 'dart:async';
import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';

import '../data.dart';
import '../options.dart';
import '../plugins/primitive.dart';
import 'pane.dart';
import 'price_scale.dart';
import 'primitive_context.dart';
import 'series.dart';
import 'time_scale.dart';
import '../renderers/last_price_animation.dart';
import '../renderers/label_alignment.dart';
import 'hit_test.dart';
import 'horz_scale_behavior.dart';
import 'tick_marks.dart';
import 'time_utils.dart' show TickMarkWeight;

export 'pane.dart' show leftPriceScaleId, rightPriceScaleId;

/// Duration of one pulse of the last price animation.

enum AxisSide { left, right }

/// Crosshair state resolved for the current frame.
class CrosshairState {
  const CrosshairState({required this.paneIndex, required this.index, required this.x, required this.y});

  final int paneIndex;

  /// Time scale index the crosshair is snapped to.
  final int index;

  /// Pane coordinates in logical pixels.
  final double x;
  final double y;
}

/// Payload of crosshair-move and click events.
class ModelEventParams {
  const ModelEventParams({this.time, this.logical, this.point, this.paneIndex, this.seriesData = const {}, this.hit});

  /// What is under the pointer, if anything.
  final HitTestResult? hit;

  final num? time;
  final int? logical;

  /// Pane coordinates in logical pixels.
  final Offset? point;
  final int? paneIndex;
  final Map<SeriesModel, SeriesData> seriesData;
}

/// A label on a price axis.
class PriceAxisLabelSpec implements AlignableLabel {
  PriceAxisLabelSpec(this.y, this.text, this.background, {this.textColor, this.title = ''}) : render = y;

  /// Where the label belongs.
  final double y;

  /// Where it is drawn after `alignLabels`.
  @override
  double render;

  @override
  double get coordinate => y;

  /// First label of the scale's first series: the center `alignLabels`
  /// pushes the others away from, like upstream's `centerSource`.
  bool isCenter = false;
  final String text;
  final Color background;
  final Color? textColor;

  /// Drawn inside the pane next to the label (series title, price line title).
  final String title;
}

class ChartModel extends ChangeNotifier {
  ChartModel(this._options, {this.behavior = const TimeHorzScaleBehavior()})
    : timeScale = TimeScale(_options.timeScale) {
    if (_options.addDefaultPane) panes.add(Pane(_options));
  }

  ChartOptions _options;
  final TimeScale timeScale;

  /// What the horizontal axis measures (time, months, price).
  final HorzScaleBehavior behavior;
  final List<Pane> panes = [];

  List<num> _times = [];
  List<int> _weights = [];

  int? _crosshairPane;
  Offset? _crosshairPoint;
  bool _crosshairExact = false;
  CrosshairState? _crosshair;

  Size _size = Size.zero;
  double _pixelRatio = 1;
  double _leftAxisWidth = 0;
  double _rightAxisWidth = 0;
  double _timeAxisHeight = 0;

  LogicalRange? _lastEmittedRange;
  Size? _lastEmittedSize;
  bool _postLayoutScheduled = false;
  bool _animationFrameScheduled = false;
  bool _disposed = false;
  final Stopwatch _clock = Stopwatch()..start();

  final List<void Function(LogicalRange?)> visibleLogicalRangeListeners = [];
  final List<void Function(Size)> sizeListeners = [];
  final List<void Function(ModelEventParams)> crosshairMoveListeners = [];
  final List<void Function(ModelEventParams)> clickListeners = [];
  final List<void Function(ModelEventParams)> dblClickListeners = [];
  final List<void Function(SeriesModel)> dataChangedListeners = [];

  void _emitDataChanged(SeriesModel s) {
    for (final l in List.of(dataChangedListeners)) {
      l(s);
    }
  }

  ChartOptions get options => _options;

  Iterable<SeriesModel> get series => panes.expand((p) => p.series);

  Size get size => _size;

  double get pixelRatio => _pixelRatio;

  double get leftAxisWidth => _leftAxisWidth;

  double get rightAxisWidth => _rightAxisWidth;

  double get timeAxisHeight => _timeAxisHeight;

  double get paneWidth => math.max(0, _size.width - _leftAxisWidth - _rightAxisWidth);

  /// Rectangle of pane [index] in chart coordinates.
  Rect paneRect(int index) => Rect.fromLTWH(_leftAxisWidth, panes[index].top, paneWidth, panes[index].height);

  CrosshairState? get crosshair => _crosshair;

  bool get hasCrosshair => _crosshairPoint != null;

  /// What the crosshair is over: its series is drawn on top with
  /// `hoveredSeriesOnTop`, its cursor used on desktop.
  HitTestResult? hovered;

  SeriesModel? get hoveredSeries => hovered?.series;

  String _scaleIdOf(SeriesModel s) => s.options.priceScaleId ?? defaultVisiblePriceScaleId;

  /// Like upstream: the only visible side scale, else the preferred one.
  String get defaultVisiblePriceScaleId {
    final left = _options.leftPriceScale.visible, right = _options.rightPriceScale.visible;
    if (left != right) return left ? leftPriceScaleId : rightPriceScaleId;
    return _options.defaultVisiblePriceScaleId;
  }

  /// Series of [pane] in drawing order.
  List<SeriesModel> drawOrder(Pane pane) {
    final hovered = hoveredSeries;
    if (!_options.hoveredSeriesOnTop || hovered == null || !pane.series.contains(hovered)) return pane.series;
    return [...pane.series.where((s) => s != hovered), hovered];
  }

  Duration get now => _clock.elapsed;

  void applyOptions(ChartOptions options) {
    final fontChanged =
        options.layout.fontSize != _options.layout.fontSize || options.layout.fontFamily != _options.layout.fontFamily;
    _options = options;
    timeScale.applyOptions(options.timeScale);
    for (final p in panes) {
      p.applyChartOptions(options);
    }
    if (fontChanged) {
      _leftAxisWidth = 0;
      _rightAxisWidth = 0;
    }
    invalidate();
  }

  // ---- panes ----

  Pane addPane({bool preserveEmpty = false}) {
    final pane = Pane(_options, preserveEmpty: preserveEmpty);
    panes.add(pane);
    invalidate();
    return pane;
  }

  void _ensurePane(int index) {
    while (panes.length <= index) {
      panes.add(Pane(_options));
    }
  }

  void removePane(int index) {
    if (panes.length < 2 || index < 0 || index >= panes.length) return;
    final pane = panes.removeAt(index);
    for (final p in pane.primitives) {
      p.detached();
    }
    if (pane.series.isNotEmpty) _rebuildTimeline();
    _resetCrosshairIfPaneGone();
    invalidate();
  }

  void swapPanes(int a, int b) {
    if (a == b || a < 0 || b < 0 || a >= panes.length || b >= panes.length) return;
    final tmp = panes[a];
    panes[a] = panes[b];
    panes[b] = tmp;
    _resetCrosshairIfPaneGone();
    invalidate();
  }

  void _cleanupIfPaneIsEmpty(Pane pane) {
    if (!pane.preserveEmpty && pane.series.isEmpty && panes.length > 1) {
      panes.remove(pane);
      _resetCrosshairIfPaneGone();
    }
  }

  void _resetCrosshairIfPaneGone() {
    _crosshairPane = null;
    _crosshairPoint = null;
    _crosshair = null;
  }

  int paneIndexOf(SeriesModel s) => panes.indexWhere((p) => p.series.contains(s));

  /// Sets the height of pane [index] by redistributing stretch factors.
  void setPaneHeight(int index, double height) {
    if (panes.length < 2) return;
    final total = panes.fold<double>(0, (sum, p) => sum + p.height);
    if (total <= 0) return;
    final maxHeight = total - (panes.length - 1) * minPaneHeight;
    final h = height.clamp(minPaneHeight, math.max(minPaneHeight, maxHeight)).toDouble();
    final others = total - panes[index].height;
    for (var i = 0; i < panes.length; i++) {
      panes[i].stretchFactor = i == index ? h : (others > 0 ? panes[i].height * (total - h) / others : 1);
    }
    invalidate();
  }

  // Separator dragging: resizes the panes on both sides of separator [index]
  // (between pane index and index + 1), keeping their total stretch.
  ({double top, double bottom, double pixelStretch})? _resizeStart;

  void startPaneResize(int index) {
    final top = panes[index], bottom = panes[index + 1];
    final totalStretch = top.stretchFactor + bottom.stretchFactor;
    final totalHeight = top.height + bottom.height;
    if (totalHeight <= 0) return;
    _resizeStart = (top: top.stretchFactor, bottom: bottom.stretchFactor, pixelStretch: totalStretch / totalHeight);
  }

  void resizePane(int index, double delta) {
    final start = _resizeStart;
    if (start == null) return;
    final total = start.top + start.bottom;
    final minStretch = minPaneHeight * start.pixelStretch;
    if (total < minStretch * 2) return;
    final top = (start.top + delta * start.pixelStretch).clamp(minStretch, total - minStretch).toDouble();
    panes[index].stretchFactor = top;
    panes[index + 1].stretchFactor = total - top;
    invalidate();
  }

  void endPaneResize() => _resizeStart = null;

  // ---- series management ----

  void addSeries(SeriesModel s, {int paneIndex = 0}) {
    _ensurePane(paneIndex);
    final pane = panes[paneIndex];
    s.priceScale = pane.priceScale(_scaleIdOf(s), _options);
    pane.series.add(s);
    if (s.data.isNotEmpty) _rebuildTimeline();
    invalidate();
  }

  void removeSeries(SeriesModel s) {
    final pane = panes.where((p) => p.series.contains(s)).firstOrNull;
    if (pane == null) return;
    pane.series.remove(s);
    for (final p in s.primitives) {
      p.detached();
    }
    _cleanupIfPaneIsEmpty(pane);
    _rebuildTimeline();
    invalidate();
  }

  void moveSeriesToPane(SeriesModel s, int paneIndex) {
    final from = panes.where((p) => p.series.contains(s)).firstOrNull;
    if (from == null) return;
    _ensurePane(paneIndex);
    final to = panes[paneIndex];
    if (from == to) return;
    from.series.remove(s);
    to.series.add(s);
    s.priceScale = to.priceScale(_scaleIdOf(s), _options);
    _cleanupIfPaneIsEmpty(from);
    _resetCrosshairIfPaneGone();
    invalidate();
  }

  void seriesOptionsChanged(SeriesModel s) {
    final index = paneIndexOf(s);
    if (index >= 0) s.priceScale = panes[index].priceScale(_scaleIdOf(s), _options);
    invalidate();
  }

  void setSeriesData(SeriesModel s, List<SeriesData> data) {
    s.setData(data);
    _rebuildTimeline();
    _emitDataChanged(s);
    invalidate();
    _schedulePrecompute(s);
  }

  /// `precomputeConflationOnInit`: build the conflation levels in a
  /// scheduled task, so the first zoom out doesn't pay for them.
  void _schedulePrecompute(SeriesModel s) {
    final o = timeScale.options;
    if (!o.enableConflation || !o.precomputeConflationOnInit) return;
    final priority = switch (o.precomputeConflationPriority) {
      ConflationPriority.background => Priority.idle,
      ConflationPriority.userVisible => Priority.animation,
      ConflationPriority.userBlocking => Priority.touch,
    };
    final version = s.dataVersion;
    SchedulerBinding.instance.scheduleTask(() {
      // Skip if the data changed again or the series was removed.
      if (_disposed || s.dataVersion != version || paneIndexOf(s) < 0) return;
      s.precomputeConflation(timeScale.possibleConflationFactors(_pixelRatio));
    }, priority);
  }

  List<SeriesData> popSeries(SeriesModel s, int count) {
    final removed = s.pop(count);
    _rebuildTimeline();
    _emitDataChanged(s);
    invalidate();
    return removed;
  }

  void updateSeries(SeriesModel s, SeriesData item) {
    final kind = s.update(item);
    if (s is LineLikeSeriesModel && s.options.lastPriceAnimation == LastPriceAnimationMode.onDataUpdate) {
      s.onRealtimeUpdate(now, lastPriceAnimationPeriod);
    }
    final time = item.time;
    switch (kind) {
      case SeriesUpdateKind.replaced:
        break;
      case SeriesUpdateKind.replacedKind:
        _rebuildTimeline();
      case SeriesUpdateKind.appended:
      case SeriesUpdateKind.appendedWhitespace:
        final hasValue = kind == SeriesUpdateKind.appended;
        if (_times.isEmpty || time > _times.last) {
          // Fast path: a new point to the right of everything. Append in
          // place: copying 100k-point lists per new bar adds up.
          final times = _times..add(time);
          final weights = _weights..add(0);
          behavior.fillWeights(times, weights, times.length - 1);
          if (times.length == 1 && behavior is TimeHorzScaleBehavior) weights[0] = TickMarkWeight.day;
          if (hasValue) s.indices.add(times.length - 1);
          _applyTimeline(times, weights, times.length - 1);
        } else {
          final index = timeScale.timeToIndex(time);
          if (index != null && (s.indices.isEmpty || index > s.indices.last)) {
            // Another series already has this time; only this series' indices grow.
            if (hasValue) {
              s.indices.add(index);
              _applyTimeline(_times, _weights, _times.length, replacedWhitespace: true);
            }
          } else {
            _rebuildTimeline();
          }
        }
    }
    _emitDataChanged(s);
    invalidate();
  }

  void _rebuildTimeline() {
    final all = <num>{};
    for (final s in series) {
      for (final d in s.allItems) {
        all.add(d.time);
      }
    }
    final times = all.toList()..sort();
    final weights = List<int>.filled(times.length, 0, growable: true);
    behavior.fillWeights(times, weights, 0);

    for (final s in series) {
      final indices = List<int>.filled(s.data.length, 0, growable: true);
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

  /// Like upstream's data layer: the last index that has a value in any
  /// series (whitespace after it doesn't count).
  int? _computeBaseIndex(List<num> times) {
    if (times.isEmpty) return null;
    var base = 0;
    for (final s in series) {
      if (s.indices.isNotEmpty) base = math.max(base, s.indices.last);
    }
    return base;
  }

  void _updateIndicesWithData() {
    if (!timeScale.options.ignoreWhitespaceIndices) return;
    timeScale.setIndicesWithData({for (final s in series) ...s.indices});
  }

  /// Mirrors `ChartModel.updateTimeScale`: keeps the visible range stable when
  /// bars are added, unless the last bar is visible and
  /// `shiftVisibleRangeOnNewBar` is on.
  void _applyTimeline(List<num> times, List<int> weights, int firstChanged, {bool replacedWhitespace = false}) {
    final oldFirstTime = timeScale.indexToTime(0);
    final visibleBars = timeScale.visibleStrictRange();
    final currentBaseIndex = timeScale.baseIndex;

    _times = times;
    _weights = weights;
    timeScale.update(times, weights, firstChanged);

    final newFirstTime = times.isEmpty ? null : times.first;
    final newBaseIndex = _computeBaseIndex(times);

    if (visibleBars != null && oldFirstTime != null && newFirstTime != null) {
      final isLastSeriesBarVisible = visibleBars.contains(currentBaseIndex);
      final isLeftBarShiftToLeft = oldFirstTime > newFirstTime;
      final isSeriesPointsAdded = newBaseIndex != null && newBaseIndex > currentBaseIndex;
      final isSeriesPointsAddedToRight = isSeriesPointsAdded && !isLeftBarShiftToLeft;
      final needShift =
          isLastSeriesBarVisible &&
          (!replacedWhitespace || timeScale.options.allowShiftVisibleRangeOnWhitespaceReplacement) &&
          timeScale.options.shiftVisibleRangeOnNewBar;
      if (isSeriesPointsAddedToRight && !needShift) {
        timeScale.setRightOffset(timeScale.rightOffset - (newBaseIndex - currentBaseIndex));
      }
    }
    timeScale.setBaseIndex(newBaseIndex);
    _updateIndicesWithData();
  }

  // ---- layout (called by the painter every frame) ----

  void layout(Size size, double pixelRatio, double Function(String text) measureText) {
    _size = size;
    _pixelRatio = pixelRatio;
    final fontSize = _options.layout.fontSize;

    _timeAxisHeight = _options.timeScale.visible
        ? math.max(_optimalTimeAxisHeight(fontSize), _options.timeScale.minimumHeight)
        : 0;
    _layoutPanes(size.height, pixelRatio, fontSize);
    _updateFormatters();

    // Axis widths depend on labels, labels on price ranges, price ranges on
    // visible bars and visible bars on the axis widths. Like upstream,
    // iterate and never shrink the axes to avoid jitter.
    final leftVisible = _options.leftPriceScale.visible;
    final rightVisible = _options.rightPriceScale.visible;
    if (!leftVisible) _leftAxisWidth = 0;
    if (!rightVisible) _rightAxisWidth = 0;
    for (var pass = 0; pass < 3; pass++) {
      timeScale.setWidth(math.max(1.0, paneWidth));
      _recalculateAutoScale();
      final left = leftVisible ? _optimalPriceAxisWidth(AxisSide.left, fontSize, measureText) : 0.0;
      final right = rightVisible ? _optimalPriceAxisWidth(AxisSide.right, fontSize, measureText) : 0.0;
      if (left <= _leftAxisWidth && right <= _rightAxisWidth) break;
      _leftAxisWidth = math.max(_leftAxisWidth, left);
      _rightAxisWidth = math.max(_rightAxisWidth, right);
    }
    if (timeScale.hasPendingRange) {
      // fitContent()/setVisibleLogicalRange() before the first layout:
      // apply now that the pane width is final.
      timeScale.applyPendingRange();
      _recalculateAutoScale();
    }

    _resolveCrosshair();
    _schedulePostLayout();
    if (_needsAnimationFrame()) _scheduleAnimationFrame();
  }

  void _layoutPanes(double height, double pixelRatio, double fontSize) {
    final separators = (panes.length - 1) * paneSeparatorHeight;
    final total = math.max(0.0, height - _timeAxisHeight - separators);
    final totalStretch = panes.fold<double>(0, (sum, p) => sum + p.stretchFactor);
    final stretchPixels = totalStretch > 0 ? total / totalStretch : 0.0;
    var top = 0.0;
    var accumulated = 0.0;
    for (var i = 0; i < panes.length; i++) {
      final pane = panes[i];
      final h = i == panes.length - 1
          ? math.max(0.0, total - accumulated)
          : (pane.stretchFactor * stretchPixels * pixelRatio).round() / pixelRatio;
      pane.top = top;
      pane.height = h;
      accumulated += h;
      top += h + paneSeparatorHeight;
      for (final ps in pane.priceScales.values) {
        ps.setHeight(h, fontSize);
      }
    }
  }

  double _optimalTimeAxisHeight(double fontSize) {
    const borderSize = 1.0;
    const tickLength = 5.0;
    final paddingTop = 3 * fontSize / 12;
    final paddingBottom = 3 * fontSize / 12;
    final labelBottomOffset = 4 * fontSize / 12;
    return (borderSize + tickLength + fontSize + paddingTop + paddingBottom + labelBottomOffset).ceilToDouble();
  }

  /// The price scale drawn on [side] of [pane].
  PriceScale scaleOnSide(Pane pane, AxisSide side) => side == AxisSide.left ? pane.leftScale : pane.rightScale;

  /// Side whose axis shows labels of [ps]: overlay scales use the right axis
  /// if visible, otherwise the left one.
  AxisSide? sideOf(Pane pane, PriceScale ps) {
    if (ps == pane.leftScale) return _options.leftPriceScale.visible ? AxisSide.left : null;
    if (ps == pane.rightScale) return _options.rightPriceScale.visible ? AxisSide.right : null;
    if (_options.rightPriceScale.visible) return AxisSide.right;
    if (_options.leftPriceScale.visible) return AxisSide.left;
    return null;
  }

  double _optimalPriceAxisWidth(AxisSide side, double fontSize, double Function(String) measureText) {
    var maxWidth = 0.0;
    for (final pane in panes) {
      final ps = scaleOnSide(pane, side);
      final marks = ps.marks();
      if (marks.isNotEmpty) {
        maxWidth = math.max(maxWidth, math.max(measureText(marks.first.label), measureText(marks.last.label)));
      }
      for (final label in priceAxisLabels(pane, side)) {
        maxWidth = math.max(maxWidth, measureText(label.text));
      }
      if (!ps.isEmpty && _options.crosshair.horzLine.labelVisible) {
        final top = ps.coordinateToDisplay(1);
        final bottom = ps.coordinateToDisplay(ps.height - 2);
        maxWidth = math.max(
          maxWidth,
          measureText(ps.formatLogical(math.min(top, bottom).floorToDouble() + 0.11111111111111)),
        );
        maxWidth = math.max(
          maxWidth,
          measureText(ps.formatLogical(math.max(top, bottom).ceilToDouble() - 0.11111111111111)),
        );
      }
    }
    if (maxWidth == 0) maxWidth = 34; // DefaultOptimalWidth

    final padding = fontSize / 12 * 5;
    var res = (1 + 5 + padding + padding + 5 + maxWidth).ceil();
    if (res.isOdd) res++; // make it even, like `suggestPriceScaleWidth`
    final options = side == AxisSide.left ? _options.leftPriceScale : _options.rightPriceScale;
    return math.max(res.toDouble(), options.minimumWidth);
  }

  void _updateFormatters() {
    final localization = _options.localization;
    final visible = timeScale.visibleStrictRange();
    for (final pane in panes) {
      for (final s in pane.series) {
        s.updateBaseValue(visible);
      }
      for (final ps in pane.priceScales.values) {
        final main = pane.series.where((s) => s.priceScale == ps).firstOrNull;
        if (main != null) {
          ps.setFormatter(main.formatter, localization);
          ps.baseValue = main.baseValue;
        }
      }
    }
  }

  void _recalculateAutoScale() {
    final visible = timeScale.visibleStrictRange();
    if (visible == null) return;
    for (final pane in panes) {
      for (final s in pane.series) {
        s.updateBaseValue(visible);
      }
      for (final ps in pane.priceScales.values) {
        final main = pane.series.where((s) => s.priceScale == ps).firstOrNull;
        ps.baseValue = main?.baseValue;
        if (!ps.isAutoScale) continue;
        PriceRange? range;
        var above = 0.0, below = 0.0;
        for (final s in pane.series) {
          if (s.priceScale != ps) continue;
          final info = s.autoscaleInfo(visible);
          if (info == null) continue;
          final r = info.priceRange;
          if (r != null && !(ps.isPercentLike && s.baseValue == null)) {
            final internal = ps.toInternalRange(r, s.baseValue ?? 0);
            range = range == null ? internal : range.merge(internal);
          }
          above = math.max(above, info.margins?.above ?? 0);
          below = math.max(below, info.margins?.below ?? 0);
        }
        if (ps.hasVisibleEdgeMarks) {
          above = math.max(above, ps.edgeMarksPadding);
          below = math.max(below, ps.edgeMarksPadding);
        }
        ps.setMargins(above, below);
        ps.updateAutoScaleRange(range);
      }
    }
  }

  String formatSeriesPrice(SeriesModel s, double price) => s.priceScale.isPercentLike
      ? s.formatPrice(price)
      : (_options.localization.priceFormatter ?? s.formatter.call)(price);

  String formatTime(num time) => behavior.formatHorzItem(time, _options);

  String formatTickMark(TickMark mark) => behavior.formatTickMark(mark, _options);

  /// Upstream's `_isAllScalingAndScrollingDisabled`.
  bool get allScalingAndScrollingDisabled {
    final scroll = _options.handleScroll, scale = _options.handleScale;
    return !scroll.horzTouchDrag &&
        !scroll.mouseWheel &&
        !scroll.pressedMouseMove &&
        !scroll.vertTouchDrag &&
        !scale.axisDoubleClickReset.time &&
        !scale.axisPressedMouseMove.time &&
        !scale.mouseWheel &&
        !scale.pinch;
  }

  List<TimeMark> timeMarks() => timeScale.marks(
    _options.layout.fontSize,
    formatTickMark,
    allScalingAndScrollingDisabled: allScalingAndScrollingDisabled,
  );

  PrimitiveContextImpl primitiveContext(Pane pane, SeriesModel? s, [Canvas? canvas]) =>
      PrimitiveContextImpl(this, pane, s, canvas);

  /// Labels on the price axis on [side] of [pane]: last values, price
  /// lines and primitives. The crosshair label is not included.
  List<PriceAxisLabelSpec> priceAxisLabels(Pane pane, AxisSide side) {
    final visible = timeScale.visibleStrictRange();
    final labels = <PriceAxisLabelSpec>[];
    final mainSeries = pane.series.where((s) => s.priceScale == scaleOnSide(pane, side)).firstOrNull;
    for (final s in pane.series) {
      if (sideOf(pane, s.priceScale) != side || s.priceScale.isEmpty) continue;
      final firstOfSeries = labels.length;
      final item = s.priceLineItem(visible);
      if (s.visible && s.options.lastValueVisible && item != null) {
        final price = s.closeValue(item);
        labels.add(
          PriceAxisLabelSpec(
            s.priceToCoordinate(price),
            formatSeriesPrice(s, price),
            s.options.priceLineColor ?? s.itemColor(item),
            title: s.options.title,
          ),
        );
      }
      for (final line in s.priceLines) {
        final o = line.options;
        if (!o.axisLabelVisible) continue;
        labels.add(
          PriceAxisLabelSpec(
            s.priceToCoordinate(o.price),
            formatSeriesPrice(s, o.price),
            o.axisLabelColor ?? o.color,
            textColor: o.axisLabelTextColor,
            title: o.title,
          ),
        );
      }
      if (s.primitives.isNotEmpty) {
        final ctx = primitiveContext(pane, s);
        for (final p in s.primitives) {
          for (final l in p.priceAxisLabels(ctx)) {
            labels.add(PriceAxisLabelSpec(l.coordinate, l.text, l.backgroundColor, textColor: l.textColor));
          }
        }
      }
      if (s == mainSeries && labels.length > firstOfSeries) labels[firstOfSeries].isCenter = true;
    }
    if (pane.primitives.isNotEmpty && side == (sideOf(pane, pane.defaultPriceScale) ?? AxisSide.right)) {
      final ctx = primitiveContext(pane, null);
      for (final p in pane.primitives) {
        for (final l in p.priceAxisLabels(ctx)) {
          labels.add(PriceAxisLabelSpec(l.coordinate, l.text, l.backgroundColor, textColor: l.textColor));
        }
      }
    }
    return labels;
  }

  List<AxisLabel> timeAxisPrimitiveLabels() {
    final labels = <AxisLabel>[];
    for (final pane in panes) {
      for (final p in pane.primitives) {
        labels.addAll(p.timeAxisLabels(primitiveContext(pane, null)));
      }
      for (final s in pane.series) {
        for (final p in s.primitives) {
          labels.addAll(p.timeAxisLabels(primitiveContext(pane, s)));
        }
      }
    }
    return labels;
  }

  // ---- crosshair ----

  /// Moves the crosshair to [point] (pane coordinates) in pane [paneIndex],
  /// or hides it when [point] is `null`.
  void setCrosshairPosition(int? paneIndex, Offset? point, {bool exact = false}) {
    _crosshairPane = point == null ? null : paneIndex;
    _crosshairPoint = point;
    _crosshairExact = exact;
    _resolveCrosshair();
    final params = _eventParams(_crosshair);
    hovered = params.hit;
    notifyListeners();
    _emit(crosshairMoveListeners, params);
  }

  void _resolveCrosshair() {
    final point = _crosshairPoint;
    final paneIndex = _crosshairPane;
    if (point == null ||
        paneIndex == null ||
        paneIndex >= panes.length ||
        timeScale.isEmpty ||
        _options.crosshair.mode == CrosshairMode.hidden) {
      _crosshair = null;
      return;
    }
    final pane = panes[paneIndex];
    final x = point.dx.clamp(0.0, math.max(0.0, paneWidth - 1)).toDouble();
    final y = point.dy.clamp(0.0, math.max(0.0, pane.height - 1)).toDouble();
    var index = timeScale.coordinateToIndex(x, considerIgnoreWhitespace: true);
    if (_options.crosshair.doNotSnapToHiddenSeriesIndices) index = _nearestVisibleSeriesIndex(index);
    final snappedX = timeScale.indexToCoordinate(index);
    var resolvedY = y;

    final mode = _options.crosshair.mode;
    if (!_crosshairExact && (mode == CrosshairMode.magnet || mode == CrosshairMode.magnetOhlc)) {
      double? best;
      for (final s in pane.series) {
        if (pane.isOverlay(s.priceScale) || !s.visible || s.priceScale.isEmpty) continue;
        final item = s.itemAt(index);
        if (item == null) continue;
        for (final v in s.magnetValues(item, ohlc: mode == CrosshairMode.magnetOhlc)) {
          final cy = s.priceToCoordinate(v);
          if (best == null || (cy - y).abs() < (best - y).abs()) best = cy;
        }
      }
      if (best != null) resolvedY = best;
    }
    _crosshair = CrosshairState(paneIndex: paneIndex, index: index, x: snappedX, y: resolvedY);
  }

  /// Nearest index where a visible series has data, for
  /// `doNotSnapToHiddenSeriesIndices`.
  int _nearestVisibleSeriesIndex(int index) {
    final visible = series.where((s) => s.visible && s.indices.isNotEmpty).toList();
    if (visible.isEmpty || visible.any((s) => s.itemAt(index) != null)) return index;
    int? best;
    for (final s in visible) {
      final pos = s.lowerBound(index);
      for (final p in [pos - 1, pos]) {
        if (p < 0 || p >= s.indices.length) continue;
        final candidate = s.indices[p];
        if (best == null || (candidate - index).abs() < (best - index).abs()) best = candidate;
      }
    }
    return best ?? index;
  }

  Map<SeriesModel, SeriesData> _dataAt(int index) => {for (final s in series) s: ?s.itemAt(index)};

  ModelEventParams _eventParams(CrosshairState? c) {
    if (c == null) return const ModelEventParams();
    final raw = _crosshairPoint;
    return ModelEventParams(
      time: timeScale.indexToTime(c.index),
      logical: c.index,
      point: Offset(c.x, c.y),
      paneIndex: c.paneIndex,
      seriesData: _dataAt(c.index),
      hit: raw == null ? null : hitTest(c.paneIndex, raw),
    );
  }

  /// What is at [point] (pane coordinates) in pane [paneIndex].
  HitTestResult? hitTest(int paneIndex, Offset point) {
    if (paneIndex < 0 || paneIndex >= panes.length) return null;
    final pane = panes[paneIndex];
    return hitTestPane(pane, timeScale, point.dx, point.dy, (s) => primitiveContext(pane, s));
  }

  void click(int paneIndex, Offset point, {bool doubleClick = false}) {
    final index = timeScale.coordinateToIndex(point.dx, considerIgnoreWhitespace: true);
    _emit(
      doubleClick ? dblClickListeners : clickListeners,
      ModelEventParams(
        time: timeScale.indexToTime(index),
        logical: index,
        point: point,
        paneIndex: paneIndex,
        seriesData: _dataAt(index),
        hit: hitTest(paneIndex, point),
      ),
    );
  }

  // ---- last price animation ----

  bool _needsAnimationFrame() {
    for (final s in series) {
      if (s is! LineLikeSeriesModel || !s.visible) continue;
      switch (s.options.lastPriceAnimation) {
        case LastPriceAnimationMode.disabled:
          break;
        case LastPriceAnimationMode.continuous:
          return true;
        case LastPriceAnimationMode.onDataUpdate:
          if (now <= s.animationEnd) return true;
      }
    }
    return false;
  }

  void _scheduleAnimationFrame() {
    if (_animationFrameScheduled) return;
    _animationFrameScheduled = true;
    SchedulerBinding.instance.scheduleFrameCallback((_) {
      _animationFrameScheduled = false;
      invalidate();
    });
  }

  // ---- notifications ----

  void invalidate() {
    if (_disposed) return;
    notifyListeners();
  }

  void _schedulePostLayout() {
    if (_postLayoutScheduled) return;
    _postLayoutScheduled = true;
    // Never call user code from inside paint.
    scheduleMicrotask(() {
      _postLayoutScheduled = false;
      if (_disposed) return;
      final range = timeScale.visibleLogicalRange();
      if (range != _lastEmittedRange) {
        _lastEmittedRange = range;
        for (final l in List.of(visibleLogicalRangeListeners)) {
          l(range);
        }
      }
      if (_size != _lastEmittedSize) {
        _lastEmittedSize = _size;
        for (final l in List.of(sizeListeners)) {
          l(_size);
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
    for (final pane in panes) {
      for (final p in pane.primitives) {
        p.detached();
      }
      for (final s in pane.series) {
        for (final p in s.primitives) {
          p.detached();
        }
      }
    }
    super.dispose();
  }
}
