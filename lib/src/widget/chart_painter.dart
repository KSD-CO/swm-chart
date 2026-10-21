import 'dart:math' as math;

import 'package:flutter/rendering.dart';

import '../model/chart_model.dart';
import '../model/series.dart';
import '../model/time_utils.dart';
import '../options.dart';
import '../renderers/draw_utils.dart';
import '../renderers/paint_context.dart';

/// Caches laid-out text. Labels repeat a lot between frames.
class TextCache {
  final Map<(String, int, double, String?, FontWeight), TextPainter> _cache = {};

  TextPainter get(String text, Color color, double fontSize, String? fontFamily, {FontWeight weight = FontWeight.normal}) {
    final key = (text, color.toARGB32(), fontSize, fontFamily, weight);
    final cached = _cache[key];
    if (cached != null) return cached;
    if (_cache.length > 1000) {
      for (final p in _cache.values) {
        p.dispose();
      }
      _cache.clear();
    }
    final painter = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(color: color, fontSize: fontSize, fontFamily: fontFamily, fontWeight: weight, height: 1),
      ),
      textDirection: TextDirection.ltr,
      maxLines: 1,
    )..layout();
    return _cache[key] = painter;
  }

  void dispose() {
    for (final p in _cache.values) {
      p.dispose();
    }
    _cache.clear();
  }
}

Color _contrastColor(Color background) {
  // Same threshold as lightweight-charts' generateContrastColors.
  final r = (background.r * 255), g = (background.g * 255), b = (background.b * 255);
  final luminance = 0.199 * r + 0.687 * g + 0.114 * b;
  return luminance > 160 ? const Color(0xFF000000) : const Color(0xFFFFFFFF);
}

class _AxisLabel {
  _AxisLabel(this.y, this.text, this.background, this.title);

  double y;
  final String text;
  final Color background;
  final String title;
}

class ChartPainter extends CustomPainter {
  ChartPainter({required this.model, required this.pixelRatio, required this.textCache}) : super(repaint: model);

  final ChartModel model;
  final double pixelRatio;
  final TextCache textCache;

  ChartOptions get _o => model.options;

  TextPainter _text(String text, {Color? color, FontWeight weight = FontWeight.normal}) =>
      textCache.get(text, color ?? _o.layout.textColor, _o.layout.fontSize, _o.layout.fontFamily, weight: weight);

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    model.layout(size, pixelRatio, (t) => _text(t).width);

    canvas.drawRect(Offset.zero & size, Paint()..color = _o.layout.backgroundColor);

    final pane = model.paneSize;
    canvas.save();
    canvas.clipRect(Offset.zero & pane);
    _paintPane(canvas, pane);
    canvas.restore();

