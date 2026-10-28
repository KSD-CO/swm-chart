// Chart indicators backed by the whole-series functions in [Ta]: each
// update recomputes the series (O(n)) and copies the outputs from the
// first changed bar on — simple, and the same numbers as [Ta] itself.
import 'dart:ui' show Color;

import '../options.dart';
import '../ta/bar.dart';
import '../ta/ta.dart';
import 'indicators.dart';

/// An [IndicatorInput] seen as a [TaBar] (its time in seconds as the date).
class _InputBar implements TaBar {
  _InputBar(this._b);
  final IndicatorInput _b;

  @override
  DateTime get date => DateTime.fromMillisecondsSinceEpoch((_b.time * 1000).round(), isUtc: true);
  @override
  double get close => _b.close;
  @override
  double get open => _b.open;
  @override
  double get high => _b.high;
  @override
  double get low => _b.low;
  @override
  double? get volume => _b.volume;
}

/// Base of the indicators computed by [Ta]: implement [series].
abstract class TaIndicator extends Indicator {
  /// Every output over the whole series, one list per [lines] entry.
  List<List<double?>> series(List<TaBar> bars);

  @override
  void compute(List<IndicatorInput> input, int from, List<List<double?>> out) {
    final all = series([for (final b in input) _InputBar(b)]);
    for (var l = 0; l < out.length && l < all.length; l++) {
      final src = all[l];
      for (var i = from; i < input.length; i++) {
        out[l][i] = i < src.length ? src[i] : null;
      }
    }
  }
}

/// Williams %R (−100…0).
class WilliamsR extends TaIndicator {
  WilliamsR([this.period = 14, this.color = const Color(0xFF26A69A)]);
  final int period;
  final Color color;
  @override
  String get name => 'Williams %R $period';
  @override
  bool get overlay => false;
  @override
  List<IndicatorLine> get lines => [IndicatorLine(name, color)];
  @override
  List<double> get levels => const [-20, -80];
  @override
  (double, double) get range => (-100, 0);
  @override
  List<List<double?>> series(List<TaBar> bars) => [Ta.williamsR(bars, period: period)];
}

/// Average Directional Index with +DI / −DI.
class Adx extends TaIndicator {
  Adx({
    this.period = 14,
    this.adxColor = const Color(0xFFFFB300),
    this.plusColor = const Color(0xFF26A69A),
    this.minusColor = const Color(0xFFEF5350),
  });
  final int period;
  final Color adxColor, plusColor, minusColor;
  @override
  String get name => 'ADX $period';
  @override
  bool get overlay => false;
  @override
  List<IndicatorLine> get lines => [
    IndicatorLine('ADX', adxColor),
    IndicatorLine('+DI', plusColor, lineWidth: 1),
    IndicatorLine('−DI', minusColor, lineWidth: 1),
  ];
  @override
  List<double> get levels => const [25];
  @override
  List<List<double?>> series(List<TaBar> bars) {
    final r = Ta.adx(bars, period: period);
    final empty = List<double?>.filled(bars.length, null);
    return r == null ? [empty, empty, empty] : [r.adx, r.plusDI, r.minusDI];
  }
}

/// On-Balance Volume. Needs volumes.
class Obv extends TaIndicator {
  Obv([this.color = const Color(0xFF42A5F5)]);
  final Color color;
  @override
  String get name => 'OBV';
  @override
  bool get overlay => false;
  @override
  List<IndicatorLine> get lines => [IndicatorLine(name, color)];
  @override
  List<List<double?>> series(List<TaBar> bars) => [Ta.obv(bars).values];
}

/// Commodity Channel Index.
class Cci extends TaIndicator {
  Cci([this.period = 20, this.color = const Color(0xFF26C6DA)]);
  final int period;
  final Color color;
  @override
  String get name => 'CCI $period';
  @override
  bool get overlay => false;
  @override
  List<IndicatorLine> get lines => [IndicatorLine(name, color)];
  @override
  List<double> get levels => const [100, -100];
  @override
  List<List<double?>> series(List<TaBar> bars) => [Ta.cci(bars, period: period)];
}

