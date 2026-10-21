// Port of lightweight-charts src/model/time-scale.ts
import 'dart:math' as math;

import '../options.dart';
import 'tick_marks.dart';
import 'time_utils.dart';

const int _minVisibleBarsCount = 2;
const int _defaultTickMarkMaxCharacterLength = 8;

/// A range of logical (bar) indices. Fractional values are allowed.
class LogicalRange {
  const LogicalRange(this.from, this.to);

  final double from;
  final double to;

  @override
  bool operator ==(Object other) => other is LogicalRange && other.from == from && other.to == to;

  @override
  int get hashCode => Object.hash(from, to);

  @override
  String toString() => 'LogicalRange($from, $to)';
}

/// A range of integer bar indices, both ends inclusive.
class IndexRange {
  const IndexRange(this.left, this.right);

  final int left;
  final int right;

  bool contains(int index) => left <= index && index <= right;
}

class TimeMark {
  TimeMark(this.coord, this.label, this.weight);

  final double coord;
  final String label;
  final int weight;
}

class TimeScale {
  TimeScale(this._options)
      : _barSpacing = _options.barSpacing,
        _rightOffset = _options.rightOffset;

  TimeScaleOptions _options;
  double _width = 0;
  int? _baseIndex;
  double _rightOffset;
  double _barSpacing;
  List<int> _times = const [];
  List<int> _weights = const [];

  double? _scrollStartX;
  double? _scaleStartX;
  ({double barSpacing, double rightOffset})? _transitionStart;

  final TickMarks _tickMarks = TickMarks();
  List<TimeMark>? _marksCache;
  double _marksFontSize = 0;

  TimeScaleOptions get options => _options;

  void applyOptions(TimeScaleOptions options) {
    final old = _options;
    _options = options;
    if (old.barSpacing != options.barSpacing) _setBarSpacing(options.barSpacing);
    if (old.rightOffset != options.rightOffset) _rightOffset = options.rightOffset;
    _correctBarSpacing();
    _correctOffset();
    _invalidateMarks();
  }

  List<int> get times => _times;

  int get pointsCount => _times.length;

  double get width => _width;

  double get barSpacing => _barSpacing;

  double get rightOffset => _rightOffset;

  bool get isEmpty => _width == 0 || _times.isEmpty || _baseIndex == null;

  int get baseIndex => _baseIndex ?? 0;

  int? indexToTime(int index) => (index >= 0 && index < _times.length) ? _times[index] : null;

  /// Index of [time], or the nearest index to the left if [findNearest] and
  /// [time] isn't present.
  int? timeToIndex(int time, {bool findNearest = false}) {
    var lo = 0;
    var hi = _times.length;
    while (lo < hi) {
      final mid = (lo + hi) >> 1;
      if (_times[mid] < time) {
        lo = mid + 1;
      } else {
        hi = mid;
      }
    }
    if (lo < _times.length && _times[lo] == time) return lo;
    if (!findNearest) return null;
    return math.max(0, math.min(lo, _times.length - 1));
  }

  void setWidth(double newWidth) {
    if (!newWidth.isFinite || newWidth <= 0 || _width == newWidth) return;
    _width = newWidth;
    _correctBarSpacing();
    _correctOffset();
    _invalidateMarks();
  }

  void update(List<int> times, List<int> weights, int firstChangedPointIndex) {
    _times = times;
    _weights = weights;
    _tickMarks.setTimeScalePoints(times, weights, firstChangedPointIndex);
    _invalidateMarks();
    _correctOffset();
  }

  void setBaseIndex(int? baseIndex) {
    _baseIndex = baseIndex;
    _invalidateMarks();
    _correctOffset();
    _doFixLeftEdge();
  }

  // ---- coordinates ----

  double indexToCoordinate(num index) {
    if (isEmpty) return 0;
    final deltaFromRight = baseIndex + _rightOffset - index;
    return _width - (deltaFromRight + 0.5) * _barSpacing - 1;
  }

  double coordinateToFloatIndex(double x) {
    final deltaFromRight = (_width - 1 - x) / _barSpacing;
    final index = baseIndex + _rightOffset - deltaFromRight;
    return (index * 1000000).round() / 1000000;
  }

