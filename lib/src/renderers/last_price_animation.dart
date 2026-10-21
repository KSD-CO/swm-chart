// Port of lightweight-charts src/views/pane/series-last-price-animation-pane-view.ts
// and src/renderers/series-last-price-animation-renderer.ts.
import 'dart:math' as math;
import 'dart:ui';

/// Length of one pulse.
const Duration lastPriceAnimationPeriod = Duration(milliseconds: 2600);

class _Stage {
  const _Stage(
    this.start,
    this.end,
    this.startRadius,
    this.endRadius,
    this.startFillAlpha,
    this.endFillAlpha,
    this.startStrokeAlpha,
    this.endStrokeAlpha,
  );

  final double start;
  final double end;
  final double startRadius;
  final double endRadius;
  final double startFillAlpha;
  final double endFillAlpha;
  final double startStrokeAlpha;
  final double endStrokeAlpha;
}

// Three stages: grow 4 -> 10 while the fill fades and the ring brightens,
// grow 10 -> 14 while the ring fades out, then rest.
const double _stage1 = 0.25, _stage2 = 0.275, _stage3 = 0.475;
const List<_Stage> _stages = [
  _Stage(0, _stage1, 4, 10, 0.25, 0, 0.4, 0.8),
  _Stage(_stage1, _stage1 + _stage2, 10, 14, 0, 0, 0.8, 0),
  _Stage(_stage1 + _stage2, _stage1 + _stage2 + _stage3, 14, 14, 0, 0, 0, 0),
];

/// Radius, fill and stroke of the pulse [elapsed] after it started.
(double radius, Color fill, Color stroke) lastPriceAnimationFrame(Duration elapsed, Color lineColor) {
  final period = lastPriceAnimationPeriod.inMicroseconds;
  final globalStage = (elapsed.inMicroseconds % period) / period;
  final stage = _stages.firstWhere((s) => globalStage >= s.start && globalStage <= s.end, orElse: () => _stages.last);
  final sub = (globalStage - stage.start) / (stage.end - stage.start);
  double lerp(double a, double b) => a + (b - a) * sub;
  return (
    lerp(stage.startRadius, stage.endRadius),
    lineColor.withValues(alpha: lerp(stage.startFillAlpha, stage.endFillAlpha)),
    lineColor.withValues(alpha: lerp(stage.startStrokeAlpha, stage.endStrokeAlpha)),
  );
}

/// Draws the pulse in logical pixels at [center], aligned to device pixels
/// horizontally like upstream.
void paintLastPriceAnimation(
  Canvas canvas,
  Offset center,
  double pixelRatio,
  double lineWidth,
  Color lineColor,
  Duration elapsed,
) {
  final pr = pixelRatio;
  final tickWidth = math.max(1, pr.floor());
  final correction = (tickWidth % 2) / 2;
  final cx = ((center.dx * pr).round() + correction) / pr;
  final c = Offset(cx, center.dy);
  final (radius, fill, stroke) = lastPriceAnimationFrame(elapsed, lineColor);

  canvas.drawCircle(c, math.max(2, lineWidth * 1.5), Paint()..color = lineColor);
  canvas.drawCircle(c, radius, Paint()..color = fill);
  canvas.drawCircle(
    c,
    radius + tickWidth / 2 / pr,
    Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = tickWidth / pr
      ..color = stroke,
  );
}
