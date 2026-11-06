import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:swm_chart/swm_chart.dart';

import 'main.dart' show FakeFeed;

/// SwmProChart: top bar, drawing toolbar, style bar, indicator picker and
/// settings, with live ticks; the save / restore buttons round-trip the
/// whole chart through JSON.
class ProScreen extends StatefulWidget {
  const ProScreen({super.key});

  @override
  State<ProScreen> createState() => ProScreenState();
}

class ProScreenState extends State<ProScreen> {
  static const _intervals = {'15m': 900, '1h': 3600, '4h': 14400, '1D': 86400};

  late final ProChartController pro = ProChartController(symbol: 'BTC/USD', interval: '1h');
  Timer? _ticks;
  String? _saved;

  @override
  void initState() {
    super.initState();
    _load('1h');
    _decorate();
  }

  void _load(String interval) {
    final seconds = _intervals[interval]!;
    final feed = FakeFeed(interval: seconds);
    final now = DateTime.now().toUtc().millisecondsSinceEpoch ~/ 1000;
    final bars = feed.history(now - now % seconds, 30000, 300);
    pro.setData(bars, volumes: [for (final _ in bars) feed.volume()]);
    pro.chart.timeScale().setVisibleLogicalRange(const LogicalRange(180, 305));
    _ticks?.cancel();
    _ticks = Timer.periodic(const Duration(seconds: 1), (_) {
      final last = pro.bars.last;
      final close = feed.tick(last.close);
      pro.update(
        CandlestickData(
          time: last.time,
          open: last.open,
          high: math.max(last.high, close),
          low: math.min(last.low, close),
          close: close,
        ),
      );
    });
  }

  /// A few indicators and drawings to start with.
  void _decorate() {
    pro.addIndicator(IndicatorCatalog.byId('ema')!, values: {'period': 50});
    pro.addIndicator(IndicatorCatalog.byId('supertrend')!);
    pro.addIndicator(IndicatorCatalog.byId('rsi')!);
    pro.chart.panes()[0].setStretchFactor(2.5);
    final bars = pro.bars;
    final n = bars.length;
    final last = bars.last.close;
    pro.drawings
      ..add(
        AnchoredVwapDrawing(
          id: 'vwap',
          anchors: [DrawingAnchor((n - 110).toDouble(), 0)],
          source: pro.mainSeries,
          volume: pro.volumeSeries,
        ),
      )
      ..add(
        PositionDrawing(
          id: 'long',
          anchors: [
            DrawingAnchor((n - 48).toDouble(), bars[n - 48].close),
            DrawingAnchor((n - 22).toDouble(), bars[n - 48].close * 1.012),
          ],
        )..completed(),
      );
    pro.trading.add(TradingLine(id: 'alert', kind: TradingLineKind.alert, price: last * 1.018, label: 'Alert'));
  }

  void _save() {
    _saved = jsonEncode(pro.saveState());
    _snack(
      'Saved ${_saved!.length} bytes: ${pro.indicators.length} indicators, '
      '${pro.drawings.drawings.length} drawings',
    );
  }

  void _restore() {
    final saved = _saved;
    if (saved == null) return _snack('Nothing saved yet');
    pro.restoreState(jsonDecode(saved) as Map<String, Object?>);
    _snack('Restored');
  }

  void _snack(String text) => ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(text), duration: const Duration(seconds: 2)));

  @override
  void dispose() {
    _ticks?.cancel();
    pro.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => SwmProChart(
    controller: pro,
    intervals: _intervals.keys.toList(),
    onIntervalChanged: _load,
    onSymbolTap: () => _snack('Symbol search goes here'),
    actions: [
      IconButton(tooltip: 'Save chart', icon: const Icon(Icons.save_outlined), onPressed: _save),
      IconButton(tooltip: 'Restore chart', icon: const Icon(Icons.restore), onPressed: _restore),
    ],
  );
}
