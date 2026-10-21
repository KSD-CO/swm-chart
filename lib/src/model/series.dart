import 'dart:math' as math;
import 'dart:ui';

import '../data.dart';
import '../options.dart';
import '../plugins/primitive.dart';
import '../renderers/area_renderer.dart';
import '../renderers/bar_renderer.dart';
import '../renderers/candlestick_renderer.dart';
import '../renderers/histogram_renderer.dart';
import '../renderers/line_renderer.dart';
import '../renderers/paint_context.dart';
import '../series_options.dart';
import 'price_formatter.dart';
import 'price_line.dart';
import 'price_scale.dart';
import 'time_scale.dart';

/// Internal model of a series. The public API is `SeriesApi`.
abstract class SeriesModel<T extends SeriesData, O extends SeriesOptions> {
  SeriesModel(this._options) : formatter = PriceFormatter(_options.priceFormat);

  O _options;
  PriceFormatter formatter;
  late PriceScale priceScale;

  List<T> _data = <T>[];

  /// Time scale index of every item in [_data].
  List<int> _indices = const [];

  final List<PriceLine> priceLines = [];
  final List<ChartPrimitive> primitives = [];

  /// First visible value; the base of the percentage price scale modes.
  double? baseValue;

  /// Time of the last [update], used by [LastPriceAnimationMode.onDataUpdate].
  Duration? lastUpdateTime;

  O get options => _options;

  set options(O value) {
    _options = value;
    formatter = PriceFormatter(value.priceFormat);
  }

  List<T> get data => _data;

  List<int> get indices => _indices;

  bool get visible => _options.visible;

  /// Replaces all data. Items must be sorted by strictly ascending time.
  void setData(List<T> data) {
    for (var i = 1; i < data.length; i++) {
      if (data[i].time <= data[i - 1].time) {
        throw ArgumentError(
          'Data must be sorted by strictly ascending time: '
          'index $i (time ${data[i].time}) <= index ${i - 1} (time ${data[i - 1].time})',
        );
      }
    }
    _data = List<T>.of(data);
  }

  /// Replaces the last item when [item] has the same time, appends it when
  /// newer. Returns `true` if it was appended.
  bool update(T item) {
    if (_data.isNotEmpty) {
      final last = _data.last;
      if (item.time < last.time) {
        throw ArgumentError('Cannot update oldest data, last time=${last.time}, new time=${item.time}');
      }
      if (item.time == last.time) {
        _data[_data.length - 1] = item;
        return false;
      }
    }
    _data.add(item);
    return true;
  }

  void setIndices(List<int> indices) => _indices = indices;

  /// First item position whose time scale index is >= [index].
  int lowerBound(int index) {
    var lo = 0;
    var hi = _indices.length;
    while (lo < hi) {
      final mid = (lo + hi) >> 1;
      if (_indices[mid] < index) {
        lo = mid + 1;
      } else {
        hi = mid;
      }
    }
    return lo;
  }

  /// Item positions `[from, to)` inside [range] (inclusive time scale indices).
  (int, int) itemsInRange(IndexRange range) => (lowerBound(range.left), lowerBound(range.right + 1));

  T? itemAt(int index) {
    final pos = lowerBound(index);
    if (pos < _indices.length && _indices[pos] == index) return _data[pos];
    return null;
  }

  T? get lastItem => _data.isEmpty ? null : _data.last;

  /// Item the price line / last value label follow.
  T? priceLineItem(IndexRange? visible) {
    if (_options.priceLineSource == PriceLineSource.lastVisible && visible != null) {
      final (from, to) = itemsInRange(visible);
      if (to > from) return _data[to - 1];
    }
    return lastItem;
  }

  void updateBaseValue(IndexRange? visible) {
    if (visible == null || _data.isEmpty) {
      baseValue = null;
      return;
    }
    final pos = math.min(lowerBound(visible.left), _data.length - 1);
    baseValue = closeValue(_data[pos]);
  }

  double priceToCoordinate(double price) => priceScale.priceToCoordinate(price, baseValue);

  double coordinateToPrice(double y) => priceScale.coordinateToPrice(y, baseValue);

  String formatPrice(double price) => priceScale.formatPrice(price, baseValue);

  double minValue(T item);

  double maxValue(T item);

  double closeValue(T item);

  List<double> magnetValues(T item, {required bool ohlc}) => [closeValue(item)];

  /// Color of the item, used for the last value label and price line.
  Color itemColor(T item);

