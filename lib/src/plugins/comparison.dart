// Compare symbols: extra lines on a percentage price scale.
import 'dart:ui' show Color;

import '../api/chart_controller.dart';
import '../data.dart';
import '../options.dart';
import '../series_options.dart';

/// Default colors of comparison lines, used in turn.
const List<Color> comparisonColors = [
  Color(0xFFFF9800),
  Color(0xFF7E57C2),
  Color(0xFF00BCD4),
  Color(0xFFE91E63),
  Color(0xFF8BC34A),
  Color(0xFF795548),
];

class _PaneState {
  _PaneState(this.previousMode);

  final PriceScaleMode previousMode;
  final List<LineSeriesApi> series = [];
}

final Expando<Map<int, _PaneState>> _states = Expando('comparisons');

/// Comparing symbols on a [ChartController].
extension ChartComparison on ChartController {
  /// Adds [data] of another symbol as a line named [title]. The first
  /// comparison in a pane switches its right price scale to percentage
  /// mode, so every line starts at 0% at the left of the view; removing the
  /// last one restores the previous mode.
  ///
  /// OHLC data is compared on its close.
  LineSeriesApi addComparison(List<SeriesData> data, {required String title, Color? color, int paneIndex = 0}) {
    final states = _states[this] ??= {};
    final scale = priceScale('right', paneIndex);
    final state = states[paneIndex] ??= _PaneState(scale.options.mode);
    if (state.series.isEmpty && scale.options.mode != PriceScaleMode.percentage) {
      scale.applyOptions(scale.options.copyWith(mode: PriceScaleMode.percentage));
    }
    final used = {for (final s in state.series) s.options.color};
    final lineColor =
        color ?? comparisonColors.firstWhere((c) => !used.contains(c), orElse: () => comparisonColors.first);
    final series = addLineSeries(
      LineSeriesOptions(title: title, color: lineColor, lineWidth: 2, priceScaleId: 'right', priceLineVisible: false),
      paneIndex,
    );
    series.setData([
      for (final d in data)
        switch (d) {
          OhlcData() => LineData(time: d.time, value: d.close),
          SingleValueData() => LineData(time: d.time, value: d.value),
          _ => WhitespaceData(time: d.time),
        },
    ]);
    state.series.add(series);
    return series;
  }

  /// Comparison lines of pane [paneIndex].
  List<LineSeriesApi> comparisons([int paneIndex = 0]) =>
      List.unmodifiable(_states[this]?[paneIndex]?.series ?? const <LineSeriesApi>[]);

  /// Removes a line added by [addComparison]; the last one restores the
  /// price scale mode.
  void removeComparison(LineSeriesApi series) {
    final states = _states[this];
    if (states == null) return;
    for (final entry in states.entries) {
      if (!entry.value.series.remove(series)) continue;
      removeSeries(series);
      if (entry.value.series.isEmpty) {
        final scale = priceScale('right', entry.key);
        scale.applyOptions(scale.options.copyWith(mode: entry.value.previousMode));
        states.remove(entry.key);
      }
      return;
    }
  }
}
