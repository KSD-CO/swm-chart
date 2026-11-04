// The rest of the common built-in indicator set as chart indicators, each
// over its [Ta] function: `chart.addIndicator(Hma(21), source: candles)`.
import 'dart:ui' show Color;

import '../options.dart';
import '../ta/bar.dart';
import '../ta/ta.dart';
import 'indicators.dart';
import 'ta_indicators.dart';

/// A [TaIndicator] described by its fields.
abstract class _Simple extends TaIndicator {
  _Simple(this.name, this.lines, {this.overlay = false, this.levels = const [], this.range, this.band});

  @override
  final String name;
  @override
  final List<IndicatorLine> lines;
  @override
  final bool overlay;
  @override
  final List<double> levels;
  @override
  final (double, double)? range;
  @override
  final IndicatorBand? band;
}

IndicatorLine _line(String name, Color color, {double width = 1.5, LineStyle style = LineStyle.solid}) =>
    IndicatorLine(name, color, lineWidth: width, lineStyle: style);

IndicatorLine _bars(String name, Color up, Color down) =>
    IndicatorLine(name, up, kind: IndicatorLineKind.histogram, negativeColor: down);

const _up = Color(0xFF26A69A);
const _down = Color(0xFFEF5350);
const _signal = Color(0xFFFF9800);

// ── moving averages (over the price) ─────────────────────────────────────

/// Hull moving average.
class Hma extends _Simple {
  Hma([this.period = 21, Color color = const Color(0xFF00BCD4)])
    : super('HMA $period', [_line('HMA $period', color)], overlay: true);
  final int period;
  @override
  List<List<double?>> series(List<TaBar> bars) => [Ta.hma(bars, period)];
}

/// Double exponential moving average.
class Dema extends _Simple {
  Dema([this.period = 21, Color color = const Color(0xFF43A047)])
    : super('DEMA $period', [_line('DEMA $period', color)], overlay: true);
  final int period;
  @override
  List<List<double?>> series(List<TaBar> bars) => [Ta.dema(bars, period)];
}

/// Triple exponential moving average.
class Tema extends _Simple {
  Tema([this.period = 21, Color color = const Color(0xFF7CB342)])
    : super('TEMA $period', [_line('TEMA $period', color)], overlay: true);
  final int period;
  @override
  List<List<double?>> series(List<TaBar> bars) => [Ta.tema(bars, period)];
}

/// Wilder's smoothed moving average (RMA / SMMA).
class Rma extends _Simple {
  Rma([this.period = 14, Color color = const Color(0xFF8D6E63)])
    : super('RMA $period', [_line('RMA $period', color)], overlay: true);
  final int period;
  @override
  List<List<double?>> series(List<TaBar> bars) => [Ta.rma(bars, period)];
}

/// Volume-weighted moving average.
class Vwma extends _Simple {
  Vwma([this.period = 20, Color color = const Color(0xFF5E35B1)])
    : super('VWMA $period', [_line('VWMA $period', color)], overlay: true);
  final int period;
  @override
  List<List<double?>> series(List<TaBar> bars) => [Ta.vwma(bars, period)];
}

/// Arnaud Legoux moving average.
class Alma extends _Simple {
  Alma({this.period = 9, this.offset = 0.85, this.sigma = 6, Color color = const Color(0xFF1E88E5)})
    : super('ALMA $period', [_line('ALMA $period', color)], overlay: true);
  final int period;
  final double offset, sigma;
  @override
  List<List<double?>> series(List<TaBar> bars) => [Ta.alma(bars, period, offset: offset, sigma: sigma)];
}

/// Least squares moving average (linear regression curve).
class Lsma extends _Simple {
  Lsma([this.period = 25, Color color = const Color(0xFFAB47BC)])
    : super('LSMA $period', [_line('LSMA $period', color)], overlay: true);
  final int period;
  @override
  List<List<double?>> series(List<TaBar> bars) => [Ta.lsma(bars, period)];
}

/// Zero-lag EMA.
class Zlema extends _Simple {
  Zlema([this.period = 21, Color color = const Color(0xFFFFB300)])
    : super('ZLEMA $period', [_line('ZLEMA $period', color)], overlay: true);
  final int period;
  @override
  List<List<double?>> series(List<TaBar> bars) => [Ta.zlema(bars, period)];
}

