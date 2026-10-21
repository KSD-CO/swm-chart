// Port of lightweight-charts src/renderers/candlesticks-renderer.ts
import 'dart:math' as math;
import 'dart:typed_data';

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

/// Visible candles in structure-of-arrays form: no object per candle.
class _Bars {
  _Bars(this.length)
      : x = Float64List(length),
        openY = Float64List(length),
        highY = Float64List(length),
        lowY = Float64List(length),
        closeY = Float64List(length),
        barColor = Int32List(length),
        borderColor = Int32List(length),
        wickColor = Int32List(length);

  final int length;
  final Float64List x;
  final Float64List openY;
  final Float64List highY;
  final Float64List lowY;
  final Float64List closeY;
  final Int32List barColor;
  final Int32List borderColor;
  final Int32List wickColor;
}

void paintCandlesticks(SeriesPaintContext ctx, CandlestickSeriesModel series) {
  final items = series.renderItems(ctx.conflationFactor);
  final (from, to) = items.itemsInRange(ctx.visibleRange);
  if (from >= to) return;

  final o = series.options;
  final ts = ctx.timeScale;
  final (xa, xb) = ts.indexTransform();
  final linear = series.priceTransform();
  final pa = linear?.$1 ?? 0, pb = linear?.$2 ?? 0;
  double y(double price) => linear != null ? pa * price + pb : series.priceToCoordinate(price);

  final up = o.upColor.toARGB32(), down = o.downColor.toARGB32();
  final borderUp = o.borderUpColor.toARGB32(), borderDown = o.borderDownColor.toARGB32();
  final wickUp = o.wickUpColor.toARGB32(), wickDown = o.wickDownColor.toARGB32();

  final bars = _Bars(to - from);
  for (var i = from; i < to; i++) {
    final d = items.data[i];
    final isUp = d.isUp;
    final j = i - from;
    bars.x[j] = xa * items.indices[i] + xb;
    bars.openY[j] = y(d.open);
    bars.highY[j] = y(d.high);
    bars.lowY[j] = y(d.low);
    bars.closeY[j] = y(d.close);
    bars.barColor[j] = d.color?.toARGB32() ?? (isUp ? up : down);
    bars.borderColor[j] = d.borderColor?.toARGB32() ?? (isUp ? borderUp : borderDown);
    bars.wickColor[j] = d.wickColor?.toARGB32() ?? (isUp ? wickUp : wickDown);
  }

  final pr = ctx.pixelRatio;
  var barWidth = optimalCandlestickWidth(ts.barSpacing, pr);
  // Grid and crosshair lines are floor(pixelRatio) wide; keep candle width
  // parity equal so the crosshair stays centered on the candle.
  if (barWidth >= 2) {
    final wickWidth = pr.floor();
    if (wickWidth % 2 != barWidth % 2) barWidth--;
  }

  // All rectangles go into one vertex batch, in upstream's drawing order:
  // wicks, borders, bodies.
  final batch = RectBatch.shared..reset();
  if (o.wickVisible) _drawWicks(batch, bars, barWidth, ts.barSpacing, pr);
  if (o.borderVisible) _drawBorder(batch, bars, barWidth, ts.barSpacing, pr);

  final borderWidth = _calculateBorderWidth(barWidth, pr);
  if (!o.borderVisible || barWidth > borderWidth * 2) {
    _drawCandles(batch, bars, barWidth, borderWidth, o.borderVisible, pr);
  }
  batch.flush(ctx.canvas);
}

void _drawWicks(RectBatch batch, _Bars bars, int barWidth, double barSpacing, double pr) {
  var wickWidth = math.min(pr.floor(), (barSpacing * pr).floor());
  wickWidth = math.max(pr.floor(), math.min(wickWidth, barWidth));
  final wickOffset = (wickWidth * 0.5).floor();

  int? prevEdge;
  for (var j = 0; j < bars.length; j++) {
    final top = (math.min(bars.openY[j], bars.closeY[j]) * pr).round();
    final bottom = (math.max(bars.openY[j], bars.closeY[j]) * pr).round();
    final high = (bars.highY[j] * pr).round();
    final low = (bars.lowY[j] * pr).round();
    final scaledX = (pr * bars.x[j]).round();

    var left = scaledX - wickOffset;
    final right = left + wickWidth - 1;
    if (prevEdge != null) {
      left = math.max(prevEdge + 1, left);
      left = math.min(left, right);
    }
    final width = (right - left + 1).toDouble();

    batch.add(left.toDouble(), high.toDouble(), width, (top - high).toDouble(), bars.wickColor[j]);
    batch.add(left.toDouble(), bottom + 1.0, width, (low - bottom).toDouble(), bars.wickColor[j]);
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

void _drawBorder(RectBatch batch, _Bars bars, int barWidth, double barSpacing, double pr) {
  final borderWidth = _calculateBorderWidth(barWidth, pr);

  int? prevEdge;
  for (var j = 0; j < bars.length; j++) {
    var left = (bars.x[j] * pr).round() - (barWidth * 0.5).floor();
    // Calculate right before patching left.
    final right = left + barWidth - 1;

    final top = (math.min(bars.openY[j], bars.closeY[j]) * pr).round();
    final bottom = (math.max(bars.openY[j], bars.closeY[j]) * pr).round();

    if (prevEdge != null) {
      left = math.max(prevEdge + 1, left);
      left = math.min(left, right);
    }
    final width = (right - left + 1).toDouble();
    final height = (bottom - top + 1).toDouble();
    if (barSpacing * pr > 2 * borderWidth) {
      batch.addInnerBorder(left.toDouble(), top.toDouble(), width, height, borderWidth.toDouble(), bars.borderColor[j]);
    } else {
      batch.add(left.toDouble(), top.toDouble(), width, height, bars.borderColor[j]);
    }
    prevEdge = right;
  }
}

void _drawCandles(
  RectBatch batch,
  _Bars bars,
  int barWidth,
  int borderWidth,
  bool borderVisible,
  double pr,
) {
  for (var j = 0; j < bars.length; j++) {
    var top = (math.min(bars.openY[j], bars.closeY[j]) * pr).round();
    var bottom = (math.max(bars.openY[j], bars.closeY[j]) * pr).round();
    var left = (bars.x[j] * pr).round() - (barWidth * 0.5).floor();
    var right = left + barWidth - 1;

    if (borderVisible) {
      left += borderWidth;
      top += borderWidth;
      right -= borderWidth;
      bottom -= borderWidth;
    }
    if (top > bottom) continue;

    batch.add(left.toDouble(), top.toDouble(), (right - left + 1).toDouble(), (bottom - top + 1).toDouble(), bars.barColor[j]);
  }
}
