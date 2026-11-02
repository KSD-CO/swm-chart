// A forecast fan (cone): nested ranges and a center line drawn forward from
// a bar, step by step into the future, where the series has no data yet.

import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/scheduler.dart';

import '../model/price_scale.dart' show PriceRange;
import '../options.dart';
import '../renderers/draw_utils.dart';
import '../series_options.dart' show AutoscaleInfo;
import 'primitive.dart';

/// One step of a [FanPrimitive]: the center value and its ranges as
/// (lower, upper), innermost first — e.g. the 80% range, then the 95% one.
class FanStep {
  const FanStep({required this.mid, required this.ranges});

  final double mid;
  final List<(double, double)> ranges;
}

class FanOptions {
  const FanOptions({
    this.fillColors = const [Color(0x382DD4A8), Color(0x2860A5FA)],
    this.edgeColors = const [null, Color(0xFF60A5FA)],
    this.edgeStyle = LineStyle.solid,
    this.centerColor = const Color(0xFFFB923C),
    this.centerStyle = LineStyle.solid,
    this.lineWidth = 1.5,
    this.smooth = true,
  });

  /// Fill of each range, innermost first; missing entries aren't filled.
  final List<Color> fillColors;

  /// Edge line of each range, innermost first; `null` draws none.
  final List<Color?> edgeColors;
  final LineStyle edgeStyle;

  /// The center line; `null` hides it.
  final Color? centerColor;
  final LineStyle centerStyle;
  final double lineWidth;

  /// Smooth curves (Catmull–Rom) through the steps instead of straight
  /// segments.
  final bool smooth;
}

/// A forecast fan attached to a series: starts at [anchorTime] (a bar of
/// the series, usually its last) at [anchorValue], and step `k` of [steps]
/// sits `k + 1` bars after it — on the logical index, so it reaches past
/// the last bar without whitespace data. Its ranges take part in
/// autoscale, so a wide fan isn't clipped.
///
/// ```dart
/// final fan = FanPrimitive(
///   anchorTime: last.time,
///   anchorValue: last.close,
///   steps: [for (final s in forecast) FanStep(mid: s.mid, ranges: [(s.lo80, s.hi80), (s.lo95, s.hi95)])],
/// );
/// series.attachPrimitive(fan);
/// chart.timeScale().applyOptions(const TimeScaleOptions(rightOffset: 12)); // room for it
/// ```
class FanPrimitive extends ChartPrimitive {
  FanPrimitive({
    required num anchorTime,
    required double anchorValue,
    List<FanStep> steps = const [],
    FanOptions options = const FanOptions(),
  }) : _anchorTime = anchorTime,
       _anchorValue = anchorValue,
       _steps = steps,
       _options = options;

  num _anchorTime;
  double _anchorValue;
  List<FanStep> _steps;
  FanOptions _options;

  // The anchor's logical index, found when painting (a primitive learns
  // the time scale only then); autoscale uses it from the next layout.
  int? _anchorIndex;

  num get anchorTime => _anchorTime;
  double get anchorValue => _anchorValue;
  List<FanStep> get steps => _steps;
  FanOptions get options => _options;

  /// Moves the fan: a new anchor and/or steps.
  void setData({num? anchorTime, double? anchorValue, List<FanStep>? steps}) {
    if (anchorTime != null && anchorTime != _anchorTime) _anchorIndex = null;
    _anchorTime = anchorTime ?? _anchorTime;
    _anchorValue = anchorValue ?? _anchorValue;
    _steps = steps ?? _steps;
    requestUpdate();
  }

  set options(FanOptions value) {
    _options = value;
    requestUpdate();
  }

  @override
  AutoscaleInfo? autoscaleInfo(int from, int to) {
    final anchor = _anchorIndex;
    if (anchor == null || _steps.isEmpty) return null;
    var lo = double.infinity, hi = double.negativeInfinity;
    for (var k = 0; k < _steps.length; k++) {
      final index = anchor + k + 1;
      if (index < from || index > to) continue;
      final s = _steps[k];
      for (final (l, u) in s.ranges) {
        if (l.isFinite) lo = math.min(lo, l);
        if (u.isFinite) hi = math.max(hi, u);
      }
      if (s.mid.isFinite) {
        lo = math.min(lo, s.mid);
        hi = math.max(hi, s.mid);
      }
    }
    if (!lo.isFinite || !hi.isFinite) return null;
    return AutoscaleInfo(priceRange: PriceRange(lo, hi));
  }