/// Tillson T3.
class T3 extends _Simple {
  T3({this.period = 5, this.vFactor = 0.7, Color color = const Color(0xFFF06292)})
    : super('T3 $period', [_line('T3 $period', color)], overlay: true);
  final int period;
  final double vFactor;
  @override
  List<List<double?>> series(List<TaBar> bars) => [Ta.t3(bars, period, vFactor: vFactor)];
}

/// McGinley dynamic.
class McGinley extends _Simple {
  McGinley([this.period = 14, Color color = const Color(0xFF26C6DA)])
    : super('McGinley $period', [_line('McGinley $period', color)], overlay: true);
  final int period;
  @override
  List<List<double?>> series(List<TaBar> bars) => [Ta.mcGinley(bars, period)];
}

/// Moving average envelope.
class Envelope extends _Simple {
  Envelope({
    this.period = 20,
    this.percent = 2.5,
    this.exponential = false,
    Color color = const Color(0xFF2196F3),
    Color fillColor = const Color(0x142196F3),
  }) : super(
         'Envelope $period',
         [
           _line('Upper', color, width: 1),
           _line('Basis', color, width: 1, style: LineStyle.dashed),
           _line('Lower', color, width: 1),
         ],
         overlay: true,
         band: IndicatorBand(0, 2, fillColor),
       );
  final int period;
  final double percent;
  final bool exponential;
  @override
  List<List<double?>> series(List<TaBar> bars) {
    final e = Ta.envelope(bars, period, percent: percent, exponential: exponential);
    return [e.upper, e.mid, e.lower];
  }
}

/// Williams alligator: jaw, teeth, lips.
class Alligator extends _Simple {
  Alligator()
    : super('Alligator', [
        _line('Jaw', const Color(0xFF2962FF)),
        _line('Teeth', const Color(0xFFE91E63)),
        _line('Lips', const Color(0xFF66BB6A)),
      ], overlay: true);
  @override
  List<List<double?>> series(List<TaBar> bars) {
    final a = Ta.alligator(bars);
    return [a.jaw, a.teeth, a.lips];
  }
}

/// Chandelier exit: long and short trailing stops.
class ChandelierExit extends _Simple {
  ChandelierExit({this.period = 22, this.multiplier = 3})
    : super('Chandelier $period', [
        _line('Long stop', _up, width: 1, style: LineStyle.dashed),
        _line('Short stop', _down, width: 1, style: LineStyle.dashed),
      ], overlay: true);
  final int period;
  final double multiplier;
  @override
  List<List<double?>> series(List<TaBar> bars) {
    final c = Ta.chandelierExit(bars, period: period, mult: multiplier);
    return [c.long, c.short];
  }
}

// ── oscillators (own pane) ───────────────────────────────────────────────

/// Stochastic RSI (%K, %D).
class StochRsi extends _Simple {
  StochRsi({this.rsiPeriod = 14, this.stochPeriod = 14, this.k = 3, this.d = 3})
    : super(
        'Stoch RSI $rsiPeriod',
        [_line('%K', const Color(0xFF2962FF)), _line('%D', _signal, width: 1.2)],
        levels: const [80, 20],
        range: (0, 100),
      );
  final int rsiPeriod, stochPeriod, k, d;
  @override
  List<List<double?>> series(List<TaBar> bars) {
    final s = Ta.stochRsi(bars, rsiPeriod: rsiPeriod, stochPeriod: stochPeriod, k: k, d: d);
    return [s.k, s.d];
  }
}

/// TRIX and its signal.
class Trix extends _Simple {
  Trix({this.period = 18, this.signal = 9})
    : super(
        'TRIX $period',
        [_line('TRIX', const Color(0xFFE91E63)), _line('Signal', _signal, width: 1.2)],
        levels: const [0],
      );
  final int period, signal;
  @override
  List<List<double?>> series(List<TaBar> bars) {
    final t = Ta.trix(bars, period: period, signal: signal);
    return [t.trix, t.signal];
  }
}

