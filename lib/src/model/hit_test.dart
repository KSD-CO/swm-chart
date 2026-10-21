// Port of lightweight-charts' hover hit testing (renderers/hit-test-common.ts,
// line-hit-test.ts, range-hit-test.ts and the pane's hit test ordering).
import 'dart:math' as math;
import 'dart:ui';

import '../data.dart';
import '../plugins/primitive.dart';
import 'pane.dart';
import 'primitive_context.dart';
import 'series.dart';
import 'time_scale.dart';

/// What kind of object is hovered, like upstream's `HoveredInfo.objectKind`.
enum HoveredObjectKind { series, customObject, customPriceLine, seriesMarker, primitive }

/// What was hit, like upstream's `HoveredItemType`.
enum HoveredItemType { seriesPoint, seriesLine, seriesRange, marker, priceLine, primitive, custom }

/// Who owns the hovered object, like upstream's `HoveredInfo.sourceKind`.
enum HoveredSourceKind { series, seriesPrimitive, panePrimitive }

/// Like upstream's `HitTestPriority`: points beat lines beat ranges.
enum HitTestPriority { range, line, point }

class HitTestResult {
  const HitTestResult({
    required this.type,
    required this.sourceKind,
    this.series,
    this.objectId,
    required this.distance,
    required this.priority,
    this.zOrder = PrimitiveZOrder.normal,
  });

  final HoveredItemType type;
  final HoveredSourceKind sourceKind;

  /// Upstream's `hoveredTargetObjectKind`.
  HoveredObjectKind get kind => switch (type) {
    HoveredItemType.custom => objectId != null ? HoveredObjectKind.customObject : HoveredObjectKind.series,
    HoveredItemType.priceLine => HoveredObjectKind.customPriceLine,
    HoveredItemType.marker => HoveredObjectKind.seriesMarker,
    HoveredItemType.primitive => HoveredObjectKind.primitive,
    _ => HoveredObjectKind.series,
  };
  final SeriesModel? series;
  final Object? objectId;
  final double distance;
  final HitTestPriority priority;
  final PrimitiveZOrder zOrder;

  /// Whether this hit should win over [other]: higher z-order first, then
  /// priority, then distance.
  bool beats(HitTestResult other) {
    if (zOrder != other.zOrder) return zOrder.index > other.zOrder.index;
    if (priority != other.priority) return priority.index > other.priority.index;
    return distance < other.distance;
  }
}

double distanceToSegment(double x, double y, double x1, double y1, double x2, double y2) {
  final dx = x2 - x1, dy = y2 - y1;
  if (dx == 0 && dy == 0) return math.sqrt((x - x1) * (x - x1) + (y - y1) * (y - y1));
  final t = (((x - x1) * dx + (y - y1) * dy) / (dx * dx + dy * dy)).clamp(0.0, 1.0);
  final px = x1 + t * dx, py = y1 + t * dy;
  return math.sqrt((x - px) * (x - px) + (y - py) * (y - py));
}

