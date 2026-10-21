// Port of lightweight-charts src/model/price-scale.ts,
// src/model/price-scale-conversions.ts and
// src/model/price-tick-mark-builder.ts.
import 'dart:math' as math;

import '../options.dart';
import 'price_formatter.dart';
import 'price_tick_span_calculator.dart';

class PriceRange {
  const PriceRange(this.min, this.max);

  final double min;
  final double max;

  double get length => max - min;

  bool get isEmpty => max == min || min.isNaN || max.isNaN;

  PriceRange merge(PriceRange? other) {
    if (other == null) return this;
    return PriceRange(math.min(min, other.min), math.max(max, other.max));
  }

  PriceRange scaleAroundCenter(double coeff) {
    if (!coeff.isFinite || length == 0) return this;
    final center = (max + min) * 0.5;
    return PriceRange(center - (center - min) * coeff, center + (max - center) * coeff);
  }

  PriceRange shift(double delta) => PriceRange(min + delta, max + delta);

  @override
  bool operator ==(Object other) => other is PriceRange && other.min == min && other.max == max;

  @override
  int get hashCode => Object.hash(min, max);

  @override
  String toString() => 'PriceRange($min, $max)';
}

// ---- conversions (price-scale-conversions.ts) ----

class LogFormula {
  const LogFormula(this.logicalOffset, this.coordOffset);

  final double logicalOffset;
  final double coordOffset;

  @override
  bool operator ==(Object other) =>
      other is LogFormula && other.logicalOffset == logicalOffset && other.coordOffset == coordOffset;

  @override
  int get hashCode => Object.hash(logicalOffset, coordOffset);
}

const LogFormula _defLogFormula = LogFormula(4, 0.0001);

double _log10(double x) => math.log(x) / math.ln10;

double toPercent(double value, double baseValue) {
  final result = 100 * (value - baseValue) / baseValue;
  return baseValue < 0 ? -result : result;
}

double fromPercent(double value, double baseValue) {
  if (baseValue < 0) value = -value;
  return (value / 100) * baseValue + baseValue;
}

double toIndexedTo100(double value, double baseValue) {
  final result = 100 * (value - baseValue) / baseValue + 100;
  return baseValue < 0 ? -result : result;
}

double fromIndexedTo100(double value, double baseValue) {
  value -= 100;
  if (baseValue < 0) value = -value;
  return (value / 100) * baseValue + baseValue;
}

double toLog(double price, LogFormula f) {
  final m = price.abs();
  if (m < 1e-15) return 0;
  final res = _log10(m + f.coordOffset) + f.logicalOffset;
  return price < 0 ? -res : res;
}

double fromLog(double logical, LogFormula f) {
  final m = logical.abs();
  if (m < 1e-15) return 0;
  final res = math.pow(10, m - f.logicalOffset) - f.coordOffset;
  return logical < 0 ? -res : res;
}

LogFormula logFormulaForPriceRange(PriceRange? range) {
  if (range == null) return _defLogFormula;
  final diff = (range.max - range.min).abs();
  if (diff >= 1 || diff < 1e-15) return _defLogFormula;
  final digits = _log10(diff).abs().ceil();
  final logicalOffset = _defLogFormula.logicalOffset + digits;
  return LogFormula(logicalOffset, 1 / math.pow(10, logicalOffset));
}

class PriceMark {
  PriceMark(this.coord, this.label, this.logical);

  double coord;
  String label;
  double logical;
}

/// A price scale. Its range is kept in *internal* units: prices in normal
/// mode, `toLog(price)` in logarithmic mode and percents in the percentage
/// modes (relative to each series' first visible value, the "base value").
class PriceScale {
  PriceScale(this.id, PriceScaleOptions options) : _options = options;

  final String id;
  PriceScaleOptions _options;
  double _height = 0;
  double _fontSize = 12;
  PriceRange? _priceRange;
  PriceFormatter _formatter = PriceFormatter(const PriceFormat.price());
  LocalizationOptions _localization = const LocalizationOptions();
  LogFormula _logFormula = _defLogFormula;

  /// Base value of the scale's main series (first visible value), used for
  /// tick marks and the crosshair label in the percentage modes.
  double? baseValue;

  double _marginAbove = 0;
  double _marginBelow = 0;

  List<PriceMark> _marks = const [];
  bool _marksValid = false;

  double? _scaleStartY;
  double? _scrollStartY;
  PriceRange? _rangeSnapshot;

  PriceScaleOptions get options => _options;

  set options(PriceScaleOptions value) {
    final oldMode = _options.mode;
    _options = value;
    if (oldMode != value.mode) _onModeChanged(oldMode);
    _marksValid = false;
  }

  double get height => _height;

