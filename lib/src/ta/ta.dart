// Technical analysis on OHLCV bars: indicators, levels, patterns and
// waves, as plain functions over a whole series (see [Ta]). The chart's
// incremental [Indicator]s wrap the ones that are lines.
//
// Ported from Stock World Monitor's own indicator code, which these
// replace there — the same math, so its screener, alerts and backtests
// keep their results.
import 'dart:math';
import 'dart:math' as math;

import 'bar.dart';

class AtrResult {
  final List<double?> values;
  const AtrResult({required this.values});
}

class AdxResult {
  final List<double?> adx;
  final List<double?> plusDI;
  final List<double?> minusDI;
  const AdxResult({required this.adx, required this.plusDI, required this.minusDI});
}

class ObvResult {
  final List<double?> values;
  const ObvResult({required this.values});
}

class PivotPointsResult {
  final double pivot;
  final double r1;
  final double r2;
  final double r3;
  final double s1;
  final double s2;
  final double s3;
  const PivotPointsResult({
    required this.pivot,
    required this.r1,
    required this.r2,
    required this.r3,
    required this.s1,
    required this.s2,
    required this.s3,
  });
}

class VolumeBucket {
  final double priceLow;
  final double priceHigh;
  final double volume;
  const VolumeBucket({required this.priceLow, required this.priceHigh, required this.volume});
}

class VolumeProfileResult {
  final List<VolumeBucket> buckets;
  final double pocPrice;
  final double pocVolume;
  const VolumeProfileResult({required this.buckets, required this.pocPrice, required this.pocVolume});
}

class MacdResult {
  final List<double?> macdLine;
  final List<double?> signalLine;
  final List<double?> histogram;
  MacdResult({required this.macdLine, required this.signalLine, required this.histogram});
}

class BollingerResult {
  final List<double?> middle; // SMA(20)
  final List<double?> upper;
  final List<double?> lower;
  BollingerResult({required this.middle, required this.upper, required this.lower});
}

class StochasticResult {
  final List<double?> k;
  final List<double?> d;
  StochasticResult({required this.k, required this.d});
}

class FibonacciLevel {
  final double ratio;
  final double price;
  const FibonacciLevel({required this.ratio, required this.price});
}

class FibonacciResult {
  final double high;
  final double low;
  final List<FibonacciLevel> levels;
  const FibonacciResult({required this.high, required this.low, required this.levels});
}

class RegressionChannelResult {
  final List<double?> mid; // best-fit trendline
  final List<double?> upper; // mid + k·σ, parallel to mid
  final List<double?> lower; // mid − k·σ, parallel to mid
  const RegressionChannelResult({required this.mid, required this.upper, required this.lower});
}

class SupportResistanceLevel {
  final double price;
  final int strength; // number of swing pivots clustered into this level
  const SupportResistanceLevel({required this.price, required this.strength});
}

enum ChartPatternType {
  doubleTop,
  doubleBottom,
  headAndShoulders,
  inverseHeadAndShoulders,
  ascendingTriangle,
  descendingTriangle,
  symmetricalTriangle,
  risingWedge,
  fallingWedge,
  bullFlag,
  bearFlag,
  cupAndHandle,
}

/// Which way a chart pattern conventionally resolves — drives its color.
/// Symmetrical triangles can break either way.
bool? chartPatternBullish(ChartPatternType t) => switch (t) {
  ChartPatternType.doubleBottom ||
  ChartPatternType.inverseHeadAndShoulders ||
  ChartPatternType.ascendingTriangle ||
  ChartPatternType.fallingWedge ||
  ChartPatternType.bullFlag ||
  ChartPatternType.cupAndHandle => true,
  ChartPatternType.doubleTop ||
  ChartPatternType.headAndShoulders ||
  ChartPatternType.descendingTriangle ||
  ChartPatternType.risingWedge ||
  ChartPatternType.bearFlag => false,
  ChartPatternType.symmetricalTriangle => null,
};

/// Display name (technical names stay in English across languages, like
/// indicator names) — also what's handed to the AI pattern explainer.
String chartPatternLabel(ChartPatternType t) => switch (t) {
  ChartPatternType.doubleTop => 'Double Top',
  ChartPatternType.doubleBottom => 'Double Bottom',
  ChartPatternType.headAndShoulders => 'Head & Shoulders',
  ChartPatternType.inverseHeadAndShoulders => 'Inverse H&S',
  ChartPatternType.ascendingTriangle => 'Ascending Triangle',
  ChartPatternType.descendingTriangle => 'Descending Triangle',
  ChartPatternType.symmetricalTriangle => 'Symmetrical Triangle',
  ChartPatternType.risingWedge => 'Rising Wedge',
  ChartPatternType.fallingWedge => 'Falling Wedge',
  ChartPatternType.bullFlag => 'Bull Flag',
  ChartPatternType.bearFlag => 'Bear Flag',
  ChartPatternType.cupAndHandle => 'Cup & Handle',
};

String candlePatternLabel(CandlePatternType t) => switch (t) {
  CandlePatternType.doji => 'Doji',
  CandlePatternType.hammer => 'Hammer',
  CandlePatternType.shootingStar => 'Shooting Star',
  CandlePatternType.bullishEngulfing => 'Bullish Engulfing',
  CandlePatternType.bearishEngulfing => 'Bearish Engulfing',
  CandlePatternType.morningStar => 'Morning Star',
  CandlePatternType.eveningStar => 'Evening Star',
};

/// Short on-chart tag for a candle pattern marker.
String candlePatternTag(CandlePatternType t) => switch (t) {
  CandlePatternType.doji => 'D',
  CandlePatternType.hammer => 'H',
  CandlePatternType.shootingStar => 'SS',
  CandlePatternType.bullishEngulfing => 'BE',
  CandlePatternType.bearishEngulfing => 'BE',
  CandlePatternType.morningStar => 'MS',
  CandlePatternType.eveningStar => 'ES',
};

enum CandlePatternType { doji, hammer, shootingStar, bullishEngulfing, bearishEngulfing, morningStar, eveningStar }

/// A classic candlestick pattern completing on bar [index].
class CandlePatternMatch {
  final int index;
  final CandlePatternType type;

  /// true = bullish reversal, false = bearish, null = indecision (doji).
  final bool? bullish;
  const CandlePatternMatch({required this.index, required this.type, required this.bullish});
}

/// ZigZag swings: [line] runs straight from swing to swing (a value on
/// every bar, so it slices like any other overlay series) and [pivots]
/// holds the swing price only on the swing bars. The last swing is still
/// forming and can move as new bars come in.
class ZigZagResult {
  final List<double?> line;
  final List<double?> pivots;
  const ZigZagResult({required this.line, required this.pivots});
}

/// Ehlers' Sine Wave: [sine] and [leadSine] cross ahead of cycle turns;
/// [period] is the measured dominant cycle length (bars). In a strong
/// trend the two lines run side by side — no usable cycle.
class SineWaveResult {
  final List<double?> sine;
  final List<double?> leadSine;
  final List<double?> period;
  const SineWaveResult({required this.sine, required this.leadSine, required this.period});
}

/// One labeled point of an Elliott wave count ('1'…'5', 'A'…'C').
class ElliottPoint {
  final int index;
  final double price;
  final String label;
  const ElliottPoint(this.index, this.price, this.label);
}

/// A possible Elliott count: the latest five-wave move on the ZigZag
/// swings that passes the hard rules, plus the A-B-C after it so far.
/// [start] is where wave 1 begins.
class ElliottCount {
  final ElliottPoint start;
  final List<ElliottPoint> waves;
  final bool isUp;
  const ElliottCount({required this.start, required this.waves, required this.isUp});
}

class SupertrendPoint {
  final double value;

  /// true while the trend is up (line below price).
  final bool isUp;
  const SupertrendPoint({required this.value, required this.isUp});
}

class AroonResult {
  final List<double?> up;
  final List<double?> down;
  const AroonResult({required this.up, required this.down});
}

// A detected pattern's defining points, in chronological order — e.g. for
// Head & Shoulders: [leftShoulder, trough1, head, trough2, rightShoulder].
// Drawn by connecting these dots and labeling the shape, not by claiming a
// price target or predicting an outcome.
class ChartPatternMatch {
  final ChartPatternType type;
  final List<int> keyIndices;
  final List<double> keyPrices;
  const ChartPatternMatch({required this.type, required this.keyIndices, required this.keyPrices});
}

class IchimokuResult {
  final List<double?> tenkan; // Conversion line (9)
  final List<double?> kijun; // Base line (26)
  final List<double?> senkouA; // Leading span A, displaced +26 (value under bar i was computed at i-26)
  final List<double?> senkouB; // Leading span B (52), displaced +26 the same way
  final List<double?> chikou; // Lagging span (shifted -26)
  IchimokuResult({
    required this.tenkan,
    required this.kijun,
    required this.senkouA,
    required this.senkouB,
    required this.chikou,
  });
}

class ParabolicSarPoint {
  final double sar;
  final bool isAbove; // true = SAR above price (bearish dots)
  const ParabolicSarPoint({required this.sar, required this.isAbove});
}

class KeltnerChannelResult {
  final List<double?> middle; // EMA(20)
  final List<double?> upper; // middle + multiplier × ATR
  final List<double?> lower; // middle − multiplier × ATR
  const KeltnerChannelResult({required this.middle, required this.upper, required this.lower});
}

class DonchianChannelResult {
  final List<double?> middle; // (upper + lower) / 2
  final List<double?> upper; // highest high over the period
  final List<double?> lower; // lowest low over the period
  const DonchianChannelResult({required this.middle, required this.upper, required this.lower});
}

class Ta {
  // ── Rolling window helpers (O(n)) ────────────────────────────────────────
  // Monotonic-deque rolling max/min: each index enters and leaves the deque
  // once, so a whole series costs O(n) instead of rescanning every window
  // (O(n·period)). Null until the first full window, like the indicators.
  static List<double?> _rollingExtreme(List<double> values, int period, {required bool max}) {
    final n = values.length;
    final result = List<double?>.filled(n, null);
    if (period <= 0) return result;
    final deque = List<int>.filled(n, 0);
    var head = 0, tail = 0; // deque[head..tail) holds candidate indices
    for (int i = 0; i < n; i++) {
      while (tail > head && (max ? values[deque[tail - 1]] <= values[i] : values[deque[tail - 1]] >= values[i])) {
        tail--;
      }
      deque[tail++] = i;
      if (deque[head] <= i - period) head++;
      if (i >= period - 1) result[i] = values[deque[head]];
    }
    return result;
  }

  /// Rolling max/min of [values] over [period] — O(n), null until the
  /// first full window. Public for callers outside the indicator set
  /// (e.g. SignalEngine's N-bar breakout conditions).
  static List<double?> rollingMax(List<double> values, int period) => _rollingExtreme(values, period, max: true);

