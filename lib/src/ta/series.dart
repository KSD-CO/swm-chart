// Building blocks for the indicators: moving averages and rolling
// statistics over a series that may start with nulls (an indicator's
// warm-up), each result aligned with its input — null where the window
// isn't full yet.

import 'dart:math' as math;

/// Index of the first non-null value from which [values] stays non-null
/// to the end, or `values.length` when there is none.
int _start(List<double?> values) {
  var start = values.length;
  for (var i = values.length - 1; i >= 0; i--) {
    if (values[i] == null || !values[i]!.isFinite) break;
    start = i;
  }
  return start;
}

/// Simple moving average.
List<double?> sSma(List<double?> values, int period) {
  final out = List<double?>.filled(values.length, null);
  final s = _start(values);
  if (period <= 0 || values.length - s < period) return out;
  var sum = 0.0;
  for (var i = s; i < values.length; i++) {
    sum += values[i]!;
    if (i - s >= period) sum -= values[i - period]!;
    if (i - s >= period - 1) out[i] = sum / period;
  }
  return out;
}

/// Exponential moving average (α = 2 / (period + 1)), seeded with the SMA
/// of the first [period] values.
List<double?> sEma(List<double?> values, int period) => _smoothed(values, period, 2 / (period + 1));

/// Wilder's moving average (RMA / SMMA, α = 1 / period), as in RSI and ATR.
List<double?> sRma(List<double?> values, int period) => _smoothed(values, period, 1 / period);

List<double?> _smoothed(List<double?> values, int period, double alpha) {
  final out = List<double?>.filled(values.length, null);
  final s = _start(values);
  if (period <= 0 || values.length - s < period) return out;
  var sum = 0.0;
  for (var i = s; i < s + period; i++) {
    sum += values[i]!;
  }
  var v = sum / period;
  out[s + period - 1] = v;
  for (var i = s + period; i < values.length; i++) {
    v += alpha * (values[i]! - v);
    out[i] = v;
  }
  return out;
}

/// Linearly weighted moving average (weights 1…period, newest heaviest).
List<double?> sWma(List<double?> values, int period) {
  final out = List<double?>.filled(values.length, null);
  final s = _start(values);
  if (period <= 0 || values.length - s < period) return out;
  final denom = period * (period + 1) / 2;
  for (var i = s + period - 1; i < values.length; i++) {
    var sum = 0.0;
    for (var k = 0; k < period; k++) {
      sum += values[i - k]! * (period - k);
    }
    out[i] = sum / denom;
  }
  return out;
}

/// Population standard deviation over a rolling window.
List<double?> sStdev(List<double?> values, int period) {
  final out = List<double?>.filled(values.length, null);
  final s = _start(values);
  if (period <= 0 || values.length - s < period) return out;
  for (var i = s + period - 1; i < values.length; i++) {
    var sum = 0.0, sq = 0.0;
    for (var k = i - period + 1; k <= i; k++) {
      sum += values[k]!;
      sq += values[k]! * values[k]!;
    }
    final mean = sum / period;
    out[i] = math.sqrt(math.max(0, sq / period - mean * mean));
  }
  return out;
}

/// Rolling sum.
List<double?> sSum(List<double?> values, int period) {
  final out = List<double?>.filled(values.length, null);
  final s = _start(values);
  if (period <= 0 || values.length - s < period) return out;
  var sum = 0.0;
  for (var i = s; i < values.length; i++) {
    sum += values[i]!;
    if (i - s >= period) sum -= values[i - period]!;
    if (i - s >= period - 1) out[i] = sum;
  }
  return out;
}

/// Rolling highest / lowest.
List<double?> sHighest(List<double?> values, int period) => _extreme(values, period, math.max);
List<double?> sLowest(List<double?> values, int period) => _extreme(values, period, math.min);

List<double?> _extreme(List<double?> values, int period, double Function(double, double) pick) {
  final out = List<double?>.filled(values.length, null);
  final s = _start(values);
  if (period <= 0 || values.length - s < period) return out;
  for (var i = s + period - 1; i < values.length; i++) {
    var v = values[i]!;
    for (var k = i - period + 1; k < i; k++) {
      v = pick(v, values[k]!);
    }
    out[i] = v;
  }
  return out;
}

/// Least-squares line through the last [period] values, evaluated at the
/// newest one (LSMA / linear regression curve), or its slope per bar.
List<double?> sLinReg(List<double?> values, int period, {bool slope = false}) {
  final out = List<double?>.filled(values.length, null);
  final s = _start(values);
  if (period < 2 || values.length - s < period) return out;
  final xMean = (period - 1) / 2;
  var sxx = 0.0;
  for (var x = 0; x < period; x++) {
    sxx += (x - xMean) * (x - xMean);
  }
  for (var i = s + period - 1; i < values.length; i++) {
    var yMean = 0.0;
    for (var x = 0; x < period; x++) {
      yMean += values[i - period + 1 + x]!;
    }
    yMean /= period;
    var sxy = 0.0;
    for (var x = 0; x < period; x++) {
      sxy += (x - xMean) * (values[i - period + 1 + x]! - yMean);
    }
    final b = sxy / sxx;
    out[i] = slope ? b : yMean + b * (period - 1 - xMean);
  }
  return out;
}

/// [a] − [b], element-wise (null where either is).
List<double?> sMinus(List<double?> a, List<double?> b) => [
  for (var i = 0; i < a.length; i++)
    if (a[i] == null || b[i] == null) null else a[i]! - b[i]!,
];

/// [values] shifted [by] bars later (positive) — the first [by] null.
List<double?> sShift(List<double?> values, int by) => [
  for (var i = 0; i < values.length; i++) i - by >= 0 && i - by < values.length ? values[i - by] : null,
];
