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

/// Wilder's RSI over [closes].
List<double?> rsi(List<double> closes, [int period = 14]) {
  final out = List<double?>.filled(closes.length, null);
  if (closes.length <= period) return out;
  var gain = 0.0, loss = 0.0;
  for (var i = 1; i <= period; i++) {
    final d = closes[i] - closes[i - 1];
    if (d > 0) {
      gain += d;
    } else {
      loss -= d;
    }
  }
  gain /= period;
  loss /= period;
  out[period] = loss == 0 ? 100 : 100 - 100 / (1 + gain / loss);
  for (var i = period + 1; i < closes.length; i++) {
    final d = closes[i] - closes[i - 1];
    gain = (gain * (period - 1) + math.max(d, 0)) / period;
    loss = (loss * (period - 1) + math.max(-d, 0)) / period;
    out[i] = loss == 0 ? 100 : 100 - 100 / (1 + gain / loss);
  }
  return out;
}

/// Simple moving average over [closes].
List<double?> sma(List<double> closes, int period) {
  final out = List<double?>.filled(closes.length, null);
  var sum = 0.0;
  for (var i = 0; i < closes.length; i++) {
    sum += closes[i];
    if (i >= period) sum -= closes[i - period];
    if (i >= period - 1) out[i] = sum / period;
  }
  return out;
}

