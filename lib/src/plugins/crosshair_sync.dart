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
        final value = time == null ? null : _valueAt(chart, series, time);
        if (time == null || value == null) {
          chart.clearCrosshairPosition();
        } else {
          chart.setCrosshairPosition(value, time, series);
        }
      }
    } finally {
      _syncing = false;
    }
  }

  static double? _valueAt(ChartController chart, SeriesApi series, num time) {
    final logical = chart.timeScale().timeToLogical(time);
    if (logical == null) return null;
    return switch (series.dataByIndex(logical.round())) {
      final OhlcData d => d.close,
      final SingleValueData d => d.value,
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