/// Ultimate oscillator.
class UltimateOscillator extends _Simple {
  UltimateOscillator({this.fast = 7, this.mid = 14, this.slow = 28})
    : super('UO $fast/$mid/$slow', [_line('UO', const Color(0xFFAB47BC))], levels: const [70, 30], range: (0, 100));
  final int fast, mid, slow;
  @override
  List<List<double?>> series(List<TaBar> bars) => [Ta.ultimateOscillator(bars, fast: fast, mid: mid, slow: slow)];
}

/// Awesome oscillator, as a histogram.
class AwesomeOscillator extends _Simple {
  AwesomeOscillator() : super('AO', [_bars('AO', _up, _down)], levels: const [0]);
  @override
  List<List<double?>> series(List<TaBar> bars) => [Ta.awesomeOscillator(bars)];
}

/// Accelerator oscillator, as a histogram.
class AcceleratorOscillator extends _Simple {
  AcceleratorOscillator() : super('AC', [_bars('AC', _up, _down)], levels: const [0]);
  @override
  List<List<double?>> series(List<TaBar> bars) => [Ta.acceleratorOscillator(bars)];
}

/// Percentage price oscillator: line, signal, histogram.
class Ppo extends _Simple {
  Ppo({this.fast = 12, this.slow = 26, this.signal = 9})
    : super(
        'PPO $fast/$slow',
        [_bars('Histogram', _up, _down), _line('PPO', const Color(0xFF2962FF)), _line('Signal', _signal, width: 1.2)],
        levels: const [0],
      );
  final int fast, slow, signal;
  @override
  List<List<double?>> series(List<TaBar> bars) {
    final p = Ta.ppo(bars, fast: fast, slow: slow, signal: signal);
    return [p.histogram, p.ppo, p.signal];
  }
}

/// Detrended price oscillator.
class Dpo extends _Simple {
  Dpo([this.period = 21]) : super('DPO $period', [_line('DPO', const Color(0xFF43A047))], levels: const [0]);
  final int period;
  @override
  List<List<double?>> series(List<TaBar> bars) => [Ta.dpo(bars, period: period)];
}

/// Momentum: close − close n bars ago.
class Momentum extends _Simple {
  Momentum([this.period = 10]) : super('Momentum $period', [_line('MOM', const Color(0xFF5C6BC0))], levels: const [0]);
  final int period;
  @override
  List<List<double?>> series(List<TaBar> bars) => [Ta.momentum(bars, period: period)];
}

/// Chande momentum oscillator.
class Cmo extends _Simple {
  Cmo([this.period = 9])
    : super('CMO $period', [_line('CMO', const Color(0xFF00897B))], levels: const [50, -50], range: (-100, 100));
  final int period;
  @override
  List<List<double?>> series(List<TaBar> bars) => [Ta.cmo(bars, period: period)];
}

/// True strength index and its signal.
class Tsi extends _Simple {
  Tsi({this.long = 25, this.short = 13, this.signal = 13})
    : super(
        'TSI $long/$short',
        [_line('TSI', const Color(0xFF2962FF)), _line('Signal', _signal, width: 1.2)],
        levels: const [0],
      );
  final int long, short, signal;
  @override
  List<List<double?>> series(List<TaBar> bars) {
    final t = Ta.tsi(bars, long: long, short: short, signal: signal);
    return [t.tsi, t.signal];
  }
}

/// Coppock curve.
class Coppock extends _Simple {
  Coppock() : super('Coppock', [_line('Coppock', const Color(0xFF00ACC1))], levels: const [0]);
  @override
  List<List<double?>> series(List<TaBar> bars) => [Ta.coppock(bars)];
}

/// Know Sure Thing and its signal.
class Kst extends _Simple {
  Kst() : super('KST', [_line('KST', const Color(0xFF43A047)), _line('Signal', _down, width: 1.2)], levels: const [0]);
  @override
  List<List<double?>> series(List<TaBar> bars) {
    final k = Ta.kst(bars);
    return [k.kst, k.signal];
  }
}

/// Fisher transform and its trigger.
class FisherTransform extends _Simple {
  FisherTransform([this.period = 9])
    : super(
        'Fisher $period',
        [_line('Fisher', const Color(0xFF2962FF)), _line('Trigger', _signal, width: 1.2)],
        levels: const [1.5, 0, -1.5],
      );
  final int period;
  @override
  List<List<double?>> series(List<TaBar> bars) {
    final f = Ta.fisherTransform(bars, period: period);
    return [f.fisher, f.trigger];
  }
}

