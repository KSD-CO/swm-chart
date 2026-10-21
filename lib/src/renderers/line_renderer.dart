// Port of lightweight-charts src/renderers/line-renderer.ts
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui';

import '../data.dart';
import '../model/series.dart';
import '../series_options.dart';
import 'draw_utils.dart';
import 'paint_context.dart';
import 'walk_line.dart';

/// Visible points of a line-like series in bitmap coordinates, extended by
/// one point on each side so the line continues past the pane edges. The
/// int is the position of the first point in the returned items.
(LinePoints, int, SeriesItems<T>)? visibleLinePoints<T extends SingleValueData>(
  SeriesPaintContext ctx,
  LineLikeSeriesModel<T, LineLikeSeriesOptions> series,
) {
  final items = series.renderItems(ctx.conflationFactor);
  var (from, to) = items.itemsInRange(ctx.visibleRange);
  from = math.max(0, from - 1);
  to = math.min(items.length, to + 1);
  if (from >= to) return null;
  final pr = ctx.pixelRatio;
  final ts = ctx.timeScale;
  final (xa, xb) = ts.indexTransform();
  final linear = series.priceTransform();
  final n = to - from;
  final xs = Float64List(n), ys = Float64List(n);
  for (var i = 0; i < n; i++) {
    xs[i] = (xa * items.indices[from + i] + xb) * pr;
    final v = items.data[from + i].value;
    ys[i] = (linear != null ? linear.$1 * v + linear.$2 : series.priceToCoordinate(v)) * pr;
  }
  return (LinePoints(xs, ys), from, items);
}

Paint linePaint(LineLikeSeriesOptions o, double pr) => Paint()
  ..style = PaintingStyle.stroke
  ..strokeWidth = o.lineWidth * pr
  ..strokeJoin = StrokeJoin.round
  ..strokeCap = StrokeCap.butt
  ..isAntiAlias = true;

/// Strokes the line, split into runs of the same color.
void strokeLine(
  SeriesPaintContext ctx,
  LineLikeSeriesModel series,
  LinePoints points,
  int from,
  Color Function(int dataIndex) colorOf,
) {
  final o = series.options;
  final pr = ctx.pixelRatio;
  final paint = linePaint(o, pr);
  final dash = dashPattern(o.lineStyle, o.lineWidth * pr);

  if (points.length == 1) {
    // A single point: a horizontal tick as wide as a bar, like upstream.
    final half = ctx.timeScale.barSpacing * pr / 2;
    paint.color = colorOf(from);
    ctx.canvas.drawLine(
      Offset(points.xs[0] - half, points.ys[0]),
      Offset(points.xs[0] + half, points.ys[0]),
      paint,
    );
    return;
  }

  for (final run in styleRuns(points.length, (i) => colorOf(from + i))) {
    final path = Path();
    walkLine(path, points, o.lineType, run.start, run.end);
    paint.color = run.style;
    ctx.canvas.drawPath(dashPath(path, dash), paint);
  }
}

void paintPointMarkers(
  SeriesPaintContext ctx,
  LineLikeSeriesModel series,
  LinePoints points,
  int from,
  Color Function(int dataIndex) colorOf,
) {
  final o = series.options;
  if (!o.pointMarkersVisible) return;
  final radius = (o.pointMarkersRadius ?? o.lineWidth / 2 + 2) * ctx.pixelRatio;
  final fill = Paint()..style = PaintingStyle.fill;
  for (var i = 0; i < points.length; i++) {
    fill.color = colorOf(from + i);
    ctx.canvas.drawCircle(Offset(points.xs[i], points.ys[i]), radius, fill);
  }
}

void paintLine(SeriesPaintContext ctx, LineSeriesModel series) {
  final visible = visibleLinePoints(ctx, series);
  if (visible == null) return;
  final (points, from, items) = visible;
  Color colorOf(int i) => series.lineColor(items.data[i]);
  if (series.options.lineVisible) strokeLine(ctx, series, points, from, colorOf);
  paintPointMarkers(ctx, series, points, from, colorOf);
}