  static List<double?> rollingMin(List<double> values, int period) => _rollingExtreme(values, period, max: false);

  static List<double> _highs(List<TaBar> points) => [for (final p in points) p.high ?? p.close];

  static List<double> _lows(List<TaBar> points) => [for (final p in points) p.low ?? p.close];

  // ── RSI (Wilder smoothing, period=14) ────────────────────────────────────
  static List<double?> rsi(List<TaBar> points, {int period = 14}) {
    final closes = points.map((p) => p.close).toList();
    final result = List<double?>.filled(closes.length, null);
    if (closes.length < period + 1) return result;

    double avgGain = 0, avgLoss = 0;
    for (int i = 1; i <= period; i++) {
      final d = closes[i] - closes[i - 1];
      if (d > 0) {
        avgGain += d;
      } else {
        avgLoss += -d;
      }
    }
    avgGain /= period;
    avgLoss /= period;

    result[period] = _rsiValue(avgGain, avgLoss);

    for (int i = period + 1; i < closes.length; i++) {
      final d = closes[i] - closes[i - 1];
      avgGain = (avgGain * (period - 1) + (d > 0 ? d : 0)) / period;
      avgLoss = (avgLoss * (period - 1) + (d < 0 ? -d : 0)) / period;
      result[i] = _rsiValue(avgGain, avgLoss);
    }
    return result;
  }

  // A window with no gains AND no losses (a halted or untraded stock —
  // common on thin Vietnamese listings) is neutral, 50 — not 100. Plain
  // `avgLoss == 0 ? 100` read it as maximally overbought, which then fed
  // false "overbought" calls into the Technical Summary, signals and alerts.
  static double _rsiValue(double up, double down) {
    if (down == 0) return up == 0 ? 50.0 : 100.0;
    return 100 - 100 / (1 + up / down);
  }

  // ── SMA ──────────────────────────────────────────────────────────────────
  static List<double?> sma(List<TaBar> points, int period) {
    final closes = points.map((p) => p.close).toList();
    final result = List<double?>.filled(closes.length, null);
    if (period <= 0 || closes.length < period) return result;
    double sum = 0;
    for (int i = 0; i < closes.length; i++) {
      sum += closes[i];
      if (i >= period) sum -= closes[i - period];
      if (i >= period - 1) result[i] = sum / period;
    }
    return result;
  }

  /// Just the latest SMA value — O(period) instead of building the whole
  /// series when only `.last` is needed (Technical Summary, Market Health
  /// scanning every stock in an index).
  static double? smaLast(List<TaBar> points, int period) {
    if (period <= 0 || points.length < period) return null;
    double sum = 0;
    for (int i = points.length - period; i < points.length; i++) {
      sum += points[i].close;
    }
    return sum / period;
  }

  // ── EMA (public wrapper around the same recurrence MACD uses) ────────────
  static List<double?> ema(List<TaBar> points, int period) {
    return _ema(points.map((p) => p.close).toList(), period);
  }

  // ── EMA ──────────────────────────────────────────────────────────────────
  static List<double?> _ema(List<double> values, int period) {
    final result = List<double?>.filled(values.length, null);
    if (values.length < period) return result;
    final k = 2.0 / (period + 1);
    double sum = 0;
    for (int i = 0; i < period; i++) {
      sum += values[i];
    }
    result[period - 1] = sum / period;
    for (int i = period; i < values.length; i++) {
      result[i] = values[i] * k + result[i - 1]! * (1 - k);
    }
    return result;
  }

  // ── MACD (12/26/9) ───────────────────────────────────────────────────────
  static MacdResult macd(List<TaBar> points, {int fast = 12, int slow = 26, int signal = 9}) {
    final closes = points.map((p) => p.close).toList();
    final ema12 = _ema(closes, fast);
    final ema26 = _ema(closes, slow);

    final macdLine = List<double?>.filled(closes.length, null);
    for (int i = 0; i < closes.length; i++) {
      if (ema12[i] != null && ema26[i] != null) {
        macdLine[i] = ema12[i]! - ema26[i]!;
      }
    }

    final macdNonNull = <double>[];
    final macdNonNullIdx = <int>[];
    for (int i = 0; i < macdLine.length; i++) {
      if (macdLine[i] != null) {
        macdNonNull.add(macdLine[i]!);
        macdNonNullIdx.add(i);
      }
    }
    final signalEma = _ema(macdNonNull, signal);
    final signalLine = List<double?>.filled(closes.length, null);
    for (int j = 0; j < macdNonNullIdx.length; j++) {
      signalLine[macdNonNullIdx[j]] = signalEma[j];
    }

    final histogram = List<double?>.filled(closes.length, null);
    for (int i = 0; i < closes.length; i++) {
      if (macdLine[i] != null && signalLine[i] != null) {
        histogram[i] = macdLine[i]! - signalLine[i]!;
      }
    }
    return MacdResult(macdLine: macdLine, signalLine: signalLine, histogram: histogram);
  }

  // ── Bollinger Bands (SMA ± stdDev σ) ────────────────────────────────────
  static BollingerResult bollinger(List<TaBar> points, {int period = 20, double stdDev = 2.0}) {
    final closes = points.map((p) => p.close).toList();
    final n = closes.length;
    final middle = List<double?>.filled(n, null);
    final upper = List<double?>.filled(n, null);
    final lower = List<double?>.filled(n, null);

    // Sliding sum + sum of squares: O(n) instead of two passes over every
    // window. Variance is clamped at 0 since floating-point cancellation can
    // leave a tiny negative on a flat window.
    double sum = 0, sumSq = 0;
    for (int i = 0; i < n; i++) {
      sum += closes[i];
      sumSq += closes[i] * closes[i];
      if (i >= period) {
        sum -= closes[i - period];
        sumSq -= closes[i - period] * closes[i - period];
      }
      if (i < period - 1) continue;
      final mean = sum / period;
      final variance = max(0.0, sumSq / period - mean * mean);
      final sd = sqrt(variance);
      middle[i] = mean;
      upper[i] = mean + stdDev * sd;
      lower[i] = mean - stdDev * sd;
    }
    return BollingerResult(middle: middle, upper: upper, lower: lower);
  }

  // ── Stochastic (%K/%D) ───────────────────────────────────────────────────
  static StochasticResult stochastic(List<TaBar> points, {int kPeriod = 14, int dPeriod = 3}) {
    final n = points.length;
    final k = List<double?>.filled(n, null);
    final hiN = _rollingExtreme(_highs(points), kPeriod, max: true);
    final loN = _rollingExtreme(_lows(points), kPeriod, max: false);

    for (int i = kPeriod - 1; i < n; i++) {
      final hi = hiN[i]!, lo = loN[i]!;
      k[i] = hi == lo ? 50.0 : (points[i].close - lo) / (hi - lo) * 100;
    }

    // %D = SMA(3) of %K
    final kNonNull = <double>[];
    final kIdx = <int>[];
    for (int i = 0; i < n; i++) {
      if (k[i] != null) {
        kNonNull.add(k[i]!);
        kIdx.add(i);
      }
    }
    final d = List<double?>.filled(n, null);
    for (int j = dPeriod - 1; j < kNonNull.length; j++) {
      double sum = 0;
      for (int m = j - dPeriod + 1; m <= j; m++) {
        sum += kNonNull[m];
      }
      d[kIdx[j]] = sum / dPeriod;
    }

    return StochasticResult(k: k, d: d);
  }

  // ── Williams %R ──────────────────────────────────────────────────────────
  static List<double?> williamsR(List<TaBar> points, {int period = 14}) {
    final n = points.length;
    final result = List<double?>.filled(n, null);
    final hiN = _rollingExtreme(_highs(points), period, max: true);
    final loN = _rollingExtreme(_lows(points), period, max: false);
    for (int i = period - 1; i < n; i++) {
      final hi = hiN[i]!, lo = loN[i]!;
      result[i] = hi == lo ? -50.0 : (hi - points[i].close) / (hi - lo) * -100;
    }
    return result;
  }

  // ── Ichimoku Cloud ───────────────────────────────────────────────────────
  static IchimokuResult ichimoku(
    List<TaBar> points, {
    int tenkanPeriod = 9,
    int kijunPeriod = 26,
    int senkouBPeriod = 52,
  }) {
    final n = points.length;
    final highs = _highs(points);
    final lows = _lows(points);

    List<double?> midpoint(int period) {
      final hi = _rollingExtreme(highs, period, max: true);
      final lo = _rollingExtreme(lows, period, max: false);
      return [for (int i = 0; i < n; i++) hi[i] == null ? null : (hi[i]! + lo[i]!) / 2];
    }

    final tenkan = midpoint(tenkanPeriod);
    final kijun = midpoint(kijunPeriod);
    final senkouBRaw = midpoint(senkouBPeriod);

    // Leading spans are displaced kijunPeriod bars into the future, the
    // standard way every charting platform draws the cloud — so the cloud
    // under today's candle is the one computed kijunPeriod bars ago. These
    // used to be drawn undisplaced (today's values under today's candle),
    // which put the whole cloud 26 bars out of place versus other charts
    // and skewed every "price above/below cloud" read and signal. The part
    // of the cloud that projects past the last candle isn't drawn.
    final shift = kijunPeriod;
    final senkouA = List<double?>.filled(n, null);
    final senkouB = List<double?>.filled(n, null);
    for (int i = shift; i < n; i++) {
      final t = tenkan[i - shift], kj = kijun[i - shift];
      if (t != null && kj != null) senkouA[i] = (t + kj) / 2;
      senkouB[i] = senkouBRaw[i - shift];
    }

    // Chikou = close shifted -kijunPeriod (lagging, plot current close at past position)
    final chikou = List<double?>.filled(n, null);
    for (int i = 0; i < n - kijunPeriod; i++) {
      chikou[i] = points[i + kijunPeriod].close;
    }

    return IchimokuResult(tenkan: tenkan, kijun: kijun, senkouA: senkouA, senkouB: senkouB, chikou: chikou);
  }

