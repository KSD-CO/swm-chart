// Derived chart types (Heikin-Ashi, Renko, line break, range bars) and
// timeframe resampling, as pure data transforms: feed the result to a
// candlestick (or bar) series.
//
// Renko, line break and range bars aren't time based: one source bar can
// produce several bricks. Bricks from the same source bar get times a
// thousandth of a second apart, so times stay strictly ascending and labels
// still show the source bar's date.
import 'dart:math' as math;
import 'dart:ui' show Color;

import '../data.dart';
import '../model/time_utils.dart' show utcDate;

const double _brickStep = 0.001;

// ---- Heikin-Ashi ----

/// Heikin-Ashi candles of [bars].
List<CandlestickData> heikinAshi(List<OhlcData> bars) {
  final converter = HeikinAshi();
  return [for (final b in bars) converter.add(b)];
}

/// Streaming Heikin-Ashi: feed bars as they arrive; a bar with the same
/// time as the previous one replaces it (a realtime tick).
class HeikinAshi {
  CandlestickData? _last;
  CandlestickData? _previous;
  num? _lastSourceTime;

  CandlestickData add(OhlcData bar) {
    if (bar.time == _lastSourceTime) {
      // Replace the last candle: recompute from the one before it.
      _last = _previous;
    }
    final prev = _last;
    final close = (bar.open + bar.high + bar.low + bar.close) / 4;
    final open = prev == null ? (bar.open + bar.close) / 2 : (prev.open + prev.close) / 2;
    final ha = CandlestickData(
      time: bar.time,
      open: open,
      high: math.max(bar.high, math.max(open, close)),
      low: math.min(bar.low, math.min(open, close)),
      close: close,
    );
    _previous = _last;
    _last = ha;
    _lastSourceTime = bar.time;
    return ha;
  }
}

// ---- Renko ----

/// Traditional Renko bricks of [boxSize], driven by closes.
///
/// The last brick spans `[low, high]`: an up brick is added when the close
/// reaches `high + boxSize`, a down brick when it reaches `low - boxSize`.
/// As a brick is one box tall, a reversal needs two boxes, as usual.
List<CandlestickData> renko(List<OhlcData> bars, {required double boxSize}) {
  if (bars.isEmpty || boxSize <= 0) return const [];
  final bricks = <CandlestickData>[];
  // Start from a zero-height brick on the box grid.
  var high = (bars.first.close / boxSize).floorToDouble() * boxSize;
  var low = high;
  for (final bar in bars) {
    final c = bar.close;
    var k = 0;
    while (true) {
      double open, close;
      if (c >= high + boxSize) {
        open = high;
        close = high + boxSize;
        low = high;
        high = close;
      } else if (c <= low - boxSize) {
        open = low;
        close = low - boxSize;
        high = low;
        low = close;
      } else {
        break;
      }
      bricks.add(
        CandlestickData(
          time: bar.time + k++ * _brickStep,
          open: open,
          high: math.max(open, close),
          low: math.min(open, close),
          close: close,
        ),
      );
    }
  }
  return bricks;
}

// ---- Line break ----

/// N-line break (3 by default): a new line when the close goes beyond the
/// extreme of the last [lines] lines in the opposite direction, or beyond
/// the last line in the same direction.
List<CandlestickData> lineBreak(List<OhlcData> bars, {int lines = 3}) {
  final out = <CandlestickData>[];
  if (bars.isEmpty) return out;
  var lastClose = bars.first.close;
  for (final bar in bars.skip(1)) {
    final c = bar.close;
    if (out.isEmpty) {
      if (c != lastClose) out.add(_line(bar.time, lastClose, c));
      continue;
    }
    final last = out.last;
    final up = last.close > last.open;
    final recent = out.sublist(math.max(0, out.length - lines));
    final hi = recent.map((l) => math.max(l.open, l.close)).reduce(math.max);
    final lo = recent.map((l) => math.min(l.open, l.close)).reduce(math.min);
    if (up) {
      if (c > last.close) {
        out.add(_line(bar.time, last.close, c));
      } else if (c < lo) {
        out.add(_line(bar.time, last.open, c));
      }
    } else {
      if (c < last.close) {
        out.add(_line(bar.time, last.close, c));
      } else if (c > hi) {
        out.add(_line(bar.time, last.open, c));
      }
    }
    lastClose = c;
  }
  // Keep times strictly ascending when one bar time repeats.
  for (var i = 1; i < out.length; i++) {
    if (out[i].time <= out[i - 1].time) {
      final l = out[i];
      out[i] = _line(out[i - 1].time + _brickStep, l.open, l.close);
    }
  }
  return out;
}

CandlestickData _line(num time, double open, double close) =>
    CandlestickData(time: time, open: open, high: math.max(open, close), low: math.min(open, close), close: close);

// ---- Range bars ----

