import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:swm_chart/swm_chart.dart';

import 'main.dart' show FakeFeed, sma;

enum ToolsMode {
  drawings('Drawings', Icons.draw),
  overlays('Overlays', Icons.layers),
  indicators('Indicators', Icons.insights),
  orders('Orders', Icons.swap_vert),
  trend('Trend', Icons.trending_up),
  analysis('Analysis', Icons.auto_graph),
  sessions('Sessions', Icons.align_horizontal_left),
  forecast('Forecast', Icons.query_stats),
  heikinAshi('Heikin-Ashi', Icons.candlestick_chart),
  renko('Renko', Icons.view_week),
  compare('Compare', Icons.compare_arrows),
  sync('Sync', Icons.link);

  const ToolsMode(this.label, this.icon);

  final String label;
  final IconData icon;
}

/// Drawing tools, overlays, indicators, technical analysis, trading lines,
/// derived chart types, symbol comparison and synced charts on an hourly
/// chart.
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

  /// The second chart of [ToolsMode.sync].
  ChartController? _chart2;
  CrosshairSync? _sync;

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
    _sync?.dispose();
    _sync = null;
    _chart?.dispose();
    _chart2?.dispose();
    _chart2 = null;
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
      case ToolsMode.trend:
        _addTrend(chart, candles);
      case ToolsMode.analysis:
        _addAnalysis(chart, candles);
      case ToolsMode.sessions:
        _addSessions(chart, candles);
      case ToolsMode.forecast:
        _addForecast(chart, candles);
      case ToolsMode.sync:
        _addSync(chart, candles);
    }
  }

  /// Crosshair on the bar [back] bars before the last, once laid out.
  void _pointAt(ChartController chart, SeriesApi series, int back) {
    final bar = _long[_long.length - back];
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_chart == chart) chart.setCrosshairPosition(bar.close, bar.time, series);
    });
  }

  /// [_long] as `Ta` bars, with a made-up volume.
  List<TaPoint> get _taBars {
    final r = math.Random(11);
    return [
      for (final b in _long)
        TaPoint(
          date: DateTime.fromMillisecondsSinceEpoch(b.time.toInt() * 1000, isUtc: true),
          open: b.open,
          high: b.high,
          low: b.low,
          close: b.close,
          volume: 200 + r.nextDouble() * 800 + (b.high - b.low) * 4,
        ),
    ];
  }

  // ---- more indicators, tooltip ----

  void _addTrend(ChartController chart, CandlestickSeriesApi candles) {
    chart.addIndicator(Supertrend(), source: candles);
    chart.addIndicator(Hma(21), source: candles);
    chart.addIndicator(Adx(), source: candles);
    chart.addIndicator(StochRsi(), source: candles);
    chart.panes()[0].setStretchFactor(2.2);
    createLegend(chart, const LegendOptions(mode: LegendMode.tooltip));
    _pointAt(chart, candles, 120);
  }

  // ---- technical analysis ----

  void _addAnalysis(ChartController chart, CandlestickSeriesApi candles) {
    final bars = _taBars;
    final times = [for (final b in _long) b.time];

    // ZigZag swings of 1% or more.
    final zigzag = Ta.zigzag(bars, deviation: 1);
    chart
        .addLineSeries(
          const LineSeriesOptions(
            title: 'ZigZag 1%',
            color: Color(0x99787B86),
            lineWidth: 1,
            lastValueVisible: false,
            priceLineVisible: false,
            crosshairMarkerVisible: false,
          ),
        )
        .setData([
          for (final (i, v) in zigzag.line.indexed)
            if (v != null) LineData(time: times[i], value: v),
        ]);

    final editor = DrawingEditor(chart);
    // An automatic Elliott count on the same swings.
    final count = Ta.elliottWaves(bars, deviation: 1);
    if (count != null) {
      final points = [count.start, ...count.waves];
      editor.add(
        PathDrawing(
          id: 'elliott',
          anchors: [for (final p in points) DrawingAnchor(p.index.toDouble(), p.price)],
          labels: [for (final p in points) p.label],
          style: const DrawingStyle(color: Color(0xFF7E57C2)),
        ),
      );
    }
    // Trend lines price has respected, extended to the right.
    for (final line in Ta.autoTrendlines(bars)) {
      editor.add(
        TrendLineDrawing(
          id: line.support ? 'support' : 'resistance',
          anchors: [DrawingAnchor(line.a.toDouble(), line.pa), DrawingAnchor(line.b.toDouble(), line.pb)],
          extendRight: true,
          style: DrawingStyle(color: line.support ? const Color(0xFF089981) : const Color(0xFFF23645), lineWidth: 2),
        ),
      );
    }

    // Support / resistance zones from clustered swing points.
    final last = _long.last.close;
    candles.attachPrimitive(
      PriceLevelsPrimitive(
        levels: [
          for (final l in Ta.supportResistance(bars, maxLevels: 3) ?? const <SupportResistanceLevel>[])
            PriceLevel(
              price: l.price,
              label: '${l.price < last ? 'S' : 'R'} ×${l.strength}',
              color: l.price < last ? const Color(0xFF089981) : const Color(0xFFF23645),
              lineStyle: LineStyle.dotted,
              axisLabel: true,
            ),
        ],
      ),
    );

    // The latest candlestick patterns as markers, a few bars apart.
    final patterns = <CandlePatternMatch>[];
    for (final p in Ta.candlePatterns(bars).reversed) {
      if (p.bullish == null || patterns.length == 3) continue;
      if (patterns.isEmpty || patterns.last.index - p.index >= 6) patterns.add(p);
    }
    createSeriesMarkers(candles, [
      for (final p in patterns.reversed)
        SeriesMarker(
          time: times[p.index],
          position: p.bullish! ? SeriesMarkerPosition.belowBar : SeriesMarkerPosition.aboveBar,
          shape: p.bullish! ? SeriesMarkerShape.arrowUp : SeriesMarkerShape.arrowDown,
          color: p.bullish! ? const Color(0xFF089981) : const Color(0xFFF23645),
          text: _patternName(p.type),
        ),
    ]);
    createLegend(chart, const LegendOptions(title: 'BTC/USD · 1h · Ta', showOhlc: false));
  }

  /// `bearishEngulfing` -> `Engulfing`: the arrow already shows the side.
  static String _patternName(CandlePatternType type) {
    final name = type.name.replaceFirst(RegExp('^(bullish|bearish)'), '');
    return name[0].toUpperCase() +
        name.substring(1).replaceAllMapped(RegExp('[A-Z]'), (m) => ' ${m[0]!.toLowerCase()}');
  }

  // ---- session volume profiles ----

  void _addSessions(ChartController chart, CandlestickSeriesApi candles) {
    final bars = _taBars;
    final times = [for (final b in _long) b.time];
    // The last few days only, so each day's profile has room.
    final from = bars.length - 24 * 4 - _long.last.time.toInt() ~/ 3600 % 24 - 1;
    final sessions = Ta.sessionVolumeProfiles(bars.sublist(from), buckets: 20);
    candles.attachPrimitive(
      SessionVolumeProfilePrimitive(
        sessions: [
          for (final s in sessions)
            SessionProfile(
              from: times[from + s.from],
              to: times[from + s.to],
              bins: [
                for (final b in s.profile.buckets)
                  VolumeProfileBin(low: b.priceLow, high: b.priceHigh, volume: b.volume, upVolume: b.upVolume),
              ],
            ),
        ],
      ),
    );
    chart.timeScale().setVisibleLogicalRange(LogicalRange((from - 1).toDouble(), (_long.length + 2).toDouble()));
    createLegend(chart, const LegendOptions(title: 'BTC/USD · 1h · Session volume profile, value area 70%'));
  }

  // ---- forecast fan ----

  void _addForecast(ChartController chart, CandlestickSeriesApi candles) {
    final last = _long.last;
    // A random-walk forecast: the 80% and 95% ranges widen with √steps.
    final vol = Ta.standardDeviation(_taBars, period: 50).last! / last.close * 0.6;
    const steps = 30;
    candles.attachPrimitive(
      FanPrimitive(
        anchorTime: last.time,
        anchorValue: last.close,
        steps: [
          for (var k = 1; k <= steps; k++)
            () {
              final mid = last.close * (1 + 0.0004 * k);
              final w = last.close * vol * math.sqrt(k.toDouble());
              return FanStep(mid: mid, ranges: [(mid - 1.28 * w, mid + 1.28 * w), (mid - 1.96 * w, mid + 1.96 * w)]);
            }(),
        ],
      ),
    );
    chart.timeScale().applyOptions(chart.timeScale().options.copyWith(rightOffset: steps + 2));
    chart.timeScale().setVisibleLogicalRange(
      LogicalRange((_long.length - 90).toDouble(), (_long.length + steps + 2).toDouble()),
    );
    createLegend(chart, const LegendOptions(title: 'BTC/USD · 1h · 30h forecast, 80% / 95%'));
  }

  // ---- synced charts ----

  void _addSync(ChartController chart, CandlestickSeriesApi candles) {
    final other = ChartController(
      options: const ChartOptions(
        timeScale: TimeScaleOptions(timeVisible: true, secondsVisible: false, rightOffset: 4),
      ),
    );
    final h4 = other.addCandlestickSeries(const CandlestickSeriesOptions(borderVisible: false))
      ..setData(resample(_long, const Timeframe.hours(4)));
    other.timeScale().fitContent();
    _chart2 = other;
    createLegend(chart, const LegendOptions(title: 'BTC/USD · 1h'));
    createLegend(other, const LegendOptions(title: 'BTC/USD · 4h (resampled)'));
    _sync = CrosshairSync([(chart, candles), (other, h4)]);
    _pointAt(chart, candles, 50);
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
    _pointAt(chart, candles, 30);
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
    _sync?.dispose();
    _chart2?.dispose();
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
        if (_chart2 != null) ...[
          const Divider(height: 1),
          Expanded(
            child: SwmChart(key: ValueKey('$_mode 2'), controller: _chart2!),
          ),
        ],
      ],
    );
  }
}