  // ── Volume Profile ───────────────────────────────────────────────────────
  // Distributes each candle's volume uniformly across its high-low range.
  // Returns buckets sorted from lowest price to highest.
  static VolumeProfileResult volumeProfile(List<TaBar> points, {int buckets = 24}) {
    if (points.isEmpty) {
      return VolumeProfileResult(buckets: [], pocPrice: 0, pocVolume: 0);
    }

    double lo = points.first.low ?? points.first.close;
    double hi = points.first.high ?? points.first.close;
    for (final p in points) {
      final low = p.low ?? p.close;
      final high = p.high ?? p.close;
      if (low < lo) lo = low;
      if (high > hi) hi = high;
    }
    final range = hi - lo;
    if (range <= 0) {
      return VolumeProfileResult(
        buckets: [VolumeBucket(priceLow: lo, priceHigh: hi, volume: points.fold(0.0, (s, p) => s + (p.volume ?? 0)))],
        pocPrice: (lo + hi) / 2,
        pocVolume: points.fold(0.0, (s, p) => s + (p.volume ?? 0)),
      );
    }

    final vols = List<double>.filled(buckets, 0);
    final bucketSize = range / buckets;

    for (final p in points) {
      final vol = p.volume ?? 0;
      if (vol <= 0) continue;
      final cLow = (p.low ?? p.close);
      final cHigh = (p.high ?? p.close);
      // Find which buckets this candle's range overlaps
      final startBucket = ((cLow - lo) / bucketSize).floor().clamp(0, buckets - 1);
      final endBucket = ((cHigh - lo) / bucketSize).floor().clamp(0, buckets - 1);
      final span = endBucket - startBucket + 1;
      final volPerBucket = vol / span;
      for (int b = startBucket; b <= endBucket; b++) {
        vols[b] += volPerBucket;
      }
    }

    double pocVol = 0;
    int pocIdx = 0;
    for (int i = 0; i < buckets; i++) {
      if (vols[i] > pocVol) {
        pocVol = vols[i];
        pocIdx = i;
      }
    }

    final result = List.generate(
      buckets,
      (i) => VolumeBucket(priceLow: lo + i * bucketSize, priceHigh: lo + (i + 1) * bucketSize, volume: vols[i]),
    );

    return VolumeProfileResult(buckets: result, pocPrice: lo + (pocIdx + 0.5) * bucketSize, pocVolume: pocVol);
  }

  // ── Fibonacci Retracement ────────────────────────────────────────────────
  // Auto-detects swing high/low from the visible points, then returns
  // price levels at standard Fibonacci ratios (0, 23.6, 38.2, 50, 61.8, 78.6, 100).
  // Returns null for degenerate cases (empty, flat range) to prevent visual clutter.
  static FibonacciResult? fibonacci(List<TaBar> points) {
    if (points.isEmpty) return null;

    // Clamp prices to reasonable range [0, 1e9] to handle corrupted API data
    double high = (points.first.high ?? points.first.close).clamp(0.0, 1e9);
    double low = (points.first.low ?? points.first.close).clamp(0.0, 1e9);

    for (final p in points) {
      final h = (p.high ?? p.close).clamp(0.0, 1e9);
      final l = (p.low ?? p.close).clamp(0.0, 1e9);
      if (h > high) high = h;
      if (l < low) low = l;
    }

    const ratios = [0.0, 0.236, 0.382, 0.500, 0.618, 0.786, 1.0];
    final range = high - low;

    // Degenerate case: flat range (single candle or all prices identical)
    // Return null to skip rendering rather than showing 7 stacked lines
    if (range < 0.01) return null;

    final levels = ratios.map((r) => FibonacciLevel(ratio: r, price: high - r * range)).toList();
    return FibonacciResult(high: high, low: low, levels: levels);
  }

  // ── Linear Regression Channel ("parallel channel") ────────────────────────
  // Least-squares trendline through closing prices, plus two lines parallel
  // to it offset by k standard deviations of the residuals — an
  // algorithmically-fitted stand-in for hand-drawn parallel trend channels.
  // Recomputed over whatever candles are currently visible (like Fibonacci/
  // Pivot Points), so it re-fits automatically as the user pans/zooms.
  static RegressionChannelResult? regressionChannel(List<TaBar> points, {double k = 2.0}) {
    final n = points.length;
    if (n < 20) return null; // too few bars for a meaningful fit

    final closes = points.map((p) => p.close).toList();
    final xMean = (n - 1) / 2.0;
    final yMean = closes.reduce((a, b) => a + b) / n;

    double num = 0, den = 0;
    for (int i = 0; i < n; i++) {
      final dx = i - xMean;
      num += dx * (closes[i] - yMean);
      den += dx * dx;
    }
    if (den == 0) return null; // degenerate (shouldn't happen for n >= 20)

    final slope = num / den;
    final intercept = yMean - slope * xMean;

    final mid = List<double?>.generate(n, (i) => slope * i + intercept);

    double sumSqResid = 0;
    for (int i = 0; i < n; i++) {
      final resid = closes[i] - mid[i]!;
      sumSqResid += resid * resid;
    }
    final stdDev = sqrt(sumSqResid / n);
    if (stdDev < 0.001) return null; // flat/degenerate series

    final upper = List<double?>.generate(n, (i) => mid[i]! + k * stdDev);
    final lower = List<double?>.generate(n, (i) => mid[i]! - k * stdDev);
    return RegressionChannelResult(mid: mid, upper: upper, lower: lower);
  }

  // ── Auto Support/Resistance ────────────────────────────────────────────────
  // Finds swing highs/lows (the same fractal pivots used for RSI divergence),
  // then greedily clusters their prices — points within ~2% of a cluster's
  // running average join it — so a level that got touched multiple times
  // (not just any single swing point) surfaces as a real support/resistance
  // zone. Only clusters with 2+ touches count; returns the strongest ones,
  // strongest first. Recomputed over whatever candles are currently visible,
  // like Fibonacci/Pivot Points/Regression Channel.
  static List<SupportResistanceLevel>? supportResistance(List<TaBar> points, {int wing = 3, int maxLevels = 4}) {
    if (points.length < wing * 2 + 10) return null;
    final closes = points.map((p) => p.close).toList();
    final pivotIdx = [...pivotHighIndices(closes, wing: wing), ...pivotLowIndices(closes, wing: wing)];
    if (pivotIdx.length < 2) return null;

    final prices = pivotIdx.map((i) => closes[i]).toList()..sort();
    final priceRange = prices.last - prices.first;
    if (priceRange <= 0) return null;
    final tolerance = priceRange * 0.02;

    final clusters = <List<double>>[];
    for (final p in prices) {
      if (clusters.isNotEmpty) {
        final cluster = clusters.last;
        final clusterAvg = cluster.reduce((a, b) => a + b) / cluster.length;
        if ((p - clusterAvg).abs() <= tolerance) {
          cluster.add(p);
          continue;
        }
      }
      clusters.add([p]);
    }

    final levels =
        clusters
            .where((c) => c.length >= 2)
            .map((c) => SupportResistanceLevel(price: c.reduce((a, b) => a + b) / c.length, strength: c.length))
            .toList()
          ..sort((a, b) => b.strength.compareTo(a.strength));

    if (levels.isEmpty) return null;
    return levels.take(maxLevels).toList();
  }

  // ── Chart Pattern Recognition ──────────────────────────────────────────────
  // Looks for classic reversal shapes using the same swing-pivot fractals as
  // everything else here — no ML, just geometric checks on real pivot prices
  // (peers within tolerance, a confirming trough/peak between them). Scans
  // every pivot pair/triple (most recent first, not just the very last one)
  // so a real formation a few swings back still surfaces. Only ever reports
  // patterns it can actually locate; never a guess or a price target.
  static List<ChartPatternMatch> detectPatterns(List<TaBar> points, {int wing = 3}) {
    if (points.length < wing * 2 + 12) return [];
    final closes = points.map((p) => p.close).toList();
    final highs = pivotHighIndices(closes, wing: wing);
    final lows = pivotLowIndices(closes, wing: wing);
    final matches = <ChartPatternMatch>[];

    // ── Double Top / Double Bottom: scan every pivot pair of the same kind
    // (most recent first), first one within tolerance with a confirming
    // opposite-kind pivot between them wins.
    ChartPatternMatch? scanDouble({
      required List<int> pivots,
      required List<int> confirmPivots,
      required bool top, // true = looking for a double top (peaks)
    }) {
      for (int a = pivots.length - 1; a >= 1; a--) {
        for (int b = a - 1; b >= 0; b--) {
          final i1 = pivots[b], i2 = pivots[a];
          final p1 = closes[i1], p2 = closes[i2];
          final avg = (p1 + p2) / 2;
          if (avg <= 0 || (p1 - p2).abs() / avg > 0.035) continue;
          final between = confirmPivots.where((i) => i > i1 && i < i2);
          if (between.isEmpty) continue;
          final t = top
              ? between.reduce((x, y) => closes[x] < closes[y] ? x : y)
              : between.reduce((x, y) => closes[x] > closes[y] ? x : y);
          final confirmDepth = top ? (avg - closes[t]) / avg : (closes[t] - avg) / avg;
          if (confirmDepth < 0.025) continue;
          return ChartPatternMatch(
            type: top ? ChartPatternType.doubleTop : ChartPatternType.doubleBottom,
            keyIndices: [i1, t, i2],
            keyPrices: [p1, closes[t], p2],
          );
        }
      }
      return null;
    }

    final doubleTop = scanDouble(pivots: highs, confirmPivots: lows, top: true);
    if (doubleTop != null) matches.add(doubleTop);
    final doubleBottom = scanDouble(pivots: lows, confirmPivots: highs, top: false);
    if (doubleBottom != null) matches.add(doubleBottom);

    // ── Head & Shoulders / Inverse H&S: scan every consecutive pivot triple
    // (most recent first) — middle one clearly past the outer two, which
    // are themselves roughly level, each pair separated by a confirming
    // opposite-kind pivot.
    ChartPatternMatch? scanHeadShoulders({
      required List<int> pivots,
      required List<int> confirmPivots,
      required bool head, // true = head is a high (bearish H&S)
    }) {
      for (int i = pivots.length - 1; i >= 2; i--) {
        final l = pivots[i - 2], h = pivots[i - 1], r = pivots[i];
        final pl = closes[l], ph = closes[h], pr = closes[r];
        final shoulderAvg = (pl + pr) / 2;
        if (shoulderAvg <= 0) continue;
        final headBeatsShoulders = head ? (ph > pl && ph > pr) : (ph < pl && ph < pr);
        if (!headBeatsShoulders) continue;
        if ((pl - pr).abs() / shoulderAvg > 0.08) continue;
        final headProminence = head ? (ph - shoulderAvg) / shoulderAvg : (shoulderAvg - ph) / shoulderAvg;
        if (headProminence < 0.025) continue;
        final confirm1 = confirmPivots.where((x) => x > l && x < h);
        final confirm2 = confirmPivots.where((x) => x > h && x < r);
        if (confirm1.isEmpty || confirm2.isEmpty) continue;
        final t1 = head
            ? confirm1.reduce((x, y) => closes[x] < closes[y] ? x : y)
            : confirm1.reduce((x, y) => closes[x] > closes[y] ? x : y);
        final t2 = head
            ? confirm2.reduce((x, y) => closes[x] < closes[y] ? x : y)
            : confirm2.reduce((x, y) => closes[x] > closes[y] ? x : y);
        return ChartPatternMatch(
          type: head ? ChartPatternType.headAndShoulders : ChartPatternType.inverseHeadAndShoulders,
          keyIndices: [l, t1, h, t2, r],
          keyPrices: [pl, closes[t1], ph, closes[t2], pr],
        );
      }
      return null;
    }

    final headShoulders = scanHeadShoulders(pivots: highs, confirmPivots: lows, head: true);
    if (headShoulders != null) matches.add(headShoulders);
    final inverseHeadShoulders = scanHeadShoulders(pivots: lows, confirmPivots: highs, head: false);
    if (inverseHeadShoulders != null) matches.add(inverseHeadShoulders);

    matches.addAll(_detectConvergingPatterns(closes, highs, lows));
    final flag = _detectFlag(closes, highs, lows, bull: true) ?? _detectFlag(closes, highs, lows, bull: false);
    if (flag != null) matches.add(flag);
    final cup = _detectCupAndHandle(closes, highs);
    if (cup != null) matches.add(cup);

    return matches;
  }

