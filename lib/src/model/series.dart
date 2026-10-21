import 'dart:math' as math;
import 'dart:ui';

import '../data.dart';
import '../options.dart';
import '../plugins/custom_series.dart';
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

/// Items a renderer draws: the series data, or its conflated version.
class SeriesItems<T extends SeriesData> {
  SeriesItems(this.data, this.indices);

  final List<T> data;

  /// Time scale index of every item.
  final List<int> indices;

  int get length => data.length;

  /// First position whose index is >= [index].
  int lowerBound(int index) {
    var lo = 0;
    var hi = indices.length;
    while (lo < hi) {
      final mid = (lo + hi) >> 1;
      if (indices[mid] < index) {
        lo = mid + 1;
      } else {
        hi = mid;
      }
    }
    return lo;
  }

  /// Positions `[from, to)` inside [range] (inclusive indices).
  (int, int) itemsInRange(IndexRange range) => (lowerBound(range.left), lowerBound(range.right + 1));
}

enum SeriesUpdateKind {
  /// The last value was replaced by another value.
  replaced,

  /// The last item switched between value and whitespace.
  replacedKind,
  appended,
  appendedWhitespace,
}

/// Internal model of a series. The public API is `SeriesApi`.
abstract class SeriesModel<T extends SeriesData, O extends SeriesOptions> {
  SeriesModel(this._options) : formatter = PriceFormatter(_options.priceFormat);

  O _options;
  PriceFormatter formatter;
  late PriceScale priceScale;

  /// Items as given, including whitespace.
  List<SeriesData> _all = <SeriesData>[];

  /// Items with values.
  List<T> _data = <T>[];

  /// Time scale index of every item in [_data].
  List<int> _indices = const [];

  /// Bumped on every data change; used by caches (conflation).
  int dataVersion = 0;

  SeriesItems<T>? _conflatedCache;
  (int, int, List<int>)? _conflatedKey;

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

  /// Items with values.
  List<T> get data => _data;

  /// Items as given, including whitespace.
  List<SeriesData> get allItems => _all;

  /// Whether [item] has no value. Custom series can treat their own items
  /// as whitespace.
  bool isWhitespace(SeriesData item) => item is WhitespaceData || item is! T;

  T? _valueItem(SeriesData item) => isWhitespace(item) ? null : item as T;

  static void _checkType<T>(SeriesData item) {
    if (item is! T && item is! WhitespaceData) {
      throw ArgumentError('Expected $T or WhitespaceData, got ${item.runtimeType}');
    }
  }

  List<int> get indices => _indices;

  bool get visible => _options.visible;

  /// Replaces all data. Items (values of type [T] or [WhitespaceData]) must
  /// be sorted by strictly ascending time.
  void setData(List<SeriesData> data) {
    for (var i = 0; i < data.length; i++) {
      _checkType<T>(data[i]);
      if (i > 0 && data[i].time <= data[i - 1].time) {
        throw ArgumentError(
          'Data must be sorted by strictly ascending time: '
          'index $i (time ${data[i].time}) <= index ${i - 1} (time ${data[i - 1].time})',
        );
      }
    }
    _all = List<SeriesData>.of(data);
    _data = [for (final d in data) ?_valueItem(d)];
    dataVersion++;
  }

  /// Replaces the last item when [item] has the same time, appends it when
  /// newer.
  SeriesUpdateKind update(SeriesData item) {
    _checkType<T>(item);
    dataVersion++;
    if (_all.isNotEmpty) {
      final last = _all.last;
      if (item.time < last.time) {
        throw ArgumentError('Cannot update oldest data, last time=${last.time}, new time=${item.time}');
      }
      if (item.time == last.time) {
        _all[_all.length - 1] = item;
        final wasValue = !isWhitespace(last);
        final value = _valueItem(item);
        if (wasValue && value != null) {
          _data[_data.length - 1] = value;
          return SeriesUpdateKind.replaced;
        }
        if (wasValue) {
          _data.removeLast();
          _indices = _indices.sublist(0, _indices.length - 1);
        } else if (value != null) {
          _data.add(value);
        }
        return SeriesUpdateKind.replacedKind;
      }
    }
    _all.add(item);
    final value = _valueItem(item);
    if (value != null) _data.add(value);
    return value != null ? SeriesUpdateKind.appended : SeriesUpdateKind.appendedWhitespace;
  }

  void setIndices(List<int> indices) => _indices = indices;

  /// Merges a group of consecutive items into one, or returns `null` when
  /// this series type doesn't support conflation.
  T? conflateGroup(List<T> group) => null;

