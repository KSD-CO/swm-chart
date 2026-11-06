// Every built-in indicator by id, with its inputs: for indicator pickers,
// settings dialogs and saving a chart's indicators.
import 'indicators.dart';
import 'ta_indicators.dart';
import 'ta_indicators_more.dart';

enum IndicatorGroup {
  movingAverages('Moving averages'),
  bands('Bands, clouds, stops'),
  momentum('Momentum'),
  trend('Trend'),
  volume('Volume'),
  volatility('Volatility');

  const IndicatorGroup(this.label);

  final String label;
}

/// One input of an indicator, e.g. its period.
class IndicatorParam {
  const IndicatorParam(this.key, this.label, this.defaultValue, {this.min = 1, this.max = 500, this.step = 1});

  /// Name in [IndicatorSpec.build]'s values and in saved charts.
  final String key;
  final String label;
  final num defaultValue;
  final num min;
  final num max;

  /// 1 for whole numbers; anything else for decimals.
  final num step;

  bool get isInteger => step == step.roundToDouble() && defaultValue == defaultValue.roundToDouble();
}

/// A built-in indicator: how to make it from its inputs.
class IndicatorSpec {
  const IndicatorSpec({
    required this.id,
    required this.title,
    required this.group,
    required this.create,
    this.params = const [],
    this.needsVolume = false,
    this.keywords = '',
  });

  /// Saved with a chart; stable across versions.
  final String id;

  /// Full name, e.g. `Relative Strength Index`.
  final String title;
  final IndicatorGroup group;
  final List<IndicatorParam> params;

  /// Reads volumes: give `addIndicator` a volume series.
  final bool needsVolume;

  /// Extra words to search by (abbreviations).
  final String keywords;
  final Indicator Function(Map<String, num> values) create;

  /// [values] filled in with the defaults.
  Map<String, num> withDefaults([Map<String, num> values = const {}]) => {
    for (final p in params) p.key: values[p.key] ?? p.defaultValue,
  };

  /// The indicator with [values] (defaults for the rest).
  Indicator build([Map<String, num> values = const {}]) => create(withDefaults(values));

  bool matches(String query) {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return true;
    return '$id $title $keywords'.toLowerCase().contains(q);
  }
}

/// The built-in indicators.
///
/// ```dart
/// final spec = IndicatorCatalog.byId('rsi')!;
/// chart.addIndicator(spec.build({'period': 21}), source: candles);
/// ```
abstract final class IndicatorCatalog {
  static IndicatorSpec? byId(String id) => _byId[id];

  /// Specs whose id, title or keywords contain [query].
  static List<IndicatorSpec> search(String query) => [
    for (final s in all)
      if (s.matches(query)) s,
  ];

  static final Map<String, IndicatorSpec> _byId = {for (final s in all) s.id: s};

  static const _period = 'period';

  static IndicatorParam _p([num value = 14, String label = 'Length']) => IndicatorParam(_period, label, value);

  static int _i(Map<String, num> v, String key) => v[key]!.round();

  static double _d(Map<String, num> v, String key) => v[key]!.toDouble();