  // Patterns only count if they're recent — an old triangle that already
  // resolved months ago isn't something to act on now.
  static const _patternLookback = 120;

  // ── Triangles & wedges: the latest two swing highs vs the latest two swing
  // lows. Each trendline's slope is measured as % of price per bar; "flat"
  // is under 0.08%/bar. Lines must converge (narrower at the end).
  static List<ChartPatternMatch> _detectConvergingPatterns(List<double> closes, List<int> highs, List<int> lows) {
    final start = closes.length - _patternLookback;
    final h = highs.where((i) => i >= start).toList();
    final l = lows.where((i) => i >= start).toList();
    if (h.length < 2 || l.length < 2) return const [];
    final h1 = h[h.length - 2], h2 = h.last;
    final l1 = l[l.length - 2], l2 = l.last;
    final first = math.min(h1, l1), last = math.max(h2, l2);
    if (last - first < 15) return const []; // too short to be a pattern
    // Highs and lows must interleave (H L H L or L H L H), not cluster.
    if (!(h1 < l2 && l1 < h2)) return const [];
    final avg = (closes[h1] + closes[h2] + closes[l1] + closes[l2]) / 4;
    if (avg <= 0) return const [];
    final sh = (closes[h2] - closes[h1]) / (h2 - h1) / avg;
    final sl = (closes[l2] - closes[l1]) / (l2 - l1) / avg;
    final widthStart = closes[h1] - closes[l1];
    final widthEnd = closes[h2] - closes[l2];
    if (widthStart <= 0 || widthEnd <= 0 || widthEnd >= widthStart) {
      return const [];
    }
    const flat = 0.0008;
    ChartPatternType? type;
    if (sh.abs() < flat && sl > flat) {
      type = ChartPatternType.ascendingTriangle;
    } else if (sl.abs() < flat && sh < -flat) {
      type = ChartPatternType.descendingTriangle;
    } else if (sh < -flat && sl > flat) {
      type = ChartPatternType.symmetricalTriangle;
    } else if (sh > flat && sl > flat && sl > sh) {
      type = ChartPatternType.risingWedge;
    } else if (sh < -flat && sl < -flat && sh < sl) {
      type = ChartPatternType.fallingWedge;
    }
    if (type == null) return const [];
    final pts = [h1, h2, l1, l2]..sort();
    return [
      ChartPatternMatch(type: type, keyIndices: pts, keyPrices: [for (final i in pts) closes[i]]),
    ];
  }

  // ── Flag: a sharp pole (≥8% within 15 bars) into a swing pivot, then a
  // tight 5–25 bar pullback that drifts against the pole and gives back
  // less than half of it, not yet broken out.
  static ChartPatternMatch? _detectFlag(List<double> closes, List<int> highs, List<int> lows, {required bool bull}) {
    final n = closes.length;
    final pivots = bull ? highs : lows;
    for (var k = pivots.length - 1; k >= 0; k--) {
      final top = pivots[k];
      final barsAfter = n - 1 - top;
      if (barsAfter < 5) continue;
      if (barsAfter > 25) break;
      final poleFrom = math.max(0, top - 15);
      var base = poleFrom;
      for (var j = poleFrom; j <= top; j++) {
        if (bull ? closes[j] < closes[base] : closes[j] > closes[base]) base = j;
      }
      if (closes[base] <= 0) continue;
      final pole = bull ? closes[top] / closes[base] - 1 : 1 - closes[top] / closes[base];
      if (pole < 0.08 || top - base < 3) continue;
      final after = closes.sublist(top + 1);
      final poleSize = (closes[top] - closes[base]).abs();
      final extreme = bull ? after.reduce(math.min) : after.reduce(math.max);
      final retrace = (closes[top] - extreme).abs() / poleSize;
      final last = closes.last;
      final drifted = bull ? last < closes[top] : last > closes[top];
      if (retrace > 0.5 || retrace < 0.1 || !drifted) continue;
      final extremeIdx = top + 1 + after.indexOf(extreme);
      return ChartPatternMatch(
        type: bull ? ChartPatternType.bullFlag : ChartPatternType.bearFlag,
        keyIndices: [base, top, extremeIdx, n - 1],
        keyPrices: [closes[base], closes[top], extreme, last],
      );
    }
    return null;
  }

  // ── Cup & handle: a rounded 12–35% dip between two roughly equal rims
  // (within 5%), then a shallow handle pullback (≤ a third of the cup).
  static ChartPatternMatch? _detectCupAndHandle(List<double> closes, List<int> highs) {
    final n = closes.length;
    final start = n - _patternLookback;
    final rims = highs.where((i) => i >= start).toList();
    for (var b = rims.length - 1; b >= 1; b--) {
      final right = rims[b];
      if (n - 1 - right < 3) continue; // needs room for a handle
      for (var a = b - 1; a >= 0; a--) {
        final left = rims[a];
        if (right - left < 20) continue;
        final lr = closes[left], rr = closes[right];
        if (lr <= 0 || (lr - rr).abs() / lr > 0.05) continue;
        var bottom = left;
        for (var j = left; j <= right; j++) {
          if (closes[j] < closes[bottom]) bottom = j;
        }
        final depth = 1 - closes[bottom] / lr;
        if (depth < 0.12 || depth > 0.35) continue;
        // Roughly U-shaped: bottom near the middle, not a V at one edge.
        final pos = (bottom - left) / (right - left);
        if (pos < 0.25 || pos > 0.75) continue;
        final handle = closes.sublist(right + 1);
        final handleLow = handle.reduce(math.min);
        final handleDepth = (rr - handleLow) / (rr - closes[bottom]);
        if (handleDepth <= 0 || handleDepth > 1 / 3) continue;
        final handleIdx = right + 1 + handle.indexOf(handleLow);
        return ChartPatternMatch(
          type: ChartPatternType.cupAndHandle,
          keyIndices: [left, bottom, right, handleIdx],
          keyPrices: [lr, closes[bottom], rr, handleLow],
        );
      }
    }
    return null;
  }

  // ── ATR (Average True Range) ──────────────────────────────────────────────
  // Measures volatility using Wilder's smoothing (14-period default).
  // Returns null if insufficient data.
  static AtrResult? atr(List<TaBar> points, {int period = 14}) {
    if (points.length < period + 1) return null;

    final trueRanges = <double>[];
    for (int i = 1; i < points.length; i++) {
      final high = points[i].high ?? points[i].close;
      final low = points[i].low ?? points[i].close;
      final prevClose = points[i - 1].close;

      final tr = max(high - low, max((high - prevClose).abs(), (low - prevClose).abs()));
      trueRanges.add(tr);
    }

    // Wilder's smoothing: first ATR is SMA, then: ATR = (prev * (n-1) + TR) / n
    final values = <double?>[];
    double atrVal = trueRanges.take(period).reduce((a, b) => a + b) / period;
    values.add(atrVal);

    for (int i = period; i < trueRanges.length; i++) {
      atrVal = (atrVal * (period - 1) + trueRanges[i]) / period;
      values.add(atrVal);
    }

    // Align length exactly with input points.
    // There are (points.length - 1) true-range values, so the first ATR value
    // corresponds to point index [period], requiring exactly [period] null pads.
    final result = <double?>[...List<double?>.filled(period, null), ...values];
    return AtrResult(values: result);
  }

  // ── ADX (Average Directional Index) ───────────────────────────────────────
  // Measures trend strength (0-100). Above 25 = strong trend, below 20 = weak.
  // Returns ADX, +DI, -DI lines using Wilder's smoothing (14-period default).
  static AdxResult? adx(List<TaBar> points, {int period = 14}) {
    if (points.length < period * 2) return null;

    final plusDM = <double>[];
    final minusDM = <double>[];
    final tr = <double>[];

    for (int i = 1; i < points.length; i++) {
      final high = points[i].high ?? points[i].close;
      final low = points[i].low ?? points[i].close;
      final prevHigh = points[i - 1].high ?? points[i - 1].close;
      final prevLow = points[i - 1].low ?? points[i - 1].close;
      final prevClose = points[i - 1].close;

      final upMove = high - prevHigh;
      final downMove = prevLow - low;

      plusDM.add(upMove > downMove && upMove > 0 ? upMove : 0);
      minusDM.add(downMove > upMove && downMove > 0 ? downMove : 0);

      tr.add(max(high - low, max((high - prevClose).abs(), (low - prevClose).abs())));
    }

    // Wilder's smoothing for +DM, -DM, TR. The first smoothed values are the
    // plain sums of the first `period` moves (bars 1..period), which already
    // give the first +DI/-DI at bar `period` — the original only started
    // emitting after one more update, a bar late versus the standard.
    double smoothPlusDM = plusDM.take(period).reduce((a, b) => a + b);
    double smoothMinusDM = minusDM.take(period).reduce((a, b) => a + b);
    double smoothTR = tr.take(period).reduce((a, b) => a + b);

    final plusDIList = <double?>[];
    final minusDIList = <double?>[];
    final dxList = <double>[];

    void emit() {
      final pDI = smoothTR > 0 ? (smoothPlusDM / smoothTR) * 100 : 0.0;
      final mDI = smoothTR > 0 ? (smoothMinusDM / smoothTR) * 100 : 0.0;
      plusDIList.add(pDI);
      minusDIList.add(mDI);
      final diSum = pDI + mDI;
      dxList.add(diSum > 0 ? ((pDI - mDI).abs() / diSum) * 100 : 0.0);
    }

    emit();
    for (int i = period; i < plusDM.length; i++) {
      smoothPlusDM = smoothPlusDM - smoothPlusDM / period + plusDM[i];
      smoothMinusDM = smoothMinusDM - smoothMinusDM / period + minusDM[i];
      smoothTR = smoothTR - smoothTR / period + tr[i];
      emit();
    }

    // ADX: SMA of the first `period` DX values, then Wilder's smoothing.
    if (dxList.length < period) return null;

    double adxVal = dxList.take(period).reduce((a, b) => a + b) / period;
    final adxList = <double?>[adxVal];

    for (int i = period; i < dxList.length; i++) {
      adxVal = (adxVal * (period - 1) + dxList[i]) / period;
      adxList.add(adxVal);
    }

    // Align length exactly with input points. DI/DX start at bar [period];
    // the first ADX averages `period` DX values, so it lands at bar
    // [period * 2 - 1] (bar 28 of a 14-period ADX, as on other platforms).
    final resultADX = <double?>[...List<double?>.filled(period * 2 - 1, null), ...adxList];
    final resultPlusDI = <double?>[...List<double?>.filled(period, null), ...plusDIList];
    final resultMinusDI = <double?>[...List<double?>.filled(period, null), ...minusDIList];

    return AdxResult(adx: resultADX, plusDI: resultPlusDI, minusDI: resultMinusDI);
  }