enum MainType { candles, bars, line, area, baseline }

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
  late SeriesApi _main;
  late final LineSeriesApi _sma;
  late final HistogramSeriesApi _volume;
  late final LineSeriesApi _rsi;
  late SeriesMarkersPlugin _markers;
  late final WatermarkPlugin<TextWatermarkPrimitive> _watermark;

  final List<CandlestickData> _bars = [];
  final List<HistogramData> _volumes = [];
  Timer? _timer;
  int _ticks = 0;
  bool _loadingHistory = false;
  MainType _type = MainType.candles;
  PriceScaleMode _mode = PriceScaleMode.normal;
  bool? _dark;

  int? _hoveredTime;

  @override
  void initState() {
    super.initState();
    _chart = ChartController(
      options: const ChartOptions(
        timeScale: TimeScaleOptions(timeVisible: true, secondsVisible: false, rightOffset: 5, barSpacing: 8),
      ),
    );
    _main = _createMain(_type);
    _sma = _chart.addLineSeries(const LineSeriesOptions(
      color: Color(0xFFFF9800),
      lineWidth: 1,
      lastValueVisible: false,
      priceLineVisible: false,
      crosshairMarkerVisible: false,
      title: 'SMA 20',
    ));
    _volume = _chart.addHistogramSeries(const HistogramSeriesOptions(
      priceScaleId: 'volume',
      priceFormat: PriceFormat.volume(),
      lastValueVisible: false,
      priceLineVisible: false,
    ));
    // Volume lives in the bottom 20% of the main pane.
    _chart.priceScale('volume').applyOptions(const PriceScaleOptions(scaleMargins: ScaleMargins(top: 0.8, bottom: 0)));

    // RSI in its own pane, a third of the main pane's height.
    _rsi = _chart.addLineSeries(
      const LineSeriesOptions(color: Color(0xFF7E57C2), lineWidth: 1.5, priceLineVisible: false, title: 'RSI 14'),
      1,
    );
    _chart.panes()[0].setStretchFactor(3);
    _rsi.createPriceLine(const PriceLineOptions(price: 70, color: Color(0x99EF5350), lineStyle: LineStyle.dashed));
    _rsi.createPriceLine(const PriceLineOptions(price: 30, color: Color(0x9926A69A), lineStyle: LineStyle.dashed));
    _chart.priceScale('right', 1).applyOptions(const PriceScaleOptions(
      autoScale: false,
      scaleMargins: ScaleMargins(top: 0.1, bottom: 0.1),
    ));
    _chart.priceScale('right', 1).setVisibleRange(const PriceRange(0, 100));

    _watermark = createTextWatermark(
      _chart.panes()[0],
      const TextWatermarkOptions(lines: [
        TextWatermarkLine(text: 'BTC/USD', color: Color(0x1F808080), fontSize: 44, fontWeight: FontWeight.bold),
        TextWatermarkLine(text: '5m · swm_chart', color: Color(0x1F808080), fontSize: 16),
      ]),
    );

    final now = DateTime.now().toUtc().millisecondsSinceEpoch ~/ 1000;
    final lastBarTime = now - now % _interval;
    _bars.addAll(_feed.history(lastBarTime + _interval, 30000, 500));
    _volumes.addAll(_bars.map(_volumeFor));
    _pushAll();

    _chart.subscribeCrosshairMove(_onCrosshairMove);
    _chart.timeScale().subscribeVisibleLogicalRangeChange(_onRangeChange);
    _timer = Timer.periodic(const Duration(milliseconds: 500), (_) => _onTick());
  }

  SeriesApi _createMain(MainType type) {
    final api = switch (type) {
      MainType.candles => _chart.addCandlestickSeries(const CandlestickSeriesOptions(borderVisible: false)),
      MainType.bars => _chart.addBarSeries(),
      MainType.line => _chart.addLineSeries(const LineSeriesOptions(lineWidth: 2, lineType: LineType.curved)),
      MainType.area => _chart.addAreaSeries(const AreaSeriesOptions(
          lineColor: Color(0xFF2962FF),
          topColor: Color(0x662962FF),
          bottomColor: Color(0x002962FF),
          lineWidth: 2,
          lastPriceAnimation: LastPriceAnimationMode.continuous,
        )),
      MainType.baseline => _chart.addBaselineSeries(const BaselineSeriesOptions(lineWidth: 2)),
    };
    _markers = createSeriesMarkers(api);
    return api;
  }

  /// Converts a bar to the data type of the main series.
  SeriesData _mainItem(CandlestickData b) => switch (_type) {
        MainType.candles => b,
        MainType.bars => BarData(time: b.time, open: b.open, high: b.high, low: b.low, close: b.close),
        MainType.line => LineData(time: b.time, value: b.close),
        MainType.area => AreaData(time: b.time, value: b.close),
        MainType.baseline => BaselineData(time: b.time, value: b.close),
      };

  void _setMainData() {
    final api = _main;
    final items = _bars.map(_mainItem).toList();
    switch (api) {
      case CandlestickSeriesApi s:
        s.setData(items.cast());
      case BarSeriesApi s:
        s.setData(items.cast());
      case LineSeriesApi s:
        s.setData(items.cast());
      case AreaSeriesApi s:
        s.setData(items.cast());
      case BaselineSeriesApi s:
        s.setData(items.cast());
    }
  }

  void _updateMain(CandlestickData bar) {
    final item = _mainItem(bar);
    switch (_main) {
      case CandlestickSeriesApi s:
        s.update(item as CandlestickData);
      case BarSeriesApi s:
        s.update(item as BarData);
      case LineSeriesApi s:
        s.update(item as LineData);
      case AreaSeriesApi s:
        s.update(item as AreaData);
      case BaselineSeriesApi s:
        s.update(item as BaselineData);
    }
  }

  HistogramData _volumeFor(CandlestickData bar) => HistogramData(
        time: bar.time,
        value: _feed.volume(),
        color: (bar.isUp ? _up : _down).withValues(alpha: 0.5),
      );

  List<double> get _closes => _bars.map((b) => b.close).toList();

  void _pushAll() {
    _setMainData();
    _volume.setData(_volumes);
    _pushIndicators();
    if (_type == MainType.baseline) {
      // Baseline around the first loaded price.
      final o = (_main as BaselineSeriesApi).options;
      (_main as BaselineSeriesApi).applyOptions(o.copyWith(baseValue: _bars[_bars.length ~/ 2].close));
    }
  }

  void _pushIndicators() {
    final closes = _closes;
    final s = sma(closes, 20);
    final r = rsi(closes);
    _sma.setData([
      for (var i = 0; i < _bars.length; i++)
        if (s[i] != null) LineData(time: _bars[i].time, value: s[i]!),
    ]);
    _rsi.setData([
      for (var i = 0; i < _bars.length; i++)
        if (r[i] != null) LineData(time: _bars[i].time, value: r[i]!),
    ]);
    _markers.setMarkers(_rsiMarkers(r));
  }

  /// Buy when RSI crosses up through 30, sell when it crosses down through 70.
  List<SeriesMarker> _rsiMarkers(List<double?> r) {
    final markers = <SeriesMarker>[];
    for (var i = 1; i < r.length; i++) {
      final prev = r[i - 1], cur = r[i];
      if (prev == null || cur == null) continue;
      if (prev < 30 && cur >= 30) {
        markers.add(SeriesMarker(
          time: _bars[i].time,
          position: SeriesMarkerPosition.belowBar,
          shape: SeriesMarkerShape.arrowUp,
          color: _up,
          text: 'Buy',
        ));
      } else if (prev > 70 && cur <= 70) {
        markers.add(SeriesMarker(
          time: _bars[i].time,
          position: SeriesMarkerPosition.aboveBar,
          shape: SeriesMarkerShape.arrowDown,
          color: _down,
          text: 'Sell',
        ));
      }
    }
    return markers;
  }

  /// Simulates a live feed: every tick updates the last bar, every 10th opens a new one.
  void _onTick() {
    final last = _bars.last;
    _ticks++;
    CandlestickData bar;
    HistogramData vol;
    final newBar = _ticks % 10 == 0;
    if (newBar) {
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
    _updateMain(bar);
    _volume.update(vol);
    final closes = _closes;
    final s = sma(closes, 20).last;
    final r = rsi(closes);
    if (s != null) _sma.update(LineData(time: bar.time, value: s));
    if (r.last != null) _rsi.update(LineData(time: bar.time, value: r.last!));
    if (newBar) _markers.setMarkers(_rsiMarkers(r));
    if (_hoveredTime == null) setState(() {});
  }

  /// Loads older bars when the user scrolls close to the first one.
  void _onRangeChange(LogicalRange? range) {
    if (range == null || _loadingHistory) return;
    final info = _main.barsInLogicalRange(range);
    if (info == null || info.barsBefore > 20) return;
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

  void _onCrosshairMove(ChartEventParams p) => setState(() => _hoveredTime = p.time);

  void _switchType(MainType type) {
    if (type == _type) return;
    _markers.detach();
    _chart.removeSeries(_main);
    setState(() => _type = type);
    _main = _createMain(type);
    _pushAll();
  }

  void _switchMode(PriceScaleMode mode) {
    setState(() => _mode = mode);
    final scale = _chart.priceScale();
    scale.applyOptions(scale.options.copyWith(mode: mode));
  }

  void _applyTheme(bool dark) {
    final bg = dark ? const Color(0xFF131722) : Colors.white;
    final text = dark ? const Color(0xFFD1D4DC) : const Color(0xFF191919);
    final grid = dark ? const Color(0xFF2A2E39) : const Color(0xFFEFF2F5);
    final border = dark ? const Color(0xFF2A2E39) : const Color(0xFFD6DCDE);
    final label = dark ? const Color(0xFF363A45) : const Color(0xFF131722);
    final o = _chart.options;
    _chart.applyOptions(o.copyWith(
      layout: o.layout.copyWith(
        backgroundColor: bg,
        textColor: text,
        panes: PaneOptions(separatorColor: border),
      ),
      crosshair: o.crosshair.copyWith(
        vertLine: o.crosshair.vertLine.copyWith(labelBackgroundColor: label),
        horzLine: o.crosshair.horzLine.copyWith(labelBackgroundColor: label),
      ),
      grid: GridOptions(vertLines: GridLineOptions(color: grid), horzLines: GridLineOptions(color: grid)),
      rightPriceScale: o.rightPriceScale.copyWith(borderColor: border, mode: _mode),
      timeScale: o.timeScale.copyWith(borderColor: border),
    ));
    // applyOptions resets every pane's right scale; restore the RSI range.
    _chart.priceScale('right', 1).applyOptions(_chart.priceScale('right', 1).options.copyWith(
          autoScale: false,
          mode: PriceScaleMode.normal,
          scaleMargins: const ScaleMargins(top: 0.1, bottom: 0.1),
        ));
    _chart.priceScale('right', 1).setVisibleRange(const PriceRange(0, 100));
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
    _watermark.detach();
    _chart.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final index = _hoveredTime == null ? _bars.length - 1 : _bars.indexWhere((b) => b.time == _hoveredTime);
    final bar = _bars[index < 0 ? _bars.length - 1 : index];
    final vol = _volumes[index < 0 ? _volumes.length - 1 : index];
    final rsiValue = _rsi.data().where((d) => d.time == bar.time).firstOrNull?.value;
    final color = bar.isUp ? _up : _down;
    final dark = _dark ?? false;

    return Scaffold(
      appBar: AppBar(
        title: const Text('BTC/USD · 5m'),
        actions: [
          PopupMenuButton<MainType>(
            tooltip: 'Series type',
            icon: const Icon(Icons.candlestick_chart),
            initialValue: _type,
            onSelected: _switchType,
            itemBuilder: (_) => [
              for (final t in MainType.values) PopupMenuItem(value: t, child: Text(t.name)),
            ],
          ),
          PopupMenuButton<PriceScaleMode>(
            tooltip: 'Price scale mode',
            icon: const Icon(Icons.straighten),
            initialValue: _mode,
            onSelected: _switchMode,
            itemBuilder: (_) => [
              for (final m in PriceScaleMode.values) PopupMenuItem(value: m, child: Text(m.name)),
            ],
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
                  style: TextStyle(
                    color: _chart.options.layout.textColor,
                    fontSize: 12,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                  child: Wrap(
                    spacing: 10,
                    children: [
                      _Legend('O', bar.open, color),
                      _Legend('H', bar.high, color),
                      _Legend('L', bar.low, color),
                      _Legend('C', bar.close, color),
                      Text('Vol ${(vol.value / 1000).toStringAsFixed(1)}K'),
                      if (rsiValue != null) _Legend('RSI', rsiValue, const Color(0xFF7E57C2)),
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