/// Money Flow Index (0…100). Needs volumes.
class Mfi extends TaIndicator {
  Mfi([this.period = 14, this.color = const Color(0xFFAB47BC)]);
  final int period;
  final Color color;
  @override
  String get name => 'MFI $period';
  @override
  bool get overlay => false;
  @override
  List<IndicatorLine> get lines => [IndicatorLine(name, color)];
  @override
  List<double> get levels => const [80, 20];
  @override
  (double, double) get range => (0, 100);
  @override
  List<List<double?>> series(List<TaBar> bars) => [Ta.mfi(bars, period: period)];
}

/// Chaikin Money Flow (−1…1). Needs volumes.
class Cmf extends TaIndicator {
  Cmf([this.period = 20, this.color = const Color(0xFF66BB6A)]);
  final int period;
  final Color color;
  @override
  String get name => 'CMF $period';
  @override
  bool get overlay => false;
  @override
  List<IndicatorLine> get lines => [IndicatorLine(name, color)];
  @override
  List<double> get levels => const [0];
  @override
  List<List<double?>> series(List<TaBar> bars) => [Ta.chaikinMoneyFlow(bars, period: period)];
}

/// Aroon up / down (0…100).
class Aroon extends TaIndicator {
  Aroon({this.period = 25, this.upColor = const Color(0xFF26A69A), this.downColor = const Color(0xFFEF5350)});
  final int period;
  final Color upColor, downColor;
  @override
  String get name => 'Aroon $period';
  @override
  bool get overlay => false;
  @override
  List<IndicatorLine> get lines => [IndicatorLine('Up', upColor), IndicatorLine('Down', downColor)];
  @override
  List<double> get levels => const [70, 30];
  @override
  (double, double) get range => (0, 100);
  @override
  List<List<double?>> series(List<TaBar> bars) {
    final r = Ta.aroon(bars, period: period);
    return [r.up, r.down];
  }
}

/// Rate of Change, in %.
class Roc extends TaIndicator {
  Roc([this.period = 12, this.color = const Color(0xFF5C6BC0)]);
  final int period;
  final Color color;
  @override
  String get name => 'ROC $period';
  @override
  bool get overlay => false;
  @override
  List<IndicatorLine> get lines => [IndicatorLine(name, color)];
  @override
  List<double> get levels => const [0];
  @override
  List<List<double?>> series(List<TaBar> bars) => [Ta.roc(bars, period: period)];
}

/// Parabolic SAR, as two dotted lines: below price in an uptrend, above it
/// in a downtrend.
class ParabolicSar extends TaIndicator {
  ParabolicSar({
    this.initialAf = 0.02,
    this.stepAf = 0.02,
    this.maxAf = 0.2,
    this.upColor = const Color(0xFF26A69A),
    this.downColor = const Color(0xFFEF5350),
  });
  final double initialAf, stepAf, maxAf;
  final Color upColor, downColor;
  @override
  String get name => 'SAR';
  @override
  bool get overlay => true;
  @override
  List<IndicatorLine> get lines => [
    IndicatorLine('SAR ↑', upColor, lineStyle: LineStyle.dotted),
    IndicatorLine('SAR ↓', downColor, lineStyle: LineStyle.dotted),
  ];
  @override
  List<List<double?>> series(List<TaBar> bars) {
    final r = Ta.parabolicSar(bars, initialAf: initialAf, stepAf: stepAf, maxAf: maxAf);
    return [
      [for (final p in r) p == null || p.isAbove ? null : p.sar],
      [for (final p in r) p == null || !p.isAbove ? null : p.sar],
    ];
  }
}

/// Kaufman's Adaptive Moving Average.
class Kama extends TaIndicator {
  Kama({this.period = 10, this.fast = 2, this.slow = 30, this.color = const Color(0xFFFF7043)});
  final int period, fast, slow;
  final Color color;
  @override
  String get name => 'KAMA $period';
  @override
  bool get overlay => true;
  @override
  List<IndicatorLine> get lines => [IndicatorLine(name, color)];
  @override
  List<List<double?>> series(List<TaBar> bars) => [Ta.kama(bars, period: period, fast: fast, slow: slow)];
}

