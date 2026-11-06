// Keeps the crosshair of several charts on the same moment.

import '../api/chart_controller.dart';
import '../data.dart';

/// Moves the crosshair of every chart in [charts] to the time the user
/// points at on any one of them — at that chart's own [SeriesApi] value
/// then — and hides it on all when it leaves.
///
/// ```dart
/// final sync = CrosshairSync([(priceChart, candles), (volumeChart, volume)]);
/// // …
/// sync.dispose();
/// ```
class CrosshairSync {
  CrosshairSync(List<(ChartController, SeriesApi)> charts) : _charts = List.of(charts) {
    for (final (chart, _) in _charts) {
      void handler(ChartEventParams p) => _moved(chart, p);
      _handlers[chart] = handler;
      chart.subscribeCrosshairMove(handler);
    }
  }

  final List<(ChartController, SeriesApi)> _charts;
  final Map<ChartController, ChartEventHandler> _handlers = {};

  // Setting the others' crosshair reports a move on them too; ignore it.
  bool _syncing = false;

  void _moved(ChartController source, ChartEventParams p) {
    if (_syncing) return;
    _syncing = true;
    try {
      final time = p.time;
      for (final (chart, series) in _charts) {
        if (identical(chart, source)) continue;
        final bar = time == null ? null : _barAt(chart, series, time);
        if (bar == null) {
          chart.clearCrosshairPosition();
        } else {
          chart.setCrosshairPosition(bar.$2, bar.$1, series);
        }
      }
    } finally {
      _syncing = false;
    }
  }

  /// Time and value of the bar of [series] holding [time]: the last one at
  /// or before it, so a 1h moment lands on its 4h bar.
  static (num, double)? _barAt(ChartController chart, SeriesApi series, num time) {
    final logical = chart.timeScale().timeToLogical(time);
    if (logical == null) return null;
    return switch (series.dataByIndex((logical + 1e-6).floor(), MismatchDirection.nearestLeft)) {
      final OhlcData d => (d.time, d.close),
      final SingleValueData d => (d.time, d.value),
      _ => null,
    };
  }

  /// Stops syncing.
  void dispose() {
    for (final MapEntry(key: chart, value: handler) in _handlers.entries) {
      chart.unsubscribeCrosshairMove(handler);
    }
    _handlers.clear();
  }
}
