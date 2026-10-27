// Technical indicators, computed incrementally: `compute(input, from)` only
// recalculates outputs from index `from` on, reusing the state kept for
// earlier bars. A realtime tick costs O(1) (O(period) for window ones).
import 'dart:math' as math;
import 'dart:ui' show Color;

import '../options.dart';

/// One bar of indicator input.
class IndicatorInput {
  const IndicatorInput({
    required this.time,
    required this.open,
    required this.high,
    required this.low,
    required this.close,
    this.volume,
  });

  /// A single value (line / area data): open = high = low = close.
  const IndicatorInput.value({required this.time, required double value, this.volume})
    : open = value,
      high = value,
      low = value,
      close = value;

  final num time;
  final double open;
  final double high;
  final double low;
  final double close;
  final double? volume;
}

/// Which price an indicator reads.
enum PriceSource { open, high, low, close, hl2, hlc3, ohlc4 }

double priceOf(IndicatorInput b, PriceSource s) => switch (s) {
  PriceSource.open => b.open,
  PriceSource.high => b.high,
  PriceSource.low => b.low,
  PriceSource.close => b.close,
  PriceSource.hl2 => (b.high + b.low) / 2,
  PriceSource.hlc3 => (b.high + b.low + b.close) / 3,
  PriceSource.ohlc4 => (b.open + b.high + b.low + b.close) / 4,
};

enum IndicatorLineKind { line, histogram }

/// An output of an indicator, drawn as one series.
class IndicatorLine {
  const IndicatorLine(
    this.name,
    this.color, {
    this.kind = IndicatorLineKind.line,
    this.lineWidth = 1.5,
    this.lineStyle = LineStyle.solid,
    this.shift = 0,
    this.negativeColor,
  });

  final String name;
  final Color color;
  final IndicatorLineKind kind;
  final double lineWidth;
  final LineStyle lineStyle;

  /// Bars the value is plotted ahead (> 0) or behind (< 0) the bar it was
  /// computed on, like Ichimoku's spans.
  final int shift;

  /// Histogram columns below zero; `null` uses [color].
  final Color? negativeColor;
}

/// A filled band between two outputs (indices into [Indicator.lines]).
class IndicatorBand {
  const IndicatorBand(this.upper, this.lower, this.fillColor, {this.invertedFillColor});

  final int upper;
  final int lower;
  final Color fillColor;

  /// Fill where the lower output is above the upper one (Ichimoku cloud).
  final Color? invertedFillColor;
}

/// Base class of indicators. Subclasses fill `out[line][i]` for `i >= from`.
abstract class Indicator {
  /// Short name shown in titles and legends, e.g. `RSI 14`.
  String get name;

  /// Drawn over the source series (moving averages, bands) instead of in a
  /// pane of its own (oscillators).
  bool get overlay;

  List<IndicatorLine> get lines;

  /// Horizontal reference levels, e.g. 70 / 30 for RSI.
  List<double> get levels => const [];

  IndicatorBand? get band => null;

  /// Fixed price range of an oscillator pane (e.g. 0..100), or `null` to
  /// autoscale.
  (double, double)? get range => null;

  /// Computes outputs from bar [from] on. `out` has one list per line,
  /// each as long as [input].
  void compute(List<IndicatorInput> input, int from, List<List<double?>> out);

  /// Full computation, for tests and one-off use.
  List<List<double?>> computeAll(List<IndicatorInput> input) {
    final out = [for (final _ in lines) List<double?>.filled(input.length, null)];
    compute(input, 0, out);
    return out;
  }
}

/// Grows (or shrinks) a state array to [n], keeping the first [keep] values.
List<double> _fit(List<double> a, int n, int keep) {
  if (a.length > keep) a.length = keep;
  while (a.length < n) {
    a.add(double.nan);
  }
  return a;
}

/// Simple moving average.
class Sma extends Indicator {
  Sma(this.period, {this.source = PriceSource.close, this.color = const Color(0xFF2962FF)});

  final int period;
  final PriceSource source;
  final Color color;
  final List<double> _prefix = [];

  @override
  String get name => 'SMA $period';

  @override
  bool get overlay => true;

  @override
  List<IndicatorLine> get lines => [IndicatorLine(name, color)];

  @override
  void compute(List<IndicatorInput> input, int from, List<List<double?>> out) {
    // Prefix sums: SMA(i) = (P[i] - P[i - period]) / period.
    _fit(_prefix, input.length, from);
    for (var i = from; i < input.length; i++) {
      _prefix[i] = (i > 0 ? _prefix[i - 1] : 0) + priceOf(input[i], source);
      out[0][i] = i < period - 1 ? null : (_prefix[i] - (i >= period ? _prefix[i - period] : 0)) / period;
    }
  }
}