/// Keltner channel: EMA ± multiplier × ATR.
class Keltner extends TaIndicator {
  Keltner({
    this.emaPeriod = 20,
    this.atrPeriod = 10,
    this.multiplier = 2,
    this.color = const Color(0xFF29B6F6),
    this.fillColor = const Color(0x1429B6F6),
  });
  final int emaPeriod, atrPeriod;
  final double multiplier;
  final Color color, fillColor;
  @override
  String get name => 'Keltner $emaPeriod';
  @override
  bool get overlay => true;
  @override
  List<IndicatorLine> get lines => [
    IndicatorLine('Upper', color, lineWidth: 1),
    IndicatorLine('Middle', color, lineWidth: 1, lineStyle: LineStyle.dashed),
    IndicatorLine('Lower', color, lineWidth: 1),
  ];
  @override
  IndicatorBand get band => IndicatorBand(0, 2, fillColor);
  @override
  List<List<double?>> series(List<TaBar> bars) {
    final r = Ta.keltnerChannel(bars, emaPeriod: emaPeriod, atrPeriod: atrPeriod, multiplier: multiplier);
    return [r.upper, r.middle, r.lower];
  }
}

/// Donchian channel: highest high / lowest low over the period.
class Donchian extends TaIndicator {
  Donchian({this.period = 20, this.color = const Color(0xFF8D6E63), this.fillColor = const Color(0x148D6E63)});
  final int period;
  final Color color, fillColor;
  @override
  String get name => 'Donchian $period';
  @override
  bool get overlay => true;
  @override
  List<IndicatorLine> get lines => [
    IndicatorLine('Upper', color, lineWidth: 1),
    IndicatorLine('Middle', color, lineWidth: 1, lineStyle: LineStyle.dashed),
    IndicatorLine('Lower', color, lineWidth: 1),
  ];
  @override
  IndicatorBand get band => IndicatorBand(0, 2, fillColor);
  @override
  List<List<double?>> series(List<TaBar> bars) {
    final r = Ta.donchianChannel(bars, period: period);
    return [r.upper, r.middle, r.lower];
  }
}

/// Supertrend, as an up line (support) and a down line (resistance).
class Supertrend extends TaIndicator {
  Supertrend({
    this.period = 10,
    this.multiplier = 3,
    this.upColor = const Color(0xFF26A69A),
    this.downColor = const Color(0xFFEF5350),
  });
  final int period;
  final double multiplier;
  final Color upColor, downColor;
  @override
  String get name => 'Supertrend $period';
  @override
  bool get overlay => true;
  @override
  List<IndicatorLine> get lines => [IndicatorLine('Up', upColor), IndicatorLine('Down', downColor)];
  @override
  List<List<double?>> series(List<TaBar> bars) {
    final r = Ta.supertrend(bars, period: period, multiplier: multiplier);
    return [
      [for (final p in r) p != null && p.isUp ? p.value : null],
      [for (final p in r) p != null && !p.isUp ? p.value : null],
    ];
  }
}

/// Moving average of volume, in its own pane. Needs volumes.
class VolumeSma extends TaIndicator {
  VolumeSma([this.period = 20, this.color = const Color(0xFFFFA726)]);
  final int period;
  final Color color;
  @override
  String get name => 'Volume MA $period';
  @override
  bool get overlay => false;
  @override
  List<IndicatorLine> get lines => [IndicatorLine(name, color)];
  @override
  List<List<double?>> series(List<TaBar> bars) => [Ta.volumeSma(bars, period: period)];
}

/// Ehlers' Sine Wave: sine and lead sine.
class SineWave extends TaIndicator {
  SineWave({this.sineColor = const Color(0xFF42A5F5), this.leadColor = const Color(0xFFFF7043)});
  final Color sineColor, leadColor;
  @override
  String get name => 'Sine Wave';
  @override
  bool get overlay => false;
  @override
  List<IndicatorLine> get lines => [IndicatorLine('Sine', sineColor), IndicatorLine('Lead', leadColor)];
  @override
  (double, double) get range => (-1, 1);
  @override
  List<List<double?>> series(List<TaBar> bars) {
    final r = Ta.sineWave(bars);
    return [r.sine, r.leadSine];
  }
}

/// Ehlers' Even Better Sinewave (−1…1).
class EvenBetterSinewave extends TaIndicator {
  EvenBetterSinewave([this.duration = 40, this.color = const Color(0xFF26C6DA)]);
  final int duration;
  final Color color;
  @override
  String get name => 'EBSW $duration';
  @override
  bool get overlay => false;
  @override
  List<IndicatorLine> get lines => [IndicatorLine(name, color)];
  @override
  List<double> get levels => const [0.85, -0.85];
  @override
  (double, double) get range => (-1, 1);
  @override
  List<List<double?>> series(List<TaBar> bars) => [Ta.evenBetterSinewave(bars, duration: duration)];
}
