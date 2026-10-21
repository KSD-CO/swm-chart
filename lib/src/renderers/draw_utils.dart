// Port of lightweight-charts src/renderers/draw-line.ts helpers.
import 'dart:ui';

import '../options.dart';

List<double> dashPattern(LineStyle style, double lineWidth) {
  switch (style) {
    case LineStyle.solid:
      return const [];
    case LineStyle.dotted:
      return [lineWidth, lineWidth];
    case LineStyle.dashed:
      return [2 * lineWidth, 2 * lineWidth];
    case LineStyle.largeDashed:
      return [6 * lineWidth, 6 * lineWidth];
    case LineStyle.sparseDotted:
      return [lineWidth, 4 * lineWidth];
  }
}

/// Horizontal line in bitmap coordinates. [width] is in physical pixels.
void drawHorizontalLine(
  Canvas canvas,
  Paint paint,
  double y,
  double left,
  double right,
  double width,
  LineStyle style,
) {
  final correction = (width.round() % 2 == 1) ? 0.5 : 0.0;
  final yy = y + correction;
  paint
    ..strokeWidth = width
    ..style = PaintingStyle.stroke;
  final dash = dashPattern(style, width);
  if (dash.isEmpty) {
    canvas.drawLine(Offset(left, yy), Offset(right, yy), paint);
    return;
  }
  for (var x = left, i = 0; x < right; i++) {
    final len = dash[i % dash.length];
    if (i.isEven) {
      canvas.drawLine(Offset(x, yy), Offset((x + len).clamp(left, right), yy), paint);
    }
    x += len;
  }
}

/// Vertical line in bitmap coordinates. [width] is in physical pixels.
void drawVerticalLine(
  Canvas canvas,
  Paint paint,
  double x,
  double top,
  double bottom,
  double width,
  LineStyle style,
) {
  final correction = (width.round() % 2 == 1) ? 0.5 : 0.0;
  final xx = x + correction;
  paint
    ..strokeWidth = width
    ..style = PaintingStyle.stroke;
  final dash = dashPattern(style, width);
  if (dash.isEmpty) {
    canvas.drawLine(Offset(xx, top), Offset(xx, bottom), paint);
    return;
  }
  for (var y = top, i = 0; y < bottom; i++) {
    final len = dash[i % dash.length];
    if (i.isEven) {
      canvas.drawLine(Offset(xx, y), Offset(xx, (y + len).clamp(top, bottom)), paint);
    }
    y += len;
  }
}

/// Returns [path] cut into dashes.
Path dashPath(Path path, List<double> pattern) {
  if (pattern.isEmpty) return path;
  final result = Path();
  for (final metric in path.computeMetrics()) {
    var distance = 0.0;
    var i = 0;
    while (distance < metric.length) {
      final len = pattern[i % pattern.length];
      if (i.isEven) {
        result.addPath(metric.extractPath(distance, distance + len), Offset.zero);
      }
      distance += len;
      i++;
    }
  }
  return result;
}

/// `fillRect` with integer bitmap coordinates, like CanvasRenderingContext2D.
void fillRect(Canvas canvas, Paint paint, double x, double y, double w, double h) {
  if (w <= 0 || h <= 0) return;
  canvas.drawRect(Rect.fromLTWH(x, y, w, h), paint);
}

void fillRectInnerBorder(Canvas canvas, Paint paint, double x, double y, double width, double height, double borderWidth) {
  fillRect(canvas, paint, x + borderWidth, y, width - borderWidth * 2, borderWidth);
  fillRect(canvas, paint, x + borderWidth, y + height - borderWidth, width - borderWidth * 2, borderWidth);
  fillRect(canvas, paint, x, y, borderWidth, height);
  fillRect(canvas, paint, x + width - borderWidth, y, borderWidth, height);
}