  @override
  void paint(PrimitivePaintContext ctx) {
    final index = ctx.timeToIndex(_anchorTime);
    if (index != _anchorIndex) {
      // First sight of the anchor (or it moved): lay out again so the
      // fan's range counts in autoscale.
      _anchorIndex = index;
      // Not during paint: after this frame.
      if (index != null) SchedulerBinding.instance.addPostFrameCallback((_) => requestUpdate());
    }
    if (index == null || _steps.isEmpty) return;
    final y0 = ctx.priceToCoordinate(_anchorValue);
    if (y0 == null) return;
    final start = Offset(ctx.logicalToCoordinate(index.toDouble()), y0);
    if (start.dx > ctx.paneSize.width) return;

    List<Offset>? edge(double Function(FanStep) of) {
      final pts = [start];
      for (var k = 0; k < _steps.length; k++) {
        final v = of(_steps[k]);
        final y = v.isFinite ? ctx.priceToCoordinate(v) : null;
        if (y == null) return null;
        pts.add(Offset(ctx.logicalToCoordinate((index + k + 1).toDouble()), y));
      }
      return pts;
    }

    final o = _options;
    final canvas = ctx.canvas;
    final rangeCount = _steps.fold(0, (n, s) => math.max(n, s.ranges.length));
    // Outermost first, so the inner ranges sit on top of it.
    for (var r = rangeCount - 1; r >= 0; r--) {
      double lowerOf(FanStep s) => r < s.ranges.length ? s.ranges[r].$1 : double.nan;
      double upperOf(FanStep s) => r < s.ranges.length ? s.ranges[r].$2 : double.nan;
      final upper = edge(upperOf), lower = edge(lowerOf);
      if (upper == null || lower == null) continue;
      if (r < o.fillColors.length) {
        final path = _curve(upper);
        final back = lower.reversed.toList();
        path.lineTo(back.first.dx, back.first.dy);
        _append(path, back);
        canvas.drawPath(path..close(), Paint()..color = o.fillColors[r]);
      }
      final edgeColor = r < o.edgeColors.length ? o.edgeColors[r] : null;
      if (edgeColor != null) {
        final paint = _stroke(edgeColor, o.lineWidth);
        final dash = dashPattern(o.edgeStyle, o.lineWidth);
        canvas.drawPath(dashPath(_curve(upper), dash), paint);
        canvas.drawPath(dashPath(_curve(lower), dash), paint);
      }
    }
    final center = o.centerColor;
    final mid = edge((s) => s.mid);
    if (center != null && mid != null) {
      canvas.drawPath(dashPath(_curve(mid), dashPattern(o.centerStyle, o.lineWidth)), _stroke(center, o.lineWidth));
    }
  }

  Paint _stroke(Color color, double width) => Paint()
    ..color = color
    ..strokeWidth = width
    ..style = PaintingStyle.stroke
    ..strokeJoin = StrokeJoin.round;

  Path _curve(List<Offset> pts) {
    final path = Path()..moveTo(pts.first.dx, pts.first.dy);
    _append(path, pts);
    return path;
  }

  /// Appends [pts] (from the path's current point, pts.first) as straight
  /// segments or a Catmull–Rom curve.
  void _append(Path path, List<Offset> pts) {
    if (!_options.smooth) {
      for (final p in pts.skip(1)) {
        path.lineTo(p.dx, p.dy);
      }
      return;
    }
    for (var i = 0; i < pts.length - 1; i++) {
      final p0 = pts[math.max(0, i - 1)], p1 = pts[i], p2 = pts[i + 1];
      final p3 = pts[math.min(pts.length - 1, i + 2)];
      path.cubicTo(
        p1.dx + (p2.dx - p0.dx) / 6,
        p1.dy + (p2.dy - p0.dy) / 6,
        p2.dx - (p3.dx - p1.dx) / 6,
        p2.dy - (p3.dy - p1.dy) / 6,
        p2.dx,
        p2.dy,
      );
    }
  }
}