  bool get isAutoScale => _options.autoScale;

  bool get isInverted => _options.invertScale;

  PriceScaleMode get mode => _options.mode;

  bool get isLog => mode == PriceScaleMode.logarithmic;

  bool get isPercentage => mode == PriceScaleMode.percentage;

  bool get isIndexedTo100 => mode == PriceScaleMode.indexedTo100;

  bool get isPercentLike => isPercentage || isIndexedTo100;

  /// Range in internal units.
  PriceRange? get internalRange => _priceRange;

  /// Visible range expressed in prices (or percents in the percentage modes).
  PriceRange? get priceRange {
    final r = _priceRange;
    if (r == null || !isLog) return r;
    return PriceRange(fromLog(r.min, _logFormula), fromLog(r.max, _logFormula));
  }

  bool get isEmpty => _height == 0 || _priceRange == null || _priceRange!.isEmpty;

  PriceFormatter get formatter => _formatter;

  void _onModeChanged(PriceScaleMode oldMode) {
    final r = _priceRange;
    if (oldMode == PriceScaleMode.logarithmic && r != null) {
      _priceRange = PriceRange(fromLog(r.min, _logFormula), fromLog(r.max, _logFormula));
    }
    if (mode == PriceScaleMode.logarithmic && _priceRange != null) {
      _logFormula = logFormulaForPriceRange(_priceRange);
      _priceRange = PriceRange(toLog(_priceRange!.min, _logFormula), toLog(_priceRange!.max, _logFormula));
    }
    if (isPercentLike || oldMode == PriceScaleMode.percentage || oldMode == PriceScaleMode.indexedTo100) {
      // Units changed; let autoscale rebuild the range.
      _priceRange = null;
      _options = _options.copyWith(autoScale: true);
    }
  }

  void setFormatter(PriceFormatter formatter, LocalizationOptions localization) {
    _formatter = formatter;
    _localization = localization;
    _marksValid = false;
  }

  /// Formats a value expressed in display units (price, or percent in the
  /// percentage modes).
  String formatLogical(double value) {
    if (isPercentage) return _localization.percentageFormatter?.call(value) ?? '${_formatPercent(value)}%';
    if (isIndexedTo100) return _formatPercent(value);
    return (_localization.priceFormatter ?? _formatter.call)(value);
  }

  /// Formats tick mark values, using the tick mark formatters of
  /// [LocalizationOptions] when set.
  List<String> _formatTickmarks(List<double> values) {
    if (isPercentage) {
      final f = _localization.tickmarksPercentageFormatter;
      if (f != null) return f(values);
    } else if (!isIndexedTo100) {
      final f = _localization.tickmarksPriceFormatter;
      if (f != null) return f(values);
    }
    return values.map(formatLogical).toList();
  }

  bool get hasVisibleEdgeMarks => _options.ensureEdgeTickMarksVisible && isAutoScale;

  double get edgeMarksPadding => _fontSize / 2;

  String _formatPercent(double v) {
    final text = v.abs().toStringAsFixed(2);
    return (v < 0 && double.parse(text) != 0) ? '−$text' : text;
  }

  /// Formats a price. In the percentage modes the price is converted with
  /// [base] first.
  String formatPrice(double price, [double? base]) {
    if (isPercentLike) return formatLogical(_priceToDisplay(price, base ?? baseValue ?? price));
    return formatLogical(price);
  }

  void setHeight(double height, double fontSize) {
    if (_height == height && _fontSize == fontSize) return;
    _height = height;
    _fontSize = fontSize;
    _marksValid = false;
  }

  void setInternalRange(PriceRange? range) {
    if (range == _priceRange) return;
    _priceRange = range;
    _marksValid = false;
  }

  void setMargins(double above, double below) {
    if (above == _marginAbove && below == _marginBelow) return;
    _marginAbove = above;
    _marginBelow = below;
    _marksValid = false;
  }

  /// Converts a price range of a series with [base] into internal units.
  PriceRange toInternalRange(PriceRange range, double base) {
    switch (mode) {
      case PriceScaleMode.normal:
        return range;
      case PriceScaleMode.logarithmic:
        return PriceRange(toLog(range.min, _logFormula), toLog(range.max, _logFormula));
      case PriceScaleMode.percentage:
        return PriceRange(toPercent(range.min, base), toPercent(range.max, base));
      case PriceScaleMode.indexedTo100:
        return PriceRange(toIndexedTo100(range.min, base), toIndexedTo100(range.max, base));
    }
  }