  /// Items to draw. With [factor] > 1, groups of [factor] consecutive items
  /// are merged like upstream's `DataConflater`, the last group absorbing
  /// the remainder; each group sits at its first item's index.
  SeriesItems<T> renderItems(int factor) {
    if (factor <= 1 || _data.length < 2 || conflateGroup(_data.sublist(0, 1)) == null) {
      return SeriesItems(_data, _indices);
    }
    final key = (dataVersion, factor, _indices);
    final cached = _conflatedCache;
    if (cached != null && _conflatedKey != null && _conflatedKey!.$1 == key.$1 && _conflatedKey!.$2 == factor &&
        identical(_conflatedKey!.$3, _indices)) {
      return cached;
    }
    final data = <T>[];
    final indices = <int>[];
    var start = 0;
    while (start < _data.length) {
      var end = math.min(start + factor, _data.length);
      // Fold a short remainder into the last group.
      if (_data.length - end < factor && _data.length - end > 0) end = _data.length;
      data.add(conflateGroup(_data.sublist(start, end)) as T);
      indices.add(_indices[start]);
      start = end;
    }
    _conflatedKey = key;
    return _conflatedCache = SeriesItems(data, indices);
  }

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
  CandlestickData conflateGroup(List<CandlestickData> g) {
    final last = g.last;
    return CandlestickData(
      time: g.first.time,
      open: g.first.open,
      high: g.map((d) => d.high).reduce(math.max),
      low: g.map((d) => d.low).reduce(math.min),
      close: last.close,
      color: last.color,
      borderColor: last.borderColor,
      wickColor: last.wickColor,
    );
  }

  @override
  void paint(SeriesPaintContext ctx) => paintCandlesticks(ctx, this);
}

class BarSeriesModel extends OhlcSeriesModel<BarData, BarSeriesOptions> {
  BarSeriesModel(super.options);

  @override
  Color itemColor(BarData item) => item.color ?? (item.isUp ? options.upColor : options.downColor);

  @override
  BarData conflateGroup(List<BarData> g) => BarData(
        time: g.first.time,
        open: g.first.open,
        high: g.map((d) => d.high).reduce(math.max),
        low: g.map((d) => d.low).reduce(math.min),
        close: g.last.close,
        color: g.last.color,
      );

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
  LineData conflateGroup(List<LineData> g) => LineData(time: g.first.time, value: g.last.value, color: g.last.color);

  @override
  void paint(SeriesPaintContext ctx) => paintLine(ctx, this);
}

class AreaSeriesModel extends LineLikeSeriesModel<AreaData, AreaSeriesOptions> {
  AreaSeriesModel(super.options);

  @override
  Color lineColor(AreaData item) => item.lineColor ?? options.lineColor;

  @override
  AreaData conflateGroup(List<AreaData> g) {
    final l = g.last;
    return AreaData(
      time: g.first.time,
      value: l.value,
      lineColor: l.lineColor,
      topColor: l.topColor,
      bottomColor: l.bottomColor,
    );
  }

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
  BaselineData conflateGroup(List<BaselineData> g) {
    final l = g.last;
    return BaselineData(
      time: g.first.time,
      value: l.value,
      topLineColor: l.topLineColor,
      topFillColor1: l.topFillColor1,
      topFillColor2: l.topFillColor2,
      bottomLineColor: l.bottomLineColor,
      bottomFillColor1: l.bottomFillColor1,
      bottomFillColor2: l.bottomFillColor2,
    );
  }

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
  HistogramData conflateGroup(List<HistogramData> g) =>
      HistogramData(time: g.first.time, value: g.last.value, color: g.last.color);

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

class CustomSeriesModel<T extends SeriesData> extends SeriesModel<T, CustomSeriesOptions> {
  CustomSeriesModel(this.view, super.options);

  final CustomSeriesView<T> view;

  @override
  bool isWhitespace(SeriesData item) => super.isWhitespace(item) || view.isWhitespace(item as T);

  @override
  double minValue(T item) => view.priceValues(item).reduce(math.min);

  @override
  double maxValue(T item) => view.priceValues(item).reduce(math.max);

  @override
  double closeValue(T item) => view.priceValues(item).last;

  @override
  List<double> magnetValues(T item, {required bool ohlc}) => ohlc ? view.priceValues(item) : [closeValue(item)];

  @override
  Color itemColor(T item) => options.color;

  @override
  void paint(SeriesPaintContext ctx) {
    var (from, to) = itemsInRange(ctx.visibleRange);
    from = math.max(0, from - 1);
    to = math.min(data.length, to + 1);
    final bars = [
      for (var i = from; i < to; i++)
        CustomBarItem<T>(x: ctx.timeScale.indexToCoordinate(indices[i]), index: indices[i], data: data[i]),
    ];
    // Custom views draw in logical pixels; the series canvas is in bitmap pixels.
    ctx.canvas.save();
    ctx.canvas.scale(ctx.pixelRatio);
    view.draw(CustomSeriesDrawContext<T>(
      canvas: ctx.canvas,
      paneSize: ctx.paneSize,
      pixelRatio: ctx.pixelRatio,
      barSpacing: ctx.timeScale.barSpacing,
      bars: bars,
      options: options,
      priceToCoordinate: priceToCoordinate,
    ));
    ctx.canvas.restore();
  }
}
