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
import 'series.dart';

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

  /// The part of [volume] traded on up bars (close ≥ open, or with no open
  /// known); the rest was on down bars.
  final double? upVolume;
  const VolumeBucket({required this.priceLow, required this.priceHigh, required this.volume, this.upVolume});
}

class VolumeProfileResult {
  final List<VolumeBucket> buckets;
  final double pocPrice;
  final double pocVolume;

  /// The value area: the price range around the point of control holding
  /// [Ta.valueAreaShare] of the volume (70% by convention) — its low (VAL)
  /// and high (VAH). Equal to the whole range for a single bucket.
  final double valueAreaLow;
  final double valueAreaHigh;

  const VolumeProfileResult({
    required this.buckets,
    required this.pocPrice,
    required this.pocVolume,
    double? valueAreaLow,
    double? valueAreaHigh,
  }) : valueAreaLow = valueAreaLow ?? pocPrice,
       valueAreaHigh = valueAreaHigh ?? pocPrice;
}

/// The volume profile of one session (a trading day, say): the bars it
/// spans, as indices into the input, and its profile.
class SessionVolumeProfile {
  /// First and last bar of the session (inclusive), indices into the bars
  /// given to [Ta.sessionVolumeProfiles].
  final int from;
  final int to;
  final VolumeProfileResult profile;
  const SessionVolumeProfile({required this.from, required this.to, required this.profile});
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
        valueAreaLow: lo,
        valueAreaHigh: hi,
      );
    }

    final vols = List<double>.filled(buckets, 0);
    final ups = List<double>.filled(buckets, 0);
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
      final isUp = p.open == null || p.close >= p.open!;
      for (int b = startBucket; b <= endBucket; b++) {
        vols[b] += volPerBucket;
        if (isUp) ups[b] += volPerBucket;
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
      (i) => VolumeBucket(
        priceLow: lo + i * bucketSize,
        priceHigh: lo + (i + 1) * bucketSize,
        volume: vols[i],
        upVolume: ups[i],
      ),
    );

    final (vaLo, vaHi) = valueArea(vols, pocIdx);
    return VolumeProfileResult(
      buckets: result,
      pocPrice: lo + (pocIdx + 0.5) * bucketSize,
      pocVolume: pocVol,
      valueAreaLow: result[vaLo].priceLow,
      valueAreaHigh: result[vaHi].priceHigh,
    );
  }

  /// The share of volume the value area holds, by convention.
  static const valueAreaShare = 0.7;

  /// The value area of a profile's [volumes] (lowest price first) around
  /// the point of control [poc]: starting there, it grows one row at a
  /// time toward whichever neighbour traded more, until it holds [share]
  /// of the total volume. The first and last row in it, as indices.
  static (int, int) valueArea(List<double> volumes, int poc, {double share = valueAreaShare}) {
    if (volumes.isEmpty) return (0, 0);
    final total = volumes.fold(0.0, (s, v) => s + v);
    var lo = poc, hi = poc;
    var held = volumes[poc];
    while (held < total * share && (lo > 0 || hi < volumes.length - 1)) {
      final below = lo > 0 ? volumes[lo - 1] : -1.0;
      final above = hi < volumes.length - 1 ? volumes[hi + 1] : -1.0;
      if (above >= below) {
        hi++;
        held += above;
      } else {
        lo--;
        held += below;
      }
    }
    return (lo, hi);
  }

  /// A volume profile for each session of [points], in order: a session is
  /// a run of consecutive bars with the same [sessionOf] key — by default
  /// the calendar day (local) of the bar, for intraday bars. Each profile
  /// is over its session's own price range, in [buckets] rows.
  static List<SessionVolumeProfile> sessionVolumeProfiles(
    List<TaBar> points, {
    int buckets = 24,
    Object Function(TaBar bar)? sessionOf,
  }) {
    final key = sessionOf ?? (TaBar b) => DateTime(b.date.year, b.date.month, b.date.day);
    final out = <SessionVolumeProfile>[];
    var start = 0;
    for (var i = 1; i <= points.length; i++) {
      if (i < points.length && key(points[i]) == key(points[start])) continue;
      out.add(
        SessionVolumeProfile(
          from: start,
          to: i - 1,
          profile: volumeProfile(points.sublist(start, i), buckets: buckets),
        ),
      );
      start = i;
    }
    return out;
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

  // ══ More indicators ═════════════════════════════════════════════════════
  // The rest of the common built-in set (TradingView's names). Each returns
  // series aligned with [points], null through its warm-up.

  static List<double?> _c(List<TaBar> p) => [for (final b in p) b.close];
  static List<double?> _h(List<TaBar> p) => [for (final b in p) b.high ?? b.close];
  static List<double?> _l(List<TaBar> p) => [for (final b in p) b.low ?? b.close];
  static List<double?> _o(List<TaBar> p) => [for (final b in p) b.open ?? b.close];
  static List<double?> _v(List<TaBar> p) => [for (final b in p) b.volume ?? 0];

  static List<double?> _src(List<TaBar> p, List<double?>? source) => source ?? _c(p);

  /// True range of each bar (the first is its high − low).
  static List<double?> trueRange(List<TaBar> points) => [
    for (var i = 0; i < points.length; i++)
      () {
        final h = points[i].high ?? points[i].close, l = points[i].low ?? points[i].close;
        if (i == 0) return h - l;
        final pc = points[i - 1].close;
        return max(h - l, max((h - pc).abs(), (l - pc).abs()));
      }(),
  ];

  // ── moving averages ──────────────────────────────────────────────────────

  /// Weighted moving average of the closes (or [source]).
  static List<double?> wma(List<TaBar> points, int period, {List<double?>? source}) =>
      sWma(_src(points, source), period);

  /// Wilder's smoothed moving average (RMA / SMMA).
  static List<double?> rma(List<TaBar> points, int period, {List<double?>? source}) =>
      sRma(_src(points, source), period);

  /// Hull moving average: WMA(2·WMA(n/2) − WMA(n), √n) — fast and smooth.
  static List<double?> hma(List<TaBar> points, int period, {List<double?>? source}) {
    final s = _src(points, source);
    final half = sWma(s, max(1, period ~/ 2)), full = sWma(s, period);
    final diff = [
      for (var i = 0; i < s.length; i++)
        if (half[i] == null || full[i] == null) null else 2 * half[i]! - full[i]!,
    ];
    return sWma(diff, max(1, sqrt(period).round()));
  }

  /// Double EMA: 2·EMA − EMA(EMA).
  static List<double?> dema(List<TaBar> points, int period, {List<double?>? source}) {
    final e1 = sEma(_src(points, source), period), e2 = sEma(e1, period);
    return [
      for (var i = 0; i < e1.length; i++)
        if (e1[i] == null || e2[i] == null) null else 2 * e1[i]! - e2[i]!,
    ];
  }

  /// Triple EMA: 3·EMA − 3·EMA² + EMA³.
  static List<double?> tema(List<TaBar> points, int period, {List<double?>? source}) {
    final e1 = sEma(_src(points, source), period), e2 = sEma(e1, period), e3 = sEma(e2, period);
    return [
      for (var i = 0; i < e1.length; i++)
        if (e1[i] == null || e2[i] == null || e3[i] == null) null else 3 * e1[i]! - 3 * e2[i]! + e3[i]!,
    ];
  }

  /// Volume-weighted moving average: Σ(close·volume) / Σvolume.
  static List<double?> vwma(List<TaBar> points, int period) {
    final pv = sSum([for (final b in points) b.close * (b.volume ?? 0)], period);
    final vol = sSum(_v(points), period);
    return [
      for (var i = 0; i < points.length; i++)
        if (pv[i] == null || vol[i] == null || vol[i] == 0) null else pv[i]! / vol[i]!,
    ];
  }

  /// Arnaud Legoux moving average: a Gaussian-weighted window centred at
  /// [offset] (0…1) of it, [sigma] its width.
  static List<double?> alma(List<TaBar> points, int period, {double offset = 0.85, double sigma = 6}) {
    final s = _c(points);
    final out = List<double?>.filled(s.length, null);
    if (period < 1 || s.length < period) return out;
    final m = offset * (period - 1), w = period / sigma;
    final weights = [for (var k = 0; k < period; k++) exp(-(k - m) * (k - m) / (2 * w * w))];
    final norm = weights.reduce((a, b) => a + b);
    for (var i = period - 1; i < s.length; i++) {
      var sum = 0.0;
      for (var k = 0; k < period; k++) {
        sum += weights[k] * s[i - period + 1 + k]!;
      }
      out[i] = sum / norm;
    }
    return out;
  }

  /// Least squares moving average (linear regression curve).
  static List<double?> lsma(List<TaBar> points, int period) => sLinReg(_c(points), period);

  /// Zero-lag EMA: the EMA of close + (close − close[lag]), lag = (n − 1) / 2.
  static List<double?> zlema(List<TaBar> points, int period) {
    final c = _c(points), lag = (period - 1) ~/ 2;
    return sEma([for (var i = 0; i < c.length; i++) i < lag ? null : 2 * c[i]! - c[i - lag]!], period);
  }

  /// Tillson T3: six chained EMAs blended with volume factor [vFactor].
  static List<double?> t3(List<TaBar> points, int period, {double vFactor = 0.7}) {
    final e1 = sEma(_c(points), period), e2 = sEma(e1, period), e3 = sEma(e2, period);
    final e4 = sEma(e3, period), e5 = sEma(e4, period), e6 = sEma(e5, period);
    final a = vFactor;
    final c1 = -a * a * a, c2 = 3 * a * a + 3 * a * a * a;
    final c3 = -6 * a * a - 3 * a - 3 * a * a * a, c4 = 1 + 3 * a + a * a * a + 3 * a * a;
    return [
      for (var i = 0; i < e1.length; i++)
        if (e3[i] == null || e4[i] == null || e5[i] == null || e6[i] == null)
          null
        else
          c1 * e6[i]! + c2 * e5[i]! + c3 * e4[i]! + c4 * e3[i]!,
    ];
  }

  /// McGinley dynamic: an average that speeds up in fast markets.
  static List<double?> mcGinley(List<TaBar> points, int period) {
    final c = _c(points);
    final out = List<double?>.filled(c.length, null);
    if (c.length < period || period < 1) return out;
    var md = sSma(c, period)[period - 1]!;
    out[period - 1] = md;
    for (var i = period; i < c.length; i++) {
      final ratio = md == 0 ? 1.0 : c[i]! / md;
      md += (c[i]! - md) / (period * pow(ratio, 4));
      out[i] = md;
    }
    return out;
  }

  /// Envelope: an SMA (or EMA) with bands [percent]% above and below.
  static ({List<double?> mid, List<double?> upper, List<double?> lower}) envelope(
    List<TaBar> points,
    int period, {
    double percent = 2.5,
    bool exponential = false,
  }) {
    final mid = exponential ? sEma(_c(points), period) : sSma(_c(points), period);
    return (
      mid: mid,
      upper: [for (final m in mid) m == null ? null : m * (1 + percent / 100)],
      lower: [for (final m in mid) m == null ? null : m * (1 - percent / 100)],
    );
  }

  // ── oscillators ──────────────────────────────────────────────────────────

  /// Stochastic RSI: the stochastic of RSI, %K smoothed [k], %D [d].
  static ({List<double?> k, List<double?> d}) stochRsi(
    List<TaBar> points, {
    int rsiPeriod = 14,
    int stochPeriod = 14,
    int k = 3,
    int d = 3,
  }) {
    final r = rsi(points, period: rsiPeriod);
    final hi = sHighest(r, stochPeriod), lo = sLowest(r, stochPeriod);
    final raw = [
      for (var i = 0; i < r.length; i++)
        if (r[i] == null || hi[i] == null || lo[i] == null)
          null
        else
          hi[i] == lo[i] ? 50.0 : 100 * (r[i]! - lo[i]!) / (hi[i]! - lo[i]!),
    ];
    final kLine = sSma(raw, k);
    return (k: kLine, d: sSma(kLine, d));
  }

  /// TRIX: the 1-bar % rate of change of a triple-smoothed EMA, and its
  /// [signal] EMA.
  static ({List<double?> trix, List<double?> signal}) trix(List<TaBar> points, {int period = 18, int signal = 9}) {
    final e3 = sEma(sEma(sEma(_c(points), period), period), period);
    final t = [
      for (var i = 0; i < e3.length; i++)
        if (i == 0 || e3[i] == null || e3[i - 1] == null || e3[i - 1] == 0)
          null
        else
          10000 * (e3[i]! - e3[i - 1]!) / e3[i - 1]!,
    ];
    return (trix: t, signal: sEma(t, signal));
  }

  /// Ultimate oscillator (Williams): buying pressure over three windows.
  static List<double?> ultimateOscillator(List<TaBar> points, {int fast = 7, int mid = 14, int slow = 28}) {
    final n = points.length;
    final bp = List<double?>.filled(n, null), tr = List<double?>.filled(n, null);
    for (var i = 1; i < n; i++) {
      final pc = points[i - 1].close;
      final low = min(points[i].low ?? points[i].close, pc);
      final high = max(points[i].high ?? points[i].close, pc);
      bp[i] = points[i].close - low;
      tr[i] = high - low;
    }
    double? avg(int i, List<double?> sb, List<double?> st) =>
        sb[i] == null || st[i] == null || st[i] == 0 ? null : sb[i]! / st[i]!;
    final b1 = sSum(bp, fast), t1 = sSum(tr, fast);
    final b2 = sSum(bp, mid), t2 = sSum(tr, mid);
    final b3 = sSum(bp, slow), t3 = sSum(tr, slow);
    return [
      for (var i = 0; i < n; i++)
        () {
          final a1 = avg(i, b1, t1), a2 = avg(i, b2, t2), a3 = avg(i, b3, t3);
          if (a1 == null || a2 == null || a3 == null) return null;
          return 100 * (4 * a1 + 2 * a2 + a3) / 7;
        }(),
    ];
  }

  /// Awesome oscillator: SMA(5) − SMA(34) of the bars' midpoints.
  static List<double?> awesomeOscillator(List<TaBar> points, {int fast = 5, int slow = 34}) {
    final hl2 = [for (final b in points) ((b.high ?? b.close) + (b.low ?? b.close)) / 2];
    return sMinus(sSma(hl2, fast), sSma(hl2, slow));
  }

  /// Accelerator oscillator: AO − SMA(AO, 5).
  static List<double?> acceleratorOscillator(List<TaBar> points) {
    final ao = awesomeOscillator(points);
    return sMinus(ao, sSma(ao, 5));
  }

  /// Percentage price oscillator: (EMA fast − EMA slow) / EMA slow in %,
  /// with its signal line and histogram.
  static ({List<double?> ppo, List<double?> signal, List<double?> histogram}) ppo(
    List<TaBar> points, {
    int fast = 12,
    int slow = 26,
    int signal = 9,
  }) {
    final f = sEma(_c(points), fast), s = sEma(_c(points), slow);
    final line = [
      for (var i = 0; i < f.length; i++)
        if (f[i] == null || s[i] == null || s[i] == 0) null else 100 * (f[i]! - s[i]!) / s[i]!,
    ];
    final sig = sEma(line, signal);
    return (ppo: line, signal: sig, histogram: sMinus(line, sig));
  }

  /// Detrended price oscillator: close[n/2 + 1 ago] − SMA(n).
  static List<double?> dpo(List<TaBar> points, {int period = 21}) {
    final c = _c(points), ma = sSma(c, period), back = period ~/ 2 + 1;
    return [
      for (var i = 0; i < c.length; i++)
        if (ma[i] == null || i - back < 0) null else c[i - back]! - ma[i]!,
    ];
  }

  /// Momentum: close − close[n ago].
  static List<double?> momentum(List<TaBar> points, {int period = 10}) {
    final c = _c(points);
    return [for (var i = 0; i < c.length; i++) i < period ? null : c[i]! - c[i - period]!];
  }

  /// Chande momentum oscillator: 100·(Σup − Σdown) / (Σup + Σdown).
  static List<double?> cmo(List<TaBar> points, {int period = 9}) {
    final c = _c(points);
    final up = <double?>[null], down = <double?>[null];
    for (var i = 1; i < c.length; i++) {
      final d = c[i]! - c[i - 1]!;
      up.add(max(0, d));
      down.add(max(0, -d));
    }
    final su = sSum(up, period), sd = sSum(down, period);
    return [
      for (var i = 0; i < c.length; i++)
        if (su[i] == null || sd[i] == null || su[i]! + sd[i]! == 0)
          (su[i] == null ? null : 0.0)
        else
          100 * (su[i]! - sd[i]!) / (su[i]! + sd[i]!),
    ];
  }

  /// True strength index: double-smoothed momentum over its double-smoothed
  /// size, ×100, and its [signal] EMA.
  static ({List<double?> tsi, List<double?> signal}) tsi(
    List<TaBar> points, {
    int long = 25,
    int short = 13,
    int signal = 13,
  }) {
    final c = _c(points);
    final m = <double?>[null, for (var i = 1; i < c.length; i++) c[i]! - c[i - 1]!];
    final num = sEma(sEma(m, long), short);
    final den = sEma(sEma([for (final v in m) v?.abs()], long), short);
    final t = [
      for (var i = 0; i < c.length; i++)
        if (num[i] == null || den[i] == null || den[i] == 0) null else 100 * num[i]! / den[i]!,
    ];
    return (tsi: t, signal: sEma(t, signal));
  }

  /// Coppock curve: WMA(10) of ROC(14) + ROC(11).
  static List<double?> coppock(List<TaBar> points, {int wmaPeriod = 10, int longRoc = 14, int shortRoc = 11}) {
    final c = _c(points);
    double? rocAt(int i, int n) => i < n || c[i - n] == 0 ? null : 100 * (c[i]! - c[i - n]!) / c[i - n]!;
    final sum = [
      for (var i = 0; i < c.length; i++)
        () {
          final a = rocAt(i, longRoc), b = rocAt(i, shortRoc);
          return a == null || b == null ? null : a + b;
        }(),
    ];
    return sWma(sum, wmaPeriod);
  }

  /// Know Sure Thing: weighted sum of four smoothed rates of change, and
  /// its 9-bar SMA signal.
  static ({List<double?> kst, List<double?> signal}) kst(List<TaBar> points) {
    final c = _c(points);
    List<double?> roc(int n) => [
      for (var i = 0; i < c.length; i++) i < n || c[i - n] == 0 ? null : 100 * (c[i]! - c[i - n]!) / c[i - n]!,
    ];
    final r1 = sSma(roc(10), 10), r2 = sSma(roc(15), 10), r3 = sSma(roc(20), 10), r4 = sSma(roc(30), 15);
    final k = [
      for (var i = 0; i < c.length; i++)
        if (r1[i] == null || r2[i] == null || r3[i] == null || r4[i] == null)
          null
        else
          r1[i]! + 2 * r2[i]! + 3 * r3[i]! + 4 * r4[i]!,
    ];
    return (kst: k, signal: sSma(k, 9));
  }

  /// Fisher transform of the bars' midpoints over [period], and its
  /// trigger (the value a bar earlier).
  static ({List<double?> fisher, List<double?> trigger}) fisherTransform(List<TaBar> points, {int period = 9}) {
    final hl2 = [for (final b in points) ((b.high ?? b.close) + (b.low ?? b.close)) / 2];
    final hi = sHighest(hl2, period), lo = sLowest(hl2, period);
    final out = List<double?>.filled(points.length, null);
    var value = 0.0, fish = 0.0;
    for (var i = 0; i < points.length; i++) {
      if (hi[i] == null || lo[i] == null) continue;
      final range = hi[i]! - lo[i]!;
      final x = range == 0 ? 0.0 : (hl2[i] - lo[i]!) / range - 0.5;
      value = (0.66 * x + 0.67 * value).clamp(-0.999, 0.999);
      fish = 0.5 * log((1 + value) / (1 - value)) + 0.5 * fish;
      out[i] = fish;
    }
    return (fisher: out, trigger: sShift(out, 1));
  }

  /// Connors RSI: the average of RSI(3), the RSI(2) of the up/down streak
  /// and the percent rank of the 1-bar change over 100 bars.
  static List<double?> connorsRsi(List<TaBar> points, {int rsiPeriod = 3, int streakPeriod = 2, int rankPeriod = 100}) {
    final c = _c(points);
    final r = rsi(points, period: rsiPeriod);
    final streak = List<double>.filled(c.length, 0);
    for (var i = 1; i < c.length; i++) {
      final d = c[i]! - c[i - 1]!;
      streak[i] = d > 0
          ? (streak[i - 1] > 0 ? streak[i - 1] + 1 : 1)
          : d < 0
          ? (streak[i - 1] < 0 ? streak[i - 1] - 1 : -1)
          : 0;
    }
    final streakRsi = rsi([
      for (var i = 0; i < c.length; i++) TaPoint(date: points[i].date, close: streak[i]),
    ], period: streakPeriod);
    final out = List<double?>.filled(c.length, null);
    for (var i = rankPeriod + 1; i < c.length; i++) {
      final change = c[i]! / c[i - 1]! - 1;
      var below = 0;
      for (var k = i - rankPeriod; k < i; k++) {
        if (c[k]! / c[k - 1]! - 1 < change) below++;
      }
      if (r[i] == null || streakRsi[i] == null) continue;
      out[i] = (r[i]! + streakRsi[i]! + 100 * below / rankPeriod) / 3;
    }
    return out;
  }

  /// Relative vigor index: close − open against high − low, smoothed, and
  /// its signal.
  static ({List<double?> rvi, List<double?> signal}) rvi(List<TaBar> points, {int period = 10}) {
    final n = points.length;
    double sym(List<double?> v, int i) => (v[i]! + 2 * v[i - 1]! + 2 * v[i - 2]! + v[i - 3]!) / 6;
    final co = [for (final b in points) b.close - (b.open ?? b.close)];
    final hl = [for (final b in points) (b.high ?? b.close) - (b.low ?? b.close)];
    final num = <double?>[for (var i = 0; i < n; i++) i < 3 ? null : sym(co, i)];
    final den = <double?>[for (var i = 0; i < n; i++) i < 3 ? null : sym(hl, i)];
    final sn = sSum(num, period), sd = sSum(den, period);
    final line = [
      for (var i = 0; i < n; i++)
        if (sn[i] == null || sd[i] == null || sd[i] == 0) null else sn[i]! / sd[i]!,
    ];
    final sig = <double?>[for (var i = 0; i < n; i++) i < 3 || line[i - 3] == null ? null : sym(line, i)];
    return (rvi: line, signal: sig);
  }

  /// Stochastic momentum index: where the close sits relative to the
  /// middle of the [period] range, double-smoothed, and its EMA signal.
  static ({List<double?> smi, List<double?> signal}) smi(
    List<TaBar> points, {
    int period = 10,
    int smooth = 3,
    int signal = 10,
  }) {
    final hi = sHighest(_h(points), period), lo = sLowest(_l(points), period);
    final rel = [
      for (var i = 0; i < points.length; i++)
        if (hi[i] == null) null else points[i].close - (hi[i]! + lo[i]!) / 2,
    ];
    final range = [
      for (var i = 0; i < points.length; i++)
        if (hi[i] == null) null else hi[i]! - lo[i]!,
    ];
    final num = sEma(sEma(rel, smooth), smooth), den = sEma(sEma(range, smooth), smooth);
    final line = [
      for (var i = 0; i < points.length; i++)
        if (num[i] == null || den[i] == null || den[i] == 0) null else 200 * num[i]! / den[i]!,
    ];
    return (smi: line, signal: sEma(line, signal));
  }

  /// Choppiness index: 100·log10(ΣATR(1) / range) / log10(n) — high when
  /// the market chops sideways, low when it trends.
  static List<double?> choppiness(List<TaBar> points, {int period = 14}) {
    final tr = sSum(trueRange(points), period);
    final hi = sHighest(_h(points), period), lo = sLowest(_l(points), period);
    return [
      for (var i = 0; i < points.length; i++)
        if (tr[i] == null || hi[i] == null || hi[i] == lo[i])
          null
        else
          100 * log(tr[i]! / (hi[i]! - lo[i]!)) / ln10 / (log(period) / ln10),
    ];
  }

  /// Vortex indicator: VI+ and VI−.
  static ({List<double?> plus, List<double?> minus}) vortex(List<TaBar> points, {int period = 14}) {
    final n = points.length;
    final vp = <double?>[null], vm = <double?>[null];
    for (var i = 1; i < n; i++) {
      final h = points[i].high ?? points[i].close, l = points[i].low ?? points[i].close;
      final ph = points[i - 1].high ?? points[i - 1].close, pl = points[i - 1].low ?? points[i - 1].close;
      vp.add((h - pl).abs());
      vm.add((l - ph).abs());
    }
    final tr = sSum([null, ...trueRange(points).skip(1)], period);
    final sp = sSum(vp, period), sm = sSum(vm, period);
    return (
      plus: [for (var i = 0; i < n; i++) tr[i] == null || tr[i] == 0 || sp[i] == null ? null : sp[i]! / tr[i]!],
      minus: [for (var i = 0; i < n; i++) tr[i] == null || tr[i] == 0 || sm[i] == null ? null : sm[i]! / tr[i]!],
    );
  }

  /// Elder ray: bull power (high − EMA) and bear power (low − EMA).
  static ({List<double?> bull, List<double?> bear}) elderRay(List<TaBar> points, {int period = 13}) {
    final e = sEma(_c(points), period);
    return (bull: sMinus(_h(points), e), bear: sMinus(_l(points), e));
  }

  /// Balance of power: (close − open) / (high − low), smoothed by [period]
  /// (1: raw).
  static List<double?> balanceOfPower(List<TaBar> points, {int period = 14}) {
    final raw = [
      for (final b in points)
        () {
          final r = (b.high ?? b.close) - (b.low ?? b.close);
          return r == 0 ? 0.0 : (b.close - (b.open ?? b.close)) / r;
        }(),
    ];
    return period <= 1 ? raw : sSma(raw, period);
  }

  /// Mass index: the sum of EMA(range) / EMA(EMA(range)) over [period] —
  /// a bulge above 27 then back below 26.5 hints at a reversal.
  static List<double?> massIndex(List<TaBar> points, {int ema = 9, int period = 25}) {
    final range = [for (final b in points) (b.high ?? b.close) - (b.low ?? b.close)];
    final e1 = sEma(range, ema), e2 = sEma(e1, ema);
    return sSum([
      for (var i = 0; i < range.length; i++)
        if (e1[i] == null || e2[i] == null || e2[i] == 0) null else e1[i]! / e2[i]!,
    ], period);
  }

  // ── volume ───────────────────────────────────────────────────────────────

  /// Accumulation / distribution line: running Σ money-flow volume.
  static List<double?> accumulationDistribution(List<TaBar> points) {
    var ad = 0.0;
    return [
      for (final b in points)
        () {
          final h = b.high ?? b.close, l = b.low ?? b.close;
          final mfm = h == l ? 0.0 : ((b.close - l) - (h - b.close)) / (h - l);
          ad += mfm * (b.volume ?? 0);
          return ad;
        }(),
    ];
  }

  /// Chaikin oscillator: EMA(3) − EMA(10) of the A/D line.
  static List<double?> chaikinOscillator(List<TaBar> points, {int fast = 3, int slow = 10}) {
    final ad = accumulationDistribution(points);
    return sMinus(sEma(ad, fast), sEma(ad, slow));
  }

  /// Price volume trend: running Σ volume × % change.
  static List<double?> priceVolumeTrend(List<TaBar> points) {
    var pvt = 0.0;
    return [
      for (var i = 0; i < points.length; i++)
        () {
          if (i > 0 && points[i - 1].close != 0) {
            pvt += (points[i].volume ?? 0) * (points[i].close - points[i - 1].close) / points[i - 1].close;
          }
          return pvt;
        }(),
    ];
  }

  /// Negative and positive volume index (start 1000): moved only on days
  /// the volume falls (NVI) or rises (PVI).
  static ({List<double?> nvi, List<double?> pvi}) volumeIndexes(List<TaBar> points) {
    var nvi = 1000.0, pvi = 1000.0;
    final n = <double?>[], p = <double?>[];
    for (var i = 0; i < points.length; i++) {
      if (i > 0 && points[i - 1].close != 0) {
        final change = (points[i].close - points[i - 1].close) / points[i - 1].close;
        final v = points[i].volume ?? 0, pv = points[i - 1].volume ?? 0;
        if (v < pv) nvi *= 1 + change;
        if (v > pv) pvi *= 1 + change;
      }
      n.add(nvi);
      p.add(pvi);
    }
    return (nvi: n, pvi: p);
  }

  /// Klinger volume oscillator: EMA(34) − EMA(55) of signed volume force,
  /// and its 13-bar EMA signal.
  static ({List<double?> kvo, List<double?> signal}) klinger(
    List<TaBar> points, {
    int fast = 34,
    int slow = 55,
    int signal = 13,
  }) {
    final hlc3 = [for (final b in points) ((b.high ?? b.close) + (b.low ?? b.close) + b.close) / 3];
    final vf = <double?>[null];
    for (var i = 1; i < points.length; i++) {
      final sign = hlc3[i] > hlc3[i - 1] ? 1 : -1;
      vf.add(sign * (points[i].volume ?? 0));
    }
    final k = sMinus(sEma(vf, fast), sEma(vf, slow));
    return (kvo: k, signal: sEma(k, signal));
  }

  /// Force index: EMA of (close − previous close) × volume.
  static List<double?> forceIndex(List<TaBar> points, {int period = 13}) => sEma([
    null,
    for (var i = 1; i < points.length; i++) (points[i].close - points[i - 1].close) * (points[i].volume ?? 0),
  ], period);

  /// Ease of movement: how far the midpoint moved per unit of volume over
  /// range, smoothed by [period] (volume scaled by [divisor]).
  static List<double?> easeOfMovement(List<TaBar> points, {int period = 14, double divisor = 10000}) {
    final raw = <double?>[null];
    for (var i = 1; i < points.length; i++) {
      final b = points[i], p = points[i - 1];
      final h = b.high ?? b.close, l = b.low ?? b.close;
      final mid = (h + l) / 2 - ((p.high ?? p.close) + (p.low ?? p.close)) / 2;
      final v = (b.volume ?? 0) / divisor;
      raw.add(v == 0 || h == l ? 0 : mid * (h - l) / v);
    }
    return sSma(raw, period);
  }

  /// Volume oscillator: % difference between a fast and a slow EMA of
  /// volume.
  static List<double?> volumeOscillator(List<TaBar> points, {int fast = 5, int slow = 10}) {
    final f = sEma(_v(points), fast), s = sEma(_v(points), slow);
    return [
      for (var i = 0; i < points.length; i++)
        if (f[i] == null || s[i] == null || s[i] == 0) null else 100 * (f[i]! - s[i]!) / s[i]!,
    ];
  }

  // ── volatility and bands ─────────────────────────────────────────────────

  /// Standard deviation of the closes.
  static List<double?> standardDeviation(List<TaBar> points, {int period = 20}) => sStdev(_c(points), period);

  /// Historical volatility: the annualised standard deviation of log
  /// returns, in % ([barsPerYear] 252 for daily bars).
  static List<double?> historicalVolatility(List<TaBar> points, {int period = 10, int barsPerYear = 252}) {
    final c = _c(points);
    final r = <double?>[
      null,
      for (var i = 1; i < c.length; i++) c[i - 1]! > 0 && c[i]! > 0 ? log(c[i]! / c[i - 1]!) : null,
    ];
    return [for (final s in sStdev(r, period)) s == null ? null : 100 * s * sqrt(barsPerYear)];
  }

  /// Bollinger %B (where the close sits in the bands, 0 at the lower, 1 at
  /// the upper) and bandwidth ((upper − lower) / middle).
  static ({List<double?> percentB, List<double?> width}) bollingerExtras(
    List<TaBar> points, {
    int period = 20,
    double mult = 2,
  }) {
    final mid = sSma(_c(points), period), sd = sStdev(_c(points), period);
    final pb = <double?>[], w = <double?>[];
    for (var i = 0; i < points.length; i++) {
      if (mid[i] == null || sd[i] == null) {
        pb.add(null);
        w.add(null);
        continue;
      }
      final up = mid[i]! + mult * sd[i]!, lo = mid[i]! - mult * sd[i]!;
      pb.add(up == lo ? 0.5 : (points[i].close - lo) / (up - lo));
      w.add(mid[i] == 0 ? null : (up - lo) / mid[i]!);
    }
    return (percentB: pb, width: w);
  }

  /// Ulcer index: the root mean square of the % drawdown from the
  /// [period]-bar high.
  static List<double?> ulcerIndex(List<TaBar> points, {int period = 14}) {
    final c = _c(points), hi = sHighest(c, period);
    final dd = [
      for (var i = 0; i < c.length; i++)
        if (hi[i] == null || hi[i] == 0) null else pow(100 * (c[i]! - hi[i]!) / hi[i]!, 2).toDouble(),
    ];
    return [for (final v in sSma(dd, period)) v == null ? null : sqrt(v)];
  }

  /// Chandelier exit: a trailing stop [mult]·ATR below the [period] high
  /// (for longs) and above the low (for shorts).
  static ({List<double?> long, List<double?> short}) chandelierExit(
    List<TaBar> points, {
    int period = 22,
    double mult = 3,
  }) {
    final a = sRma(trueRange(points), period);
    final hi = sHighest(_h(points), period), lo = sLowest(_l(points), period);
    return (
      long: [for (var i = 0; i < points.length; i++) hi[i] == null || a[i] == null ? null : hi[i]! - mult * a[i]!],
      short: [for (var i = 0; i < points.length; i++) lo[i] == null || a[i] == null ? null : lo[i]! + mult * a[i]!],
    );
  }

  /// Williams alligator: jaw, teeth and lips — RMAs of the midpoint over
  /// 13, 8 and 5 bars, shifted 8, 5 and 3 bars ahead (on the bars, so the
  /// last few are null).
  static ({List<double?> jaw, List<double?> teeth, List<double?> lips}) alligator(List<TaBar> points) {
    final hl2 = [for (final b in points) ((b.high ?? b.close) + (b.low ?? b.close)) / 2];
    return (jaw: sShift(sRma(hl2, 13), 8), teeth: sShift(sRma(hl2, 8), 5), lips: sShift(sRma(hl2, 5), 3));
  }

  /// Williams fractals: bar indices that are the highest (up) or lowest
  /// (down) of the [side] bars either side.
  static ({List<int> up, List<int> down}) fractals(List<TaBar> points, {int side = 2}) {
    final h = _h(points), l = _l(points);
    final up = <int>[], down = <int>[];
    for (var i = side; i < points.length - side; i++) {
      var isUp = true, isDown = true;
      for (var k = i - side; k <= i + side; k++) {
        if (k == i) continue;
        if (h[k]! >= h[i]!) isUp = false;
        if (l[k]! <= l[i]!) isDown = false;
      }
      if (isUp) up.add(i);
      if (isDown) down.add(i);
    }
    return (up: up, down: down);
  }

  /// Open of each bar (the close where it has none) — for callers mixing
  /// the new indicators with their own sources.
  static List<double?> opens(List<TaBar> points) => _o(points);
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
