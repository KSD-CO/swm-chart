// Port of lightweight-charts src/model/price-scale.ts and
// src/model/price-tick-mark-builder.ts (normal mode only).
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

class PriceMark {
  PriceMark(this.coord, this.label, this.logical);

  double coord;
  String label;
  double logical;
}

class PriceScale {
  PriceScale(this.id, this._options);

  final String id;
  PriceScaleOptions _options;
  double _height = 0;
  double _fontSize = 12;
  PriceRange? _priceRange;
  PriceFormatter _formatter = PriceFormatter(const PriceFormat.price());
  PriceFormatterFn? _formatterOverride;

  List<PriceMark> _marks = const [];
  bool _marksValid = false;

  double? _scaleStartY;
  double? _scrollStartY;
  PriceRange? _rangeSnapshot;

  PriceScaleOptions get options => _options;

  set options(PriceScaleOptions value) {
    _options = value;
    _marksValid = false;
  }

  double get height => _height;

  bool get isAutoScale => _options.autoScale;

  bool get isInverted => _options.invertScale;

  PriceRange? get priceRange => _priceRange;

  bool get isEmpty => _height == 0 || _priceRange == null || _priceRange!.isEmpty;

  PriceFormatter get formatter => _formatter;

  void setFormatter(PriceFormatter formatter, PriceFormatterFn? override) {
    _formatter = formatter;
    _formatterOverride = override;
    _marksValid = false;
  }

  String formatPrice(double price) => (_formatterOverride ?? _formatter.call)(price);

  void setHeight(double height, double fontSize) {
    if (_height == height && _fontSize == fontSize) return;
    _height = height;
    _fontSize = fontSize;
    _marksValid = false;
  }

  void setPriceRange(PriceRange? range) {
    if (range == _priceRange) return;
    _priceRange = range;
    _marksValid = false;
  }

  /// Recomputes the range from the series attached to this scale.
  /// [range] is the union of their autoscale ranges for the visible bars.
  void updateAutoScaleRange(PriceRange? range) {
    if (!isAutoScale || range == null) return;
    if (range.min == range.max) {
      // Degenerate range: extend by a few min moves so the scale isn't blank.
      final extend = 5 * _formatter.format.minMove;
      range = PriceRange(range.min - extend, range.max + extend);
    }
    setPriceRange(range);
  }

  double _topMarginPx() =>
      isInverted ? _options.scaleMargins.bottom * _height : _options.scaleMargins.top * _height;

  double _bottomMarginPx() =>
      isInverted ? _options.scaleMargins.top * _height : _options.scaleMargins.bottom * _height;

  double get internalHeight => _height - _topMarginPx() - _bottomMarginPx();

  double _invertedCoordinate(double coordinate) =>
      isInverted ? coordinate : _height - 1 - coordinate;

  double priceToCoordinate(double price) {
    if (isEmpty) return 0;
    final range = _priceRange!;
    final invCoordinate = _bottomMarginPx() + (internalHeight - 1) * (price - range.min) / range.length;
    return _invertedCoordinate(invCoordinate);
  }

  double coordinateToPrice(double coordinate) {
    if (isEmpty) return 0;
    final invCoordinate = _invertedCoordinate(coordinate);
    final range = _priceRange!;
    return range.min + range.length * ((invCoordinate - _bottomMarginPx()) / (internalHeight - 1));
  }

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
    setPriceRange(snapshot.scaleAroundCenter(scaleCoeff));
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
    final priceUnitsPerPixel = snapshot.length / (internalHeight - 1);
    setPriceRange(snapshot.shift(pixelDelta * priceUnitsPerPixel));
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

  double _tickMarkHeight() => (_fontSize * _options.tickMarkDensity).ceilToDouble();

  double _tickSpan(double high, double low) {
    final maxTickSpan = (high - low) * _tickMarkHeight() / _height;
    final base = _formatter.base;
    return [
      PriceTickSpanCalculator(base, const [2, 2.5, 2]).tickSpan(high, low, maxTickSpan),
      PriceTickSpanCalculator(base, const [2, 2, 2.5]).tickSpan(high, low, maxTickSpan),
      PriceTickSpanCalculator(base, const [2.5, 2, 2]).tickSpan(high, low, maxTickSpan),
    ].reduce(math.min);
  }

  List<PriceMark> _rebuildTickMarks() {
    if (isEmpty) return const [];

    final bottom = coordinateToPrice(_height - 1);
    final top = coordinateToPrice(0);

    final extraMargin = _options.entireTextOnly ? _fontSize / 2 : 0.0;
    final minCoord = extraMargin;
    final maxCoord = _height - 1 - extraMargin;

    final high = math.max(bottom, top);
    final low = math.min(bottom, top);
    if (high == low) return const [];

    final span = _tickSpan(high, low);
    var mod = high % span;
    mod += mod < 0 ? span : 0;

    final marks = <PriceMark>[];
    for (var logical = high - mod; logical > low; logical -= span) {
      final coord = priceToCoordinate(logical);
      if (coord < minCoord || coord > maxCoord) continue;
      marks.add(PriceMark(coord, formatPrice(logical), logical));
    }
    return marks;
  }
}