/// Hit test of [series] at ([x], [y]) in pane coordinates.
HitTestResult? hitTestSeries(SeriesModel series, TimeScale ts, IndexRange visible, double x, double y) {
  if (!series.visible || series.priceScale.isEmpty || series.data.isEmpty) return null;
  final tol = series.options.hitTestTolerance;
  final barSpacing = ts.barSpacing;
  final index = ts.coordinateToIndex(x);

  HitTestResult result(double distance, HitTestPriority p) => HitTestResult(
    type: switch (p) {
      HitTestPriority.range => HoveredItemType.seriesRange,
      HitTestPriority.line => HoveredItemType.seriesLine,
      HitTestPriority.point => HoveredItemType.seriesPoint,
    },
    sourceKind: HoveredSourceKind.series,
    series: series,
    distance: distance,
    priority: p,
  );

  if (series is CustomSeriesModel) return _hitTestCustom(series, ts, visible, x, y);

  // Range series: the bar under x, its vertical extent widened by the tolerance.
  (double, double)? range(SeriesData item) {
    if (item is OhlcData) return (series.priceToCoordinate(item.high), series.priceToCoordinate(item.low));
    if (series is HistogramSeriesModel && item is HistogramData) {
      return (series.priceToCoordinate(item.value), series.priceToCoordinate(series.options.base));
    }
    return null;
  }

  if (series is! LineLikeSeriesModel) {
    HitTestResult? best;
    for (final i in [index - 1, index, index + 1]) {
      final item = series.itemAt(i);
      if (item == null) continue;
      final cx = ts.indexToCoordinate(i);
      if ((x - cx).abs() > barSpacing / 2 + tol) continue;
      final r = range(item);
      if (r == null) continue;
      final top = math.min(r.$1, r.$2), bottom = math.max(r.$1, r.$2);
      double? distance;
      if (y >= top && y <= bottom) {
        distance = 0;
      } else if (y >= top - tol && y <= bottom + tol) {
        distance = math.min((y - top).abs(), (bottom - y).abs());
      }
      if (distance != null && (best == null || distance < best.distance)) {
        best = result(distance, HitTestPriority.range);
      }
    }
    return best;
  }

  // Line-like series: distance to the segments around x, and to point markers.
  final o = series.options;
  final pointRadius = o.pointMarkersVisible ? (o.pointMarkersRadius ?? o.lineWidth / 2 + 2) : null;
  final radius = math.max(o.lineWidth / 2, pointRadius ?? 0) + tol;
  final (from, to) = series.itemsInRange(IndexRange(visible.left - 1, visible.right + 1));
  if (from >= to) return null;
  final pos = series.lowerBound(index);
  final start = math.max(from, pos - 2), end = math.min(to, pos + 2);

  Offset point(int i) =>
      Offset(ts.indexToCoordinate(series.indices[i]), series.priceToCoordinate(series.data[i].value));

  HitTestResult? best;
  if (pointRadius != null) {
    for (var i = start; i < end; i++) {
      final d = (point(i) - Offset(x, y)).distance;
      if (d <= pointRadius + tol && (best == null || d < best.distance)) best = result(d, HitTestPriority.point);
    }
  }
  if (best != null) return best;

  if (to - from < 2) {
    final p = point(from);
    final half = math.max(barSpacing / 2, radius);
    final d = distanceToSegment(x, y, p.dx - half, p.dy, p.dx + half, p.dy);
    return d <= radius ? result(d, HitTestPriority.point) : null;
  }

  for (var i = math.max(from + 1, start); i < math.min(to, end + 1); i++) {
    final a = point(i - 1), b = point(i);
    if (x < a.dx - radius || x > b.dx + radius) continue;
    final d = distanceToSegment(x, y, a.dx, a.dy, b.dx, b.dy);
    if (d <= radius && (best == null || d < best.distance)) best = result(d, HitTestPriority.line);
  }
  return best;
}

HitTestResult? _hitTestCustom(CustomSeriesModel series, TimeScale ts, IndexRange visible, double x, double y) {
  final r = series.hitTest(ts, visible, x, y);
  if (r == null) return null;
  return HitTestResult(
    type: HoveredItemType.custom,
    sourceKind: HoveredSourceKind.series,
    series: series,
    objectId: r.objectId,
    distance: r.distance,
    priority: HitTestPriority.point,
  );
}

HitTestPriority _primitivePriority(PrimitiveHitTestResult r) => switch (r.hitTestPriority) {
  0 => HitTestPriority.range,
  1 => HitTestPriority.line,
  _ => HitTestPriority.point,
};

HoveredItemType _primitiveType(PrimitiveHitTestResult r) =>
    r.itemType == PrimitiveItemType.marker ? HoveredItemType.marker : HoveredItemType.primitive;

/// Topmost hit in [pane] at ([x], [y]): primitives, custom price lines and
/// series, like upstream's pane hit test.
HitTestResult? hitTestPane(
  Pane pane,
  TimeScale ts,
  double x,
  double y,
  PrimitiveContextImpl Function(SeriesModel? s) contextFor,
) {
  final visible = ts.visibleStrictRange();
  if (visible == null) return null;
  HitTestResult? best;
  void consider(HitTestResult? r) {
    if (r != null && (best == null || r.beats(best!))) best = r;
  }

  for (final p in pane.primitives) {
    final r = p.hitTest(contextFor(null), x, y);
    if (r != null) {
      consider(
        HitTestResult(
          type: _primitiveType(r),
          sourceKind: HoveredSourceKind.panePrimitive,
          objectId: r.externalId,
          distance: r.distance,
          priority: _primitivePriority(r),
          zOrder: r.zOrder,
        ),
      );
    }
  }
  for (final s in pane.series) {
    if (!s.visible || s.priceScale.isEmpty) continue;
    for (final p in s.primitives) {
      final r = p.hitTest(contextFor(s), x, y);
      if (r != null) {
        consider(
          HitTestResult(
            type: _primitiveType(r),
            sourceKind: HoveredSourceKind.seriesPrimitive,
            series: s,
            objectId: r.externalId,
            distance: r.distance,
            priority: _primitivePriority(r),
            zOrder: r.zOrder,
          ),
        );
      }
    }
    for (final line in s.priceLines) {
      final o = line.options;
      if (!o.lineVisible) continue;
      final d = (s.priceToCoordinate(o.price) - y).abs();
      if (d <= o.lineWidth / 2 + s.options.hitTestTolerance) {
        consider(
          HitTestResult(
            type: HoveredItemType.priceLine,
            sourceKind: HoveredSourceKind.series,
            series: s,
            objectId: o.id,
            distance: d,
            priority: HitTestPriority.line,
          ),
        );
      }
    }
    consider(hitTestSeries(s, ts, visible, x, y));
  }
  return best;
}
