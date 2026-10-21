// Port of lightweight-charts src/renderers/area-renderer*.ts and
// baseline-renderer-*.ts.
import 'dart:math' as math;
import 'dart:ui';

import '../model/series.dart';
import 'line_renderer.dart';
import 'paint_context.dart';
import 'walk_line.dart';

/// Fills the area between the line and [baseY] (bitmap coordinates), one
/// path per style run so per-point fill colors work.
void _fillArea<K>(
  SeriesPaintContext ctx,
  LineLikeSeriesModel series,
  LinePoints points,
  int from,
  double baseY,
  K Function(int dataIndex) styleOf,
  Shader Function(K style) shaderOf,
) {
  final paint = Paint()
    ..style = PaintingStyle.fill
    ..isAntiAlias = true;
  final type = series.options.lineType;

  if (points.length == 1) {
    // Single point: a bar-wide column, like upstream.
    final half = ctx.timeScale.barSpacing * ctx.pixelRatio / 2;
    final x = points.xs[0], y = points.ys[0];
    paint.shader = shaderOf(styleOf(from));
    ctx.canvas.drawRect(Rect.fromLTRB(x - half, math.min(y, baseY), x + half, math.max(y, baseY)), paint);
    return;
  }

  for (final run in styleRuns(points.length, (i) => styleOf(from + i))) {
    final path = Path();
    walkLine(path, points, type, run.start, run.end);
    path
      ..lineTo(points.xs[run.end], baseY)
      ..lineTo(points.xs[run.start], baseY)
      ..close();
    paint.shader = shaderOf(run.style);
    ctx.canvas.drawPath(path, paint);
  }
}

/// Top and bottom of the gradient in bitmap coordinates.
(double, double) _gradientBounds(SeriesPaintContext ctx, LinePoints points, bool relative) {
  final paneHeight = ctx.paneSize.height * ctx.pixelRatio;
  if (!relative) return (0, paneHeight);
  final top = points.ys.reduce(math.min);
  final bottom = points.ys.reduce(math.max);
  return (top, bottom == top ? top + 1 : bottom);
}

void paintArea(SeriesPaintContext ctx, AreaSeriesModel series) {
  final visible = visibleLinePoints(ctx, series);
  if (visible == null) return;
  final (points, from, items) = visible;
  final o = series.options;
  final pr = ctx.pixelRatio;

  final baseY = o.invertFilledArea ? 0.0 : ctx.paneSize.height * pr;
  final (top, bottom) = o.relativeGradient ? _gradientBounds(ctx, points, true) : (0.0, ctx.paneSize.height * pr);

  _fillArea<(Color, Color)>(ctx, series, points, from, baseY, (i) {
    final d = items.data[i];
    return (d.topColor ?? o.topColor, d.bottomColor ?? o.bottomColor);
  }, (style) => Gradient.linear(Offset(0, top), Offset(0, bottom), [style.$1, style.$2]));

  Color colorOf(int i) => series.lineColor(items.data[i]);
  if (o.lineVisible) strokeLine(ctx, series, points, from, colorOf);
  paintPointMarkers(ctx, series, points, from, colorOf);
}

void paintBaseline(SeriesPaintContext ctx, BaselineSeriesModel series) {
  final visible = visibleLinePoints(ctx, series);
  if (visible == null) return;
  final (points, from, items) = visible;
  final o = series.options;
  final pr = ctx.pixelRatio;
  final width = ctx.paneSize.width * pr;
  final height = ctx.paneSize.height * pr;

  final baseY = series.priceToCoordinate(o.baseValue) * pr;
  final (top, bottom) = _gradientBounds(ctx, points, o.relativeGradient);
  final ratio = ((baseY - top) / (bottom - top)).clamp(0.0, 1.0);

  _fillArea<(Color, Color, Color, Color)>(ctx, series, points, from, baseY, (i) {
    final d = items.data[i];
    return (
      d.topFillColor1 ?? o.topFillColor1,
      d.topFillColor2 ?? o.topFillColor2,
      d.bottomFillColor1 ?? o.bottomFillColor1,
      d.bottomFillColor2 ?? o.bottomFillColor2,
    );
  }, (s) => Gradient.linear(Offset(0, top), Offset(0, bottom), [s.$1, s.$2, s.$3, s.$4], [0, ratio, ratio, 1]));

  if (o.lineVisible) {
    // The line takes the top color above the base value and the bottom
    // color below it; clip instead of upstream's hard-stop gradient.
    final canvas = ctx.canvas;
    canvas.save();
    canvas.clipRect(Rect.fromLTRB(0, 0, width, baseY));
    strokeLine(ctx, series, points, from, (i) => items.data[i].topLineColor ?? o.topLineColor);
    canvas.restore();
    canvas.save();
    canvas.clipRect(Rect.fromLTRB(0, baseY, width, height));
    strokeLine(ctx, series, points, from, (i) => items.data[i].bottomLineColor ?? o.bottomLineColor);
    canvas.restore();
  }
  paintPointMarkers(ctx, series, points, from, (i) => series.lineColor(items.data[i]));
}