  static final List<IndicatorSpec> all = [
    // ---- moving averages ----
    IndicatorSpec(
      id: 'sma',
      title: 'Simple Moving Average',
      group: IndicatorGroup.movingAverages,
      keywords: 'SMA MA',
      params: [_p(20)],
      create: (v) => Sma(_i(v, _period)),
    ),
    IndicatorSpec(
      id: 'ema',
      title: 'Exponential Moving Average',
      group: IndicatorGroup.movingAverages,
      keywords: 'EMA MA',
      params: [_p(20)],
      create: (v) => Ema(_i(v, _period)),
    ),
    IndicatorSpec(
      id: 'wma',
      title: 'Weighted Moving Average',
      group: IndicatorGroup.movingAverages,
      keywords: 'WMA MA',
      params: [_p(20)],
      create: (v) => Wma(_i(v, _period)),
    ),
    IndicatorSpec(
      id: 'hma',
      title: 'Hull Moving Average',
      group: IndicatorGroup.movingAverages,
      keywords: 'HMA MA',
      params: [_p(21)],
      create: (v) => Hma(_i(v, _period)),
    ),
    IndicatorSpec(
      id: 'dema',
      title: 'Double EMA',
      group: IndicatorGroup.movingAverages,
      keywords: 'DEMA MA',
      params: [_p(21)],
      create: (v) => Dema(_i(v, _period)),
    ),
    IndicatorSpec(
      id: 'tema',
      title: 'Triple EMA',
      group: IndicatorGroup.movingAverages,
      keywords: 'TEMA MA',
      params: [_p(21)],
      create: (v) => Tema(_i(v, _period)),
    ),
    IndicatorSpec(
      id: 'rma',
      title: 'Smoothed Moving Average (RMA)',
      group: IndicatorGroup.movingAverages,
      keywords: 'RMA SMMA MA',
      params: [_p(14)],
      create: (v) => Rma(_i(v, _period)),
    ),
    IndicatorSpec(
      id: 'vwma',
      title: 'Volume-Weighted Moving Average',
      group: IndicatorGroup.movingAverages,
      keywords: 'VWMA MA',
      needsVolume: true,
      params: [_p(20)],
      create: (v) => Vwma(_i(v, _period)),
    ),
    IndicatorSpec(
      id: 'alma',
      title: 'Arnaud Legoux Moving Average',
      group: IndicatorGroup.movingAverages,
      keywords: 'ALMA MA',
      params: [
        _p(9),
        const IndicatorParam('offset', 'Offset', 0.85, min: 0, max: 1, step: 0.05),
        const IndicatorParam('sigma', 'Sigma', 6, min: 0.5, max: 50, step: 0.5),
      ],
      create: (v) => Alma(period: _i(v, _period), offset: _d(v, 'offset'), sigma: _d(v, 'sigma')),
    ),
    IndicatorSpec(
      id: 'lsma',
      title: 'Least Squares Moving Average',
      group: IndicatorGroup.movingAverages,
      keywords: 'LSMA linear regression MA',
      params: [_p(25)],
      create: (v) => Lsma(_i(v, _period)),
    ),
    IndicatorSpec(
      id: 'zlema',
      title: 'Zero-Lag EMA',
      group: IndicatorGroup.movingAverages,
      keywords: 'ZLEMA MA',
      params: [_p(21)],
      create: (v) => Zlema(_i(v, _period)),
    ),
    IndicatorSpec(
      id: 't3',
      title: 'T3 Moving Average',
      group: IndicatorGroup.movingAverages,
      keywords: 'Tillson MA',
      params: [_p(5), const IndicatorParam('vFactor', 'Volume factor', 0.7, min: 0, max: 1, step: 0.05)],
      create: (v) => T3(period: _i(v, _period), vFactor: _d(v, 'vFactor')),
    ),
    IndicatorSpec(
      id: 'mcginley',
      title: 'McGinley Dynamic',
      group: IndicatorGroup.movingAverages,
      keywords: 'MA',
      params: [_p(14)],
      create: (v) => McGinley(_i(v, _period)),
    ),
    IndicatorSpec(
      id: 'kama',
      title: 'Kaufman Adaptive Moving Average',
      group: IndicatorGroup.movingAverages,
      keywords: 'KAMA MA',
      params: [_p(10), const IndicatorParam('fast', 'Fast length', 2), const IndicatorParam('slow', 'Slow length', 30)],
      create: (v) => Kama(period: _i(v, _period), fast: _i(v, 'fast'), slow: _i(v, 'slow')),
    ),
    IndicatorSpec(
      id: 'envelope',
      title: 'Envelope',
      group: IndicatorGroup.movingAverages,
      keywords: 'MA bands',
      params: [_p(20), const IndicatorParam('percent', 'Percent', 2.5, min: 0.1, max: 50, step: 0.1)],
      create: (v) => Envelope(period: _i(v, _period), percent: _d(v, 'percent')),
    ),
    IndicatorSpec(
      id: 'alligator',
      title: 'Williams Alligator',
      group: IndicatorGroup.movingAverages,
      keywords: 'Bill Williams',
      create: (_) => Alligator(),
    ),
    // ---- bands, clouds, stops ----
    IndicatorSpec(
      id: 'bollinger',
      title: 'Bollinger Bands',
      group: IndicatorGroup.bands,
      keywords: 'BB BOLL',
      params: [_p(20), const IndicatorParam('multiplier', 'StdDev', 2, min: 0.1, max: 10, step: 0.1)],
      create: (v) => Bollinger(period: _i(v, _period), multiplier: _d(v, 'multiplier')),
    ),
    IndicatorSpec(
      id: 'keltner',
      title: 'Keltner Channels',
      group: IndicatorGroup.bands,
      keywords: 'KC',
      params: [
        const IndicatorParam('emaPeriod', 'EMA length', 20),
        const IndicatorParam('atrPeriod', 'ATR length', 10),
        const IndicatorParam('multiplier', 'Multiplier', 2, min: 0.1, max: 10, step: 0.1),
      ],
      create: (v) =>
          Keltner(emaPeriod: _i(v, 'emaPeriod'), atrPeriod: _i(v, 'atrPeriod'), multiplier: _d(v, 'multiplier')),
    ),
    IndicatorSpec(
      id: 'donchian',
      title: 'Donchian Channels',
      group: IndicatorGroup.bands,
      keywords: 'DC',
      params: [_p(20)],
      create: (v) => Donchian(period: _i(v, _period)),
    ),
    IndicatorSpec(
      id: 'ichimoku',
      title: 'Ichimoku Cloud',
      group: IndicatorGroup.bands,
      keywords: 'kumo',
      params: [
        const IndicatorParam('conversion', 'Conversion line', 9),
        const IndicatorParam('base', 'Base line', 26),
        const IndicatorParam('spanB', 'Leading span B', 52),
        const IndicatorParam('displacement', 'Displacement', 26),
      ],
      create: (v) => Ichimoku(
        conversion: _i(v, 'conversion'),
        base: _i(v, 'base'),
        spanB: _i(v, 'spanB'),
        displacement: _i(v, 'displacement'),
      ),
    ),
    IndicatorSpec(
      id: 'supertrend',
      title: 'Supertrend',
      group: IndicatorGroup.bands,
      params: [_p(10, 'ATR length'), const IndicatorParam('multiplier', 'Factor', 3, min: 0.1, max: 20, step: 0.1)],
      create: (v) => Supertrend(period: _i(v, _period), multiplier: _d(v, 'multiplier')),
    ),
    IndicatorSpec(
      id: 'psar',
      title: 'Parabolic SAR',
      group: IndicatorGroup.bands,
      keywords: 'SAR stop and reverse',
      params: [
        const IndicatorParam('initialAf', 'Start', 0.02, min: 0.001, max: 1, step: 0.01),
        const IndicatorParam('stepAf', 'Increment', 0.02, min: 0.001, max: 1, step: 0.01),
        const IndicatorParam('maxAf', 'Maximum', 0.2, min: 0.01, max: 1, step: 0.01),
      ],
      create: (v) => ParabolicSar(initialAf: _d(v, 'initialAf'), stepAf: _d(v, 'stepAf'), maxAf: _d(v, 'maxAf')),
    ),
    IndicatorSpec(
      id: 'chandelier',
      title: 'Chandelier Exit',
      group: IndicatorGroup.bands,
      params: [_p(22, 'ATR length'), const IndicatorParam('multiplier', 'Multiplier', 3, min: 0.1, max: 20, step: 0.1)],
      create: (v) => ChandelierExit(period: _i(v, _period), multiplier: _d(v, 'multiplier')),
    ),
    // ---- momentum ----
    IndicatorSpec(
      id: 'rsi',
      title: 'Relative Strength Index',
      group: IndicatorGroup.momentum,
      keywords: 'RSI',
      params: [_p(14)],
      create: (v) => Rsi(_i(v, _period)),
    ),
    IndicatorSpec(
      id: 'stochrsi',
      title: 'Stochastic RSI',
      group: IndicatorGroup.momentum,
      keywords: 'StochRSI',
      params: [
        const IndicatorParam('rsiPeriod', 'RSI length', 14),
        const IndicatorParam('stochPeriod', 'Stochastic length', 14),
        const IndicatorParam('k', 'K', 3),
        const IndicatorParam('d', 'D', 3),
      ],
      create: (v) =>
          StochRsi(rsiPeriod: _i(v, 'rsiPeriod'), stochPeriod: _i(v, 'stochPeriod'), k: _i(v, 'k'), d: _i(v, 'd')),
    ),
    IndicatorSpec(
      id: 'stochastic',
      title: 'Stochastic',
      group: IndicatorGroup.momentum,
      keywords: 'KD stoch',
      params: [
        _p(14, '%K length'),
        const IndicatorParam('smoothK', '%K smoothing', 3),
        const IndicatorParam('d', '%D', 3),
      ],
      create: (v) => Stochastic(period: _i(v, _period), smoothK: _i(v, 'smoothK'), d: _i(v, 'd')),
    ),
    IndicatorSpec(
      id: 'macd',
      title: 'MACD',
      group: IndicatorGroup.momentum,
      keywords: 'moving average convergence divergence',
      params: [
        const IndicatorParam('fast', 'Fast length', 12),
        const IndicatorParam('slow', 'Slow length', 26),
        const IndicatorParam('signal', 'Signal', 9),
      ],
      create: (v) => Macd(fast: _i(v, 'fast'), slow: _i(v, 'slow'), signal: _i(v, 'signal')),
    ),
    IndicatorSpec(
      id: 'ppo',
      title: 'Percentage Price Oscillator',
      group: IndicatorGroup.momentum,
      keywords: 'PPO',
      params: [
        const IndicatorParam('fast', 'Fast length', 12),
        const IndicatorParam('slow', 'Slow length', 26),
        const IndicatorParam('signal', 'Signal', 9),
      ],
      create: (v) => Ppo(fast: _i(v, 'fast'), slow: _i(v, 'slow'), signal: _i(v, 'signal')),
    ),
    IndicatorSpec(
      id: 'williamsr',
      title: 'Williams %R',
      group: IndicatorGroup.momentum,
      keywords: 'WPR %R',
      params: [_p(14)],
      create: (v) => WilliamsR(_i(v, _period)),
    ),
    IndicatorSpec(
      id: 'cci',
      title: 'Commodity Channel Index',
      group: IndicatorGroup.momentum,
      keywords: 'CCI',
      params: [_p(20)],
      create: (v) => Cci(_i(v, _period)),
    ),
    IndicatorSpec(
      id: 'roc',
      title: 'Rate of Change',
      group: IndicatorGroup.momentum,
      keywords: 'ROC',
      params: [_p(12)],
      create: (v) => Roc(_i(v, _period)),
    ),
    IndicatorSpec(
      id: 'momentum',
      title: 'Momentum',
      group: IndicatorGroup.momentum,
      keywords: 'MOM',
      params: [_p(10)],
      create: (v) => Momentum(_i(v, _period)),
    ),
    IndicatorSpec(
      id: 'cmo',
      title: 'Chande Momentum Oscillator',
      group: IndicatorGroup.momentum,
      keywords: 'CMO',
      params: [_p(9)],
      create: (v) => Cmo(_i(v, _period)),
    ),
    IndicatorSpec(
      id: 'tsi',
      title: 'True Strength Index',
      group: IndicatorGroup.momentum,
      keywords: 'TSI',
      params: [
        const IndicatorParam('long', 'Long length', 25),
        const IndicatorParam('short', 'Short length', 13),
        const IndicatorParam('signal', 'Signal', 13),
      ],
      create: (v) => Tsi(long: _i(v, 'long'), short: _i(v, 'short'), signal: _i(v, 'signal')),
    ),
    IndicatorSpec(
      id: 'trix',
      title: 'TRIX',
      group: IndicatorGroup.momentum,
      params: [_p(18), const IndicatorParam('signal', 'Signal', 9)],
      create: (v) => Trix(period: _i(v, _period), signal: _i(v, 'signal')),
    ),
    IndicatorSpec(
      id: 'ultimate',
      title: 'Ultimate Oscillator',
      group: IndicatorGroup.momentum,
      keywords: 'UO',
      params: [
        const IndicatorParam('fast', 'Fast length', 7),
        const IndicatorParam('mid', 'Middle length', 14),
        const IndicatorParam('slow', 'Slow length', 28),
      ],
      create: (v) => UltimateOscillator(fast: _i(v, 'fast'), mid: _i(v, 'mid'), slow: _i(v, 'slow')),
    ),
    IndicatorSpec(
      id: 'awesome',
      title: 'Awesome Oscillator',
      group: IndicatorGroup.momentum,
      keywords: 'AO Bill Williams',
      create: (_) => AwesomeOscillator(),
    ),
    IndicatorSpec(
      id: 'accelerator',
      title: 'Accelerator Oscillator',
      group: IndicatorGroup.momentum,
      keywords: 'AC Bill Williams',
      create: (_) => AcceleratorOscillator(),
    ),
    IndicatorSpec(
      id: 'dpo',
      title: 'Detrended Price Oscillator',
      group: IndicatorGroup.momentum,
      keywords: 'DPO',
      params: [_p(21)],
      create: (v) => Dpo(_i(v, _period)),
    ),
    IndicatorSpec(id: 'coppock', title: 'Coppock Curve', group: IndicatorGroup.momentum, create: (_) => Coppock()),
    IndicatorSpec(
      id: 'kst',
      title: 'Know Sure Thing',
      group: IndicatorGroup.momentum,
      keywords: 'KST',
      create: (_) => Kst(),
    ),
    IndicatorSpec(
      id: 'fisher',
      title: 'Fisher Transform',
      group: IndicatorGroup.momentum,
      params: [_p(9)],
      create: (v) => FisherTransform(_i(v, _period)),
    ),
    IndicatorSpec(
      id: 'connorsrsi',
      title: 'Connors RSI',
      group: IndicatorGroup.momentum,
      keywords: 'CRSI',
      create: (_) => ConnorsRsi(),
    ),
    IndicatorSpec(
      id: 'rvi',
      title: 'Relative Vigor Index',
      group: IndicatorGroup.momentum,
      keywords: 'RVGI RVI',
      params: [_p(10)],
      create: (v) => Rvi(_i(v, _period)),
    ),
    IndicatorSpec(
      id: 'smi',
      title: 'Stochastic Momentum Index',
      group: IndicatorGroup.momentum,
      keywords: 'SMI',
      params: [_p(10), const IndicatorParam('smooth', 'Smoothing', 3), const IndicatorParam('signal', 'Signal', 10)],
      create: (v) => Smi(period: _i(v, _period), smooth: _i(v, 'smooth'), signal: _i(v, 'signal')),
    ),
    // ---- trend ----
    IndicatorSpec(
      id: 'adx',
      title: 'Average Directional Index',
      group: IndicatorGroup.trend,
      keywords: 'ADX DMI DI',
      params: [_p(14)],
      create: (v) => Adx(period: _i(v, _period)),
    ),
    IndicatorSpec(
      id: 'aroon',
      title: 'Aroon',
      group: IndicatorGroup.trend,
      params: [_p(25)],
      create: (v) => Aroon(period: _i(v, _period)),
    ),
    IndicatorSpec(
      id: 'vortex',
      title: 'Vortex Indicator',
      group: IndicatorGroup.trend,
      keywords: 'VI',
      params: [_p(14)],
      create: (v) => Vortex(_i(v, _period)),
    ),
    IndicatorSpec(
      id: 'elderray',
      title: 'Elder Ray',
      group: IndicatorGroup.trend,
      keywords: 'bull bear power',
      params: [_p(13)],
      create: (v) => ElderRay(_i(v, _period)),
    ),
    IndicatorSpec(
      id: 'bop',
      title: 'Balance of Power',
      group: IndicatorGroup.trend,
      keywords: 'BOP',
      params: [_p(14)],
      create: (v) => BalanceOfPower(_i(v, _period)),
    ),
    IndicatorSpec(
      id: 'choppiness',
      title: 'Choppiness Index',
      group: IndicatorGroup.trend,
      keywords: 'CHOP',
      params: [_p(14)],
      create: (v) => Choppiness(_i(v, _period)),
    ),
    IndicatorSpec(id: 'massindex', title: 'Mass Index', group: IndicatorGroup.trend, create: (_) => MassIndex()),
    IndicatorSpec(
      id: 'sinewave',
      title: 'Ehlers Sine Wave',
      group: IndicatorGroup.trend,
      keywords: 'cycle',
      create: (_) => SineWave(),
    ),
    IndicatorSpec(
      id: 'ebsw',
      title: 'Even Better Sinewave',
      group: IndicatorGroup.trend,
      keywords: 'Ehlers cycle EBSW',
      params: [const IndicatorParam('duration', 'Duration', 40)],
      create: (v) => EvenBetterSinewave(_i(v, 'duration')),
    ),
    // ---- volume ----
    IndicatorSpec(
      id: 'vwap',
      title: 'VWAP',
      group: IndicatorGroup.volume,
      keywords: 'volume weighted average price',
      needsVolume: true,
      create: (_) => Vwap(),
    ),
    IndicatorSpec(
      id: 'obv',
      title: 'On Balance Volume',
      group: IndicatorGroup.volume,
      keywords: 'OBV',
      needsVolume: true,
      create: (_) => Obv(),
    ),
    IndicatorSpec(
      id: 'mfi',
      title: 'Money Flow Index',
      group: IndicatorGroup.volume,
      keywords: 'MFI',
      needsVolume: true,
      params: [_p(14)],
      create: (v) => Mfi(_i(v, _period)),
    ),
    IndicatorSpec(
      id: 'cmf',
      title: 'Chaikin Money Flow',
      group: IndicatorGroup.volume,
      keywords: 'CMF',
      needsVolume: true,
      params: [_p(20)],
      create: (v) => Cmf(_i(v, _period)),
    ),
    IndicatorSpec(
      id: 'ad',
      title: 'Accumulation / Distribution',
      group: IndicatorGroup.volume,
      keywords: 'A/D ADL',
      needsVolume: true,
      create: (_) => AccumulationDistribution(),
    ),
    IndicatorSpec(
      id: 'chaikinosc',
      title: 'Chaikin Oscillator',
      group: IndicatorGroup.volume,
      needsVolume: true,
      create: (_) => ChaikinOscillator(),
    ),
    IndicatorSpec(
      id: 'pvt',
      title: 'Price Volume Trend',
      group: IndicatorGroup.volume,
      keywords: 'PVT',
      needsVolume: true,
      create: (_) => PriceVolumeTrend(),
    ),
    IndicatorSpec(
      id: 'nvipvi',
      title: 'Negative / Positive Volume Index',
      group: IndicatorGroup.volume,
      keywords: 'NVI PVI',
      needsVolume: true,
      create: (_) => VolumeIndexes(),
    ),
    IndicatorSpec(
      id: 'klinger',
      title: 'Klinger Oscillator',
      group: IndicatorGroup.volume,
      keywords: 'KVO',
      needsVolume: true,
      create: (_) => Klinger(),
    ),
    IndicatorSpec(
      id: 'force',
      title: 'Elder Force Index',
      group: IndicatorGroup.volume,
      keywords: 'EFI',
      needsVolume: true,
      params: [_p(13)],
      create: (v) => ForceIndex(_i(v, _period)),
    ),
    IndicatorSpec(
      id: 'eom',
      title: 'Ease of Movement',
      group: IndicatorGroup.volume,
      keywords: 'EOM EMV',
      needsVolume: true,
      params: [_p(14)],
      create: (v) => EaseOfMovement(_i(v, _period)),
    ),
    IndicatorSpec(
      id: 'volosc',
      title: 'Volume Oscillator',
      group: IndicatorGroup.volume,
      needsVolume: true,
      params: [const IndicatorParam('fast', 'Fast length', 5), const IndicatorParam('slow', 'Slow length', 10)],
      create: (v) => VolumeOscillator(fast: _i(v, 'fast'), slow: _i(v, 'slow')),
    ),
    IndicatorSpec(
      id: 'volsma',
      title: 'Volume Moving Average',
      group: IndicatorGroup.volume,
      keywords: 'volume MA',
      needsVolume: true,
      params: [_p(20)],
      create: (v) => VolumeSma(_i(v, _period)),
    ),
    // ---- volatility ----
    IndicatorSpec(
      id: 'atr',
      title: 'Average True Range',
      group: IndicatorGroup.volatility,
      keywords: 'ATR',
      params: [_p(14)],
      create: (v) => Atr(_i(v, _period)),
    ),
    IndicatorSpec(
      id: 'stdev',
      title: 'Standard Deviation',
      group: IndicatorGroup.volatility,
      keywords: 'StdDev',
      params: [_p(20)],
      create: (v) => StandardDeviation(_i(v, _period)),
    ),
    IndicatorSpec(
      id: 'hv',
      title: 'Historical Volatility',
      group: IndicatorGroup.volatility,
      keywords: 'HV',
      params: [_p(10), const IndicatorParam('barsPerYear', 'Bars per year', 252, max: 100000)],
      create: (v) => HistoricalVolatility(period: _i(v, _period), barsPerYear: _i(v, 'barsPerYear')),
    ),
    IndicatorSpec(
      id: 'bbpercentb',
      title: 'Bollinger Bands %B',
      group: IndicatorGroup.volatility,
      keywords: '%B BB',
      params: [_p(20), const IndicatorParam('multiplier', 'StdDev', 2, min: 0.1, max: 10, step: 0.1)],
      create: (v) => BollingerPercentB(period: _i(v, _period), multiplier: _d(v, 'multiplier')),
    ),
    IndicatorSpec(
      id: 'bbwidth',
      title: 'Bollinger BandWidth',
      group: IndicatorGroup.volatility,
      keywords: 'BBW BB',
      params: [_p(20), const IndicatorParam('multiplier', 'StdDev', 2, min: 0.1, max: 10, step: 0.1)],
      create: (v) => BollingerWidth(period: _i(v, _period), multiplier: _d(v, 'multiplier')),
    ),
    IndicatorSpec(
      id: 'ulcer',
      title: 'Ulcer Index',
      group: IndicatorGroup.volatility,
      params: [_p(14)],
      create: (v) => UlcerIndex(_i(v, _period)),
    ),
  ];
}
