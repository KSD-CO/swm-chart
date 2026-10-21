import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/animation.dart' show Curves;
import 'package:flutter/rendering.dart';

import '../model/chart_model.dart';
import '../model/pane.dart';
import '../model/series.dart';
import '../options.dart';
import '../plugins/primitive.dart';
import '../renderers/draw_utils.dart';
import '../renderers/paint_context.dart';
import 'attribution_logo.dart';

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

/// Black or white, whichever reads better on [background]. Same threshold
/// as lightweight-charts' `generateContrastColors`.
Color contrastColor(Color background) {
  final r = background.r * 255, g = background.g * 255, b = background.b * 255;
  final luminance = 0.199 * r + 0.687 * g + 0.114 * b;
  return luminance > 160 ? const Color(0xFF000000) : const Color(0xFFFFFFFF);
}

class ChartPainter extends CustomPainter {
  ChartPainter({required this.model, required this.pixelRatio, required this.textCache, this.activeSeparator})
      : super(repaint: model);

  final ChartModel model;
  final double pixelRatio;
  final TextCache textCache;

  /// Separator being dragged, drawn with the hover color.
  final int? activeSeparator;

  ChartOptions get _o => model.options;

  TextPainter _text(String text, {Color? color, FontWeight weight = FontWeight.normal}) =>
      textCache.get(text, color ?? _o.layout.textColor, _o.layout.fontSize, _o.layout.fontFamily, weight: weight);

  double get _labelHeight {
    final f = _o.layout.fontSize;
    return f + 2 * (2.5 / 12 * f);
  }

  double get pr => pixelRatio;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    model.layout(size, pixelRatio, (t) => _text(t).width);

    final bottomColor = _o.layout.backgroundBottomColor;
    canvas.drawRect(
      Offset.zero & size,
      bottomColor == null
          ? (Paint()..color = _o.layout.backgroundColor)
          : (Paint()
            ..shader = ui.Gradient.linear(Offset.zero, Offset(0, size.height), [_o.layout.backgroundColor, bottomColor])),
    );

    for (var i = 0; i < model.panes.length; i++) {
      final pane = model.panes[i];
      final rect = model.paneRect(i);
      canvas.save();
      canvas.clipRect(rect);
      canvas.translate(rect.left, rect.top);
      _paintPane(canvas, i, pane, rect.size);
      canvas.restore();

      if (model.leftAxisWidth > 0) _paintPriceAxis(canvas, i, pane, AxisSide.left);
      if (model.rightAxisWidth > 0) _paintPriceAxis(canvas, i, pane, AxisSide.right);
      if (i < model.panes.length - 1) _paintSeparator(canvas, i, pane, size.width);
    }

    if (_o.layout.attributionLogo && model.panes.isNotEmpty) {
      final logo = attributionLogoRect(model.paneRect(model.panes.length - 1));
      if (logo.top >= 0) paintAttributionLogo(canvas, logo.topLeft, darkBackground: isDarkTheme(_o.layout.textColor));
    }

