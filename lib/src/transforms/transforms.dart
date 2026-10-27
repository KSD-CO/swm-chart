// Derived chart types (Heikin-Ashi, Renko, line break, range bars) and
// timeframe resampling, as pure data transforms: feed the result to a
// candlestick (or bar) series.
//
// Renko, line break and range bars aren't time based: one source bar can
// produce several bricks. Bricks from the same source bar get times a
// thousandth of a second apart, so times stay strictly ascending and labels
// still show the source bar's date.
import 'dart:math' as math;

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