/// Connors RSI.
class ConnorsRsi extends _Simple {
  ConnorsRsi() : super('CRSI', [_line('CRSI', const Color(0xFF7E57C2))], levels: const [90, 10], range: (0, 100));
  @override
  List<List<double?>> series(List<TaBar> bars) => [Ta.connorsRsi(bars)];
}

/// Relative vigor index and its signal.
class Rvi extends _Simple {
  Rvi([this.period = 10])
    : super('RVGI $period', [_line('RVGI', _up), _line('Signal', _down, width: 1.2)], levels: const [0]);
  final int period;
  @override
  List<List<double?>> series(List<TaBar> bars) {
    final r = Ta.rvi(bars, period: period);
    return [r.rvi, r.signal];
  }
}

/// Stochastic momentum index and its signal.
class Smi extends _Simple {
  Smi({this.period = 10, this.smooth = 3, this.signal = 10})
    : super(
        'SMI $period',
        [_line('SMI', const Color(0xFF2962FF)), _line('Signal', _signal, width: 1.2)],
        levels: const [40, -40],
        range: (-100, 100),
      );
  final int period, smooth, signal;
  @override
  List<List<double?>> series(List<TaBar> bars) {
    final s = Ta.smi(bars, period: period, smooth: smooth, signal: signal);
    return [s.smi, s.signal];
  }
}

/// Choppiness index.
class Choppiness extends _Simple {
  Choppiness([this.period = 14])
    : super('CHOP $period', [_line('CHOP', const Color(0xFF26A69A))], levels: const [61.8, 38.2], range: (0, 100));
  final int period;
  @override
  List<List<double?>> series(List<TaBar> bars) => [Ta.choppiness(bars, period: period)];
}

/// Vortex indicator (VI+, VI−).
class Vortex extends _Simple {
  Vortex([this.period = 14]) : super('Vortex $period', [_line('VI+', _up), _line('VI−', _down)], levels: const [1]);
  final int period;
  @override
  List<List<double?>> series(List<TaBar> bars) {
    final v = Ta.vortex(bars, period: period);
    return [v.plus, v.minus];
  }
}

/// Elder ray: bull and bear power, as histograms.
class ElderRay extends _Simple {
  ElderRay([this.period = 13])
    : super(
        'Elder Ray $period',
        [_bars('Bull power', _up, _down), _bars('Bear power', _down, _down)],
        levels: const [0],
      );
  final int period;
  @override
  List<List<double?>> series(List<TaBar> bars) {
    final e = Ta.elderRay(bars, period: period);
    return [e.bull, e.bear];
  }
}

/// Balance of power.
class BalanceOfPower extends _Simple {
  BalanceOfPower([this.period = 14])
    : super('BOP', [_line('BOP', const Color(0xFFEF6C00))], levels: const [0], range: (-1, 1));
  final int period;
  @override
  List<List<double?>> series(List<TaBar> bars) => [Ta.balanceOfPower(bars, period: period)];
}

/// Mass index.
class MassIndex extends _Simple {
  MassIndex() : super('Mass Index', [_line('MI', const Color(0xFF8E24AA))], levels: const [27, 26.5]);
  @override
  List<List<double?>> series(List<TaBar> bars) => [Ta.massIndex(bars)];
}

// ── volume ───────────────────────────────────────────────────────────────

/// Accumulation / distribution line.
class AccumulationDistribution extends _Simple {
  AccumulationDistribution() : super('A/D', [_line('A/D', const Color(0xFF29B6F6))]);
  @override
  List<List<double?>> series(List<TaBar> bars) => [Ta.accumulationDistribution(bars)];
}

/// Chaikin oscillator.
class ChaikinOscillator extends _Simple {
  ChaikinOscillator() : super('Chaikin Osc', [_line('Chaikin', const Color(0xFFEC407A))], levels: const [0]);
  @override
  List<List<double?>> series(List<TaBar> bars) => [Ta.chaikinOscillator(bars)];
}