    if (model.timeAxisHeight > 0) _paintTimeAxis(canvas, size);
  }

  void _paintSeparator(Canvas canvas, int index, Pane pane, double width) {
    final o = _o.layout.panes;
    final y = pane.top + pane.height;
    canvas.drawRect(Rect.fromLTWH(0, y, width, paneSeparatorHeight), Paint()..color = o.separatorColor);
    if (activeSeparator == index) {
      canvas.drawRect(Rect.fromLTWH(0, y - 3, width, paneSeparatorHeight + 6), Paint()..color = o.separatorHoverColor);
    }
  }

  // ---- pane ----

  void _paintPane(Canvas canvas, int index, Pane pane, Size paneSize) {
    final ts = model.timeScale;
    final visible = ts.visibleStrictRange();
    final crosshair = model.crosshair;

    canvas.save();
    canvas.scale(1 / pr);
    _paintGrid(canvas, pane, paneSize);
    canvas.restore();

    _paintPrimitives(canvas, pane, PrimitiveZOrder.bottom);

    canvas.save();
    canvas.scale(1 / pr);
    if (visible != null) {
      final ctx = SeriesPaintContext(
        canvas: canvas,
        pixelRatio: pr,
        timeScale: ts,
        visibleRange: visible,
        paneSize: paneSize,
        backgroundColor: _o.layout.backgroundColor,
        conflationFactor: ts.conflationFactor(pr),
      );
      _paintBaseLines(canvas, pane, paneSize);
      for (final s in model.drawOrder(pane)) {
        if (s.visible && !s.priceScale.isEmpty) s.paint(ctx);
      }
      _paintPriceLines(canvas, pane, paneSize);
    }
    canvas.restore();

    _paintPrimitives(canvas, pane, PrimitiveZOrder.normal);

    canvas.save();
    canvas.scale(1 / pr);
    if (crosshair != null) _paintCrosshairLines(canvas, paneSize, crosshair, crosshair.paneIndex == index);
    canvas.restore();

    if (crosshair != null) _paintCrosshairMarkers(canvas, pane, crosshair);
    _paintLastPriceAnimation(canvas, pane);
    _paintAxisLabelTitles(canvas, pane, paneSize);
    _paintPrimitives(canvas, pane, PrimitiveZOrder.top);
  }

  void _paintPrimitives(Canvas canvas, Pane pane, PrimitiveZOrder z) {
    for (final p in pane.primitives) {
      if (p.zOrder == z) p.paint(model.primitiveContext(pane, null, canvas));
    }
    for (final s in pane.series) {
      if (!s.visible || s.priceScale.isEmpty) continue;
      for (final p in s.primitives) {
        if (p.zOrder == z) p.paint(model.primitiveContext(pane, s, canvas));
      }
    }
  }

  void _paintGrid(Canvas canvas, Pane pane, Size paneSize) {
    final grid = _o.grid;
    final lineWidth = math.max(1, pr.floor()).toDouble();
    final paint = Paint()..isAntiAlias = false;

    if (grid.vertLines.visible) {
      paint.color = grid.vertLines.color;
      for (final mark in model.timeScale.marks(_o.layout.fontSize, model.formatTickMark)) {
        final x = (mark.coord * pr).roundToDouble();
        drawVerticalLine(canvas, paint, x, 0, paneSize.height * pr, lineWidth, grid.vertLines.style);
      }
    }
    if (grid.horzLines.visible) {
      paint.color = grid.horzLines.color;
      for (final mark in pane.defaultPriceScale.marks()) {
        final y = (mark.coord * pr).roundToDouble();
        drawHorizontalLine(canvas, paint, y, 0, paneSize.width * pr, lineWidth, grid.horzLines.style);
      }
    }
  }

  /// Zero line of the percentage modes, like upstream's base line.
  void _paintBaseLines(Canvas canvas, Pane pane, Size paneSize) {
    final paint = Paint()..isAntiAlias = false;
    for (final s in pane.series) {
      final o = s.options;
      final ps = s.priceScale;
      if (!s.visible || !o.baseLineVisible || !ps.isPercentLike || ps.isEmpty || s.baseValue == null) continue;
      final y = (s.priceToCoordinate(s.baseValue!) * pr).roundToDouble();
      paint.color = o.baseLineColor;
      final width = math.max(1, (o.baseLineWidth * pr).floor()).toDouble();
      drawHorizontalLine(canvas, paint, y, 0, paneSize.width * pr, width, o.baseLineStyle);
    }
  }

  void _paintPriceLines(Canvas canvas, Pane pane, Size paneSize) {
    final paint = Paint()..isAntiAlias = false;
    final visible = model.timeScale.visibleStrictRange();
    for (final s in pane.series) {
      if (!s.visible || s.priceScale.isEmpty) continue;
      final item = s.priceLineItem(visible);
      if (s.options.priceLineVisible && item != null) {
        final y = (s.priceToCoordinate(s.closeValue(item)) * pr).roundToDouble();
        paint.color = s.options.priceLineColor ?? s.itemColor(item);
        final width = math.max(1, (s.options.priceLineWidth * pr).floor()).toDouble();
        drawHorizontalLine(canvas, paint, y, 0, paneSize.width * pr, width, s.options.priceLineStyle);
      }
      for (final line in s.priceLines) {
        final o = line.options;
        if (!o.lineVisible) continue;
        final y = (s.priceToCoordinate(o.price) * pr).roundToDouble();
        paint.color = o.color;
        final width = math.max(1, (o.lineWidth * pr).floor()).toDouble();
        drawHorizontalLine(canvas, paint, y, 0, paneSize.width * pr, width, o.lineStyle);
      }
    }
  }

  void _paintCrosshairLines(Canvas canvas, Size paneSize, CrosshairState c, bool hoveredPane) {
    final paint = Paint()..isAntiAlias = false;
    final vert = _o.crosshair.vertLine;
    final horz = _o.crosshair.horzLine;
    if (vert.visible) {
      paint.color = vert.color;
      final width = math.max(1, (vert.width * pr).floor()).toDouble();
      drawVerticalLine(canvas, paint, (c.x * pr).roundToDouble(), 0, paneSize.height * pr, width, vert.style);
    }
    if (horz.visible && hoveredPane) {
      paint.color = horz.color;
      final width = math.max(1, (horz.width * pr).floor()).toDouble();
      drawHorizontalLine(canvas, paint, (c.y * pr).roundToDouble(), 0, paneSize.width * pr, width, horz.style);
    }
  }

  void _paintCrosshairMarkers(Canvas canvas, Pane pane, CrosshairState c) {
    for (final s in pane.series) {
      if (s is! LineLikeSeriesModel || !s.visible || !s.options.crosshairMarkerVisible) continue;
      final item = s.itemAt(c.index);
      if (item == null || s.priceScale.isEmpty) continue;
      final o = s.options;
      final center = Offset(c.x, s.priceToCoordinate(item.value));
      canvas.drawCircle(
        center,
        o.crosshairMarkerRadius + o.crosshairMarkerBorderWidth,
        Paint()..color = o.crosshairMarkerBorderColor ?? _o.layout.backgroundColor,
      );
      canvas.drawCircle(
        center,
        o.crosshairMarkerRadius,
        Paint()..color = o.crosshairMarkerBackgroundColor ?? s.lineColor(item),
      );
    }
  }

  /// Port of `series-last-price-animation-renderer.ts`: a pulsing circle on
  /// the last point.
  void _paintLastPriceAnimation(Canvas canvas, Pane pane) {
    for (final s in pane.series) {
      if (s is! LineLikeSeriesModel || !s.visible || s.priceScale.isEmpty) continue;
      final mode = s.options.lastPriceAnimation;
      if (mode == LastPriceAnimationMode.disabled) continue;
      final last = s.lastItem;
      if (last == null) continue;
      final elapsed = mode == LastPriceAnimationMode.continuous
          ? model.now
          : (s.lastUpdateTime == null ? null : model.now - s.lastUpdateTime!);
      if (elapsed == null || (mode == LastPriceAnimationMode.onDataUpdate && elapsed >= lastPriceAnimationPeriod)) {
        continue;
      }
      final t = (elapsed.inMicroseconds % lastPriceAnimationPeriod.inMicroseconds) /
          lastPriceAnimationPeriod.inMicroseconds;
      final x = model.timeScale.indexToCoordinate(s.indices.last);
      final y = s.priceToCoordinate(last.value);
      final color = s.lineColor(last);
      final radius = s.options.lineWidth + 1;
      // Expanding, fading ring over the first half of the period.
      final ringT = (t * 2).clamp(0.0, 1.0);
      final ringRadius = radius + (radius * 2.5) * Curves.easeOut.transform(ringT);
      final alpha = (1 - ringT) * 0.4;
      canvas.drawCircle(Offset(x, y), ringRadius, Paint()..color = color.withValues(alpha: alpha * color.a));
      canvas.drawCircle(Offset(x, y), radius, Paint()..color = color);
    }
  }

  /// Titles of last value labels and price lines, drawn inside the pane next
  /// to the axis.
  void _paintAxisLabelTitles(Canvas canvas, Pane pane, Size paneSize) {
    final padding = _o.layout.fontSize / 12 * 5;
    for (final side in AxisSide.values) {
      final axisWidth = side == AxisSide.left ? model.leftAxisWidth : model.rightAxisWidth;
      if (axisWidth == 0) continue;
      for (final label in _alignedLabels(pane, side)) {
        if (label.title.isEmpty) continue;
        final text = _text(label.title, color: label.textColor ?? contrastColor(label.background));
        final width = text.width + padding * 2;
        final left = side == AxisSide.right ? paneSize.width - width : 0.0;
        final rect = Rect.fromLTWH(left, label.y - _labelHeight / 2, width, _labelHeight);
        canvas.drawRect(rect, Paint()..color = label.background);
        text.paint(canvas, Offset(rect.left + padding, label.y - text.height / 2));
      }
    }
  }

  // ---- price axis ----

  List<PriceAxisLabelSpec> _alignedLabels(Pane pane, AxisSide side) {
    final labels = model.priceAxisLabels(pane, side);
    if (model.scaleOnSide(pane, side).options.alignLabels) _alignLabels(labels, pane.height);
    return labels;
  }

  /// Pushes overlapping labels apart, like lightweight-charts' `alignLabels`.
  void _alignLabels(List<PriceAxisLabelSpec> labels, double paneHeight) {
    if (labels.length < 2) return;
    final h = _labelHeight;
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

  void _paintPriceAxis(Canvas canvas, int index, Pane pane, AxisSide side) {
    final ps = model.scaleOnSide(pane, side);
    final isLeft = side == AxisSide.left;
    final width = isLeft ? model.leftAxisWidth : model.rightAxisWidth;
    final left = isLeft ? 0.0 : model.size.width - width;
    final f = _o.layout.fontSize;
    final padding = f / 12 * 5;
    const tickLength = 5.0;

    canvas.save();
    canvas.clipRect(Rect.fromLTWH(left, pane.top, width, pane.height));
    canvas.translate(0, pane.top);

    if (ps.options.borderVisible) {
      final borderWidth = math.max(1, pr.floor()) / pr;
      canvas.drawRect(
        Rect.fromLTWH(isLeft ? left + width - borderWidth : left, 0, borderWidth, pane.height),
        Paint()..color = ps.options.borderColor,
      );
    }

    double textX(TextPainter t) => isLeft ? left + width - 1 - tickLength - padding - t.width : left + 1 + tickLength + padding;

    final tickPaint = Paint()..color = ps.options.borderColor;
    final tickWidth = math.max(1, pr.floor()) / pr;
    for (final mark in ps.marks()) {
      final t = _text(mark.label);
      t.paint(canvas, Offset(textX(t), mark.coord - t.height / 2));
      if (ps.options.ticksVisible) {
        final x = isLeft ? left + width - 1 - tickLength : left + 1;
        canvas.drawRect(Rect.fromLTWH(x, mark.coord - tickWidth / 2, tickLength, tickWidth), tickPaint);
      }
    }

    for (final label in _alignedLabels(pane, side)) {
      _paintAxisLabel(canvas, left, width, label.y, label.text, label.background, label.textColor, isLeft, textX);
    }

    final c = model.crosshair;
    final horz = _o.crosshair.horzLine;
    if (c != null && c.paneIndex == index && horz.visible && horz.labelVisible && !ps.isEmpty) {
      final text = ps.formatLogical(ps.coordinateToDisplay(c.y));
      _paintAxisLabel(canvas, left, width, c.y, text, horz.labelBackgroundColor, null, isLeft, textX);
    }
    canvas.restore();
  }

  void _paintAxisLabel(
    Canvas canvas,
    double left,
    double width,
    double y,
    String text,
    Color background,
    Color? textColor,
    bool isLeft,
    double Function(TextPainter) textX,
  ) {
    final rect = Rect.fromLTWH(left, y - _labelHeight / 2, width, _labelHeight);
    const r = Radius.circular(2);
    canvas.drawRRect(
      isLeft
          ? RRect.fromRectAndCorners(rect, topLeft: r, bottomLeft: r)
          : RRect.fromRectAndCorners(rect, topRight: r, bottomRight: r),
      Paint()..color = background,
    );
    final t = _text(text, color: textColor ?? contrastColor(background));
    t.paint(canvas, Offset(textX(t), y - t.height / 2));
  }

  // ---- time axis ----

  void _paintTimeAxis(Canvas canvas, Size size) {
    final ts = model.timeScale;
    final top = size.height - model.timeAxisHeight;
    final height = model.timeAxisHeight;
    final paneLeft = model.leftAxisWidth;
    final paneWidth = model.paneWidth;
    final f = _o.layout.fontSize;

    canvas.save();
    canvas.clipRect(Rect.fromLTWH(0, top, size.width, height));

    if (ts.options.borderVisible) {
      final borderWidth = math.max(1, pr.floor()) / pr;
      final border = Paint()..color = ts.options.borderColor;
      canvas.drawRect(Rect.fromLTWH(0, top, size.width, borderWidth), border);
      if (model.leftAxisWidth > 0 && _o.leftPriceScale.borderVisible) {
        canvas.drawRect(
          Rect.fromLTWH(paneLeft - borderWidth, top, borderWidth, height),
          Paint()..color = _o.leftPriceScale.borderColor,
        );
      }
      if (model.rightAxisWidth > 0 && _o.rightPriceScale.borderVisible) {
        canvas.drawRect(
          Rect.fromLTWH(paneLeft + paneWidth, top, borderWidth, height),
          Paint()..color = _o.rightPriceScale.borderColor,
        );
      }
    }

    canvas.save();
    canvas.clipRect(Rect.fromLTWH(paneLeft, top, paneWidth, height));
    final marks = ts.marks(f, model.formatTickMark);
    if (marks.isNotEmpty) {
      final maxWeight = model.behavior.maxTickMarkWeight(marks.map((m) => m.weight));
      final bold = ts.options.allowBoldLabels;
      final labelY = top + 1 + 5 + 3 * f / 12;
      final tickPaint = Paint()..color = ts.options.borderColor;
      final tickWidth = math.max(1, pr.floor()) / pr;
      for (final mark in marks) {
        if (mark.coord < -50 || mark.coord > paneWidth + 50) continue;
        final t = _text(mark.label, weight: bold && mark.weight >= maxWeight ? FontWeight.bold : FontWeight.normal);
        final x = (mark.coord - t.width / 2).clamp(0.0, math.max(0.0, paneWidth - t.width)).toDouble();
        t.paint(canvas, Offset(paneLeft + x, labelY));
        if (ts.options.ticksVisible) {
          canvas.drawRect(Rect.fromLTWH(paneLeft + mark.coord - tickWidth / 2, top + 1, tickWidth, 5), tickPaint);
        }
      }
    }

    for (final label in model.timeAxisPrimitiveLabels()) {
      _paintTimeLabel(canvas, label.coordinate, top, height, label.text, label.backgroundColor, label.textColor);
    }

    final c = model.crosshair;
    final vert = _o.crosshair.vertLine;
    final time = c == null ? null : ts.indexToTime(c.index);
    if (c != null && time != null && vert.visible && vert.labelVisible) {
      _paintTimeLabel(canvas, c.x, top, height, model.formatTime(time), vert.labelBackgroundColor, null);
    }
    canvas.restore();
    canvas.restore();
  }

  void _paintTimeLabel(Canvas canvas, double x, double top, double height, String text, Color bg, Color? fg) {
    final f = _o.layout.fontSize;
    final t = _text(text, color: fg ?? contrastColor(bg));
    final paddingH = 9 * f / 12;
    final w = t.width + paddingH * 2;
    final paneWidth = model.paneWidth;
    final left = model.leftAxisWidth + (x - w / 2).clamp(0.0, math.max(0.0, paneWidth - w)).toDouble();
    const r = Radius.circular(2);
    canvas.drawRRect(
      RRect.fromRectAndCorners(Rect.fromLTWH(left, top, w, height), bottomLeft: r, bottomRight: r),
      Paint()..color = bg,
    );
    t.paint(canvas, Offset(left + paddingH, top + (height - t.height) / 2));
  }

  @override
  bool shouldRepaint(ChartPainter oldDelegate) =>
      oldDelegate.model != model || oldDelegate.pixelRatio != pixelRatio || oldDelegate.activeSeparator != activeSeparator;
}