  /// Sets the autoscaled range. [range] is in internal units.
  void updateAutoScaleRange(PriceRange? range) {
    if (!isAutoScale || range == null) return;
    if (range.min == range.max) {
      // Degenerate range: extend by a few min moves so the scale isn't blank.
      final extend = 5 * _formatter.format.minMove;
      if (isLog) {
        final min = fromLog(range.min, _logFormula) - extend;
        final max = fromLog(range.max, _logFormula) + extend;
        range = PriceRange(toLog(min, _logFormula), toLog(max, _logFormula));
      } else {
        range = PriceRange(range.min - extend, range.max + extend);
      }
    }
    if (isLog) {
      final prices = PriceRange(fromLog(range.min, _logFormula), fromLog(range.max, _logFormula));
      final formula = logFormulaForPriceRange(prices);
      if (formula != _logFormula) {
        _logFormula = formula;
        range = PriceRange(toLog(prices.min, formula), toLog(prices.max, formula));
      }
    }
    setInternalRange(range);
  }

  double _topMarginPx() =>
      isInverted ? _options.scaleMargins.bottom * _height + _marginBelow : _options.scaleMargins.top * _height + _marginAbove;

  double _bottomMarginPx() =>
      isInverted ? _options.scaleMargins.top * _height + _marginAbove : _options.scaleMargins.bottom * _height + _marginBelow;

  double get internalHeight => _height - _topMarginPx() - _bottomMarginPx();

  double _invertedCoordinate(double coordinate) => isInverted ? coordinate : _height - 1 - coordinate;

  double _internalToCoordinate(double v) {
    if (isEmpty) return 0;
    final range = _priceRange!;
    final invCoordinate = _bottomMarginPx() + (internalHeight - 1) * (v - range.min) / range.length;
    return _invertedCoordinate(invCoordinate);
  }

  double _coordinateToInternal(double coordinate) {
    if (isEmpty) return 0;
    final invCoordinate = _invertedCoordinate(coordinate);
    final range = _priceRange!;
    return range.min + range.length * ((invCoordinate - _bottomMarginPx()) / (internalHeight - 1));
  }

  /// Price -> display units (percent in percentage modes, price otherwise).
  double _priceToDisplay(double price, double base) {
    switch (mode) {
      case PriceScaleMode.percentage:
        return toPercent(price, base);
      case PriceScaleMode.indexedTo100:
        return toIndexedTo100(price, base);
      case PriceScaleMode.normal:
      case PriceScaleMode.logarithmic:
        return price;
    }
  }

  double _displayToPrice(double value, double base) {
    switch (mode) {
      case PriceScaleMode.percentage:
        return fromPercent(value, base);
      case PriceScaleMode.indexedTo100:
        return fromIndexedTo100(value, base);
      case PriceScaleMode.normal:
      case PriceScaleMode.logarithmic:
        return value;
    }
  }

  double _displayToInternal(double v) => isLog ? toLog(v, _logFormula) : v;

  double _internalToDisplay(double v) => isLog ? fromLog(v, _logFormula) : v;

  /// [base] is the first visible value of the series the price belongs to;
  /// only used in the percentage modes.
  double priceToCoordinate(double price, [double? base]) =>
      _internalToCoordinate(_displayToInternal(_priceToDisplay(price, base ?? baseValue ?? price)));

  double coordinateToPrice(double coordinate, [double? base]) =>
      _displayToPrice(_internalToDisplay(_coordinateToInternal(coordinate)), base ?? baseValue ?? 0);

  /// Value at [coordinate] in display units (percent in percentage modes).
  double coordinateToDisplay(double coordinate) => _internalToDisplay(_coordinateToInternal(coordinate));

  double displayToCoordinate(double value) => _internalToCoordinate(_displayToInternal(value));

  // ---- manual scaling (drag on the price axis) ----

  void startScale(double y) {
    if (isEmpty) return;
    _scaleStartY = _height - y;
    _rangeSnapshot = _priceRange;
    _options = _options.copyWith(autoScale: false);
  }

  void scaleTo(double y) {
    final start = _scaleStartY;
    final snapshot = _rangeSnapshot;
    if (start == null || snapshot == null) return;
    final x = math.max(0.0, _height - y);
    var scaleCoeff = (start + (_height - 1) * 0.2) / (x + (_height - 1) * 0.2);
    scaleCoeff = math.max(scaleCoeff, 0.1);
    setInternalRange(snapshot.scaleAroundCenter(scaleCoeff));
  }

  void endScale() {
    _scaleStartY = null;
    _rangeSnapshot = null;
  }

  // ---- manual scrolling (vertical drag on the pane when not auto-scaled) ----

  void startScroll(double y) {
    if (isAutoScale || isEmpty) return;
    _scrollStartY = y;
    _rangeSnapshot = _priceRange;
  }