  // ── OBV (On-Balance Volume) ───────────────────────────────────────────────
  // Cumulative volume indicator: adds volume on up days, subtracts on down days.
  static ObvResult obv(List<TaBar> points) {
    if (points.isEmpty) return ObvResult(values: []);

    final values = <double?>[];
    double cumulative = 0;

    for (int i = 0; i < points.length; i++) {
      final vol = points[i].volume ?? 0;
      if (i == 0) {
        cumulative = vol.toDouble();
      } else {
        final prev = points[i - 1].close;
        final curr = points[i].close;
        if (curr > prev) {
          cumulative += vol;
        } else if (curr < prev) {
          cumulative -= vol;
        }
        // If curr == prev, OBV stays same (don't add/subtract)
      }
      values.add(cumulative);
    }

    return ObvResult(values: values);
  }

  // ── Pivot Points (Standard) ───────────────────────────────────────────────
  // Support/resistance from the last *completed* session's high/low/close.
  // Using the still-forming candle (today's, during market hours) made the
  // levels drift all session long. Intraday candles are rolled up into
  // their day first, so a 5-minute chart gets daily pivots rather than
  // pivots of a single 5-minute bar.
  static PivotPointsResult? pivotPoints(List<TaBar> points, {DateTime? now}) {
    if (points.isEmpty) return null;
    final clock = now ?? DateTime.now();
    bool sameDay(DateTime a, DateTime b) => a.year == b.year && a.month == b.month && a.day == b.day;

    List<TaBar> session;
    final intraday = points.length >= 2 && sameDay(points[points.length - 1].date, points[points.length - 2].date);
    if (intraday) {
      var day = points.last.date;
      if (sameDay(day, clock)) {
        // Today is still trading — use the most recent earlier day, if any.
        // A loop, not lastWhere(orElse:): [points] may be a list of a
        // TaBar subtype, which rejects an orElse typed for TaBar.
        for (var i = points.length - 1; i >= 0; i--) {
          if (!sameDay(points[i].date, clock)) {
            day = points[i].date;
            break;
          }
        }
      }
      session = [
        for (final p in points)
          if (sameDay(p.date, day)) p,
      ];
    } else {
      // A daily/weekly/monthly candle is still forming while "now" is inside
      // its period (judged by the spacing to the previous candle).
      final inProgress =
          points.length >= 2 &&
          clock.isBefore(points.last.date.add(points.last.date.difference(points[points.length - 2].date)));
      session = [inProgress ? points[points.length - 2] : points.last];
    }

    final high = session.map((p) => p.high ?? p.close).reduce(max);
    final low = session.map((p) => p.low ?? p.close).reduce(min);
    final close = session.last.close;

    final pivot = (high + low + close) / 3;
    final r1 = 2 * pivot - low;
    final s1 = 2 * pivot - high;
    final r2 = pivot + (high - low);
    final s2 = pivot - (high - low);
    final r3 = high + 2 * (pivot - low);
    final s3 = low - 2 * (high - pivot);

    return PivotPointsResult(pivot: pivot, r1: r1, r2: r2, r3: r3, s1: s1, s2: s2, s3: s3);
  }

  // ── CCI (Commodity Channel Index, period=20) ──────────────────────────────
  // CCI = (Typical Price − SMA(TP)) / (0.015 × Mean Deviation)
  static List<double?> cci(List<TaBar> points, {int period = 20}) {
    final n = points.length;
    final result = List<double?>.filled(n, null);
    if (n < period) return result;

    final tp = points.map((p) => ((p.high ?? p.close) + (p.low ?? p.close) + p.close) / 3).toList();

    // The rolling SMA is a plain sliding-window sum (O(1) per step). Mean
    // absolute deviation has no equivalent shortcut — it's a function of
    // every value's distance from *that window's* mean, which shifts on
    // every step — so it still needs one pass over the window each time.
    // The win here over the original is skipping the two `tp.sublist(...)`
    // allocations (one per SMA, one per deviation) and their `.map`/
    // `.reduce` closures on every single step; the window itself is small
    // and fixed (period=20), and this whole series is now only computed
    // once per data change (see the classic indicator panels), not
    // on every pan/zoom frame, so a further true-O(n) rewrite (which would
    // need an order-statistics structure to track a moving mean deviation)
    // isn't worth the added complexity.
    double windowSum = 0;
    for (int j = 0; j < period; j++) {
      windowSum += tp[j];
    }
    for (int i = period - 1; i < n; i++) {
      if (i > period - 1) windowSum += tp[i] - tp[i - period];
      final sma = windowSum / period;
      double devSum = 0;
      for (int j = i - period + 1; j <= i; j++) {
        devSum += (tp[j] - sma).abs();
      }
      final meanDev = devSum / period;
      result[i] = meanDev == 0 ? 0 : (tp[i] - sma) / (0.015 * meanDev);
    }
    return result;
  }

  // ── MFI (Money Flow Index, period=14) ─────────────────────────────────────
  // Volume-weighted RSI: splits each bar's typical-price × volume into
  // positive/negative money flow depending on whether typical price rose or
  // fell versus the prior bar, then ratios them the same way RSI ratios
  // gains/losses. Above 80 = overbought, below 20 = oversold.
  static List<double?> mfi(List<TaBar> points, {int period = 14}) {
    final n = points.length;
    final result = List<double?>.filled(n, null);
    if (n < period + 1) return result;

    final tp = points.map((p) => ((p.high ?? p.close) + (p.low ?? p.close) + p.close) / 3).toList();
    // Whether bar j's raw money flow counts as positive or negative only
    // depends on j itself (tp[j] vs tp[j-1]), never on where the rolling
    // window currently sits — so it's precomputed once per bar instead of
    // reclassified on every window that happens to contain it. That turns
    // the rolling posMf/negMf sums below into an O(1)-per-step sliding
    // window (add the entering bar, drop the leaving one) rather than the
    // O(period) rescan the original nested loop did for every i.
    final posFlow = List<double>.filled(n, 0);
    final negFlow = List<double>.filled(n, 0);
    for (int j = 1; j < n; j++) {
      final rawMf = tp[j] * (points[j].volume ?? 0);
      if (tp[j] > tp[j - 1]) {
        posFlow[j] = rawMf;
      } else if (tp[j] < tp[j - 1]) {
        negFlow[j] = rawMf;
      }
    }

    double posMf = 0, negMf = 0;
    for (int j = 1; j <= period; j++) {
      posMf += posFlow[j];
      negMf += negFlow[j];
    }
    result[period] = _rsiValue(posMf, negMf);
    for (int i = period + 1; i < n; i++) {
      posMf += posFlow[i] - posFlow[i - period];
      negMf += negFlow[i] - negFlow[i - period];
      result[i] = _rsiValue(posMf, negMf);
    }
    return result;
  }

  // ── Chaikin Money Flow (period=20) ────────────────────────────────────────
  // CMF = sum(Money Flow Volume, period) / sum(Volume, period), where each
  // bar's Money Flow Multiplier ((C−L)−(H−C))/(H−L) captures whether it
  // closed nearer its high (buying pressure) or low (selling pressure).
  // Oscillates roughly ±1; sustained readings above/below 0 confirm
  // accumulation/distribution rather than a single-bar reading.
  static List<double?> chaikinMoneyFlow(List<TaBar> points, {int period = 20}) {
    final n = points.length;
    final result = List<double?>.filled(n, null);
    if (n < period) return result;

    final mfv = List<double>.generate(n, (i) {
      final h = points[i].high ?? points[i].close;
      final l = points[i].low ?? points[i].close;
      final c = points[i].close;
      if (h == l) return 0.0;
      final mfm = ((c - l) - (h - c)) / (h - l);
      return mfm * (points[i].volume ?? 0);
    });

    double sumMfv = 0, sumVol = 0;
    for (int i = 0; i < n; i++) {
      sumMfv += mfv[i];
      sumVol += points[i].volume ?? 0;
      if (i >= period) {
        sumMfv -= mfv[i - period];
        sumVol -= points[i - period].volume ?? 0;
      }
      if (i >= period - 1) result[i] = sumVol > 0 ? sumMfv / sumVol : 0.0;
    }
    return result;
  }

  // ── Keltner Channel (EMA middle ± multiplier × ATR) ───────────────────────
  static KeltnerChannelResult keltnerChannel(
    List<TaBar> points, {
    int emaPeriod = 20,
    int atrPeriod = 10,
    double multiplier = 2.0,
  }) {
    final n = points.length;
    final middle = _ema(points.map((p) => p.close).toList(), emaPeriod);
    final atrResult = atr(points, period: atrPeriod);
    final upper = List<double?>.filled(n, null);
    final lower = List<double?>.filled(n, null);
    if (atrResult != null) {
      for (int i = 0; i < n; i++) {
        final m = middle[i];
        final a = i < atrResult.values.length ? atrResult.values[i] : null;
        if (m != null && a != null) {
          upper[i] = m + multiplier * a;
          lower[i] = m - multiplier * a;
        }
      }
    }
    return KeltnerChannelResult(middle: middle, upper: upper, lower: lower);
  }

  // ── Donchian Channel (highest high / lowest low over the period) ─────────
  static DonchianChannelResult donchianChannel(List<TaBar> points, {int period = 20}) {
    final n = points.length;
    final upper = List<double?>.filled(n, null);
    final lower = List<double?>.filled(n, null);
    final middle = List<double?>.filled(n, null);
    final hiN = _rollingExtreme(_highs(points), period, max: true);
    final loN = _rollingExtreme(_lows(points), period, max: false);
    for (int i = period - 1; i < n; i++) {
      upper[i] = hiN[i];
      lower[i] = loN[i];
      middle[i] = (hiN[i]! + loN[i]!) / 2;
    }
    return DonchianChannelResult(middle: middle, upper: upper, lower: lower);
  }

