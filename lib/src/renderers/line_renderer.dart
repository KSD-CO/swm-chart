// Port of lightweight-charts src/renderers/line-renderer.ts (simple and stepped lines).
import 'dart:math' as math;
import 'dart:ui';

import '../model/series.dart';
import '../options.dart';
import 'draw_utils.dart';
import 'paint_context.dart';

void paintLine(SeriesPaintContext ctx, LineSeriesModel series) {
  var (from, to) = series.itemsInRange(ctx.visibleRange);
  // Include one point on each side so the line continues past the edges.
  from = math.max(0, from - 1);
  to = math.min(series.data.length, to + 1);
  if (from >= to) return;

  final o = series.options;
  final pr = ctx.pixelRatio;
  final ts = ctx.timeScale;
  final ps = series.priceScale;

  final xs = List<double>.generate(to - from, (i) => ts.indexToCoordinate(series.indices[from + i]) * pr);
  final ys = List<double>.generate(to - from, (i) => ps.priceToCoordinate(series.data[from + i].value) * pr);

  final paint = Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = o.lineWidth * pr
    ..strokeJoin = StrokeJoin.round
    ..strokeCap = StrokeCap.butt
    ..isAntiAlias = true;

  if (o.lineVisible) {
    if (xs.length == 1) {
      // A single point has no segment; draw a dot like the upstream renderer.
      final fill = Paint()..color = series.itemColor(series.data[from]);
      ctx.canvas.drawCircle(Offset(xs[0], ys[0]), o.lineWidth * pr / 2, fill);
    } else {
      final dash = dashPattern(o.lineStyle, o.lineWidth * pr);
      // Split the line into runs of the same color.
      var runStart = 0;
      while (runStart < xs.length - 1) {
        final color = series.itemColor(series.data[from + runStart + 1]);
        final path = Path()..moveTo(xs[runStart], ys[runStart]);
        var i = runStart + 1;
        for (; i < xs.length; i++) {
          if (i > runStart + 1 && series.itemColor(series.data[from + i]) != color) break;
          if (o.lineType == LineType.withSteps) path.lineTo(xs[i], ys[i - 1]);
          path.lineTo(xs[i], ys[i]);
        }
        paint.color = color;
        ctx.canvas.drawPath(dashPath(path, dash), paint);
        runStart = i - 1;
      }
    }
  }

  if (o.pointMarkersVisible) {
    final radius = (o.pointMarkersRadius ?? o.lineWidth / 2 + 2) * pr;
    final fill = Paint()..style = PaintingStyle.fill;
    for (var i = 0; i < xs.length; i++) {
      fill.color = series.itemColor(series.data[from + i]);
      ctx.canvas.drawCircle(Offset(xs[i], ys[i]), radius, fill);
    }
  }
}
