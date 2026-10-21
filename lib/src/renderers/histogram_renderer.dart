// Port of lightweight-charts src/renderers/histogram-renderer.ts
import 'dart:math' as math;
import 'dart:typed_data';

import '../model/series.dart';
import 'draw_utils.dart';
import 'paint_context.dart';

const int _showSpacingMinimalBarWidth = 1;
const int _alignToMinimalWidthLimit = 4;

void paintHistogram(SeriesPaintContext ctx, HistogramSeriesModel series) {
  final items = series.renderItems(ctx.conflationFactor);
  final (from, to) = items.itemsInRange(ctx.visibleRange);
  if (from >= to) return;

  final pr = ctx.pixelRatio;
  final ts = ctx.timeScale;
  final barSpacing = ts.barSpacing;
  final (xa, xb) = ts.indexTransform();
  final linear = series.priceTransform();
  final defaultColor = series.options.color.toARGB32();

  final spacing = (barSpacing * pr).ceil() <= _showSpacingMinimalBarWidth ? 0 : math.max(1, pr.floor());
  final columnWidth = (barSpacing * pr).round() - spacing;

  // Columns as parallel arrays: no object per column.
  final n = to - from;
  final lefts = Int32List(n), rights = Int32List(n), roundedCenters = Int32List(n), indices = Int32List(n);
  final centers = Float64List(n), ys = Float64List(n);
  final colors = Int32List(n);
  for (var i = from; i < to; i++) {
    final item = items.data[i];
    final j = i - from;
    final index = items.indices[i];
    final xMedia = xa * index + xb;
    final x = (xMedia * pr).round();
    if (columnWidth % 2 != 0) {
      final halfWidth = (columnWidth - 1) ~/ 2;
      lefts[j] = x - halfWidth;
      rights[j] = x + halfWidth;
    } else {
      // Shift a pixel to the left.
      final halfWidth = columnWidth ~/ 2;
      lefts[j] = x - halfWidth;
      rights[j] = x + halfWidth - 1;
    }
    roundedCenters[j] = x;
    centers[j] = xMedia * pr;
    indices[j] = index;
    ys[j] = linear != null ? linear.$1 * item.value + linear.$2 : series.priceToCoordinate(item.value);
    colors[j] = item.color?.toARGB32() ?? defaultColor;
  }

  // Align neighbouring columns so gaps are uniform.
  for (var j = 1; j < n; j++) {
    if (indices[j] != indices[j - 1] + 1) continue;
    if (lefts[j] - rights[j - 1] != spacing + 1) {
      if (roundedCenters[j - 1] > centers[j - 1]) {
        // prev was shifted to the left, so add a pixel to its right.
        rights[j - 1] = lefts[j] - spacing - 1;
      } else {
        lefts[j] = rights[j - 1] + spacing + 1;
      }
    }
  }

  var minWidth = (barSpacing * pr).ceil();
  for (var j = 0; j < n; j++) {
    // Happens when bar spacing < 1.
    if (rights[j] < lefts[j]) rights[j] = lefts[j];
    minWidth = math.min(minWidth, rights[j] - lefts[j] + 1);
  }

  if (spacing > 0 && minWidth < _alignToMinimalWidthLimit) {
    for (var j = 0; j < n; j++) {
      final width = rights[j] - lefts[j] + 1;
      if (width > minWidth) {
        if (roundedCenters[j] > centers[j]) {
          rights[j] -= 1;
        } else {
          lefts[j] += 1;
        }
      }
    }
  }

  final tickWidth = math.max(1, pr.floor());
  final histogramBase = (series.priceToCoordinate(series.options.base) * pr).round();
  final topHistogramBase = histogramBase - tickWidth ~/ 2;
  final bottomHistogramBase = topHistogramBase + tickWidth;

  final batch = RectBatch.shared..reset(n);
  for (var j = 0; j < n; j++) {
    final y = (ys[j] * pr).round();
    int top;
    int bottom;
    if (y <= topHistogramBase) {
      top = y;
      bottom = bottomHistogramBase;
    } else {
      top = topHistogramBase;
      bottom = y - tickWidth ~/ 2 + tickWidth;
    }
    batch.add(lefts[j].toDouble(), top.toDouble(), (rights[j] - lefts[j] + 1).toDouble(), (bottom - top).toDouble(),
        colors[j]);
  }
  batch.flush(ctx.canvas);
}
