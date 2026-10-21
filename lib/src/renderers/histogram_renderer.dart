// Port of lightweight-charts src/renderers/histogram-renderer.ts
import 'dart:math' as math;
import 'dart:ui';

import '../model/series.dart';
import 'draw_utils.dart';
import 'paint_context.dart';

const int _showSpacingMinimalBarWidth = 1;
const int _alignToMinimalWidthLimit = 4;

class _Column {
  _Column(this.left, this.right, this.roundedCenter, this.center, this.index, this.y, this.color);

  int left;
  int right;
  final int roundedCenter;
  final double center;
  final int index;
  final double y;
  final Color color;
}

void paintHistogram(SeriesPaintContext ctx, HistogramSeriesModel series) {
  final (from, to) = series.itemsInRange(ctx.visibleRange);
  if (from >= to) return;

  final pr = ctx.pixelRatio;
  final ts = ctx.timeScale;
  final barSpacing = ts.barSpacing;

  final spacing = (barSpacing * pr).ceil() <= _showSpacingMinimalBarWidth ? 0 : math.max(1, pr.floor());
  final columnWidth = (barSpacing * pr).round() - spacing;

  final columns = <_Column>[];
  for (var i = from; i < to; i++) {
    final item = series.data[i];
    final index = series.indices[i];
    final xMedia = ts.indexToCoordinate(index);
    final x = (xMedia * pr).round();
    int left;
    int right;
    if (columnWidth % 2 != 0) {
      final halfWidth = (columnWidth - 1) ~/ 2;
      left = x - halfWidth;
      right = x + halfWidth;
    } else {
      // Shift a pixel to the left.
      final halfWidth = columnWidth ~/ 2;
      left = x - halfWidth;
      right = x + halfWidth - 1;
    }
    columns.add(_Column(left, right, x, xMedia * pr, index, series.priceToCoordinate(item.value), series.itemColor(item)));
  }

  // Align neighbouring columns so gaps are uniform.
  for (var i = 1; i < columns.length; i++) {
    final current = columns[i];
    final prev = columns[i - 1];
    if (current.index != prev.index + 1) continue;
    if (current.left - prev.right != spacing + 1) {
      if (prev.roundedCenter > prev.center) {
        // prev was shifted to the left, so add a pixel to its right.
        prev.right = current.left - spacing - 1;
      } else {
        current.left = prev.right + spacing + 1;
      }
    }
  }

  var minWidth = (barSpacing * pr).ceil();
  for (final current in columns) {
    // Happens when bar spacing < 1.
    if (current.right < current.left) current.right = current.left;
    minWidth = math.min(minWidth, current.right - current.left + 1);
  }

  if (spacing > 0 && minWidth < _alignToMinimalWidthLimit) {
    for (final current in columns) {
      final width = current.right - current.left + 1;
      if (width > minWidth) {
        if (current.roundedCenter > current.center) {
          current.right -= 1;
        } else {
          current.left += 1;
        }
      }
    }
  }

  final tickWidth = math.max(1, pr.floor());
  final histogramBase = (series.priceToCoordinate(series.options.base) * pr).round();
  final topHistogramBase = histogramBase - tickWidth ~/ 2;
  final bottomHistogramBase = topHistogramBase + tickWidth;

  final paint = Paint()..isAntiAlias = false;
  for (final column in columns) {
    final y = (column.y * pr).round();
    int top;
    int bottom;
    if (y <= topHistogramBase) {
      top = y;
      bottom = bottomHistogramBase;
    } else {
      top = topHistogramBase;
      bottom = y - tickWidth ~/ 2 + tickWidth;
    }
    paint.color = column.color;
    fillRect(ctx.canvas, paint, column.left.toDouble(), top.toDouble(), (column.right - column.left + 1).toDouble(),
        (bottom - top).toDouble());
  }
}
