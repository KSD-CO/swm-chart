// Port of lightweight-charts src/renderers/walk-line.ts
import 'dart:math' as math;
import 'dart:ui';

import '../options.dart';

/// Points of a line in bitmap coordinates.
class LinePoints {
  LinePoints(this.xs, this.ys);

  final List<double> xs;
  final List<double> ys;

  int get length => xs.length;
}

/// A run of consecutive points `[start, end]` sharing a style. Neighbouring
/// runs share their boundary point, so segment `i-1 -> i` belongs to the run
/// containing point `i`, as upstream's `walkLine` does.
class StyleRun<K> {
  StyleRun(this.start, this.end, this.style);

  final int start;
  final int end;
  final K style;
}

List<StyleRun<K>> styleRuns<K>(int length, K Function(int index) styleOf) {
  if (length == 0) return const [];
  if (length == 1) return [StyleRun(0, 0, styleOf(0))];
  final runs = <StyleRun<K>>[];
  var start = 0;
  var style = styleOf(1);
  for (var i = 2; i < length; i++) {
    final s = styleOf(i);
    if (s != style) {
      runs.add(StyleRun(start, i - 1, style));
      start = i - 1;
      style = s;
    }
  }
  runs.add(StyleRun(start, length - 1, style));
  return runs;
}

/// Adds the line through points `[start, end]` to [path] (starting with a
/// moveTo).
void walkLine(Path path, LinePoints p, LineType type, int start, int end) {
  path.moveTo(p.xs[start], p.ys[start]);
  for (var i = start + 1; i <= end; i++) {
    switch (type) {
      case LineType.simple:
        path.lineTo(p.xs[i], p.ys[i]);
      case LineType.withSteps:
        path.lineTo(p.xs[i], p.ys[i - 1]);
        path.lineTo(p.xs[i], p.ys[i]);
      case LineType.curved:
        final (cp1, cp2) = _controlPoints(p, i);
        path.cubicTo(cp1.dx, cp1.dy, cp2.dx, cp2.dy, p.xs[i], p.ys[i]);
    }
  }
}

double _segmentSlope(double x1, double y1, double x2, double y2) {
  final width = x2 - x1;
  return width != 0 ? (y2 - y1) / width : 0;
}

/// Slope limiter from Steffen's method for monotone interpolation
/// (Steffen, M. 1990, Astron. Astrophys. 239, 443).
double _monotoneSlope(double leftWidth, double leftSlope, double rightWidth, double rightSlope) {
  if (leftWidth <= 0 || rightWidth <= 0) return 0;
  final weightedSlope = (leftSlope * rightWidth + rightSlope * leftWidth) / (leftWidth + rightWidth);
  return (leftSlope.sign + rightSlope.sign) *
      math.min(math.min(leftSlope.abs(), rightSlope.abs()), 0.5 * weightedSlope.abs());
}

/// Control points of the cubic between points `end - 1` and `end`.
(Offset, Offset) _controlPoints(LinePoints p, int end) {
  final sx = p.xs[end - 1], sy = p.ys[end - 1];
  final ex = p.xs[end], ey = p.ys[end];
  final width = ex - sx;
  final slope = _segmentSlope(sx, sy, ex, ey);

  double slopeThrough(double px, double py, int neighbour) {
    if (neighbour < 0 || neighbour >= p.length) return slope;
    final nx = p.xs[neighbour], ny = p.ys[neighbour];
    return _monotoneSlope((nx - px).abs(), _segmentSlope(px, py, nx, ny), width, slope);
  }

  final offset = width / 3;
  final startSlope = slopeThrough(sx, sy, end - 2);
  final endSlope = slopeThrough(ex, ey, end + 1);
  return (Offset(sx + offset, sy + offset * startSlope), Offset(ex - offset, ey - offset * endSlope));
}