  // ── Parabolic SAR ─────────────────────────────────────────────────────────
  // Returns {sar, isAbove} per candle (sar above price = bearish dots).
  //
  // A direct port of TradingView's reference `ta.sar` (Pine): advance the
  // SAR, check for a reversal against the *current* bar first, and only
  // then clamp it to the prior two bars' lows/highs. A reversal restarts
  // at the more extreme of the old extreme point and the current bar. The
  // earlier version clamped before checking for a reversal and restarted
  // at the extreme point alone, which drifted from TradingView's values
  // after some reversals (seen on AAPL, up to ~4%).
  static List<ParabolicSarPoint?> parabolicSar(
    List<TaBar> points, {
    double initialAf = 0.02,
    double stepAf = 0.02,
    double maxAf = 0.2,
  }) {
    final n = points.length;
    final result = List<ParabolicSarPoint?>.filled(n, null);
    if (n < 2) return result;
    double hi(int i) => points[i].high ?? points[i].close;
    double lo(int i) => points[i].low ?? points[i].close;

    var isBelow = points[1].close > points[0].close; // SAR below = uptrend
    var extreme = isBelow ? hi(1) : lo(1);
    var sar = isBelow ? lo(0) : hi(0);
    var af = initialAf;
    for (int i = 1; i < n; i++) {
      var firstTrendBar = i == 1;
      sar = sar + af * (extreme - sar);
      if (isBelow) {
        if (sar > lo(i)) {
          firstTrendBar = true;
          isBelow = false;
          sar = max(hi(i), extreme);
          extreme = lo(i);
          af = initialAf;
        }
      } else if (sar < hi(i)) {
        firstTrendBar = true;
        isBelow = true;
        sar = min(lo(i), extreme);
        extreme = hi(i);
        af = initialAf;
      }
      if (!firstTrendBar) {
        if (isBelow && hi(i) > extreme) {
          extreme = hi(i);
          af = min(af + stepAf, maxAf);
        } else if (!isBelow && lo(i) < extreme) {
          extreme = lo(i);
          af = min(af + stepAf, maxAf);
        }
      }
      if (isBelow) {
        sar = min(sar, lo(i - 1));
        if (i > 1) sar = min(sar, lo(i - 2));
      } else {
        sar = max(sar, hi(i - 1));
        if (i > 1) sar = max(sar, hi(i - 2));
      }
      result[i] = ParabolicSarPoint(sar: sar, isAbove: !isBelow);
    }
    return result;
  }

  // ── VWAP (rolling 20-period, works on any timeframe with volume) ──────────
  // Standard formula: cumulative(price × volume) / cumulative(volume)
  static List<double?> vwap(List<TaBar> points, {int period = 20}) {
    final result = List<double?>.filled(points.length, null);
    if (points.length < period) return result;

    double sumPV = 0, sumV = 0;
    double pv(int j) {
      final tp = ((points[j].high ?? points[j].close) + (points[j].low ?? points[j].close) + points[j].close) / 3;
      return tp * (points[j].volume ?? 0);
    }

    for (int i = 0; i < points.length; i++) {
      sumPV += pv(i);
      sumV += points[i].volume ?? 0;
      if (i >= period) {
        sumPV -= pv(i - period);
        sumV -= points[i - period].volume ?? 0;
      }
      if (i >= period - 1) result[i] = sumV > 0 ? sumPV / sumV : null;
    }
    return result;
  }

  // ── ZigZag (swings of at least [deviation] percent) ─────────────────────
  // Follows the extreme (high in an up leg, low in a down leg) and confirms
  // it as a swing once price reverses from it by [deviation] percent. Uses
  // highs/lows when present, else closes.
  static ZigZagResult zigzag(List<TaBar> points, {double deviation = 5}) {
    final n = points.length;
    final line = List<double?>.filled(n, null);
    final pivots = List<double?>.filled(n, null);
    if (n < 2) return ZigZagResult(line: line, pivots: pivots);
    final d = deviation / 100;
    double hi(int i) => points[i].high ?? points[i].close;
    double lo(int i) => points[i].low ?? points[i].close;

    final swings = <(int, double)>[];
    var dir = 0; // 1 = up leg (tracking a high), -1 = down leg
    var hiIdx = 0, loIdx = 0;
    var extIdx = 0;
    var ext = points[0].close;
    for (int i = 1; i < n; i++) {
      if (dir == 0) {
        if (hi(i) > hi(hiIdx)) hiIdx = i;
        if (lo(i) < lo(loIdx)) loIdx = i;
        if (hi(i) >= lo(loIdx) * (1 + d)) {
          swings.add((loIdx, lo(loIdx)));
          dir = 1;
          extIdx = i;
          ext = hi(i);
        } else if (lo(i) <= hi(hiIdx) * (1 - d)) {
          swings.add((hiIdx, hi(hiIdx)));
          dir = -1;
          extIdx = i;
          ext = lo(i);
        }
      } else if (dir == 1) {
        if (hi(i) > ext) {
          ext = hi(i);
          extIdx = i;
        } else if (lo(i) <= ext * (1 - d)) {
          swings.add((extIdx, ext));
          dir = -1;
          extIdx = i;
          ext = lo(i);
        }
      } else {
        if (lo(i) < ext) {
          ext = lo(i);
          extIdx = i;
        } else if (hi(i) >= ext * (1 + d)) {
          swings.add((extIdx, ext));
          dir = 1;
          extIdx = i;
          ext = hi(i);
        }
      }
    }
    // The leg still forming, up to its current extreme.
    if (dir != 0) swings.add((extIdx, ext));

    for (final (i, v) in swings) {
      pivots[i] = v;
    }
    for (int k = 1; k < swings.length; k++) {
      final (i0, v0) = swings[k - 1];
      final (i1, v1) = swings[k];
      for (int i = i0; i <= i1; i++) {
        line[i] = i1 == i0 ? v1 : v0 + (v1 - v0) * (i - i0) / (i1 - i0);
      }
    }
    return ZigZagResult(line: line, pivots: pivots);
  }

  // ── Elliott waves (a possible count on the ZigZag swings) ───────────────
  // Looks for the most recent five swings that pass Elliott's hard rules:
  // wave 2 doesn't retrace past the start of wave 1, wave 3 isn't the
  // shortest of 1/3/5, wave 4 doesn't overlap wave 1's territory, wave 3
  // goes beyond wave 1. Then labels up to three swings after wave 5 as
  // A-B-C while B stays short of wave 5's extreme. Null when no stretch of
  // swings passes — better nothing than a forced count.
  static ElliottCount? elliottWaves(List<TaBar> points, {double deviation = 5}) {
    final z = zigzag(points, deviation: deviation);
    final swings = <(int, double)>[
      for (final (i, v) in z.pivots.indexed)
        if (v != null) (i, v),
    ];
    if (swings.length < 6) return null;
    for (var s = swings.length - 6; s >= 0; s--) {
      final p = [for (var k = 0; k < 6; k++) swings[s + k].$2];
      final up = p[1] > p[0];
      // Work in "up" terms; mirror a down move.
      final q = up ? p : [for (final v in p) -v];
      final len1 = q[1] - q[0], len3 = q[3] - q[2], len5 = q[5] - q[4];
      final valid =
          q[1] > q[0] &&
          q[2] < q[1] &&
          q[2] > q[0] &&
          q[3] > q[1] &&
          q[4] < q[3] &&
          q[4] > q[1] &&
          q[5] > q[4] &&
          !(len3 < len1 && len3 < len5);
      if (!valid) continue;
      final waves = <ElliottPoint>[for (var k = 1; k <= 5; k++) ElliottPoint(swings[s + k].$1, swings[s + k].$2, '$k')];
      // The correction so far.
      const abc = ['A', 'B', 'C'];
      for (var k = 0; k < 3 && s + 6 + k < swings.length; k++) {
        final (i, v) = swings[s + 6 + k];
        final w = up ? v : -v;
        if (k == 1 && w >= q[5]) break; // B beyond wave 5's extreme
        waves.add(ElliottPoint(i, v, abc[k]));
      }
      return ElliottCount(start: ElliottPoint(swings[s].$1, swings[s].$2, '0'), waves: waves, isUp: up);
    }
    return null;
  }

  // ── Ehlers Even Better Sinewave ──────────────────────────────────────────
  // Ehlers (2013): a high-pass filter removes the trend longer than
  // [duration] bars, a super smoother removes noise shorter than 10 bars,
  // and the wave is normalized by its own power. It sits near +1 through an
  // upswing and near −1 through a downswing, and swings across only when
  // the move actually turns — unlike the classic Sine Wave, it doesn't
  // keep flipping inside a trend.
  static List<double?> evenBetterSinewave(List<TaBar> points, {int duration = 40}) {
    final n = points.length;
    final out = List<double?>.filled(n, null);
    if (n < 12) return out;
    const deg = math.pi / 180;
    final alpha1 = (1 - math.sin(360 / duration * deg)) / math.cos(360 / duration * deg);
    final a1 = math.exp(-1.414 * math.pi / 10);
    final b1 = 2 * a1 * math.cos(1.414 * 180 / 10 * deg);
    final c2 = b1, c3 = -a1 * a1, c1 = 1 - c2 - c3;
    final hp = List<double>.filled(n, 0);
    final filt = List<double>.filled(n, 0);
    for (var i = 1; i < n; i++) {
      hp[i] = 0.5 * (1 + alpha1) * (points[i].close - points[i - 1].close) + alpha1 * hp[i - 1];
      if (i < 2) continue;
      filt[i] = c1 * (hp[i] + hp[i - 1]) / 2 + c2 * filt[i - 1] + c3 * filt[i - 2];
      if (i < 10) continue; // let the filters settle
      final wave = (filt[i] + filt[i - 1] + filt[i - 2]) / 3;
      final pwr = (filt[i] * filt[i] + filt[i - 1] * filt[i - 1] + filt[i - 2] * filt[i - 2]) / 3;
      if (pwr > 0) out[i] = (wave / math.sqrt(pwr)).clamp(-1.0, 1.0);
    }
    return out;
  }