/// Exponential moving average, seeded with the SMA of the first [period]
/// values like TradingView.
class Ema extends Indicator {
  Ema(this.period, {this.source = PriceSource.close, this.color = const Color(0xFFFF9800)});

  final int period;
  final PriceSource source;
  final Color color;

  @override
  String get name => 'EMA $period';

  @override
  bool get overlay => true;

  @override
  List<IndicatorLine> get lines => [IndicatorLine(name, color)];

  @override
  void compute(List<IndicatorInput> input, int from, List<List<double?>> out) =>
      emaInto([for (final b in input) priceOf(b, source)], period, from, out[0]);
}

/// EMA of [values] into [out] from [from] on; `null` values are skipped
/// until [period] valid values seed the average.
void emaInto(List<double?> values, int period, int from, List<double?> out) {
  final k = 2 / (period + 1);
  for (var i = from; i < values.length; i++) {
    final v = values[i];
    final prev = i > 0 ? out[i - 1] : null;
    if (v == null) {
      out[i] = null;
    } else if (prev != null) {
      out[i] = v * k + prev * (1 - k);
    } else {
      // Seed with the SMA of the first `period` valid values.
      var count = 0;
      var sum = 0.0;
      for (var j = i; j >= 0 && count < period; j--) {
        final x = values[j];
        if (x == null) break;
        sum += x;
        count++;
      }
      out[i] = count == period ? sum / period : null;
    }
  }
}

/// Weighted moving average (weights 1..period, newest heaviest).
class Wma extends Indicator {
  Wma(this.period, {this.source = PriceSource.close, this.color = const Color(0xFF26A69A)});

  final int period;
  final PriceSource source;
  final Color color;

  @override
  String get name => 'WMA $period';

  @override
  bool get overlay => true;

  @override
  List<IndicatorLine> get lines => [IndicatorLine(name, color)];

  @override
  void compute(List<IndicatorInput> input, int from, List<List<double?>> out) {
    final denominator = period * (period + 1) / 2;
    for (var i = from; i < input.length; i++) {
      if (i < period - 1) {
        out[0][i] = null;
        continue;
      }
      var sum = 0.0;
      for (var w = 1; w <= period; w++) {
        sum += w * priceOf(input[i - period + w], source);
      }
      out[0][i] = sum / denominator;
    }
  }
}

/// Bollinger Bands: SMA ± [multiplier] population standard deviations.
class Bollinger extends Indicator {
  Bollinger({
    this.period = 20,
    this.multiplier = 2,
    this.source = PriceSource.close,
    this.color = const Color(0xFF2962FF),
    this.basisColor = const Color(0xFFFF9800),
    this.fillColor = const Color(0x142962FF),
  });

  final int period;
  final double multiplier;
  final PriceSource source;
  final Color color;
  final Color basisColor;
  final Color fillColor;

  @override
  String get name => 'BB $period ${_n(multiplier)}';

  @override
  bool get overlay => true;

  @override
  List<IndicatorLine> get lines => [
    IndicatorLine('Basis', basisColor, lineWidth: 1),
    IndicatorLine('Upper', color, lineWidth: 1),
    IndicatorLine('Lower', color, lineWidth: 1),
  ];

  @override
  IndicatorBand get band => IndicatorBand(1, 2, fillColor);

  @override
  void compute(List<IndicatorInput> input, int from, List<List<double?>> out) {
    for (var i = from; i < input.length; i++) {
      if (i < period - 1) {
        out[0][i] = out[1][i] = out[2][i] = null;
        continue;
      }
      var sum = 0.0;
      for (var j = i - period + 1; j <= i; j++) {
        sum += priceOf(input[j], source);
      }
      final mean = sum / period;
      var squares = 0.0;
      for (var j = i - period + 1; j <= i; j++) {
        final d = priceOf(input[j], source) - mean;
        squares += d * d;
      }
      final sd = math.sqrt(squares / period);
      out[0][i] = mean;
      out[1][i] = mean + multiplier * sd;
      out[2][i] = mean - multiplier * sd;
    }
  }
}

/// Relative Strength Index with Wilder's smoothing.
class Rsi extends Indicator {
  Rsi([this.period = 14, this.color = const Color(0xFF7E57C2)]);

  final int period;
  final Color color;
  final List<double> _gain = [];
  final List<double> _loss = [];

  @override
  String get name => 'RSI $period';

  @override
  bool get overlay => false;

  @override
  List<IndicatorLine> get lines => [IndicatorLine(name, color)];

  @override
  List<double> get levels => const [70, 30];

  @override
  (double, double) get range => (0, 100);

