import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:swm_chart/swm_chart.dart';

void main() => runApp(const DemoApp());

class DemoApp extends StatelessWidget {
  const DemoApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'swm_chart demo',
      theme: ThemeData(colorSchemeSeed: Colors.teal, useMaterial3: true),
      darkTheme: ThemeData(colorSchemeSeed: Colors.teal, brightness: Brightness.dark, useMaterial3: true),
      home: const TradingScreen(),
    );
  }
}

/// Random-walk bar generator standing in for a market data feed.
class FakeFeed {
  FakeFeed({required this.interval});

  final int interval; // seconds per bar
  final math.Random _random = math.Random(42);

  CandlestickData nextBar(int time, double prevClose) {
    final open = prevClose;
    final close = math.max(1.0, open + (_random.nextDouble() - 0.5) * open * 0.01);
    final high = math.max(open, close) + _random.nextDouble() * open * 0.003;
    final low = math.min(open, close) - _random.nextDouble() * open * 0.003;
    return CandlestickData(time: time, open: open, high: high, low: low, close: close);
  }

  /// [count] bars ending right before [endTime], walking backwards from [endOpen].
  List<CandlestickData> history(int endTime, double endOpen, int count) {
    final bars = <CandlestickData>[];
    var close = endOpen;
    for (var i = 1; i <= count; i++) {
      final bar = nextBar(endTime - i * interval, close);
      // Walk backwards: the generated "close" becomes the next older bar's close.
      final reversed = CandlestickData(time: bar.time, open: bar.close, high: bar.high, low: bar.low, close: bar.open);
      bars.add(reversed);
      close = reversed.open;
    }
    return bars.reversed.toList();
  }

  double volume() => 1000 + _random.nextDouble() * 50000;

  double tick(double price) => math.max(1.0, price + (_random.nextDouble() - 0.5) * price * 0.002);
}

class TradingScreen extends StatefulWidget {
  const TradingScreen({super.key});

  @override
  State<TradingScreen> createState() => _TradingScreenState();
}

class _TradingScreenState extends State<TradingScreen> {
  static const _up = Color(0xFF26A69A);
  static const _down = Color(0xFFEF5350);
  static const _interval = 5 * 60;

  final FakeFeed _feed = FakeFeed(interval: _interval);
  late final ChartController _chart;
  late final CandlestickSeriesApi _candles;
  late final HistogramSeriesApi _volume;
  late final LineSeriesApi _line;

  final List<CandlestickData> _bars = [];
  final List<HistogramData> _volumes = [];
  Timer? _timer;
  int _ticks = 0;
  bool _loadingHistory = false;
  bool _showLine = false;
  bool? _dark;

  CandlestickData? _hovered;
  HistogramData? _hoveredVolume;

  @override
  void initState() {
    super.initState();
    _chart = ChartController(
      options: const ChartOptions(
        timeScale: TimeScaleOptions(timeVisible: true, secondsVisible: false, rightOffset: 5, barSpacing: 8),
      ),
    );
    _candles = _chart.addCandlestickSeries(const CandlestickSeriesOptions(borderVisible: false));
    _line = _chart.addLineSeries(const LineSeriesOptions(lineWidth: 2, visible: false));
    _volume = _chart.addHistogramSeries(const HistogramSeriesOptions(
      priceScaleId: 'volume',
      priceFormat: PriceFormat.volume(),
      lastValueVisible: false,
      priceLineVisible: false,
    ));
    // Volume lives in the bottom 20% of the pane.
    _chart.priceScale('volume').applyOptions(const PriceScaleOptions(scaleMargins: ScaleMargins(top: 0.8, bottom: 0)));

    final now = DateTime.now().toUtc().millisecondsSinceEpoch ~/ 1000;
    final lastBarTime = now - now % _interval;
    _bars.addAll(_feed.history(lastBarTime + _interval, 30000, 500));
    _volumes.addAll(_bars.map(_volumeFor));
    _pushAll();

    _chart.subscribeCrosshairMove(_onCrosshairMove);
    _chart.timeScale().subscribeVisibleLogicalRangeChange(_onRangeChange);
    _timer = Timer.periodic(const Duration(milliseconds: 500), (_) => _onTick());
  }

  HistogramData _volumeFor(CandlestickData bar) => HistogramData(
        time: bar.time,
        value: _feed.volume(),
        color: (bar.isUp ? _up : _down).withValues(alpha: 0.5),
      );

  LineData _lineFor(CandlestickData bar) => LineData(time: bar.time, value: bar.close);

  void _pushAll() {
    _candles.setData(_bars);
    _volume.setData(_volumes);
    _line.setData(_bars.map(_lineFor).toList());
  }