  int coordinateToIndex(double x) => coordinateToFloatIndex(x).ceil();

  LogicalRange? visibleLogicalRange() {
    if (isEmpty) return null;
    final rightBorder = _rightOffset + baseIndex;
    final leftBorder = rightBorder - _width / _barSpacing + 1;
    return LogicalRange(leftBorder, rightBorder);
  }

  IndexRange? visibleStrictRange() {
    final range = visibleLogicalRange();
    if (range == null) return null;
    return IndexRange(range.from.floor(), range.to.ceil());
  }

  // ---- bar spacing / offset ----

  void setRightOffset(double offset) {
    _rightOffset = offset;
    _correctOffset();
    _invalidateMarks();
  }

  void setBarSpacing(double newBarSpacing) {
    _setBarSpacing(newBarSpacing);
    _correctOffset();
  }

  void _setBarSpacing(double newBarSpacing) {
    final old = _barSpacing;
    _barSpacing = newBarSpacing;
    _correctBarSpacing();
    if (old != _barSpacing) _invalidateMarks();
  }

  void _correctBarSpacing() {
    // The max bar spacing depends on the width; don't clamp before layout.
    if (_width == 0) return;
    final clamped = _barSpacing.clamp(_minBarSpacing(), math.max(_minBarSpacing(), _maxBarSpacing())).toDouble();
    if (clamped != _barSpacing) {
      _barSpacing = clamped;
      _invalidateMarks();
    }
  }

  double _maxBarSpacing() => _options.maxBarSpacing > 0 ? _options.maxBarSpacing : _width * 0.5;

  double _minBarSpacing() {
    // With both edges fixed, zooming out must not move the first/last bars off the edges.
    if (_options.fixLeftEdge && _options.fixRightEdge && _times.isNotEmpty) {
      return _width / _times.length;
    }
    return _options.minBarSpacing;
  }

  void _correctOffset() {
    // Both bounds depend on the width; don't clamp before layout.
    if (_width == 0) return;
    final minRightOffset = _minRightOffset();
    if (minRightOffset != null && _rightOffset < minRightOffset) {
      _rightOffset = minRightOffset;
      _invalidateMarks();
    }
    final maxRightOffset = _maxRightOffset();
    if (_rightOffset > maxRightOffset) {
      _rightOffset = maxRightOffset;
      _invalidateMarks();
    }
  }

  double? _minRightOffset() {
    if (_times.isEmpty || _baseIndex == null || _width == 0) return null;
    final barsEstimation = _options.fixLeftEdge
        ? _width / _barSpacing
        : math.min(math.min(_minVisibleBarsCount, _times.length).toDouble(), _width / _barSpacing);
    return 0 - _baseIndex! - 1 + barsEstimation;
  }

  double _maxRightOffset() {
    if (_options.fixRightEdge) return 0;
    return (_width / _barSpacing) -
        math.min(math.min(_minVisibleBarsCount, _times.length).toDouble(), _width / _barSpacing);
  }

  void _doFixLeftEdge() {
    if (!_options.fixLeftEdge || _times.isEmpty || _width == 0) return;
    final visible = visibleStrictRange();
    if (visible == null) return;
    final delta = visible.left;
    if (delta < 0) setRightOffset(_rightOffset - delta - 1);
    _correctBarSpacing();
  }

  /// Zooms by [scale] steps around [zoomPoint] (mouse-wheel style; >0 zooms in).
  void zoom(double zoomPoint, double scale) {
    final floatIndexAtZoomPoint = coordinateToFloatIndex(zoomPoint);
    setBarSpacing(_barSpacing + scale * (_barSpacing / 10));
    if (!_options.rightBarStaysOnScroll) {
      setRightOffset(_rightOffset + (floatIndexAtZoomPoint - coordinateToFloatIndex(zoomPoint)));
    }
  }