  @override
  void compute(List<IndicatorInput> input, int from, List<List<double?>> out) {
    _fit(_gain, input.length, from);
    _fit(_loss, input.length, from);
    for (var i = from; i < input.length; i++) {
      if (i < period) {
        out[0][i] = null;
        continue;
      }
      double gain, loss;
      if (i == period) {
        gain = 0;
        loss = 0;
        for (var j = 1; j <= period; j++) {
          final d = input[j].close - input[j - 1].close;
          if (d > 0) {
            gain += d;
          } else {
            loss -= d;
          }
        }
        gain /= period;
        loss /= period;
      } else {
        final d = input[i].close - input[i - 1].close;
        gain = (_gain[i - 1] * (period - 1) + math.max(d, 0)) / period;
        loss = (_loss[i - 1] * (period - 1) + math.max(-d, 0)) / period;
      }
      _gain[i] = gain;
      _loss[i] = loss;
      out[0][i] = loss == 0 ? 100 : 100 - 100 / (1 + gain / loss);
    }
  }
}

/// MACD: EMA(fast) − EMA(slow), its EMA signal and the histogram.
class Macd extends Indicator {
  Macd({
    this.fast = 12,
    this.slow = 26,
    this.signal = 9,
    this.macdColor = const Color(0xFF2962FF),
    this.signalColor = const Color(0xFFFF9800),
    this.upColor = const Color(0x9926A69A),
    this.downColor = const Color(0x99EF5350),
  });

  final int fast;
  final int slow;
  final int signal;
  final Color macdColor;
  final Color signalColor;
  final Color upColor;
  final Color downColor;

  final List<double?> _fast = [];
  final List<double?> _slow = [];

  @override
  String get name => 'MACD $fast $slow $signal';

  @override
  bool get overlay => false;

  @override
  List<IndicatorLine> get lines => [
    IndicatorLine('Histogram', upColor, kind: IndicatorLineKind.histogram, negativeColor: downColor),
    IndicatorLine('MACD', macdColor),
    IndicatorLine('Signal', signalColor),
  ];

  @override
  void compute(List<IndicatorInput> input, int from, List<List<double?>> out) {
    final closes = [for (final b in input) b.close];
    for (final a in [_fast, _slow]) {
      if (a.length > from) a.length = from;
      while (a.length < input.length) {
        a.add(null);
      }
    }
    emaInto(closes, fast, from, _fast);
    emaInto(closes, slow, from, _slow);
    for (var i = from; i < input.length; i++) {
      final f = _fast[i], s = _slow[i];
      out[1][i] = f == null || s == null ? null : f - s;
    }
    emaInto(out[1], signal, from, out[2]);
    for (var i = from; i < input.length; i++) {
      final m = out[1][i], sig = out[2][i];
      out[0][i] = m == null || sig == null ? null : m - sig;
    }
  }
}

/// Stochastic oscillator: %K smoothed by [smoothK], %D its SMA over [d].
class Stochastic extends Indicator {
  Stochastic({
    this.period = 14,
    this.smoothK = 3,
    this.d = 3,
    this.kColor = const Color(0xFF2962FF),
    this.dColor = const Color(0xFFFF9800),
  });

  final int period;
  final int smoothK;
  final int d;
  final Color kColor;
  final Color dColor;
  final List<double?> _raw = [];

  @override
  String get name => 'Stoch $period $smoothK $d';

  @override
  bool get overlay => false;

  @override
  List<IndicatorLine> get lines => [IndicatorLine('%K', kColor), IndicatorLine('%D', dColor)];

  @override
  List<double> get levels => const [80, 20];

  @override
  (double, double) get range => (0, 100);

  static double? _smaOf(List<double?> values, int i, int n) {
    if (i < n - 1) return null;
    var sum = 0.0;
    for (var j = i - n + 1; j <= i; j++) {
      final v = values[j];
      if (v == null) return null;
      sum += v;
    }
    return sum / n;
  }

  @override
  void compute(List<IndicatorInput> input, int from, List<List<double?>> out) {
    if (_raw.length > from) _raw.length = from;
    for (var i = _raw.length; i < input.length; i++) {
      if (i < period - 1) {
        _raw.add(null);
        continue;
      }
      var hh = double.negativeInfinity, ll = double.infinity;
      for (var j = i - period + 1; j <= i; j++) {
        hh = math.max(hh, input[j].high);
        ll = math.min(ll, input[j].low);
      }
      _raw.add(hh == ll ? 50 : (input[i].close - ll) / (hh - ll) * 100);
    }
    for (var i = from; i < input.length; i++) {
      out[0][i] = _smaOf(_raw, i, smoothK);
    }
    for (var i = from; i < input.length; i++) {
      out[1][i] = _smaOf(out[0], i, d);
    }
  }
}

/// Average True Range with Wilder's smoothing.
class Atr extends Indicator {
  Atr([this.period = 14, this.color = const Color(0xFFEF5350)]);

