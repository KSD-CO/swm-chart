import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:swm_chart/swm_chart.dart';

import 'main.dart' show FakeFeed, sma;

enum ToolsMode { drawings, overlays }

/// Drawing tools and analysis overlays on an hourly chart.
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

  ChartController? _chart;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now().toUtc().millisecondsSinceEpoch ~/ 1000;
    _bars = FakeFeed(interval: _interval).history(now - now % _interval, 30000, _count);
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
    final candles = chart.addCandlestickSeries(const CandlestickSeriesOptions(borderVisible: false))..setData(_bars);
    chart.timeScale().fitContent(); // applied once laid out
    _chart = chart;
    switch (_mode) {
      case ToolsMode.drawings:
        _addDrawings(chart);
      case ToolsMode.overlays:
        _addOverlays(chart, candles);
    }
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
          child: SegmentedButton<ToolsMode>(
            segments: const [
              ButtonSegment(value: ToolsMode.drawings, label: Text('Drawings'), icon: Icon(Icons.draw)),
              ButtonSegment(value: ToolsMode.overlays, label: Text('Overlays'), icon: Icon(Icons.layers)),
            ],
            selected: {_mode},
            onSelectionChanged: (s) => mode = s.first,
          ),
        ),
        Expanded(
          child: SwmChart(key: ValueKey(_mode), controller: _chart!),
        ),
      ],
    );
  }
}