  /// Sets [newBarSpacing] and keeps the logical [anchorIndex] at x = [focalX].
  /// Used by pinch-to-zoom.
  void zoomAnchored(double newBarSpacing, double anchorIndex, double focalX) {
    setBarSpacing(newBarSpacing);
    if (_options.rightBarStaysOnScroll) return;
    final deltaFromRight = (_width - 1 - focalX) / _barSpacing;
    setRightOffset(anchorIndex - baseIndex + deltaFromRight);
  }

  // Drag on the time axis scales around the right edge.
  void startScale(double x) {
    if (_scrollStartX != null) endScroll();
    if (_scaleStartX != null || _transitionStart != null || isEmpty) return;
    _scaleStartX = x;
    _transitionStart = (barSpacing: _barSpacing, rightOffset: _rightOffset);
  }

  void scaleTo(double x) {
    final start = _transitionStart;
    if (start == null) return;
    final startLengthFromRight = (_width - x).clamp(0, _width);
    final currentLengthFromRight = (_width - _scaleStartX!).clamp(0, _width);
    if (startLengthFromRight == 0 || currentLengthFromRight == 0) return;
    setBarSpacing(start.barSpacing * startLengthFromRight / currentLengthFromRight);
  }

  void endScale() {
    if (_scaleStartX == null) return;
    _scaleStartX = null;
    _transitionStart = null;
  }

  void startScroll(double x) {
    if (_scrollStartX != null || _transitionStart != null || isEmpty) return;
    _scrollStartX = x;
    _transitionStart = (barSpacing: _barSpacing, rightOffset: _rightOffset);
  }

  void scrollTo(double x) {
    final start = _scrollStartX;
    if (start == null) return;
    final shiftInLogical = (start - x) / _barSpacing;
    _rightOffset = _transitionStart!.rightOffset + shiftInLogical;
    _invalidateMarks();
    _correctOffset();
  }

  void endScroll() {
    if (_scrollStartX == null) return;
    _scrollStartX = null;
    _transitionStart = null;
  }

  bool get isScrolling => _scrollStartX != null;

  void restoreDefault() {
    _setBarSpacing(_options.barSpacing);
    setRightOffset(_options.rightOffset);
  }

  void fitContent() {
    if (_times.isEmpty) return;
    setLogicalRange(LogicalRange(0, _times.length - 1 + _options.rightOffset));
  }

  void setLogicalRange(LogicalRange range) {
    if (_width == 0) return;
    final length = range.to - range.from + 1;
    _setBarSpacing(_width / length);
    _rightOffset = range.to - baseIndex;
    _correctOffset();
    _invalidateMarks();
  }

  // ---- tick marks ----

  void _invalidateMarks() => _marksCache = null;

  List<TimeMark> marks(double fontSize, String Function(TickMark) formatLabel) {
    if (isEmpty) return const [];
    if (_marksCache != null && _marksFontSize == fontSize) return _marksCache!;

    final spacing = _barSpacing;
    final pixelsPer8Characters = (fontSize + 4) * 5;
    final pixelsPerCharacter = pixelsPer8Characters / _defaultTickMarkMaxCharacterLength;
    final maxLabelWidth = pixelsPerCharacter * _options.tickMarkMaxCharacterLength;
    final indexPerLabel = (maxLabelWidth / spacing).round();

    final visibleBars = visibleStrictRange()!;
    final firstBar = math.max(visibleBars.left, visibleBars.left - indexPerLabel);
    final lastBar = math.max(visibleBars.right, visibleBars.right - indexPerLabel);

    final items = _tickMarks.build(spacing, maxLabelWidth);
    final result = <TimeMark>[];
    for (final tm in items) {
      if (tm.index < firstBar || tm.index > lastBar) continue;
      result.add(TimeMark(indexToCoordinate(tm.index), formatLabel(tm), tm.weight));
    }

    _marksCache = result;
    _marksFontSize = fontSize;
    return result;
  }

  String formatTickMark(TickMark mark) {
    final type = weightToTickMarkType(mark.weight, _options.timeVisible, _options.secondsVisible);
    return _options.tickMarkFormatter?.call(mark.time, type) ?? defaultTickMarkFormatter(mark.time, type);
  }

  /// Weights of points, exposed for tests.
  List<int> get weights => _weights;
}