    if (model.priceAxisWidth > 0) _paintPriceAxis(canvas, pane);
    if (model.timeAxisHeight > 0) _paintTimeAxis(canvas, pane);
  }

  // ---- pane ----

  void _paintPane(Canvas canvas, Size pane) {
    final pr = pixelRatio;
    final ts = model.timeScale;
    final visible = ts.visibleStrictRange();

    canvas.save();
    canvas.scale(1 / pr);
    _paintGrid(canvas, pane);

    if (visible != null) {
      final ctx = SeriesPaintContext(
        canvas: canvas,
        pixelRatio: pr,
        timeScale: ts,
        visibleRange: visible,
        paneSize: pane,
        backgroundColor: _o.layout.backgroundColor,
      );
      for (final s in model.series) {
        if (s.visible && !s.priceScale.isEmpty) s.paint(ctx);
      }
      _paintPriceLines(canvas, pane);
    }
    _paintCrosshairLines(canvas, pane);
    canvas.restore();

    _paintCrosshairMarkers(canvas);
    _paintSeriesTitles(canvas, pane);
  }

  void _paintGrid(Canvas canvas, Size pane) {
    final pr = pixelRatio;
    final grid = _o.grid;
    final lineWidth = math.max(1, pr.floor()).toDouble();
    final paint = Paint()..isAntiAlias = false;

    if (grid.vertLines.visible) {
      paint.color = grid.vertLines.color;
      for (final mark in model.timeScale.marks(_o.layout.fontSize, model.timeScale.formatTickMark)) {
        final x = (mark.coord * pr).roundToDouble();
        drawVerticalLine(canvas, paint, x, 0, pane.height * pr, lineWidth, grid.vertLines.style);
      }
    }
    if (grid.horzLines.visible) {
      paint.color = grid.horzLines.color;
      for (final mark in model.rightPriceScale.marks()) {
        final y = (mark.coord * pr).roundToDouble();
        drawHorizontalLine(canvas, paint, y, 0, pane.width * pr, lineWidth, grid.horzLines.style);
      }
    }
  }

  Color _lastValueColor(SeriesModel s) {
    final last = s.lastItem!;
    return s.options.priceLineColor ?? s.itemColor(last);
  }

  void _paintPriceLines(Canvas canvas, Size pane) {
    final pr = pixelRatio;
    final paint = Paint()..isAntiAlias = false;
    for (final s in model.series) {
      final last = s.lastItem;
      if (!s.visible || !s.options.priceLineVisible || last == null || s.priceScale.isEmpty) continue;
      final y = (s.priceScale.priceToCoordinate(s.closeValue(last)) * pr).roundToDouble();
      paint.color = _lastValueColor(s);
      final width = math.max(1, (s.options.priceLineWidth * pr).floor()).toDouble();
      drawHorizontalLine(canvas, paint, y, 0, pane.width * pr, width, s.options.priceLineStyle);
    }
  }

  void _paintCrosshairLines(Canvas canvas, Size pane) {
    final c = model.crosshair;
    if (c == null) return;
    final pr = pixelRatio;
    final paint = Paint()..isAntiAlias = false;
    final vert = _o.crosshair.vertLine;
    final horz = _o.crosshair.horzLine;
    if (vert.visible) {
      paint.color = vert.color;
      final width = math.max(1, (vert.width * pr).floor()).toDouble();
      drawVerticalLine(canvas, paint, (c.x * pr).roundToDouble(), 0, pane.height * pr, width, vert.style);
    }
    if (horz.visible) {
      paint.color = horz.color;
      final width = math.max(1, (horz.width * pr).floor()).toDouble();
      drawHorizontalLine(canvas, paint, (c.y * pr).roundToDouble(), 0, pane.width * pr, width, horz.style);
    }
  }

  void _paintCrosshairMarkers(Canvas canvas) {
    final c = model.crosshair;
    if (c == null) return;
    for (final s in model.series) {
      if (s is! LineSeriesModel || !s.visible || !s.options.crosshairMarkerVisible) continue;
      final item = s.itemAt(c.index);
      if (item == null || s.priceScale.isEmpty) continue;
      final o = s.options;
      final center = Offset(c.x, s.priceScale.priceToCoordinate(item.value));
      final radius = o.crosshairMarkerRadius;
      canvas.drawCircle(
        center,
        radius + o.crosshairMarkerBorderWidth,
        Paint()..color = o.crosshairMarkerBorderColor ?? _o.layout.backgroundColor,
      );
      canvas.drawCircle(center, radius, Paint()..color = o.crosshairMarkerBackgroundColor ?? s.itemColor(item));
    }
  }

  void _paintSeriesTitles(Canvas canvas, Size pane) {
    if (model.priceAxisWidth == 0) return;
    final labelHeight = _labelHeight();
    for (final label in _lastValueLabels()) {
      if (label.title.isEmpty) continue;
      final text = _text(label.title, color: _contrastColor(label.background));
      final padding = _o.layout.fontSize / 12 * 5;
      final width = text.width + padding * 2;
      final rect = Rect.fromLTWH(pane.width - width, label.y - labelHeight / 2, width, labelHeight);
      canvas.drawRect(rect, Paint()..color = label.background);
      text.paint(canvas, Offset(rect.left + padding, label.y - text.height / 2));
    }
  }

  // ---- price axis ----

  double _labelHeight() {
    final f = _o.layout.fontSize;
    return f + 2 * (2.5 / 12 * f);
  }

  List<_AxisLabel> _lastValueLabels() {
    final labels = <_AxisLabel>[];
    for (final s in model.series) {
      final last = s.lastItem;
      if (!s.visible || !s.options.lastValueVisible || last == null || s.priceScale.isEmpty) continue;
      final price = s.closeValue(last);
      labels.add(_AxisLabel(
        s.priceScale.priceToCoordinate(price),
        model.formatSeriesPrice(s, price),
        _lastValueColor(s),
        s.options.title,
      ));
    }
    _alignLabels(labels);
    return labels;
  }

  /// Pushes overlapping labels apart, like lightweight-charts' `alignLabels`.
  void _alignLabels(List<_AxisLabel> labels) {
    if (labels.length < 2) return;
    final h = _labelHeight();
    final paneHeight = model.paneSize.height;
    labels.sort((a, b) => a.y.compareTo(b.y));
    for (var i = 1; i < labels.length; i++) {
      final minY = labels[i - 1].y + h;
      if (labels[i].y < minY) labels[i].y = minY;
    }
    final overflow = labels.last.y + h / 2 - paneHeight;
    if (overflow > 0) {
      labels.last.y -= overflow;
      for (var i = labels.length - 2; i >= 0; i--) {
        final maxY = labels[i + 1].y - h;
        if (labels[i].y > maxY) labels[i].y = maxY;
      }
    }
  }

  void _paintPriceAxis(Canvas canvas, Size pane) {
    final ps = model.rightPriceScale;
    final left = pane.width;
    final width = model.priceAxisWidth;
    final f = _o.layout.fontSize;
    final padding = f / 12 * 5;
    const tickLength = 5.0;
    final pr = pixelRatio;

    canvas.save();
    canvas.clipRect(Rect.fromLTWH(left, 0, width, pane.height));

    if (ps.options.borderVisible) {
      final borderWidth = math.max(1, pr.floor()) / pr;
      canvas.drawRect(Rect.fromLTWH(left, 0, borderWidth, pane.height), Paint()..color = ps.options.borderColor);
    }

    final textX = left + 1 + tickLength + padding;
    for (final mark in ps.marks()) {
      final t = _text(mark.label);
      t.paint(canvas, Offset(textX, mark.coord - t.height / 2));
    }

    final labelHeight = _labelHeight();
    for (final label in _lastValueLabels()) {
      _paintAxisLabel(canvas, left, width, label.y, labelHeight, label.text, label.background, textX);
    }

    final c = model.crosshair;
    final horz = _o.crosshair.horzLine;
    if (c != null && horz.visible && horz.labelVisible && !ps.isEmpty) {
      _paintAxisLabel(canvas, left, width, c.y, labelHeight, ps.formatPrice(c.price), horz.labelBackgroundColor, textX);
    }
    canvas.restore();
  }

  void _paintAxisLabel(
    Canvas canvas,
    double left,
    double width,
    double y,
    double height,
    String text,
    Color background,
    double textX,
  ) {
    final rect = Rect.fromLTWH(left, y - height / 2, width, height);
    canvas.drawRRect(
      RRect.fromRectAndCorners(rect, topRight: const Radius.circular(2), bottomRight: const Radius.circular(2)),
      Paint()..color = background,
    );
    final t = _text(text, color: _contrastColor(background));
    t.paint(canvas, Offset(textX, y - t.height / 2));
  }

  // ---- time axis ----

  void _paintTimeAxis(Canvas canvas, Size pane) {
    final ts = model.timeScale;
    final top = pane.height;
    final height = model.timeAxisHeight;
    final f = _o.layout.fontSize;
    final pr = pixelRatio;

    canvas.save();
    canvas.clipRect(Rect.fromLTWH(0, top, model.size.width, height));

    if (ts.options.borderVisible) {
      final borderWidth = math.max(1, pr.floor()) / pr;
      canvas.drawRect(Rect.fromLTWH(0, top, model.size.width, borderWidth), Paint()..color = ts.options.borderColor);
      if (model.priceAxisWidth > 0 && model.rightPriceScale.options.borderVisible) {
        canvas.drawRect(
          Rect.fromLTWH(pane.width, top, borderWidth, height),
          Paint()..color = model.rightPriceScale.options.borderColor,
        );
      }
    }

    final marks = ts.marks(f, ts.formatTickMark);
    if (marks.isNotEmpty) {
      // The heaviest visible weight is drawn bold (capped at month), like upstream.
      var maxWeight = marks.map((m) => m.weight).reduce(math.max);
      if (maxWeight > TickMarkWeight.day) maxWeight = TickMarkWeight.month;

      final labelY = top + 1 + 5 + 3 * f / 12;
      for (final mark in marks) {
        if (mark.coord < -50 || mark.coord > pane.width + 50) continue;
        final t = _text(mark.label, weight: mark.weight >= maxWeight ? FontWeight.bold : FontWeight.normal);
        final x = (mark.coord - t.width / 2).clamp(0.0, math.max(0.0, pane.width - t.width)).toDouble();
        t.paint(canvas, Offset(x, labelY));
      }
    }

    final c = model.crosshair;
    final vert = _o.crosshair.vertLine;
    final time = c == null ? null : ts.indexToTime(c.index);
    if (c != null && time != null && vert.visible && vert.labelVisible) {
      final t = _text(model.formatTime(time), color: _contrastColor(vert.labelBackgroundColor));
      final paddingH = 9 * f / 12;
      final w = t.width + paddingH * 2;
      final left = (c.x - w / 2).clamp(0.0, math.max(0.0, pane.width - w)).toDouble();
      final rect = Rect.fromLTWH(left, top, w, height);
      canvas.drawRRect(
        RRect.fromRectAndCorners(rect, bottomLeft: const Radius.circular(2), bottomRight: const Radius.circular(2)),
        Paint()..color = vert.labelBackgroundColor,
      );
      t.paint(canvas, Offset(left + paddingH, top + (height - t.height) / 2));
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(ChartPainter oldDelegate) =>
      oldDelegate.model != model || oldDelegate.pixelRatio != pixelRatio;
}
