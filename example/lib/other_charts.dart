import 'package:flutter/material.dart';
import 'package:swm_chart/swm_chart.dart';

/// US Treasury-like yield curve: time is the maturity in months.
class YieldCurveScreen extends StatefulWidget {
  const YieldCurveScreen({super.key});

  @override
  State<YieldCurveScreen> createState() => _YieldCurveScreenState();
}

class _YieldCurveScreenState extends State<YieldCurveScreen> {
  late final ChartController _chart = ChartController.yieldCurve(
    yieldCurve: const YieldCurveOptions(minimumTimeRange: 360),
  );

  static const _maturities = [1, 2, 3, 6, 12, 24, 36, 60, 84, 120, 240, 360];
  static const _today = [5.52, 5.50, 5.46, 5.33, 5.05, 4.72, 4.53, 4.36, 4.33, 4.29, 4.50, 4.40];
  static const _yearAgo = [4.70, 4.75, 4.80, 4.95, 4.85, 4.40, 4.17, 3.94, 3.89, 3.82, 4.02, 3.85];

  @override
  void initState() {
    super.initState();
    _chart.addAreaSeries(const AreaSeriesOptions(
      lineColor: Color(0xFF2962FF),
      topColor: Color(0x552962FF),
      bottomColor: Color(0x002962FF),
      lineWidth: 2,
      lineType: LineType.curved,
      pointMarkersVisible: true,
      title: 'Today',
    )).setData([for (var i = 0; i < _maturities.length; i++) AreaData(time: _maturities[i], value: _today[i])]);
    _chart.addLineSeries(const LineSeriesOptions(
      color: Color(0xFFFF9800),
      lineWidth: 2,
      lineStyle: LineStyle.dashed,
      lineType: LineType.curved,
      title: '1Y ago',
    )).setData([for (var i = 0; i < _maturities.length; i++) LineData(time: _maturities[i], value: _yearAgo[i])]);
    _chart.timeScale().fitContent(); // applied once the chart is laid out
  }

  @override
  void dispose() {
    _chart.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => SwmChart(controller: _chart);
}

/// Options chain: time is the strike price.
class OptionsChainScreen extends StatefulWidget {
  const OptionsChainScreen({super.key});

  @override
  State<OptionsChainScreen> createState() => _OptionsChainScreenState();
}

class _OptionsChainScreenState extends State<OptionsChainScreen> {
  late final ChartController _chart = ChartController.options(precision: 0);

  @override
  void initState() {
    super.initState();
    const spot = 100.0;
    final strikes = [for (var k = 70.0; k <= 130; k += 2.5) k];
    // Implied volatility smile and open interest.
    _chart.addLineSeries(const LineSeriesOptions(color: Color(0xFF7E57C2), lineWidth: 2, title: 'IV %')).setData([
      for (final k in strikes) LineData(time: k, value: 18 + 0.02 * (k - spot) * (k - spot) / 2.5),
    ]);
    _chart.addHistogramSeries(
      const HistogramSeriesOptions(priceScaleId: 'oi', priceFormat: PriceFormat.volume(), lastValueVisible: false, priceLineVisible: false),
    ).setData([
      for (final k in strikes)
        HistogramData(
          time: k,
          value: 5000 / (1 + ((k - spot) / 8) * ((k - spot) / 8)),
          color: k < spot ? const Color(0x8026A69A) : const Color(0x80EF5350),
        ),
    ]);
    _chart.priceScale('oi').applyOptions(const PriceScaleOptions(scaleMargins: ScaleMargins(top: 0.7, bottom: 0)));
    _chart.timeScale().fitContent(); // applied once the chart is laid out
  }

  @override
  void dispose() {
    _chart.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => SwmChart(controller: _chart);
}