  // ── Ehlers Sine Wave (dominant-cycle phase) ─────────────────────────────
  // John Ehlers' Sine Wave indicator (Rocket Science for Traders): measure
  // the dominant cycle with a Hilbert-transform homodyne discriminator,
  // take the cycle's phase from one period of smoothed price, and plot
  // sin(phase) and sin(phase + 45°).
  static SineWaveResult sineWave(List<TaBar> points) {
    final n = points.length;
    final sine = List<double?>.filled(n, null);
    final lead = List<double?>.filled(n, null);
    final outPeriod = List<double?>.filled(n, null);
    if (n < 50) {
      return SineWaveResult(sine: sine, leadSine: lead, period: outPeriod);
    }
    const deg = math.pi / 180;
    final price = [for (final p in points) ((p.high ?? p.close) + (p.low ?? p.close)) / 2];
    final smooth = List<double>.filled(n, 0);
    final detrender = List<double>.filled(n, 0);
    final q1 = List<double>.filled(n, 0);
    final i1 = List<double>.filled(n, 0);
    final i2 = List<double>.filled(n, 0);
    final q2 = List<double>.filled(n, 0);
    final re = List<double>.filled(n, 0);
    final im = List<double>.filled(n, 0);
    final period = List<double>.filled(n, 0);
    final smoothPeriod = List<double>.filled(n, 0);
    var dcPhase = 0.0;
    double hilbert(List<double> x, int i, double p) =>
        (0.0962 * x[i] + 0.5769 * x[i - 2] - 0.5769 * x[i - 4] - 0.0962 * x[i - 6]) * (0.075 * p + 0.54);

    for (var i = 0; i < n; i++) {
      if (i < 3) {
        smooth[i] = price[i];
        continue;
      }
      smooth[i] = (4 * price[i] + 3 * price[i - 1] + 2 * price[i - 2] + price[i - 3]) / 10;
      if (i < 12) continue;
      final prevP = period[i - 1];
      detrender[i] = hilbert(smooth, i, prevP);
      q1[i] = hilbert(detrender, i, prevP);
      i1[i] = detrender[i - 3];
      final jI = hilbert(i1, i, prevP);
      final jQ = hilbert(q1, i, prevP);
      i2[i] = 0.2 * (i1[i] - jQ) + 0.8 * i2[i - 1];
      q2[i] = 0.2 * (q1[i] + jI) + 0.8 * q2[i - 1];
      re[i] = 0.2 * (i2[i] * i2[i - 1] + q2[i] * q2[i - 1]) + 0.8 * re[i - 1];
      im[i] = 0.2 * (i2[i] * q2[i - 1] - q2[i] * i2[i - 1]) + 0.8 * im[i - 1];
      var per = prevP;
      if (im[i] != 0 && re[i] != 0) {
        per = 360 / (math.atan(im[i] / re[i]) / deg);
      }
      if (prevP > 0) {
        per = per.clamp(0.67 * prevP, 1.5 * prevP).toDouble();
      }
      per = per.clamp(6, 50).toDouble();
      period[i] = 0.2 * per + 0.8 * prevP;
      smoothPeriod[i] = 0.33 * period[i] + 0.67 * smoothPeriod[i - 1];

      final dc = (smoothPeriod[i] + 0.5).floor();
      if (dc < 1 || i < dc || i < 40) continue;
      var realPart = 0.0, imagPart = 0.0;
      for (var c = 0; c < dc; c++) {
        realPart += math.sin(360 * c / dc * deg) * smooth[i - c];
        imagPart += math.cos(360 * c / dc * deg) * smooth[i - c];
      }
      if (imagPart.abs() > 0) dcPhase = math.atan(realPart / imagPart) / deg;
      if (imagPart.abs() <= 0.001) dcPhase += 90 * realPart.sign;
      dcPhase += 90;
      dcPhase += 360 / smoothPeriod[i];
      if (imagPart < 0) dcPhase += 180;
      if (dcPhase > 315) dcPhase -= 360;
      sine[i] = math.sin(dcPhase * deg);
      lead[i] = math.sin((dcPhase + 45) * deg);
      outPeriod[i] = smoothPeriod[i];
    }
    return SineWaveResult(sine: sine, leadSine: lead, period: outPeriod);
  }

  // ── KAMA (Kaufman's Adaptive Moving Average) ────────────────────────────
  // A moving average that sets its own speed from the efficiency ratio
  // (net move over [period] bars ÷ the sum of bar-to-bar moves): close to
  // 1 in a clean trend, so it follows like a [fast]-period EMA; near 0 in
  // chop, so it barely moves, like a [slow]-period EMA.
  static List<double?> kama(List<TaBar> points, {int period = 10, int fast = 2, int slow = 30}) {
    final result = List<double?>.filled(points.length, null);
    if (points.length <= period) return result;
    final fastSc = 2 / (fast + 1);
    final slowSc = 2 / (slow + 1);
    var prev = points[period - 1].close;
    for (int i = period; i < points.length; i++) {
      final change = (points[i].close - points[i - period].close).abs();
      double volatility = 0;
      for (int j = i - period + 1; j <= i; j++) {
        volatility += (points[j].close - points[j - 1].close).abs();
      }
      final er = volatility == 0 ? 0.0 : change / volatility;
      final sc = pow(er * (fastSc - slowSc) + slowSc, 2).toDouble();
      prev = prev + sc * (points[i].close - prev);
      result[i] = prev;
    }
    return result;
  }

  // ── Supertrend (ATR bands that flip with the trend) ──────────────────────
  // Standard definition (as on TradingView): bands at hl2 ± multiplier×ATR
  // (Wilder), each band only allowed to tighten while the trend holds, and
  // the trend flips when the close crosses the opposite band.
  static List<SupertrendPoint?> supertrend(List<TaBar> points, {int period = 10, double multiplier = 3}) {
    final n = points.length;
    final out = List<SupertrendPoint?>.filled(n, null);
    final atrValues = atr(points, period: period)?.values;
    if (atrValues == null) return out;
    double? upper, lower;
    var up = true;
    for (int i = 0; i < n; i++) {
      final a = i < atrValues.length ? atrValues[i] : null;
      if (a == null) continue;
      final h = points[i].high ?? points[i].close;
      final l = points[i].low ?? points[i].close;
      final hl2 = (h + l) / 2;
      final basicUpper = hl2 + multiplier * a;
      final basicLower = hl2 - multiplier * a;
      final prevClose = points[i - 1].close;
      final prevUpper = upper, prevLower = lower;
      upper = (prevUpper == null || basicUpper < prevUpper || prevClose > prevUpper) ? basicUpper : prevUpper;
      lower = (prevLower == null || basicLower > prevLower || prevClose < prevLower) ? basicLower : prevLower;
      if (prevUpper != null && prevLower != null) {
        final close = points[i].close;
        if (up && close < prevLower) {
          up = false;
        } else if (!up && close > prevUpper) {
          up = true;
        }
      }
      out[i] = SupertrendPoint(value: up ? lower : upper, isUp: up);
    }
    return out;
  }

  // ── Aroon (0–100: how recently the period high / low was set) ────────────
  // Window of period+1 bars, as on TradingView.
  static AroonResult aroon(List<TaBar> points, {int period = 25}) {
    final n = points.length;
    final up = List<double?>.filled(n, null);
    final down = List<double?>.filled(n, null);
    for (int i = period; i < n; i++) {
      var hiIdx = i - period, loIdx = i - period;
      for (int j = i - period; j <= i; j++) {
        if ((points[j].high ?? points[j].close) >= (points[hiIdx].high ?? points[hiIdx].close)) {
          hiIdx = j;
        }
        if ((points[j].low ?? points[j].close) <= (points[loIdx].low ?? points[loIdx].close)) {
          loIdx = j;
        }
      }
      up[i] = 100 * (period - (i - hiIdx)) / period;
      down[i] = 100 * (period - (i - loIdx)) / period;
    }
    return AroonResult(up: up, down: down);
  }

  // ── Rate of Change (% change vs N bars ago) ──────────────────────────────
  static List<double?> roc(List<TaBar> points, {int period = 12}) {
    final n = points.length;
    final out = List<double?>.filled(n, null);
    for (int i = period; i < n; i++) {
      final past = points[i - period].close;
      if (past != 0) out[i] = (points[i].close - past) / past * 100;
    }
    return out;
  }

  // ── Volume moving average (for the volume bars) ──────────────────────────
  static List<double?> volumeSma(List<TaBar> points, {int period = 20}) {
    final n = points.length;
    final out = List<double?>.filled(n, null);
    double sum = 0;
    for (int i = 0; i < n; i++) {
      sum += points[i].volume ?? 0;
      if (i >= period) sum -= points[i - period].volume ?? 0;
      if (i >= period - 1) out[i] = sum / period;
    }
    return out;
  }