/// Price volume trend.
class PriceVolumeTrend extends _Simple {
  PriceVolumeTrend() : super('PVT', [_line('PVT', const Color(0xFF5C6BC0))]);
  @override
  List<List<double?>> series(List<TaBar> bars) => [Ta.priceVolumeTrend(bars)];
}

/// Negative and positive volume index.
class VolumeIndexes extends _Simple {
  VolumeIndexes() : super('NVI / PVI', [_line('NVI', _down), _line('PVI', _up)]);
  @override
  List<List<double?>> series(List<TaBar> bars) {
    final v = Ta.volumeIndexes(bars);
    return [v.nvi, v.pvi];
  }
}

/// Klinger volume oscillator and its signal.
class Klinger extends _Simple {
  Klinger()
    : super(
        'Klinger',
        [_line('KVO', const Color(0xFF2962FF)), _line('Signal', _signal, width: 1.2)],
        levels: const [0],
      );
  @override
  List<List<double?>> series(List<TaBar> bars) {
    final k = Ta.klinger(bars);
    return [k.kvo, k.signal];
  }
}

/// Elder's force index.
class ForceIndex extends _Simple {
  ForceIndex([this.period = 13]) : super('Force $period', [_line('EFI', const Color(0xFFD81B60))], levels: const [0]);
  final int period;
  @override
  List<List<double?>> series(List<TaBar> bars) => [Ta.forceIndex(bars, period: period)];
}

/// Ease of movement.
class EaseOfMovement extends _Simple {
  EaseOfMovement([this.period = 14]) : super('EOM $period', [_line('EOM', const Color(0xFF43A047))], levels: const [0]);
  final int period;
  @override
  List<List<double?>> series(List<TaBar> bars) => [Ta.easeOfMovement(bars, period: period)];
}

/// Volume oscillator (% between a fast and a slow volume EMA).
class VolumeOscillator extends _Simple {
  VolumeOscillator({this.fast = 5, this.slow = 10})
    : super('Vol Osc $fast/$slow', [_line('VO', const Color(0xFF00897B))], levels: const [0]);
  final int fast, slow;
  @override
  List<List<double?>> series(List<TaBar> bars) => [Ta.volumeOscillator(bars, fast: fast, slow: slow)];
}

// ── volatility ───────────────────────────────────────────────────────────

/// Standard deviation of the closes.
class StandardDeviation extends _Simple {
  StandardDeviation([this.period = 20]) : super('StdDev $period', [_line('StdDev', const Color(0xFF7E57C2))]);
  final int period;
  @override
  List<List<double?>> series(List<TaBar> bars) => [Ta.standardDeviation(bars, period: period)];
}

/// Historical volatility, annualised, in %.
class HistoricalVolatility extends _Simple {
  HistoricalVolatility({this.period = 10, this.barsPerYear = 252})
    : super('HV $period', [_line('HV', const Color(0xFF00ACC1))]);
  final int period, barsPerYear;
  @override
  List<List<double?>> series(List<TaBar> bars) => [
    Ta.historicalVolatility(bars, period: period, barsPerYear: barsPerYear),
  ];
}

/// Bollinger %B.
class BollingerPercentB extends _Simple {
  BollingerPercentB({this.period = 20, this.multiplier = 2})
    : super('%B $period', [_line('%B', const Color(0xFF26A69A))], levels: const [1, 0.5, 0]);
  final int period;
  final double multiplier;
  @override
  List<List<double?>> series(List<TaBar> bars) => [Ta.bollingerExtras(bars, period: period, mult: multiplier).percentB];
}

/// Bollinger bandwidth.
class BollingerWidth extends _Simple {
  BollingerWidth({this.period = 20, this.multiplier = 2})
    : super('BBW $period', [_line('BBW', const Color(0xFF2962FF))]);
  final int period;
  final double multiplier;
  @override
  List<List<double?>> series(List<TaBar> bars) => [Ta.bollingerExtras(bars, period: period, mult: multiplier).width];
}

/// Ulcer index.
class UlcerIndex extends _Simple {
  UlcerIndex([this.period = 14]) : super('Ulcer $period', [_line('UI', const Color(0xFFEF5350))]);
  final int period;
  @override
  List<List<double?>> series(List<TaBar> bars) => [Ta.ulcerIndex(bars, period: period)];
}
