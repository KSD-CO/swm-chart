import 'dart:math' as math;
import 'dart:ui';

import '../data.dart';
import '../options.dart';
import '../renderers/candlestick_renderer.dart';
import '../renderers/histogram_renderer.dart';
import '../renderers/line_renderer.dart';
import '../renderers/paint_context.dart';
import 'price_formatter.dart';
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

  double minValue(T item);

  double maxValue(T item);

  double closeValue(T item);

  List<double> magnetValues(T item, {required bool ohlc}) => [closeValue(item)];

  Color itemColor(T item);

  PriceRange? autoscaleRange(IndexRange range) {
    if (!visible || _data.isEmpty) return null;
    final (from, to) = itemsInRange(range);
    if (from >= to) return null;
    var min = double.infinity;
    var max = double.negativeInfinity;
    for (var i = from; i < to; i++) {
      final item = _data[i];
      min = math.min(min, minValue(item));
      max = math.max(max, maxValue(item));
    }
    return PriceRange(min, max);
  }

  void paint(SeriesPaintContext ctx);
}

class CandlestickSeriesModel extends SeriesModel<CandlestickData, CandlestickSeriesOptions> {
  CandlestickSeriesModel(super.options);

  @override
  double minValue(CandlestickData item) => item.low;

  @override
  double maxValue(CandlestickData item) => item.high;

  @override
  double closeValue(CandlestickData item) => item.close;

  @override
  List<double> magnetValues(CandlestickData item, {required bool ohlc}) =>
      ohlc ? [item.open, item.high, item.low, item.close] : [item.close];

  @override
  Color itemColor(CandlestickData item) => item.color ?? (item.isUp ? options.upColor : options.downColor);

  @override
  void paint(SeriesPaintContext ctx) => paintCandlesticks(ctx, this);
}

class LineSeriesModel extends SeriesModel<LineData, LineSeriesOptions> {
  LineSeriesModel(super.options);

  @override
  double minValue(LineData item) => item.value;

  @override
  double maxValue(LineData item) => item.value;

  @override
  double closeValue(LineData item) => item.value;

  @override
  Color itemColor(LineData item) => item.color ?? options.color;

  @override
  void paint(SeriesPaintContext ctx) => paintLine(ctx, this);
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
  PriceRange? autoscaleRange(IndexRange range) {
    // Columns grow from `base`, so it must stay in view.
    final base = options.base;
    return super.autoscaleRange(range)?.merge(PriceRange(base, base));
  }

  @override
  void paint(SeriesPaintContext ctx) => paintHistogram(ctx, this);
}