  // ── Candlestick patterns ─────────────────────────────────────────────────
  // Classic single/multi-bar reversal patterns. Reversal patterns only
  // count after a prior move in the opposite direction (close below/above
  // where it was 5 bars earlier) — a "hammer" in the middle of a rally
  // isn't one. Bars without an open price are skipped.
  static List<CandlePatternMatch> candlePatterns(List<TaBar> points) {
    final out = <CandlePatternMatch>[];
    final n = points.length;
    double body(int i) => (points[i].close - points[i].open!).abs();
    double range(int i) => (points[i].high ?? points[i].close) - (points[i].low ?? points[i].close);
    bool hasOhlc(int i) => points[i].open != null && points[i].high != null && points[i].low != null;
    bool downtrend(int i) => i >= 5 && points[i].close < points[i - 5].close;
    bool uptrend(int i) => i >= 5 && points[i].close > points[i - 5].close;
    bool bull(int i) => points[i].close > points[i].open!;
    bool bear(int i) => points[i].close < points[i].open!;

    // Average body over the previous 10 bars — "long" / "small" candles are
    // judged relative to recent activity, not absolute price.
    double avgBody(int i) {
      var sum = 0.0, count = 0;
      for (int j = math.max(0, i - 10); j < i; j++) {
        if (points[j].open == null) continue;
        sum += body(j);
        count++;
      }
      return count == 0 ? 0 : sum / count;
    }

    for (int i = 1; i < n; i++) {
      if (!hasOhlc(i)) continue;
      final r = range(i);
      if (r <= 0) continue;
      final b = body(i);
      final o = points[i].open!, c = points[i].close;
      final h = points[i].high!, l = points[i].low!;
      final upperShadow = h - math.max(o, c);
      final lowerShadow = math.min(o, c) - l;

      // Three-bar stars first — they take precedence over a doji/hammer on
      // their own last bar.
      if (i >= 2 && hasOhlc(i - 1) && hasOhlc(i - 2)) {
        final b1 = body(i - 2), b2 = body(i - 1);
        final avg = avgBody(i - 2);
        final mid1 = (points[i - 2].open! + points[i - 2].close) / 2;
        final longFirst = avg > 0 && b1 >= avg;
        if (longFirst && b2 <= b1 * 0.3) {
          if (bear(i - 2) &&
              bull(i) &&
              c > mid1 &&
              downtrend(i - 2) &&
              math.max(points[i - 1].open!, points[i - 1].close) <= points[i - 2].close) {
            out.add(CandlePatternMatch(index: i, type: CandlePatternType.morningStar, bullish: true));
            continue;
          }
          if (bull(i - 2) &&
              bear(i) &&
              c < mid1 &&
              uptrend(i - 2) &&
              math.min(points[i - 1].open!, points[i - 1].close) >= points[i - 2].close) {
            out.add(CandlePatternMatch(index: i, type: CandlePatternType.eveningStar, bullish: false));
            continue;
          }
        }
      }

      if (hasOhlc(i - 1)) {
        final po = points[i - 1].open!, pc = points[i - 1].close;
        final engulfs = math.max(o, c) >= math.max(po, pc) && math.min(o, c) <= math.min(po, pc) && b > body(i - 1);
        if (engulfs && bear(i - 1) && bull(i) && downtrend(i - 1)) {
          out.add(CandlePatternMatch(index: i, type: CandlePatternType.bullishEngulfing, bullish: true));
          continue;
        }
        if (engulfs && bull(i - 1) && bear(i) && uptrend(i - 1)) {
          out.add(CandlePatternMatch(index: i, type: CandlePatternType.bearishEngulfing, bullish: false));
          continue;
        }
      }

      if (b <= r * 0.35 && lowerShadow >= 2 * b && upperShadow <= r * 0.25 && b > 0 && downtrend(i - 1)) {
        out.add(CandlePatternMatch(index: i, type: CandlePatternType.hammer, bullish: true));
        continue;
      }
      if (b <= r * 0.35 && upperShadow >= 2 * b && lowerShadow <= r * 0.25 && b > 0 && uptrend(i - 1)) {
        out.add(CandlePatternMatch(index: i, type: CandlePatternType.shootingStar, bullish: false));
        continue;
      }
      // Doji only on a bar with a meaningful range — a near-flat bar on an
      // untraded day isn't indecision, it's no trading.
      final avg = avgBody(i);
      if (b <= r * 0.1 && avg > 0 && r >= avg) {
        out.add(CandlePatternMatch(index: i, type: CandlePatternType.doji, bullish: null));
      }
    }
    return out;
  }

  // ── RSI Divergence ─────────────────────────────────────────────────────────
  // Compares the two most recent swing pivots (fractals) in price vs RSI
  // within a lookback window. Bullish: price makes a lower low while RSI
  // makes a higher low (downtrend losing momentum). Bearish: price makes a
  // higher high while RSI makes a lower high (uptrend losing momentum).
  // Exposed publicly (computed once over the full series) so callers that
  // need a per-bar historical check — like the signal engine scanning every
  // candle — aren't stuck re-scanning an O(n) window for every bar.
  static List<int> pivotLowIndices(List<double> closes, {int wing = 3}) {
    final pivots = <int>[];
    for (int i = wing; i < closes.length - wing; i++) {
      var isLow = true;
      for (int j = i - wing; j <= i + wing; j++) {
        if (j != i && closes[j] < closes[i]) {
          isLow = false;
          break;
        }
      }
      if (isLow) pivots.add(i);
    }
    return pivots;
  }

  static List<int> pivotHighIndices(List<double> closes, {int wing = 3}) {
    final pivots = <int>[];
    for (int i = wing; i < closes.length - wing; i++) {
      var isHigh = true;
      for (int j = i - wing; j <= i + wing; j++) {
        if (j != i && closes[j] > closes[i]) {
          isHigh = false;
          break;
        }
      }
      if (isHigh) pivots.add(i);
    }
    return pivots;
  }

  // What a price/RSI divergence must clear to count. Without these, two
  // near-equal lows a few bars apart — a close 0.3% lower with RSI 0.6
  // higher — read as a divergence nobody would see on the chart.
  static const divergenceMinPriceMove = 0.01;
  static const divergenceMinRsiGap = 3.0;
  static const divergenceMinBars = 5;

  /// The newest pivot and the latest earlier one at least
  /// [divergenceMinBars] before it, or null.
  static (int, int)? divergencePivots(List<int> pivots) {
    if (pivots.length < 2) return null;
    final i2 = pivots.last;
    for (var k = pivots.length - 2; k >= 0; k--) {
      if (i2 - pivots[k] >= divergenceMinBars) return (pivots[k], i2);
    }
    return null;
  }

  /// Whether pivots [i1] → [i2] diverge from RSI: bullish when the price
  /// made a lower low (by at least [divergenceMinPriceMove]) while RSI made
  /// a higher low (by at least [divergenceMinRsiGap] points) from a weak
  /// reading under 40; bearish the mirror image, from a strong one over 60.
  static bool isRsiDivergence(List<double> closes, List<double?> rsiVals, int i1, int i2, {required bool bullish}) {
    final r1 = rsiVals[i1], r2 = rsiVals[i2];
    final c1 = closes[i1], c2 = closes[i2];
    if (r1 == null || r2 == null || c1 <= 0) return false;
    final move = (c2 - c1) / c1;
    return bullish
        ? move <= -divergenceMinPriceMove && r2 - r1 >= divergenceMinRsiGap && r1 < 40
        : move >= divergenceMinPriceMove && r1 - r2 >= divergenceMinRsiGap && r1 > 60;
  }

  static bool rsiBullishDivergence(List<TaBar> points, {int lookback = 40, int rsiPeriod = 14, int wing = 3}) {
    final n = points.length;
    if (n < rsiPeriod + lookback) return false;
    final closes = points.map((p) => p.close).toList();
    final pair = divergencePivots(pivotLowIndices(closes, wing: wing).where((i) => i >= n - lookback).toList());
    if (pair == null) return false;
    return isRsiDivergence(closes, rsi(points, period: rsiPeriod), pair.$1, pair.$2, bullish: true);
  }

  static bool rsiBearishDivergence(List<TaBar> points, {int lookback = 40, int rsiPeriod = 14, int wing = 3}) {
    final n = points.length;
    if (n < rsiPeriod + lookback) return false;
    final closes = points.map((p) => p.close).toList();
    final pair = divergencePivots(pivotHighIndices(closes, wing: wing).where((i) => i >= n - lookback).toList());
    if (pair == null) return false;
    return isRsiDivergence(closes, rsi(points, period: rsiPeriod), pair.$1, pair.$2, bullish: false);
  }

  /// The current support and resistance trend lines: through two recent
  /// swing lows (support) / highs (resistance) that price has respected
  /// ever since — no bar closed through the line (0.3% tolerance) from the
  /// first swing point to the last bar — and that still sit within
  /// [maxDistance] of the last close (a steep line far from price says
  /// nothing about the next move). Of those, the one nearest the price
  /// wins. At most one of each; none when no candidate qualifies.
  static List<AutoTrendline> autoTrendlines(
    List<TaBar> points, {
    int wing = 3,
    int minSpan = 8,
    int candidates = 8,
    double tolerance = 0.003,
    double maxDistance = 0.08,
  }) {
    final n = points.length;
    if (n < minSpan + wing * 2) return const [];
    final lows = points.map((p) => p.low ?? p.close).toList();
    final highs = points.map((p) => p.high ?? p.close).toList();
    final closes = points.map((p) => p.close).toList();

    AutoTrendline? best(List<int> pivots, List<double> prices, bool support) {
      final recent = pivots.length > candidates ? pivots.sublist(pivots.length - candidates) : pivots;
      AutoTrendline? found;
      for (var x = 0; x < recent.length; x++) {
        for (var y = x + 1; y < recent.length; y++) {
          final a = recent[x], b = recent[y];
          if (b - a < minSpan) continue;
          final line = AutoTrendline(a, b, prices[a], prices[b], support);
          var valid = true;
          for (var k = a; k < n && valid; k++) {
            final level = line.priceAt(k.toDouble());
            if (level <= 0) {
              valid = false;
            } else if (support) {
              valid = closes[k] >= level * (1 - tolerance);
            } else {
              valid = closes[k] <= level * (1 + tolerance);
            }
          }
          if (!valid) continue;
          final last = closes[n - 1];
          final distance = (line.priceAt((n - 1).toDouble()) - last).abs() / last;
          if (distance > maxDistance) continue;
          final foundDistance = found == null
              ? double.infinity
              : (found.priceAt((n - 1).toDouble()) - last).abs() / last;
          if (distance < foundDistance) found = line;
        }
      }
      return found;
    }

    return [
      ?best(pivotLowIndices(lows, wing: wing), lows, true),
      ?best(pivotHighIndices(highs, wing: wing), highs, false),
    ];
  }

  /// Regular divergences between price and an [oscillator] over the whole
  /// series, for drawing on that oscillator's panel: each pair of
  /// consecutive price swing lows where price makes a lower low but the
  /// oscillator a higher low (bullish), and swing highs with a higher high
  /// against a lower oscillator high (bearish). Pairs further apart than
  /// [maxSpan] bars are skipped — too far apart to be one setup.
  static List<Divergence> divergences(
    List<TaBar> points,
    List<double?> oscillator, {
    int wing = 3,
    int minSpan = 5,
    int maxSpan = 60,
  }) {
    final closes = points.map((p) => p.close).toList();
    final out = <Divergence>[];
    void scan(List<int> pivots, bool bullish) {
      for (var k = 1; k < pivots.length; k++) {
        final a = pivots[k - 1], b = pivots[k];
        final span = b - a;
        if (span < minSpan || span > maxSpan) continue;
        if (a >= oscillator.length || b >= oscillator.length) continue;
        final oa = oscillator[a], ob = oscillator[b];
        if (oa == null || ob == null) continue;
        final priceDiverges = bullish ? closes[b] < closes[a] && ob > oa : closes[b] > closes[a] && ob < oa;
        if (priceDiverges) out.add(Divergence(a, b, bullish));
      }
    }

    scan(pivotLowIndices(closes, wing: wing), true);
    scan(pivotHighIndices(closes, wing: wing), false);
    out.sort((x, y) => x.end.compareTo(y.end));
    return out;
  }
}

/// An automatically drawn trend line through two swing points — [a]/[b]
/// are bar indices, [pa]/[pb] the prices there. Extends to the right.
class AutoTrendline {
  final int a;
  final int b;
  final double pa;
  final double pb;
  final bool support;
  const AutoTrendline(this.a, this.b, this.pa, this.pb, this.support);

  double priceAt(double i) => pa + (pb - pa) * (i - a) / (b - a);
}

/// A divergence between two swing points (bar indices into the series it
/// was found on).
class Divergence {
  final int start;
  final int end;
  final bool bullish;
  const Divergence(this.start, this.end, this.bullish);
}