  /// Simulates a live feed: every tick updates the last bar, every 10th opens a new one.
  void _onTick() {
    final last = _bars.last;
    _ticks++;
    CandlestickData bar;
    HistogramData vol;
    if (_ticks % 10 == 0) {
      bar = _feed.nextBar(last.time + _interval, last.close);
      vol = _volumeFor(bar);
      _bars.add(bar);
      _volumes.add(vol);
    } else {
      final price = _feed.tick(last.close);
      bar = CandlestickData(
        time: last.time,
        open: last.open,
        high: math.max(last.high, price),
        low: math.min(last.low, price),
        close: price,
      );
      final prevVol = _volumes.last;
      vol = HistogramData(
        time: bar.time,
        value: prevVol.value + _feed.volume() / 20,
        color: (bar.isUp ? _up : _down).withValues(alpha: 0.5),
      );
      _bars[_bars.length - 1] = bar;
      _volumes[_volumes.length - 1] = vol;
    }
    _candles.update(bar);
    _volume.update(vol);
    _line.update(_lineFor(bar));
    if (_hovered == null) setState(() {});
  }

  /// Loads older bars when the user scrolls close to the first one.
  void _onRangeChange(LogicalRange? range) {
    if (range == null || range.from > 20 || _loadingHistory) return;
    _loadingHistory = true;
    Future<void>.delayed(const Duration(milliseconds: 300), () {
      if (!mounted) return;
      final first = _bars.first;
      final older = _feed.history(first.time, first.open, 300);
      _bars.insertAll(0, older);
      _volumes.insertAll(0, older.map(_volumeFor));
      _pushAll();
      _loadingHistory = false;
    });
  }

  void _onCrosshairMove(ChartEventParams p) {
    setState(() {
      _hovered = p.seriesData[_candles] as CandlestickData?;
      _hoveredVolume = p.seriesData[_volume] as HistogramData?;
    });
  }

  void _applyTheme(bool dark) {
    final bg = dark ? const Color(0xFF131722) : Colors.white;
    final text = dark ? const Color(0xFFD1D4DC) : const Color(0xFF191919);
    final grid = dark ? const Color(0xFF2A2E39) : const Color(0xFFEFF2F5);
    final border = dark ? const Color(0xFF2A2E39) : const Color(0xFFD6DCDE);
    final label = dark ? const Color(0xFF363A45) : const Color(0xFF131722);
    final o = _chart.options;
    _chart.applyOptions(o.copyWith(
      layout: o.layout.copyWith(backgroundColor: bg, textColor: text),
      crosshair: o.crosshair.copyWith(
        vertLine: o.crosshair.vertLine.copyWith(labelBackgroundColor: label),
        horzLine: o.crosshair.horzLine.copyWith(labelBackgroundColor: label),
      ),
      grid: GridOptions(vertLines: GridLineOptions(color: grid), horzLines: GridLineOptions(color: grid)),
      rightPriceScale: o.rightPriceScale.copyWith(borderColor: border),
      timeScale: o.timeScale.copyWith(borderColor: border),
    ));
  }

  void _toggleSeries() {
    setState(() => _showLine = !_showLine);
    _candles.applyOptions(_candles.options.copyWith(visible: !_showLine));
    _line.applyOptions(_line.options.copyWith(visible: _showLine));
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final dark = Theme.of(context).brightness == Brightness.dark;
    if (_dark != dark) {
      _dark = dark;
      _applyTheme(dark);
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _chart.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bar = _hovered ?? _bars.last;
    final vol = _hoveredVolume ?? _volumes.last;
    final color = bar.isUp ? _up : _down;
    final dark = _dark ?? false;

    return Scaffold(
      appBar: AppBar(
        title: const Text('BTC/USD · 5m'),
        actions: [
          IconButton(
            tooltip: _showLine ? 'Candles' : 'Line',
            icon: Icon(_showLine ? Icons.candlestick_chart : Icons.show_chart),
            onPressed: _toggleSeries,
          ),
          IconButton(
            tooltip: 'Fit content',
            icon: const Icon(Icons.fit_screen),
            onPressed: () => _chart.timeScale().fitContent(),
          ),
          IconButton(
            tooltip: 'Go to real time',
            icon: const Icon(Icons.last_page),
            onPressed: () => _chart.timeScale().scrollToRealTime(),
          ),
          IconButton(
            tooltip: 'Theme',
            icon: Icon(dark ? Icons.light_mode : Icons.dark_mode),
            onPressed: () {
              setState(() => _dark = !dark);
              _applyTheme(!dark);
            },
          ),
        ],
      ),
      body: SafeArea(
        child: Container(
          color: _chart.options.layout.backgroundColor,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
                child: DefaultTextStyle(
                  style: TextStyle(color: _chart.options.layout.textColor, fontSize: 12, fontFeatures: const [FontFeature.tabularFigures()]),
                  child: Wrap(
                    spacing: 10,
                    children: [
                      _Legend('O', bar.open, color),
                      _Legend('H', bar.high, color),
                      _Legend('L', bar.low, color),
                      _Legend('C', bar.close, color),
                      Text('Vol ${(vol.value / 1000).toStringAsFixed(1)}K'),
                    ],
                  ),
                ),
              ),
              Expanded(child: SwmChart(controller: _chart)),
            ],
          ),
        ),
      ),
    );
  }
}

class _Legend extends StatelessWidget {
  const _Legend(this.label, this.value, this.color);

  final String label;
  final double value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Text.rich(TextSpan(children: [
      TextSpan(text: '$label '),
      TextSpan(text: value.toStringAsFixed(2), style: TextStyle(color: color)),
    ]));
  }
}
