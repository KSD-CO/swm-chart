// A legend (and optional tooltip) showing the values under the crosshair,
// like TradingView's: OHLC with the change for candles and bars, one value
// per line series, and one row per indicator.
import 'package:flutter/painting.dart';

import '../api/chart_controller.dart';
import '../data.dart';
import '../indicators/attach.dart';
import '../model/series.dart';
import 'primitive.dart';

enum LegendMode {
  /// Rows at the top-left of each pane.
  legend,

  /// A box next to the crosshair in the pane it is in (time and values).
  tooltip,
}

class LegendOptions {
  const LegendOptions({
    this.mode = LegendMode.legend,
    this.title,
    this.showOhlc = true,
    this.showChange = true,
    this.fontSize = 11,
    this.textColor,
    this.backgroundColor,
    this.formatTime,
  });

  final LegendMode mode;

  /// First row of the first pane, e.g. `BTC/USD · 5m`.
  final String? title;

  /// Open, high, low and close for candlestick and bar series; otherwise
  /// only the close.
  final bool showOhlc;

  /// Change from the previous close, in percent.
  final bool showChange;
  final double fontSize;

  /// Labels; `null` uses the chart's text color.
  final Color? textColor;

  /// Background behind the rows (legend) or of the box (tooltip); `null`
  /// uses the chart background, slightly transparent.
  final Color? backgroundColor;

  /// Time in the tooltip; `null` uses the chart's crosshair time format.
  final String Function(num time)? formatTime;
}

/// One value of a legend row.
class LegendValue {
  const LegendValue(this.text, this.color, {this.label});

  final String? label;
  final String text;
  final Color color;
}

/// One row: a series, or an indicator with all its lines.
class LegendRow {
  const LegendRow(this.name, this.values);

  final String name;
  final List<LegendValue> values;
}

/// Adds a legend to every pane of [chart], following the crosshair (or
/// showing the last bar when it is hidden). Panes added later get one too.
///
/// ```dart
/// final legend = createLegend(chart, const LegendOptions(title: 'BTC/USD · 1h'));
/// ```
ChartLegend createLegend(ChartController chart, [LegendOptions options = const LegendOptions()]) =>
    ChartLegend._(chart, options);

class ChartLegend {
  ChartLegend._(this.chart, this._options) {
    _sync();
    chart.model.addListener(_sync);
  }

  final ChartController chart;
  LegendOptions _options;
  final Map<PaneApi, _LegendPrimitive> _primitives = {};

  LegendOptions get options => _options;

  set options(LegendOptions value) {
    _options = value;
    for (final p in _primitives.values) {
      p.requestUpdate();
    }
  }

  // Attach to new panes, drop removed ones.
  void _sync() {
    final panes = chart.panes();
    if (panes.length == _primitives.length && panes.every(_primitives.containsKey)) return;
    _primitives.removeWhere((pane, _) => !panes.contains(pane));
    for (final pane in panes) {
      if (_primitives.containsKey(pane)) continue;
      final p = _LegendPrimitive(this, pane);
      _primitives[pane] = p;
      pane.attachPrimitive(p);
    }
  }

  /// Rows of [pane] at logical [index] (`null`: the last bar of each series).
  List<LegendRow> rowsOf(PaneApi pane, int? index) {
    final rows = <LegendRow>[];
    final done = <IndicatorHandle>{};
    for (final s in pane.getSeries()) {
      if (!s.options.visible) continue;
      final handle = indicatorOf(s);
      if (handle != null) {
        if (!done.add(handle)) continue;
        final values = <LegendValue>[];
        for (final line in handle.series) {
          final v = _valueOf(line, index);
          if (v != null) values.add(v);
        }
        if (values.isNotEmpty) rows.add(LegendRow(handle.indicator.name, values));
        continue;
      }
      final row = _rowOf(s, index);
      if (row != null) rows.add(row);
    }
    return rows;
  }

  SeriesData? _itemOf(SeriesApi s, int? index) => index == null ? s.model.lastItem : s.dataByIndex(index);

  LegendValue? _valueOf(SeriesApi s, int? index) {
    final item = _itemOf(s, index);
    if (item == null) return null;
    final model = s.model as SeriesModel<SeriesData, dynamic>;
    return LegendValue(s.formatPrice(model.closeValue(item)), model.itemColor(item));
  }

  LegendRow? _rowOf(SeriesApi s, int? index) {
    final item = _itemOf(s, index);
    if (item == null) return null;
    final model = s.model as SeriesModel<SeriesData, dynamic>;
    final color = model.itemColor(item);
    final name = s.options.title.isNotEmpty ? s.options.title : _typeName(s);
    final values = <LegendValue>[];
    if (item is OhlcData && _options.showOhlc) {
      values
        ..add(LegendValue(s.formatPrice(item.open), color, label: 'O'))
        ..add(LegendValue(s.formatPrice(item.high), color, label: 'H'))
        ..add(LegendValue(s.formatPrice(item.low), color, label: 'L'))
        ..add(LegendValue(s.formatPrice(item.close), color, label: 'C'));
    } else {
      values.add(LegendValue(s.formatPrice(model.closeValue(item)), color));
    }
    if (_options.showChange && item is OhlcData) {
      final change = _change(s, item);
      if (change != null) {
        values.add(LegendValue('${change >= 0 ? '+' : '−'}${change.abs().toStringAsFixed(2)}%', color));
      }
    }
    return LegendRow(name, values);
  }

