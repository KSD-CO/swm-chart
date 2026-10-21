// Port of lightweight-charts src/renderers/candlesticks-renderer.ts
import 'dart:math' as math;
import 'dart:ui';

import '../model/series.dart';
import 'draw_utils.dart';
import 'paint_context.dart';

const double _barBorderWidth = 1;

int optimalCandlestickWidth(double barSpacing, double pixelRatio) {
  const specialCaseFrom = 2.5;
  const specialCaseTo = 4.0;
  const specialCaseCoeff = 3;
  if (barSpacing >= specialCaseFrom && barSpacing <= specialCaseTo) {
    return (specialCaseCoeff * pixelRatio).floor();
  }
  // Coefficient is 1 for small bar spacing and goes to 0.8 as it grows.
  const reducingCoeff = 0.2;
  final coeff = 1 - reducingCoeff * math.atan(math.max(specialCaseTo, barSpacing) - specialCaseTo) / (math.pi * 0.5);
  final res = (barSpacing * coeff * pixelRatio).floor();
  final scaledBarSpacing = (barSpacing * pixelRatio).floor();
  final optimal = math.min(res, scaledBarSpacing);
  return math.max(pixelRatio.floor(), optimal);
}

class _Bar {
  _Bar(this.x, this.openY, this.highY, this.lowY, this.closeY, this.barColor, this.borderColor, this.wickColor);

  final double x;
  final double openY;
  final double highY;
  final double lowY;
  final double closeY;
  final Color barColor;
  final Color borderColor;
  final Color wickColor;
}

void paintCandlesticks(SeriesPaintContext ctx, CandlestickSeriesModel series) {
  final items = series.renderItems(ctx.conflationFactor);
  final (from, to) = items.itemsInRange(ctx.visibleRange);
  if (from >= to) return;

  final o = series.options;
  final ts = ctx.timeScale;
  final bars = <_Bar>[];
  for (var i = from; i < to; i++) {
    final d = items.data[i];
    final up = d.isUp;
    bars.add(_Bar(
      ts.indexToCoordinate(items.indices[i]),
      series.priceToCoordinate(d.open),
      series.priceToCoordinate(d.high),
      series.priceToCoordinate(d.low),
      series.priceToCoordinate(d.close),
      d.color ?? (up ? o.upColor : o.downColor),
      d.borderColor ?? (up ? o.borderUpColor : o.borderDownColor),
      d.wickColor ?? (up ? o.wickUpColor : o.wickDownColor),
    ));
  }

  final pr = ctx.pixelRatio;
  var barWidth = optimalCandlestickWidth(ts.barSpacing, pr);
  // Grid and crosshair lines are floor(pixelRatio) wide; keep candle width
  // parity equal so the crosshair stays centered on the candle.
  if (barWidth >= 2) {
    final wickWidth = pr.floor();
    if (wickWidth % 2 != barWidth % 2) barWidth--;
  }

  final paint = Paint()..isAntiAlias = false;
  final canvas = ctx.canvas;

  if (o.wickVisible) _drawWicks(canvas, paint, bars, barWidth, ts.barSpacing, pr);
  if (o.borderVisible) _drawBorder(canvas, paint, bars, barWidth, ts.barSpacing, pr);

  final borderWidth = _calculateBorderWidth(barWidth, pr);
  if (!o.borderVisible || barWidth > borderWidth * 2) {
    _drawCandles(canvas, paint, bars, barWidth, borderWidth, o.borderVisible, pr);
  }
}

void _drawWicks(Canvas canvas, Paint paint, List<_Bar> bars, int barWidth, double barSpacing, double pr) {
  var wickWidth = math.min(pr.floor(), (barSpacing * pr).floor());
  wickWidth = math.max(pr.floor(), math.min(wickWidth, barWidth));
  final wickOffset = (wickWidth * 0.5).floor();

  int? prevEdge;
  for (final bar in bars) {
    paint.color = bar.wickColor;

    final top = (math.min(bar.openY, bar.closeY) * pr).round();
    final bottom = (math.max(bar.openY, bar.closeY) * pr).round();
    final high = (bar.highY * pr).round();
    final low = (bar.lowY * pr).round();
    final scaledX = (pr * bar.x).round();

    var left = scaledX - wickOffset;
    final right = left + wickWidth - 1;
    if (prevEdge != null) {
      left = math.max(prevEdge + 1, left);
      left = math.min(left, right);
    }
    final width = (right - left + 1).toDouble();

    fillRect(canvas, paint, left.toDouble(), high.toDouble(), width, (top - high).toDouble());
    fillRect(canvas, paint, left.toDouble(), bottom + 1.0, width, (low - bottom).toDouble());
    prevEdge = right;
  }
}

int _calculateBorderWidth(int barWidth, double pr) {
  var borderWidth = (_barBorderWidth * pr).floor();
  if (barWidth <= 2 * borderWidth) {
    borderWidth = ((barWidth - 1) * 0.5).floor();
  }
  final res = math.max(pr.floor(), borderWidth);
  if (barWidth <= res * 2) {
    // Bodies won't be drawn; restore the original value.
    return math.max(pr.floor(), (_barBorderWidth * pr).floor());
  }
  return res;
}

void _drawBorder(Canvas canvas, Paint paint, List<_Bar> bars, int barWidth, double barSpacing, double pr) {
  final borderWidth = _calculateBorderWidth(barWidth, pr);

  int? prevEdge;
  for (final bar in bars) {
    paint.color = bar.borderColor;

    var left = (bar.x * pr).round() - (barWidth * 0.5).floor();
    // Calculate right before patching left.
    final right = left + barWidth - 1;

    final top = (math.min(bar.openY, bar.closeY) * pr).round();
    final bottom = (math.max(bar.openY, bar.closeY) * pr).round();

    if (prevEdge != null) {
      left = math.max(prevEdge + 1, left);
      left = math.min(left, right);
    }
    final width = (right - left + 1).toDouble();
    final height = (bottom - top + 1).toDouble();
    if (barSpacing * pr > 2 * borderWidth) {
      fillRectInnerBorder(canvas, paint, left.toDouble(), top.toDouble(), width, height, borderWidth.toDouble());
    } else {
      fillRect(canvas, paint, left.toDouble(), top.toDouble(), width, height);
    }
    prevEdge = right;
  }
}

void _drawCandles(
  Canvas canvas,
  Paint paint,
  List<_Bar> bars,
  int barWidth,
  int borderWidth,
  bool borderVisible,
  double pr,
) {
  for (final bar in bars) {
    var top = (math.min(bar.openY, bar.closeY) * pr).round();
    var bottom = (math.max(bar.openY, bar.closeY) * pr).round();
    var left = (bar.x * pr).round() - (barWidth * 0.5).floor();
    var right = left + barWidth - 1;

    if (borderVisible) {
      left += borderWidth;
      top += borderWidth;
      right -= borderWidth;
      bottom -= borderWidth;
    }
    if (top > bottom) continue;

    paint.color = bar.barColor;
    fillRect(canvas, paint, left.toDouble(), top.toDouble(), (right - left + 1).toDouble(), (bottom - top + 1).toDouble());
  }
}