  final int period;
  final Color color;

  @override
  String get name => 'ATR $period';

  @override
  bool get overlay => false;

  @override
  List<IndicatorLine> get lines => [IndicatorLine(name, color)];

  static double trueRange(List<IndicatorInput> input, int i) {
    final b = input[i];
    if (i == 0) return b.high - b.low;
    final prevClose = input[i - 1].close;
    return math.max(b.high - b.low, math.max((b.high - prevClose).abs(), (b.low - prevClose).abs()));
  }

  @override
  void compute(List<IndicatorInput> input, int from, List<List<double?>> out) {
    for (var i = from; i < input.length; i++) {
      if (i < period - 1) {
        out[0][i] = null;
      } else if (i == period - 1) {
        var sum = 0.0;
        for (var j = 0; j < period; j++) {
          sum += trueRange(input, j);
        }
        out[0][i] = sum / period;
      } else {
        out[0][i] = (out[0][i - 1]! * (period - 1) + trueRange(input, i)) / period;
      }
    }
  }
}

/// Volume-weighted average price, reset each UTC day by default. Needs
/// volumes ([IndicatorInput.volume]).
class Vwap extends Indicator {
  Vwap({this.color = const Color(0xFF00BCD4), this.sessionSeconds = 86400, this.source = PriceSource.hlc3});

  final Color color;

  /// Length of a session; the average restarts when `time ~/ sessionSeconds`
  /// changes. `0` never resets.
  final int sessionSeconds;
  final PriceSource source;

  final List<double> _pv = [];
  final List<double> _v = [];

  @override
  String get name => 'VWAP';

  @override
  bool get overlay => true;

  @override
  List<IndicatorLine> get lines => [IndicatorLine(name, color)];

  @override
  void compute(List<IndicatorInput> input, int from, List<List<double?>> out) {
    _fit(_pv, input.length, from);
    _fit(_v, input.length, from);
    for (var i = from; i < input.length; i++) {
      final b = input[i];
      final volume = b.volume ?? 0;
      final newSession =
          i == 0 || (sessionSeconds > 0 && input[i - 1].time ~/ sessionSeconds != b.time ~/ sessionSeconds);
      _pv[i] = (newSession ? 0 : _pv[i - 1]) + priceOf(b, source) * volume;
      _v[i] = (newSession ? 0 : _v[i - 1]) + volume;
      out[0][i] = _v[i] == 0 ? null : _pv[i] / _v[i];
    }
  }
}

/// Ichimoku Kinko Hyo. Senkou spans are plotted [displacement] bars ahead
/// (the cloud), Chikou [displacement] bars behind.
class Ichimoku extends Indicator {
  Ichimoku({
    this.conversion = 9,
    this.base = 26,
    this.spanB = 52,
    this.displacement = 26,
    this.bullishCloud = const Color(0x3326A69A),
    this.bearishCloud = const Color(0x33EF5350),
  });

  final int conversion;
  final int base;
  final int spanB;
  final int displacement;
  final Color bullishCloud;
  final Color bearishCloud;

  @override
  String get name => 'Ichimoku $conversion $base $spanB';

  @override
  bool get overlay => true;

  @override
  List<IndicatorLine> get lines => [
    const IndicatorLine('Tenkan', Color(0xFF2962FF), lineWidth: 1),
    const IndicatorLine('Kijun', Color(0xFFB71C1C), lineWidth: 1),
    IndicatorLine('Senkou A', const Color(0xFF26A69A), lineWidth: 1, shift: displacement),
    IndicatorLine('Senkou B', const Color(0xFFEF5350), lineWidth: 1, shift: displacement),
    IndicatorLine('Chikou', const Color(0xFF43A047), lineWidth: 1, shift: -displacement),
  ];

  @override
  IndicatorBand get band => IndicatorBand(2, 3, bullishCloud, invertedFillColor: bearishCloud);

  static double? _mid(List<IndicatorInput> input, int i, int n) {
    if (i < n - 1) return null;
    var hh = double.negativeInfinity, ll = double.infinity;
    for (var j = i - n + 1; j <= i; j++) {
      hh = math.max(hh, input[j].high);
      ll = math.min(ll, input[j].low);
    }
    return (hh + ll) / 2;
  }

  @override
  void compute(List<IndicatorInput> input, int from, List<List<double?>> out) {
    for (var i = from; i < input.length; i++) {
      final tenkan = _mid(input, i, conversion);
      final kijun = _mid(input, i, base);
      out[0][i] = tenkan;
      out[1][i] = kijun;
      out[2][i] = tenkan == null || kijun == null ? null : (tenkan + kijun) / 2;
      out[3][i] = _mid(input, i, spanB);
      out[4][i] = input[i].close;
    }
  }
}

String _n(double v) => v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toString();