  /// Change of [item]'s close from the previous bar's close, in percent.
  double? _change(SeriesApi s, OhlcData item) {
    final data = s.model.data;
    final pos = s.model.lowerBound(s.chart.timeScale().timeToIndex(item.time) ?? -1);
    if (pos <= 0 || pos >= data.length) return null;
    final prev = data[pos - 1];
    if (prev is! OhlcData || prev.close == 0) return null;
    return (item.close - prev.close) / prev.close * 100;
  }

  static String _typeName(SeriesApi s) => switch (s.seriesType()) {
    SeriesType.candlestick => 'Candles',
    SeriesType.bar => 'Bars',
    SeriesType.line => 'Line',
    SeriesType.area => 'Area',
    SeriesType.baseline => 'Baseline',
    SeriesType.histogram => 'Histogram',
    SeriesType.custom => 'Series',
  };

  void dispose() {
    chart.model.removeListener(_sync);
    for (final entry in _primitives.entries) {
      entry.key.detachPrimitive(entry.value);
    }
    _primitives.clear();
  }
}

class _LegendPrimitive extends ChartPrimitive {
  _LegendPrimitive(this._legend, this._pane);

  final ChartLegend _legend;
  final PaneApi _pane;

  @override
  PrimitiveZOrder get zOrder => PrimitiveZOrder.top;

  @override
  void paint(PrimitivePaintContext ctx) {
    final o = _legend.options;
    final textColor = o.textColor ?? ctx.textColor;
    final background = o.backgroundColor ?? ctx.backgroundColor.withValues(alpha: 0.75);
    final index = ctx.crosshairIndex;
    final rows = _legend.rowsOf(_pane, index);
    final title = _pane.paneIndex() == 0 ? o.title : null;

    if (o.mode == LegendMode.tooltip) {
      final at = ctx.crosshairPosition;
      if (at == null || index == null || rows.isEmpty) return;
      _paintTooltip(ctx, at, index, rows, textColor, background);
      return;
    }

    var y = 4.0;
    if (title != null) {
      y += _paintSpans(ctx, Offset(6, y), [_span(title, textColor, o, bold: true)], background);
    }
    for (final row in rows) {
      y += _paintSpans(ctx, Offset(6, y), _rowSpans(row, textColor, o), background);
    }
  }

  TextSpan _span(String text, Color color, LegendOptions o, {bool bold = false}) => TextSpan(
    text: text,
    style: TextStyle(color: color, fontSize: o.fontSize, fontWeight: bold ? FontWeight.w600 : FontWeight.normal),
  );

  List<TextSpan> _rowSpans(LegendRow row, Color textColor, LegendOptions o) => [
    _span(row.name, textColor, o, bold: true),
    for (final v in row.values) ...[
      _span('  ${v.label == null ? '' : '${v.label} '}', textColor, o),
      _span(v.text, v.color, o),
    ],
  ];

  /// Paints one line of text with a background; returns its height.
  double _paintSpans(PrimitivePaintContext ctx, Offset at, List<TextSpan> spans, Color background) {
    final tp = TextPainter(
      text: TextSpan(children: spans, style: const TextStyle(height: 1.2)),
      textDirection: TextDirection.ltr,
      maxLines: 1,
      ellipsis: '…',
    )..layout(maxWidth: ctx.paneSize.width - at.dx - 4);
    ctx.canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(at.dx - 3, at.dy - 1, tp.width + 6, tp.height + 2),
        const Radius.circular(3),
      ),
      Paint()..color = background,
    );
    tp.paint(ctx.canvas, at);
    final h = tp.height + 3;
    tp.dispose();
    return h;
  }

  void _paintTooltip(
    PrimitivePaintContext ctx,
    Offset at,
    int index,
    List<LegendRow> rows,
    Color textColor,
    Color background,
  ) {
    final o = _legend.options;
    final time = _legend.chart.timeScale().coordinateToTime(at.dx);
    final timeText = time == null ? null : (o.formatTime?.call(time) ?? _legend.chart.model.formatTime(time));
    final painters = [
      if (timeText != null)
        TextPainter(text: _span(timeText, textColor, o, bold: true), textDirection: TextDirection.ltr),
      for (final row in rows)
        TextPainter(
          text: TextSpan(children: _rowSpans(row, textColor, o)),
          textDirection: TextDirection.ltr,
        ),
    ];
    var width = 0.0, height = 0.0;
    for (final p in painters) {
      p.layout(maxWidth: ctx.paneSize.width * 0.8);
      width = width > p.width ? width : p.width;
      height += p.height + 2;
    }
    const pad = 8.0, gap = 14.0;
    // Right of the crosshair, or left of it near the right edge.
    var left = at.dx + gap;
    if (left + width + pad * 2 > ctx.paneSize.width) left = at.dx - gap - width - pad * 2;
    final top = (at.dy - height / 2 - pad).clamp(
      2.0,
      (ctx.paneSize.height - height - pad * 2 - 2).clamp(2.0, double.infinity),
    );
    final box = Rect.fromLTWH(left, top, width + pad * 2, height + pad * 2);
    ctx.canvas.drawRRect(
      RRect.fromRectAndRadius(box, const Radius.circular(6)),
      Paint()..color = o.backgroundColor ?? ctx.backgroundColor.withValues(alpha: 0.92),
    );
    ctx.canvas.drawRRect(
      RRect.fromRectAndRadius(box, const Radius.circular(6)),
      Paint()
        ..style = PaintingStyle.stroke
        ..color = textColor.withValues(alpha: 0.2),
    );
    var y = top + pad;
    for (final p in painters) {
      p.paint(ctx.canvas, Offset(left + pad, y));
      y += p.height + 2;
      p.dispose();
    }
  }
}