/// Range bars: each bar spans [range] from high to low. Prices are walked
/// open -> low/high -> high/low -> close within each source bar (low first
/// for an up bar), so a wide bar produces several range bars.
List<CandlestickData> rangeBars(List<OhlcData> bars, {required double range}) {
  final out = <CandlestickData>[];
  if (bars.isEmpty || range <= 0) return out;
  double? open, high, low, close;
  for (final bar in bars) {
    var k = 0;
    final path = bar.close >= bar.open
        ? [bar.open, bar.low, bar.high, bar.close]
        : [bar.open, bar.high, bar.low, bar.close];
    for (var i = 0; i < path.length; i++) {
      final target = path[i];
      if (open == null) {
        open = high = low = close = target;
        continue;
      }
      // Walk towards the target, closing a bar each time the range fills.
      var p = close!;
      while (p != target) {
        final up = target > p;
        final limit = up ? low! + range : high! - range;
        final next = up ? math.min(target, limit) : math.max(target, limit);
        p = next;
        high = math.max(high!, p);
        low = math.min(low!, p);
        close = p;
        if (high - low >= range - 1e-12) {
          out.add(CandlestickData(time: bar.time + k++ * _brickStep, open: open!, high: high, low: low, close: p));
          open = high = low = close = p;
        }
      }
    }
  }
  return out;
}

// ---- Point & Figure ----

/// Point & Figure columns of [boxSize], driven by closes: a column of Xs
/// (rising) grows while closes make new boxes up, and turns into a column
/// of Os when the close falls [reversal] boxes below its top (and back).
/// Each column is one candle, from its first box to its last — rising
/// columns up, falling ones down — timed at the bar that started it.
List<CandlestickData> pointAndFigure(List<OhlcData> bars, {required double boxSize, int reversal = 3}) {
  final out = <CandlestickData>[];
  if (bars.isEmpty || boxSize <= 0 || reversal < 1) return out;
  double box(double price) => (price / boxSize).floorToDouble() * boxSize;
  var top = box(bars.first.close), bottom = top;
  bool? rising; // null until the first move of a box
  num start = bars.first.time;
  void emit() {
    final up = rising ?? true;
    final column = CandlestickData(
      time: start,
      open: up ? bottom : top,
      high: top,
      low: bottom,
      close: up ? top : bottom,
    );
    if (out.isNotEmpty && out.last.time == start) {
      out[out.length - 1] = column;
    } else {
      out.add(column);
    }
  }

  for (final bar in bars.skip(1)) {
    final c = bar.close;
    if (rising != false && c >= top + boxSize) {
      rising ??= true;
      top = box(c);
      emit();
    } else if (rising != true && c <= bottom - boxSize) {
      rising ??= false;
      bottom = box(c) + (c % boxSize == 0 ? 0 : boxSize);
      emit();
    } else if (rising == true && c <= top - reversal * boxSize) {
      rising = false;
      start = bar.time;
      top = top - boxSize;
      bottom = box(c) + (c % boxSize == 0 ? 0 : boxSize);
      emit();
    } else if (rising == false && c >= bottom + reversal * boxSize) {
      rising = true;
      start = bar.time;
      bottom = bottom + boxSize;
      top = box(c);
      emit();
    }
  }
  return out;
}

// ---- Kagi ----

/// A Kagi line, driven by closes: it runs on while the price keeps its
/// direction and turns when it reverses by [reversal] (a price amount).
/// Thick (yang, [yangColor]) once it climbs past the last shoulder, thin
/// (yin, [yinColor]) once it falls below the last waist — here the colors,
/// a line series having one width. One point per turn and per new extreme.
List<LineData> kagi(
  List<OhlcData> bars, {
  required double reversal,
  Color yangColor = const Color(0xFF26A69A),
  Color yinColor = const Color(0xFFEF5350),
}) {
  final out = <LineData>[];
  if (bars.isEmpty || reversal <= 0) return out;
  var extreme = bars.first.close;
  bool? up;
  var yang = true;
  double? shoulder, waist; // the last turn up top, the last turn down low
  num? lastTime;
  void point(num time, double value) {
    final t = lastTime != null && time <= lastTime! ? lastTime! + _brickStep : time;
    out.add(LineData(time: t, value: value, color: yang ? yangColor : yinColor));
    lastTime = t;
  }

  point(bars.first.time, extreme);
  for (final bar in bars.skip(1)) {
    final c = bar.close;
    if (up != false && c > extreme) {
      up ??= true;
      extreme = c;
    } else if (up != true && c < extreme) {
      up ??= false;
      extreme = c;
    } else if (up == true && c <= extreme - reversal) {
      shoulder = extreme;
      point(bar.time, extreme);
      up = false;
      extreme = c;
    } else if (up == false && c >= extreme + reversal) {
      waist = extreme;
      point(bar.time, extreme);
      up = true;
      extreme = c;
    } else {
      continue;
    }
    if (shoulder != null && extreme > shoulder) yang = true;
    if (waist != null && extreme < waist) yang = false;
  }
  point(bars.last.time, extreme);
  return out;
}

