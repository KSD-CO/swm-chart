// Port of lightweight-charts src/renderers/bars-renderer.ts
import 'dart:math' as math;

import '../model/series.dart';
import 'draw_utils.dart';
import 'paint_context.dart';

int optimalBarWidth(double barSpacing, double pixelRatio) => (barSpacing * 0.3 * pixelRatio).floor();

void paintBars(SeriesPaintContext ctx, BarSeriesModel series) {
  final items = series.renderItems(ctx.conflationFactor);
  final (from, to) = items.itemsInRange(ctx.visibleRange);
  if (from >= to) return;

  final o = series.options;
  final pr = ctx.pixelRatio;
  final ts = ctx.timeScale;
  final barSpacing = ts.barSpacing;

  var barWidth = math.max(pr.floor(), optimalBarWidth(barSpacing, pr));
  // Keep parity with the crosshair line so it stays centered.
  if (barWidth >= 2) {
    final lineWidth = math.max(1, pr.floor());
    if (lineWidth % 2 != barWidth % 2) barWidth--;
  }
  // When compressed a bar could become thinner than 1 logical pixel.
  final barLineWidth = o.thinBars ? math.min(barWidth, pr.floor()) : barWidth;
  final drawOpenClose = barLineWidth <= barWidth && barSpacing >= (1.5 * pr).floor();

  final batch = RectBatch.shared..reset();
  final (xa, xb) = ts.indexTransform();
  final linear = series.priceTransform();
  double y(double price) => linear != null ? linear.$1 * price + linear.$2 : series.priceToCoordinate(price);
  final upColor = o.upColor.toARGB32(), downColor = o.downColor.toARGB32();

  for (var i = from; i < to; i++) {
    final d = items.data[i];
    final color = d.color?.toARGB32() ?? (d.isUp ? upColor : downColor);

    final x = xa * items.indices[i] + xb;
    final openY = y(d.open);
    final highY = y(d.high);
    final lowY = y(d.low);
    final closeY = y(d.close);

    final bodyWidthHalf = (barLineWidth * 0.5).floor();
    final bodyCenter = (x * pr).round();
    final bodyLeft = bodyCenter - bodyWidthHalf;
    final bodyWidth = barLineWidth;
    final bodyRight = bodyLeft + bodyWidth - 1;

    final high = math.min(highY, lowY);
    final low = math.max(highY, lowY);
    final bodyTop = (high * pr).round() - bodyWidthHalf;
    final bodyBottom = (low * pr).round() + bodyWidthHalf;
    final bodyHeight = math.max(bodyBottom - bodyTop, barLineWidth);

    batch.add(bodyLeft.toDouble(), bodyTop.toDouble(), bodyWidth.toDouble(), bodyHeight.toDouble(), color);

    if (!drawOpenClose) continue;
    final sideWidth = (barWidth * 1.5).ceil();

    if (o.openVisible) {
      final openLeft = bodyCenter - sideWidth;
      var openTop = math.max(bodyTop, (openY * pr).round() - bodyWidthHalf);
      var openBottom = openTop + bodyWidth - 1;
      if (openBottom > bodyTop + bodyHeight - 1) {
        openBottom = bodyTop + bodyHeight - 1;
        openTop = openBottom - bodyWidth + 1;
      }
      batch.add(openLeft.toDouble(), openTop.toDouble(), (bodyLeft - openLeft).toDouble(),
          (openBottom - openTop + 1).toDouble(), color);
    }

    final closeRight = bodyCenter + sideWidth;
    var closeTop = math.max(bodyTop, (closeY * pr).round() - bodyWidthHalf);
    var closeBottom = closeTop + bodyWidth - 1;
    if (closeBottom > bodyTop + bodyHeight - 1) {
      closeBottom = bodyTop + bodyHeight - 1;
      closeTop = closeBottom - bodyWidth + 1;
    }
    batch.add(bodyRight + 1.0, closeTop.toDouble(), (closeRight - bodyRight).toDouble(),
        (closeBottom - closeTop + 1).toDouble(), color);
  }
  batch.flush(ctx.canvas);
}