  /// Default autoscale: data range plus primitives' ranges and margins.
  AutoscaleInfo? baseAutoscaleInfo(IndexRange range) {
    PriceRange? priceRange;
    if (_data.isNotEmpty) {
      final (from, to) = itemsInRange(range);
      if (from < to) {
        var min = double.infinity;
        var max = double.negativeInfinity;
        for (var i = from; i < to; i++) {
          final item = _data[i];
          min = math.min(min, minValue(item));
          max = math.max(max, maxValue(item));
        }
        priceRange = PriceRange(min, max);
      }
    }
    AutoscaleMargins? margins;
    for (final p in primitives) {
      final info = p.autoscaleInfo(range.left, range.right);
      if (info == null) continue;
      if (info.priceRange != null) priceRange = info.priceRange!.merge(priceRange);
      final m = info.margins;
      if (m != null) {
        margins = AutoscaleMargins(
          above: math.max(margins?.above ?? 0, m.above),
          below: math.max(margins?.below ?? 0, m.below),
        );
      }
    }
    if (priceRange == null && margins == null) return null;
    return AutoscaleInfo(priceRange: priceRange, margins: margins);
  }

  AutoscaleInfo? autoscaleInfo(IndexRange range) {
    if (!visible) return null;
    final provider = _options.autoscaleInfoProvider;
    if (provider != null) return provider(() => baseAutoscaleInfo(range));
    return baseAutoscaleInfo(range);
  }

  void paint(SeriesPaintContext ctx);
}

abstract class OhlcSeriesModel<T extends OhlcData, O extends SeriesOptions> extends SeriesModel<T, O> {
  OhlcSeriesModel(super.options);

  @override
  double minValue(T item) => item.low;

  @override
  double maxValue(T item) => item.high;

  @override
  double closeValue(T item) => item.close;

  @override
  List<double> magnetValues(T item, {required bool ohlc}) =>
      ohlc ? [item.open, item.high, item.low, item.close] : [item.close];
}

class CandlestickSeriesModel extends OhlcSeriesModel<CandlestickData, CandlestickSeriesOptions> {
  CandlestickSeriesModel(super.options);

  @override
  Color itemColor(CandlestickData item) => item.color ?? (item.isUp ? options.upColor : options.downColor);

  @override
  void paint(SeriesPaintContext ctx) => paintCandlesticks(ctx, this);
}

class BarSeriesModel extends OhlcSeriesModel<BarData, BarSeriesOptions> {
  BarSeriesModel(super.options);

  @override
  Color itemColor(BarData item) => item.color ?? (item.isUp ? options.upColor : options.downColor);

  @override
  void paint(SeriesPaintContext ctx) => paintBars(ctx, this);
}

/// Line, area and baseline series.
abstract class LineLikeSeriesModel<T extends SingleValueData, O extends LineLikeSeriesOptions>
    extends SeriesModel<T, O> {
  LineLikeSeriesModel(super.options);

  @override
  double minValue(T item) => item.value;

  @override
  double maxValue(T item) => item.value;

  @override
  double closeValue(T item) => item.value;

  /// Color of the line at [item].
  Color lineColor(T item);

  @override
  Color itemColor(T item) => lineColor(item);
}

class LineSeriesModel extends LineLikeSeriesModel<LineData, LineSeriesOptions> {
  LineSeriesModel(super.options);

  @override
  Color lineColor(LineData item) => item.color ?? options.color;

  @override
  void paint(SeriesPaintContext ctx) => paintLine(ctx, this);
}

class AreaSeriesModel extends LineLikeSeriesModel<AreaData, AreaSeriesOptions> {
  AreaSeriesModel(super.options);

  @override
  Color lineColor(AreaData item) => item.lineColor ?? options.lineColor;

  @override
  void paint(SeriesPaintContext ctx) => paintArea(ctx, this);
}

class BaselineSeriesModel extends LineLikeSeriesModel<BaselineData, BaselineSeriesOptions> {
  BaselineSeriesModel(super.options);

  @override
  Color lineColor(BaselineData item) => item.value >= options.baseValue
      ? (item.topLineColor ?? options.topLineColor)
      : (item.bottomLineColor ?? options.bottomLineColor);

  @override
  void paint(SeriesPaintContext ctx) => paintBaseline(ctx, this);
}

class HistogramSeriesModel extends SeriesModel<HistogramData, HistogramSeriesOptions> {
  HistogramSeriesModel(super.options);

  @override
  double minValue(HistogramData item) => item.value;

  @override
  double maxValue(HistogramData item) => item.value;

  @override
  double closeValue(HistogramData item) => item.value;

  @override
  Color itemColor(HistogramData item) => item.color ?? options.color;

  @override
  AutoscaleInfo? baseAutoscaleInfo(IndexRange range) {
    // Columns grow from `base`, so it must stay in view.
    final info = super.baseAutoscaleInfo(range);
    final base = PriceRange(options.base, options.base);
    return AutoscaleInfo(priceRange: base.merge(info?.priceRange), margins: info?.margins);
  }

  @override
  void paint(SeriesPaintContext ctx) => paintHistogram(ctx, this);
}