// ---- Box size ----

/// A round box size for Renko, Point & Figure, Kagi and range bars: the
/// average true range of the last [period] bars rounded to 1, 2, 2.5 or 5
/// times a power of ten (1% of the last close when there are too few bars).
double autoBoxSize(List<OhlcData> bars, {int period = 14}) {
  if (bars.isEmpty) return 1;
  double raw;
  if (bars.length <= period) {
    raw = bars.last.close.abs() * 0.01;
  } else {
    var sum = 0.0;
    for (var i = bars.length - period; i < bars.length; i++) {
      final b = bars[i], prev = bars[i - 1].close;
      sum += math.max(b.high - b.low, math.max((b.high - prev).abs(), (b.low - prev).abs()));
    }
    raw = sum / period;
  }
  if (raw <= 0 || !raw.isFinite) return 1;
  final magnitude = math.pow(10, (math.log(raw) / math.ln10).floor()).toDouble();
  final step = raw / magnitude;
  final nice = step < 1.5
      ? 1.0
      : step < 2.25
      ? 2.0
      : step < 3.75
      ? 2.5
      : step < 7.5
      ? 5.0
      : 10.0;
  return nice * magnitude;
}

// ---- Resampling ----

/// A timeframe to resample to.
sealed class Timeframe {
  const Timeframe();

  const factory Timeframe.seconds(int seconds) = _Fixed;
  const factory Timeframe.minutes(int minutes) = _Minutes;
  const factory Timeframe.hours(int hours) = _Hours;
  const factory Timeframe.days(int days) = _Days;

  /// Weeks starting on Monday (UTC).
  const factory Timeframe.weeks() = _Weeks;

  /// Calendar months (UTC).
  const factory Timeframe.months() = _Months;

  /// Start (UTC seconds) of the period containing [time].
  num bucket(num time);
}

class _Fixed extends Timeframe {
  const _Fixed(this.seconds);

  final int seconds;

  @override
  num bucket(num time) => (time / seconds).floor() * seconds;
}

class _Minutes extends _Fixed {
  const _Minutes(int minutes) : super(minutes * 60);
}

class _Hours extends _Fixed {
  const _Hours(int hours) : super(hours * 3600);
}

class _Days extends _Fixed {
  const _Days(int days) : super(days * 86400);
}

class _Weeks extends Timeframe {
  const _Weeks();

  @override
  num bucket(num time) {
    final d = utcDate(time);
    final day = DateTime.utc(d.year, d.month, d.day).subtract(Duration(days: d.weekday - DateTime.monday));
    return day.millisecondsSinceEpoch ~/ 1000;
  }
}

class _Months extends Timeframe {
  const _Months();

  @override
  num bucket(num time) {
    final d = utcDate(time);
    return DateTime.utc(d.year, d.month).millisecondsSinceEpoch ~/ 1000;
  }
}

/// Aggregates [bars] into [timeframe] candles: first open, highest high,
/// lowest low, last close, timed at the start of the period.
List<CandlestickData> resample(List<OhlcData> bars, Timeframe timeframe) {
  final r = Resampler(timeframe);
  final out = <CandlestickData>[];
  for (final b in bars) {
    final c = r.add(b);
    if (out.isNotEmpty && out.last.time == c.time) {
      out[out.length - 1] = c;
    } else {
      out.add(c);
    }
  }
  return out;
}

/// Sums [values] (e.g. volumes) per [timeframe] period.
List<HistogramData> resampleSum(List<SingleValueData> values, Timeframe timeframe) {
  final out = <HistogramData>[];
  for (final v in values) {
    final t = timeframe.bucket(v.time);
    if (out.isNotEmpty && out.last.time == t) {
      out[out.length - 1] = HistogramData(time: t, value: out.last.value + v.value, color: v.color);
    } else {
      out.add(HistogramData(time: t, value: v.value, color: v.color));
    }
  }
  return out;
}

/// Streaming resampler: feed source bars (a repeated time replaces the
/// previous source bar, like a realtime tick) and get the current candle of
/// the period, ready for `series.update`.
class Resampler {
  Resampler(this.timeframe);

  final Timeframe timeframe;

  num? _period;

  /// Source bars of the current period except the last one, aggregated.
  CandlestickData? _closed;
  OhlcData? _lastSource;

  CandlestickData add(OhlcData bar) {
    final period = timeframe.bucket(bar.time);
    if (period != _period) {
      _period = period;
      _closed = null;
    } else if (_lastSource != null && _lastSource!.time != bar.time) {
      _closed = _merge(_closed, _lastSource!, period);
    }
    _lastSource = bar;
    return _merge(_closed, bar, period);
  }

  static CandlestickData _merge(CandlestickData? a, OhlcData b, num period) => CandlestickData(
    time: period,
    open: a?.open ?? b.open,
    high: a == null ? b.high : math.max(a.high, b.high),
    low: a == null ? b.low : math.min(a.low, b.low),
    close: b.close,
  );
}
