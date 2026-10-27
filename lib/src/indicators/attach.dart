// Puts an [Indicator] on a chart and keeps it in sync with its source.
import 'dart:ui' show Color;

import '../api/chart_controller.dart';
import '../data.dart';
import '../model/price_line.dart';
import '../model/price_scale.dart' show PriceRange;
import '../options.dart';
import '../plugins/overlays.dart';
import '../series_options.dart';
import 'indicators.dart';

final Expando<IndicatorHandle> _handles = Expando('indicator');

/// The indicator [series] belongs to, if it was added by
/// [ChartIndicators.addIndicator] (used by legends to group its lines).
IndicatorHandle? indicatorOf(SeriesApi series) => _handles[series.model];

/// An indicator on a chart, returned by [ChartIndicators.addIndicator].
class IndicatorHandle {
  IndicatorHandle._(this.chart, this.indicator, this.source, this.volume, this.paneIndex);

  final ChartController chart;
  final Indicator indicator;
  final SeriesApi source;
  final SeriesApi? volume;

  /// Pane the indicator is drawn in.
  final int paneIndex;

  /// One series per [Indicator.lines] entry.
  final List<SeriesApi> series = [];
  BandFillPrimitive? _band;
  final List<IndicatorInput> _input = [];
  late List<List<double?>> _out;
  bool _removed = false;

  /// Current outputs, one list per line, aligned with the source bars.
  List<List<double?>> get values => _out;

  /// Inputs read from the source (and volume) series.
  List<IndicatorInput> get inputs => List.unmodifiable(_input);

  void _onSourceChanged() => _sync();

  /// Removes the indicator's series, band and levels from the chart.
  void remove() {
    if (_removed) return;
    _removed = true;
    source.unsubscribeDataChanged(_onSourceChanged);
    volume?.unsubscribeDataChanged(_onSourceChanged);
    final band = _band;
    if (band != null && series.isNotEmpty) series[indicator.band!.upper].detachPrimitive(band);
    for (final s in series) {
      chart.removeSeries(s);
    }
    series.clear();
  }

  /// Shows or hides every series of the indicator.
  set visible(bool value) {
    for (final s in series) {
      s.applyOptions(_withVisible(s.options, value));
    }
  }

  static SeriesOptions _withVisible(SeriesOptions o, bool visible) => switch (o) {
    LineSeriesOptions() => o.copyWith(visible: visible),
    HistogramSeriesOptions() => o.copyWith(visible: visible),
    _ => o,
  };

  // ---- inputs ----

  IndicatorInput? _inputOf(SeriesData d) {
    final v = _volumeAt(d.time);
    if (d is OhlcData) {
      return IndicatorInput(time: d.time, open: d.open, high: d.high, low: d.low, close: d.close, volume: v);
    }
    if (d is SingleValueData) return IndicatorInput.value(time: d.time, value: d.value, volume: v);
    return null;
  }

  /// Volume at [time], by binary search: O(log n) per bar.
  double? _volumeAt(num time) {
    final v = volume;
    if (v == null) return null;
    final data = v.model.data;
    var lo = 0, hi = data.length;
    while (lo < hi) {
      final mid = (lo + hi) >> 1;
      if (data[mid].time < time) {
        lo = mid + 1;
      } else {
        hi = mid;
      }
    }
    if (lo < data.length && data[lo].time == time) {
      final d = data[lo];
      if (d is SingleValueData) return d.value;
    }
    return null;
  }

  /// Recomputes what changed: the last bar (a tick or a new bar) costs
  /// O(1) per line, anything else a full recomputation.
  void _sync() {
    if (_removed) return;
    final data = source.model.data;
    final n = data.length;
    final old = _input.length;
    int from;
    if (old > 0 && n == old && data[n - 1].time == _input[n - 1].time) {
      from = n - 1; // the last bar was updated
    } else if (old > 0 && n == old + 1 && data[old - 1].time == _input[old - 1].time) {
      from = old - 1; // a new bar: refresh the previous one too, then append
    } else {
      from = 0;
    }
    _input.length = from;
    for (var i = from; i < n; i++) {
      final input = _inputOf(data[i]);
      if (input != null) _input.add(input);
    }
    if (_input.length != n) {
      // Unexpected data types: fall back to the inputs we could read.
      from = 0;
    }
    final len = _input.length;
    for (final line in _out) {
      if (line.length > len) line.length = len;
      while (line.length < len) {
        line.add(null);
      }
    }
    indicator.compute(_input, from, _out);
    _apply(from);
  }

  num _timeAt(int index) {
    final n = _input.length;
    if (index < n) return _input[index].time;
    // Beyond the data (forward-shifted lines): extrapolate the last step.
    final step = n > 1 ? _input[n - 1].time - _input[n - 2].time : 1;
    return _input[n - 1].time + step * (index - n + 1);
  }

