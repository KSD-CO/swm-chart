import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:swm_chart/swm_chart.dart';

import 'main.dart' show FakeFeed, sma;

enum ToolsMode {
  drawings('Drawings', Icons.draw),
  overlays('Overlays', Icons.layers),
  indicators('Indicators', Icons.insights),
  orders('Orders', Icons.swap_vert),
  heikinAshi('Heikin-Ashi', Icons.candlestick_chart),
  renko('Renko', Icons.view_week),
  compare('Compare', Icons.compare_arrows);

  const ToolsMode(this.label, this.icon);

  final String label;
  final IconData icon;
}

/// Drawing tools, overlays, indicators, trading lines, derived chart types
/// and symbol comparison on an hourly chart.
class ToolsScreen extends StatefulWidget {
  const ToolsScreen({super.key, this.mode = ToolsMode.drawings});

  final ToolsMode mode;

  @override
  State<ToolsScreen> createState() => ToolsScreenState();
}

class ToolsScreenState extends State<ToolsScreen> {
  static const _interval = 3600;
  static const _count = 90;

  late ToolsMode _mode = widget.mode;
  late final List<CandlestickData> _bars;

  /// A longer history for indicators, chart types and comparisons.
  late final List<CandlestickData> _long;

  ChartController? _chart;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now().toUtc().millisecondsSinceEpoch ~/ 1000;
    _long = FakeFeed(interval: _interval).history(now - now % _interval, 30000, 200);
    _bars = _long.sublist(_long.length - _count);
    _build();
  }

  ToolsMode get mode => _mode;

  set mode(ToolsMode value) {
    if (value == _mode) return;
    setState(() {
      _mode = value;
      _build();
    });
  }

  void _build() {
    _chart?.dispose();
    final chart = ChartController(
      options: const ChartOptions(
        timeScale: TimeScaleOptions(timeVisible: true, secondsVisible: false, rightOffset: 4),
      ),
    );
    final data = switch (_mode) {
      ToolsMode.drawings || ToolsMode.overlays => _bars,
      ToolsMode.heikinAshi => heikinAshi(_long),
      ToolsMode.renko => renko(_long, boxSize: 50),
      _ => _long,
    };
    final candles = chart.addCandlestickSeries(const CandlestickSeriesOptions(borderVisible: false))..setData(data);
    chart.timeScale().fitContent(); // applied once laid out
    _chart = chart;
    switch (_mode) {
      case ToolsMode.drawings:
        _addDrawings(chart);
      case ToolsMode.overlays:
        _addOverlays(chart, candles);
      case ToolsMode.indicators:
        _addIndicators(chart, candles);
      case ToolsMode.orders:
        _addOrders(chart, candles);
      case ToolsMode.heikinAshi:
        createLegend(chart, const LegendOptions(title: 'BTC/USD · 1h · Heikin-Ashi'));
      case ToolsMode.renko:
        createLegend(chart, const LegendOptions(title: 'BTC/USD · Renko 50', showChange: false));
      case ToolsMode.compare:
        _addComparisons(chart);
    }
  }

  // ---- indicators ----

  void _addIndicators(ChartController chart, CandlestickSeriesApi candles) {
    chart.addIndicator(Bollinger(), source: candles);
    chart.addIndicator(Ema(50, color: const Color(0xFFE91E63)), source: candles);
    chart.addIndicator(Rsi(14), source: candles);
    chart.addIndicator(Macd(), source: candles);
    chart.panes()[0].setStretchFactor(2.2);
    createLegend(chart, const LegendOptions(title: 'BTC/USD · 1h'));
    // Show the legend following the crosshair.
    final bar = _long[_long.length - 30];
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_chart == chart) chart.setCrosshairPosition(bar.close, bar.time, candles);
    });
  }

  // ---- trading lines ----

  void _addOrders(ChartController chart, CandlestickSeriesApi candles) {
    final last = _long.last.close;
    double at(double pct) => (last * (1 + pct / 100) * 100).roundToDouble() / 100;
    TradingLines(candles, onAlert: (alert, price) => debugPrint('Alert ${alert.id} at $price'))
      ..add(TradingLine(id: 'pos', kind: TradingLineKind.position, price: at(-0.9), quantity: 0.5))
      ..add(TradingLine(id: 'tp', kind: TradingLineKind.takeProfit, price: at(1.6), quantity: 0.5))
      ..add(TradingLine(id: 'sl', kind: TradingLineKind.stopLoss, price: at(-2.2), quantity: 0.5))
      ..add(TradingLine(id: 'buy', kind: TradingLineKind.order, price: at(-1.6), quantity: 0.25))
      ..add(TradingLine(id: 'alert', kind: TradingLineKind.alert, price: at(0.8), label: 'Alert ↑'));
    createLegend(chart, const LegendOptions(title: 'BTC/USD · 1h'));
  }

  // ---- comparison ----

  /// Another symbol on the same hours: a seeded random walk.
  List<LineData> _symbol(int seed, double start, double drift) {
    final r = math.Random(seed);
    var v = start;
    return [
      for (final b in _long)
        LineData(time: b.time, value: v = math.max(1, v * (1 + (r.nextDouble() - 0.5 + drift) * 0.012))),
    ];
  }

  void _addComparisons(ChartController chart) {
    chart.addComparison(_symbol(3, 2400, 0.06), title: 'ETH');
    chart.addComparison(_symbol(5, 150, -0.04), title: 'SOL');
    createLegend(chart, const LegendOptions(title: 'BTC/USD vs ETH, SOL · 1h'));
  }

  // ---- drawings ----

  /// Index of the lowest low / highest high in [from, to).
  int _extreme(int from, int to, {required bool high}) {
    var best = from;
    for (var i = from; i < to; i++) {
      final better = high ? _bars[i].high > _bars[best].high : _bars[i].low < _bars[best].low;
      if (better) best = i;
    }
    return best;
  }

  DrawingAnchor _at(int i, {required bool high}) => DrawingAnchor(i.toDouble(), high ? _bars[i].high : _bars[i].low);

  void _addDrawings(ChartController chart) {
    // The editor attaches its layer to the chart and handles the pointer.
    final editor = DrawingEditor(chart);
    final n = _bars.length;
    final low1 = _extreme(n - 54, n - 34, high: false);
    final high1 = _extreme(n - 34, n - 14, high: true);
    final low2 = _extreme(n - 14, n, high: false);
    // The big swing down, for the retracement.
    final peak = _extreme(0, n - 40, high: true);
    final box = _bars.sublist(n - 12, n - 1);
    final boxHigh = box.map((b) => b.high).reduce(math.max);
    final boxLow = box.map((b) => b.low).reduce(math.min);
    const blue = Color(0xFF2962FF);

    editor
      ..add(FibRetracementDrawing(id: 'fib', anchors: [_at(peak, high: true), _at(low1, high: false)]))
      ..add(
        TrendLineDrawing(
          id: 'trend',
          anchors: [_at(low1, high: false), _at(low2, high: false)],
          extendRight: true,
          style: const DrawingStyle(color: blue, lineWidth: 2),
        ),
      )
      ..add(
        RectangleDrawing(
          id: 'range',
          anchors: [DrawingAnchor((n - 12).toDouble(), boxHigh), DrawingAnchor((n - 2).toDouble(), boxLow)],
          style: const DrawingStyle(color: Color(0xFFFF9800), fillColor: Color(0x22FF9800)),
        ),
      )
      ..add(
        HorizontalLineDrawing(
          id: 'resistance',
          anchors: [DrawingAnchor((n - 1).toDouble(), _bars[high1].high)],
          label: 'Resistance',
          style: const DrawingStyle(color: Color(0xFFF23645), lineStyle: LineStyle.dashed),
        ),
      )
      ..add(
        PathDrawing.elliottImpulse(
          id: 'elliott',
          anchors: [
            for (final (from, to, high) in [
              (0, 4, false),
              (4, 10, true),
              (10, 14, false),
              (14, 22, true),
              (22, 26, false),
              (26, 34, true),
            ])
              _at(_extreme(from, to, high: high), high: high),
          ],
          style: const DrawingStyle(color: Color(0xFF7E57C2)),
        ),
      )
      ..add(
        TextDrawing(
          id: 'note',
          anchors: [DrawingAnchor((n - 24).toDouble(), _bars[low1].low - (_bars[peak].high - _bars[low1].low) * 0.08)],
          text: 'Breakout?',
          style: const DrawingStyle(color: Colors.white, fontSize: 12),
          backgroundColor: blue,
        ),
      )
      ..select('trend');
  }

  // ---- overlays ----

  void _addOverlays(ChartController chart, CandlestickSeriesApi candles) {
    final closes = [for (final b in _bars) b.close];
    final mid = sma(closes, 20);

    // Bollinger bands (20, 2).
    final band = <BandPoint>[];
    for (var i = 19; i < _bars.length; i++) {
      final window = closes.sublist(i - 19, i + 1);
      final mean = mid[i]!;
      final sd = math.sqrt(window.map((c) => (c - mean) * (c - mean)).reduce((a, b) => a + b) / 20);
      band.add(BandPoint(time: _bars[i].time, upper: mean + 2 * sd, lower: mean - 2 * sd));
    }
    candles.attachPrimitive(
      BandFillPrimitive(
        points: band,
        options: const BandFillOptions(
          fillColor: Color(0x1A2962FF),
          upperLineColor: Color(0xFF2962FF),
          lowerLineColor: Color(0xFF2962FF),
        ),
      ),
    );
    chart
        .addLineSeries(
          const LineSeriesOptions(
            color: Color(0xFFFF9800),
            lineWidth: 1,
            lastValueVisible: false,
            priceLineVisible: false,
            crosshairMarkerVisible: false,
          ),
        )
        .setData([
          for (var i = 0; i < _bars.length; i++)
            if (mid[i] != null) LineData(time: _bars[i].time, value: mid[i]!),
        ]);

    // Classic pivots from the previous 24 bars.
    final prev = _bars.sublist(_bars.length - 48, _bars.length - 24);
    final h = prev.map((b) => b.high).reduce(math.max);
    final l = prev.map((b) => b.low).reduce(math.min);
    final p = (h + l + prev.last.close) / 3;
    final from = _bars[_bars.length - 24].time;
    PriceLevel level(double price, String label, Color color) => PriceLevel(
      price: price,
      label: label,
      color: color,
      lineStyle: LineStyle.dashed,
      fromTime: from,
      axisLabel: true,
      id: label,
    );
    candles.attachPrimitive(
      PriceLevelsPrimitive(
        levels: [
          level(2 * p - l, 'R1', const Color(0xFFF23645)),
          level(p, 'P', const Color(0xFF787B86)),
          level(2 * p - h, 'S1', const Color(0xFF089981)),
        ],
      ),
    );

    // Volume profile of the chart: 24 price bins, split by bar direction.
    final lo = _bars.map((b) => b.low).reduce(math.min);
    final hi = _bars.map((b) => b.high).reduce(math.max);
    const binCount = 24;
    final step = (hi - lo) / binCount;
    final volume = List<double>.filled(binCount, 0), up = List<double>.filled(binCount, 0);
    final random = math.Random(7);
    for (final b in _bars) {
      final bin = ((b.close - lo) / step).floor().clamp(0, binCount - 1);
      final v = 500 + random.nextDouble() * 1500;
      volume[bin] += v;
      if (b.isUp) up[bin] += v;
    }
    candles.attachPrimitive(
      VolumeProfilePrimitive(
        bins: [
          for (var i = 0; i < binCount; i++)
            VolumeProfileBin(low: lo + i * step, high: lo + (i + 1) * step, volume: volume[i], upVolume: up[i]),
        ],
        options: const VolumeProfileOptions(widthFraction: 0.25),
      ),
    );
  }

  @override
  void dispose() {
    _chart?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.all(8),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                for (final m in ToolsMode.values)
                  Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: ChoiceChip(
                      avatar: Icon(m.icon, size: 16),
                      label: Text(m.label),
                      selected: m == _mode,
                      onSelected: (_) => mode = m,
                    ),
                  ),
              ],
            ),
          ),
        ),
        Expanded(
          child: SwmChart(key: ValueKey(_mode), controller: _chart!),
        ),
      ],
    );
  }
}
