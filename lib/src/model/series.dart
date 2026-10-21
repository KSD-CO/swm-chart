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
  List<int> _indices = <int>[];

  /// Bumped on every data change; used by caches (conflation).
  int dataVersion = 0;

  // Min/max per chunk of [_minMaxChunk] items, so autoscale over a wide
  // visible range costs O(n / chunk) instead of O(n), like upstream's
  // plot list min/max cache. Chunks from [_minMaxDirtyFrom] on are stale.
  static const int _minMaxChunk = 64;
  final List<double> _chunkMin = [];
  final List<double> _chunkMax = [];
  int _minMaxDirtyFrom = 0;

  // Conflation levels (2, 4, ... 512) built like upstream's DataConflater:
  // level 2 from the data, level 2k from level k. Items from
  // [_conflationDirtyFrom] on changed since they were built.
  final Map<int, SeriesItems<T>> _levels = {};
  List<int>? _levelsIndices;
  int _conflationDirtyFrom = 0;

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
    _minMaxDirtyFrom = 0;
    _levels.clear();
  }

  /// Replaces the last item when [item] has the same time, appends it when
  /// newer.
  SeriesUpdateKind update(SeriesData item) {
    _checkType<T>(item);
    dataVersion++;
    // Only the last item changes (or one is appended).
    _minMaxDirtyFrom = math.min(_minMaxDirtyFrom, math.max(0, _data.length - 1));
    _conflationDirtyFrom = math.min(_conflationDirtyFrom, math.max(0, _data.length - 1));
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

  /// Removes the last [count] items (values and whitespace) and returns them.
  List<SeriesData> pop(int count) {
    final n = count.clamp(0, _all.length);
    final removed = _all.sublist(_all.length - n);
    _all = _all.sublist(0, _all.length - n);
    _data = [for (final d in _all) ?_valueItem(d)];
    dataVersion++;
    _minMaxDirtyFrom = 0;
    _levels.clear();
    return removed;
  }

  /// Merges a group of consecutive items into one, or returns `null` when
  /// this series type doesn't support conflation.
  T? conflateGroup(List<T> g) => null;

  /// Whether this series can be conflated.
  bool get supportsConflation => true;

  /// Merges two consecutive (possibly already merged) items; [aIndex] and
  /// [bIndex] are their logical indices. Upstream's `_mergeTwoRows`:
  /// first open/time, extreme high/low, last close.
  T mergeItems(T a, int aIndex, T b, int bIndex) => conflateGroup([a, b]) as T;

  /// Upstream's `_normalizeConflationLevel`: the smallest power of two
  /// >= [barsToMerge], between 2 and 512.
  static int normalizeConflationLevel(int barsToMerge) {
    var level = 2;
    while (level < barsToMerge && level < 512) {
      level *= 2;
    }
    return level;
  }

  /// Items to draw: the data, or its conflation level for [factor].
  SeriesItems<T> renderItems(int factor) {
    final base = SeriesItems(_data, _indices);
    if (factor <= 1 || _data.length < 2 || !supportsConflation) return base;
    if (!identical(_levelsIndices, _indices)) {
      // The time scale was rebuilt: indices changed for every item.
      _levels.clear();
      _levelsIndices = _indices;
    }
    if (_levels.isEmpty) {
      _conflationDirtyFrom = _data.length;
    } else if (_conflationDirtyFrom < _data.length) {
      _updateLevelsFrom(_conflationDirtyFrom, base);
    }
    return _level(normalizeConflationLevel(factor), base);
  }

  /// Conflation levels currently cached.
  Iterable<int> get cachedConflationLevels => _levels.keys;

  /// Builds [levels] ahead of time (`precomputeConflationOnInit`).
  void precomputeConflation(Iterable<int> levels) {
    if (_data.length < 2 || !supportsConflation) return;
    for (final level in levels) {
      if (level > 1) renderItems(level);
    }
  }

  SeriesItems<T> _level(int level, SeriesItems<T> base) {
    final cached = _levels[level];
    if (cached != null) return cached;
    final source = level == 2 ? base : _level(level ~/ 2, base);
    final result = SeriesItems<T>(<T>[], <int>[]);
    _mergePairs(source, result, 0);
    return _levels[level] = result;
  }

  /// Upstream's `_buildChunksFromData` with a merge factor of 2, writing
  /// [target] from chunk [fromChunk] on: pairs of items, and a final odd
  /// item folded into the previous chunk.
  void _mergePairs(SeriesItems<T> source, SeriesItems<T> target, int fromChunk) {
    target.data.length = fromChunk;
    target.indices.length = fromChunk;
    final n = source.length;
    for (var i = fromChunk * 2; i < n; i += 2) {
      if (i + 1 < n) {
        target.data.add(mergeItems(source.data[i], source.indices[i], source.data[i + 1], source.indices[i + 1]));
        target.indices.add(source.indices[i]);
      } else if (target.data.isEmpty) {
        target.data.add(source.data[i]);
        target.indices.add(source.indices[i]);
      } else {
        final last = target.data.length - 1;
        target.data[last] = mergeItems(target.data[last], target.indices[last], source.data[i], source.indices[i]);
      }
    }
  }

  /// Like upstream's `updateLastConflatedChunk`: after the items from
  /// [from] changed, rebuild only the trailing chunks of every level.
  void _updateLevelsFrom(int from, SeriesItems<T> base) {
    var dirty = from;
    for (var level = 2; level <= 512; level *= 2) {
      final target = _levels[level];
      if (target == null) break;
      final source = level == 2 ? base : _levels[level ~/ 2]!;
      // One chunk earlier: it may hold a folded odd remainder.
      final fromChunk = math.max(0, dirty ~/ 2 - 1);
      _mergePairs(source, target, fromChunk);
      dirty = fromChunk;
    }
    _conflationDirtyFrom = _data.length;
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

  /// `y = a * price + b`, or `null` when the scale isn't linear (log).
  (double, double)? priceTransform() => priceScale.linearTransform(baseValue);

  double coordinateToPrice(double y) => priceScale.coordinateToPrice(y, baseValue);

  String formatPrice(double price) => priceScale.formatPrice(price, baseValue);

  double minValue(T item);

  double maxValue(T item);

  double closeValue(T item);

  List<double> magnetValues(T item, {required bool ohlc}) => [closeValue(item)];

  /// Color of the item, used for the last value label and price line.
  Color itemColor(T item);

  void _updateMinMaxChunks() {
    final chunks = (_data.length + _minMaxChunk - 1) ~/ _minMaxChunk;
    final firstDirty = math.min(_minMaxDirtyFrom ~/ _minMaxChunk, _chunkMin.length);
    _chunkMin.length = math.min(_chunkMin.length, firstDirty);
    _chunkMax.length = _chunkMin.length;
    for (var c = firstDirty; c < chunks; c++) {
      var min = double.infinity, max = double.negativeInfinity;
      final end = math.min((c + 1) * _minMaxChunk, _data.length);
      for (var i = c * _minMaxChunk; i < end; i++) {
        final item = _data[i];
        min = math.min(min, minValue(item));
        max = math.max(max, maxValue(item));
      }
      _chunkMin.add(min);
      _chunkMax.add(max);
    }
    _minMaxDirtyFrom = _data.length;
  }

  /// Min and max of items `[from, to)`.
  (double, double) _minMax(int from, int to) {
    if (_minMaxDirtyFrom < _data.length) _updateMinMaxChunks();
    var min = double.infinity, max = double.negativeInfinity;
    var i = from;
    while (i < to) {
      if (i % _minMaxChunk == 0 && i + _minMaxChunk <= to) {
        final c = i ~/ _minMaxChunk;
        min = math.min(min, _chunkMin[c]);
        max = math.max(max, _chunkMax[c]);
        i += _minMaxChunk;
      } else {
        final item = _data[i];
        min = math.min(min, minValue(item));
        max = math.max(max, maxValue(item));
        i++;
      }
    }
    return (min, max);
  }

  /// Default autoscale: data range plus primitives' ranges and margins.
  AutoscaleInfo? baseAutoscaleInfo(IndexRange range) {
    PriceRange? priceRange;
    if (_data.isNotEmpty) {
      final (from, to) = itemsInRange(range);
      if (from < to) {
        final (min, max) = _minMax(from, to);
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
  bool get supportsConflation => view.conflationReducer != null;

  @override
  T mergeItems(T a, int aIndex, T b, int bIndex) => view.conflationReducer!(
    CustomConflationContext(data: a, index: aIndex, priceValues: view.priceValues(a)),
    CustomConflationContext(data: b, index: bIndex, priceValues: view.priceValues(b)),
  );

  CustomSeriesDrawContext<T> _drawContext(
    Canvas? canvas,
    Size paneSize,
    double pixelRatio,
    TimeScale ts,
    IndexRange visible,
    SeriesItems<T> items,
  ) {
    var (from, to) = items.itemsInRange(visible);
    from = math.max(0, from - 1);
    to = math.min(items.length, to + 1);
    return CustomSeriesDrawContext<T>(
      canvas: canvas ?? Canvas(PictureRecorder()),
      paneSize: paneSize,
      pixelRatio: pixelRatio,
      barSpacing: ts.barSpacing,
      bars: [
        for (var i = from; i < to; i++)
          CustomBarItem<T>(x: ts.indexToCoordinate(items.indices[i]), index: items.indices[i], data: items.data[i]),
      ],
      options: options,
      priceToCoordinate: priceToCoordinate,
    );
  }

  /// Delegates to [CustomSeriesView.hitTest].
  CustomSeriesHitTestResult? hitTest(TimeScale ts, IndexRange visible, double x, double y) {
    final ctx = _drawContext(null, Size(ts.width, priceScale.height), 1, ts, visible, renderItems(1));
    return view.hitTest(ctx, x, y);
  }

  @override
  void paint(SeriesPaintContext ctx) {
    // Custom views draw in logical pixels; the series canvas is in bitmap pixels.
    ctx.canvas.save();
    ctx.canvas.scale(ctx.pixelRatio);
    view.draw(
      _drawContext(
        ctx.canvas,
        ctx.paneSize,
        ctx.pixelRatio,
        ctx.timeScale,
        ctx.visibleRange,
        renderItems(ctx.conflationFactor),
      ),
    );
    ctx.canvas.restore();
  }
}