  SeriesData _point(IndicatorLine line, num time, double value) => switch (line.kind) {
    IndicatorLineKind.histogram => HistogramData(
      time: time,
      value: value,
      color: value < 0 ? (line.negativeColor ?? line.color) : line.color,
    ),
    IndicatorLineKind.line => LineData(time: time, value: value),
  };

  List<SeriesData> _lineData(int l) {
    final line = indicator.lines[l];
    final values = _out[l];
    return [
      for (var i = 0; i < values.length; i++)
        if (values[i] != null && i + line.shift >= 0) _point(line, _timeAt(i + line.shift), values[i]!),
    ];
  }

  void _apply(int from) {
    final lines = indicator.lines;
    for (var l = 0; l < lines.length; l++) {
      final line = lines[l];
      final s = series[l];
      if (from == 0 || line.shift < 0) {
        // Lines plotted in the past can't be updated in place.
        s.setData(_lineData(l));
        continue;
      }
      for (var i = from; i < _out[l].length; i++) {
        final v = _out[l][i];
        if (v == null || i + line.shift < 0) continue;
        s.update(_point(line, _timeAt(i + line.shift), v));
      }
    }
    final bandDef = indicator.band;
    final band = _band;
    if (bandDef != null && band != null) {
      final upper = lines[bandDef.upper], lower = lines[bandDef.lower];
      final shift = upper.shift;
      final points = <BandPoint>[
        for (var i = 0; i < _input.length; i++)
          if (_out[bandDef.upper][i] != null && _out[bandDef.lower][i] != null && i + shift >= 0)
            BandPoint(time: _timeAt(i + shift), upper: _out[bandDef.upper][i]!, lower: _out[bandDef.lower][i]!),
      ];
      assert(upper.shift == lower.shift, 'a band needs both lines on the same shift');
      band.points = points;
    }
  }
}

/// Indicators on a [ChartController].
extension ChartIndicators on ChartController {
  /// Draws [indicator] computed from [source] and keeps it up to date as
  /// the source gets new data.
  ///
  /// Overlays (moving averages, bands, VWAP, Ichimoku) go over [source] on
  /// its price scale; oscillators (RSI, MACD, …) get a new pane below,
  /// unless [paneIndex] is given. [volume] supplies volumes (VWAP).
  ///
  /// ```dart
  /// chart.addIndicator(Bollinger(), source: candles);
  /// final rsi = chart.addIndicator(Rsi(14), source: candles);
  /// rsi.remove();
  /// ```
  IndicatorHandle addIndicator(Indicator indicator, {required SeriesApi source, SeriesApi? volume, int? paneIndex}) {
    final sourcePane = source.getPane().paneIndex();
    final pane = paneIndex ?? (indicator.overlay ? sourcePane : addPane().paneIndex());
    final handle = IndicatorHandle._(this, indicator, source, volume, pane);
    final scaleId = indicator.overlay && pane == sourcePane ? source.options.priceScaleId : null;
    final range = indicator.range;
    AutoscaleInfo? fixedRange(AutoscaleInfo? Function() _) =>
        AutoscaleInfo(priceRange: PriceRange(range!.$1, range.$2));

    for (final line in indicator.lines) {
      final title = indicator.lines.length == 1 ? indicator.name : line.name;
      final series = switch (line.kind) {
        IndicatorLineKind.histogram => addHistogramSeries(
          HistogramSeriesOptions(
            color: line.color,
            title: title,
            priceScaleId: scaleId,
            lastValueVisible: false,
            priceLineVisible: false,
            autoscaleInfoProvider: range == null ? null : fixedRange,
          ),
          pane,
        ),
        IndicatorLineKind.line => addLineSeries(
          LineSeriesOptions(
            color: line.color,
            lineWidth: line.lineWidth,
            lineStyle: line.lineStyle,
            title: title,
            priceScaleId: scaleId,
            lastValueVisible: !indicator.overlay,
            priceLineVisible: false,
            crosshairMarkerVisible: false,
            autoscaleInfoProvider: range == null ? null : fixedRange,
          ),
          pane,
        ),
      };
      handle.series.add(series);
      _handles[series.model] = handle;
    }
    for (final level in indicator.levels) {
      handle.series.first.createPriceLine(
        PriceLineOptions(
          price: level,
          color: const Color(0x80787B86),
          lineStyle: LineStyle.dashed,
          axisLabelVisible: false,
        ),
      );
    }
    final bandDef = indicator.band;
    if (bandDef != null) {
      final band = BandFillPrimitive(
        options: BandFillOptions(fillColor: bandDef.fillColor, invertedFillColor: bandDef.invertedFillColor),
      );
      handle._band = band;
      handle.series[bandDef.upper].attachPrimitive(band);
    }
    handle._out = [for (final _ in indicator.lines) <double?>[]];
    handle._sync();
    source.subscribeDataChanged(handle._onSourceChanged);
    volume?.subscribeDataChanged(handle._onSourceChanged);
    return handle;
  }
}