  void scrollTo(double y) {
    final start = _scrollStartY;
    final snapshot = _rangeSnapshot;
    if (start == null || snapshot == null || isEmpty) return;
    var pixelDelta = y - start;
    if (isInverted) pixelDelta = -pixelDelta;
    final unitsPerPixel = snapshot.length / (internalHeight - 1);
    setInternalRange(snapshot.shift(pixelDelta * unitsPerPixel));
  }

  void endScroll() {
    _scrollStartY = null;
    _rangeSnapshot = null;
  }

  // ---- tick marks ----

  List<PriceMark> marks() {
    if (!_marksValid) {
      _marks = _rebuildTickMarks();
      _marksValid = true;
    }
    return _marks;
  }

  int get _markBase => isPercentLike ? 100 : _formatter.base;

  double _tickMarkHeight() => (_fontSize * _options.tickMarkDensity).ceilToDouble();

  double _tickSpan(double high, double low) {
    final maxTickSpan = (high - low) * _tickMarkHeight() / _height;
    final base = _markBase;
    return [
      PriceTickSpanCalculator(base, const [2, 2.5, 2]).tickSpan(high, low, maxTickSpan),
      PriceTickSpanCalculator(base, const [2, 2, 2.5]).tickSpan(high, low, maxTickSpan),
      PriceTickSpanCalculator(base, const [2.5, 2, 2]).tickSpan(high, low, maxTickSpan),
    ].reduce(math.min);
  }

  List<PriceMark> _rebuildTickMarks() {
    if (isEmpty) return const [];

    final bottom = coordinateToDisplay(_height - 1);
    final top = coordinateToDisplay(0);

    final extraMargin = _options.entireTextOnly ? _fontSize / 2 : 0.0;
    final minCoord = extraMargin;
    final maxCoord = _height - 1 - extraMargin;

    final high = math.max(bottom, top);
    final low = math.min(bottom, top);
    if (high == low) return const [];

    var span = _tickSpan(high, low);
    var mod = high % span;
    mod += mod < 0 ? span : 0;

    final sign = high >= low ? 1 : -1;
    double? prevCoord;
    final marks = <PriceMark>[];
    final firstSpan = span;
    for (var logical = high - mod; logical > low; logical -= span) {
      final coord = displayToCoordinate(logical);
      // Needed for log scale, where marks get denser towards the bottom.
      if (prevCoord != null && (coord - prevCoord).abs() < _tickMarkHeight()) continue;
      if (coord < minCoord || coord > maxCoord) continue;
      marks.add(PriceMark(coord, '', logical));
      prevCoord = coord;
      if (isLog) span = _tickSpan(logical * sign, low);
    }

    if (hasVisibleEdgeMarks && _shouldApplyEdgeMarks(firstSpan, low, high)) {
      final padding = edgeMarksPadding;
      _applyEdgeMarks(marks, firstSpan, minCoord, maxCoord, padding, padding * 2);
    }

    final labels = _formatTickmarks([for (final m in marks) m.logical]);
    for (var i = 0; i < marks.length; i++) {
      marks[i].label = labels[i];
    }
    return marks;
  }

  bool _shouldApplyEdgeMarks(double span, double low, double high) {
    final range = priceRange;
    if (range == null) return false;
    return (range.min - low < span) && (high - range.max < span);
  }

  /// Port of upstream's `_applyEdgeMarks`: adds marks at the top and bottom
  /// edges, dropping regular marks too close to them.
  void _applyEdgeMarks(List<PriceMark> marks, double span, double minCoord, double maxCoord, double minPadding,
      double maxPadding) {
    final topMark = _boundaryMark(minCoord, minPadding, maxPadding);
    final bottomMark = _boundaryMark(maxCoord, -maxPadding, -minPadding);
    final spanPx = displayToCoordinate(0) - displayToCoordinate(span);
    if (marks.isNotEmpty && marks.first.coord - topMark.coord < spanPx / 2) marks.removeAt(0);
    if (marks.isNotEmpty && bottomMark.coord - marks.last.coord < spanPx / 2) marks.removeLast();
    marks
      ..insert(0, topMark)
      ..add(bottomMark);
  }

  PriceMark _boundaryMark(double coord, double minPadding, double maxPadding) {
    final avgPadding = (minPadding + maxPadding) / 2;
    final value1 = coordinateToDisplay(coord + minPadding);
    final value2 = coordinateToDisplay(coord + maxPadding);
    final minValue = math.min(value1, value2), maxValue = math.max(value1, value2);
    final valueSpan = math.max(0.1, _tickSpan(maxValue, minValue));
    final value = coordinateToDisplay(coord + avgPadding);
    final rounded = value - (value % valueSpan);
    return PriceMark(displayToCoordinate(rounded), '', rounded);
  }
}
