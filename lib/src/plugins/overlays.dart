// Overlay primitives for technical analysis that lightweight-charts leaves
// to plugins: a filled band between two lines (Bollinger, Keltner,
// Donchian, channels, an Ichimoku cloud), horizontal price levels with
// labels (Fibonacci, pivots, support / resistance) and a volume profile.
import 'dart:math' as math;

import 'package:flutter/painting.dart';

import '../options.dart';
import '../renderers/draw_utils.dart';
import 'primitive.dart';

// ---- band fill ----

/// One point of a [BandFillPrimitive]: the upper and lower value at [time].
class BandPoint {
  const BandPoint({required this.time, required this.upper, required this.lower});

  final num time;
  final double upper;
  final double lower;
}

class BandFillOptions {
  const BandFillOptions({
    this.fillColor = const Color(0x332962FF),
    this.invertedFillColor,
    this.upperLineColor,
    this.lowerLineColor,
    this.lineWidth = 1,
    this.lineStyle = LineStyle.solid,
  });

  /// Fill where `upper >= lower`.
  final Color fillColor;

  /// Fill where `upper < lower` (e.g. a bearish Ichimoku cloud); `null`
  /// uses [fillColor] everywhere.
  final Color? invertedFillColor;

  /// Edge lines; `null` draws none (e.g. when line series draw them).
  final Color? upperLineColor;
  final Color? lowerLineColor;
  final double lineWidth;
  final LineStyle lineStyle;
}

/// Fills the area between two lines. Attach to the series whose price
/// scale the values belong to (`SeriesApi.attachPrimitive`), or to a pane
/// for its default scale. Points must be sorted by time; a time missing
/// from the time scale breaks the band.
class BandFillPrimitive extends ChartPrimitive {
  BandFillPrimitive({List<BandPoint> points = const [], BandFillOptions options = const BandFillOptions()})
    : _points = points,
      _options = options;

  List<BandPoint> _points;
  BandFillOptions _options;

  List<BandPoint> get points => _points;

  set points(List<BandPoint> value) {
    _points = value;
    requestUpdate();
  }

  BandFillOptions get options => _options;

  set options(BandFillOptions value) {
    _options = value;
    requestUpdate();
  }

  @override
  PrimitiveZOrder get zOrder => PrimitiveZOrder.bottom;

  @override
  void paint(PrimitivePaintContext ctx) {
    final o = _options;
    final canvas = ctx.canvas;
    final width = ctx.paneSize.width;
    // Runs of consecutive points on the time scale, as (x, yUpper, yLower).
    final runs = <List<(double, double, double)>>[];
    var run = <(double, double, double)>[];
    for (final p in _points) {
      final x = ctx.timeToCoordinate(p.time);
      final yu = ctx.priceToCoordinate(p.upper);
      final yl = ctx.priceToCoordinate(p.lower);
      if (x == null || yu == null || yl == null || !p.upper.isFinite || !p.lower.isFinite) {
        if (run.length > 1) runs.add(run);
        run = [];
        continue;
      }
      run.add((x, yu, yl));
    }
    if (run.length > 1) runs.add(run);

    final fill = Paint()..style = PaintingStyle.fill;
    for (final r in runs) {
      // Skip runs entirely off screen.
      if (r.last.$1 < 0 || r.first.$1 > width) continue;
      final inverted = o.invertedFillColor;
      if (inverted == null) {
        final path = Path()..moveTo(r.first.$1, r.first.$2);
        for (final (x, yu, _) in r.skip(1)) {
          path.lineTo(x, yu);
        }
        for (final (x, _, yl) in r.reversed) {
          path.lineTo(x, yl);
        }
        path.close();
        canvas.drawPath(path, fill..color = o.fillColor);
      } else {
        // Two colours: one quad per interval, split where the lines cross.
        for (var i = 1; i < r.length; i++) {
          final (x0, u0, l0) = r[i - 1];
          final (x1, u1, l1) = r[i];
          // On screen, a smaller y is a higher price.
          final d0 = l0 - u0, d1 = l1 - u1;
          if (d0 * d1 < 0) {
            final t = d0 / (d0 - d1);
            final xc = x0 + (x1 - x0) * t;
            final yc = u0 + (u1 - u0) * t;
            canvas.drawPath(
              Path()..addPolygon([Offset(x0, u0), Offset(xc, yc), Offset(x0, l0)], true),
              fill..color = ctx.priceScaleInverted == (d0 > 0) ? inverted : o.fillColor,
            );
            canvas.drawPath(
              Path()..addPolygon([Offset(xc, yc), Offset(x1, u1), Offset(x1, l1)], true),
              fill..color = ctx.priceScaleInverted == (d1 > 0) ? inverted : o.fillColor,
            );
          } else {
            final up = (d0 + d1) >= 0;
            canvas.drawPath(
              Path()..addPolygon([Offset(x0, u0), Offset(x1, u1), Offset(x1, l1), Offset(x0, l0)], true),
              fill..color = ctx.priceScaleInverted == up ? inverted : o.fillColor,
            );
          }
        }
      }
      _edge(canvas, ctx, [for (final (x, yu, _) in r) Offset(x, yu)], o.upperLineColor);
      _edge(canvas, ctx, [for (final (x, _, yl) in r) Offset(x, yl)], o.lowerLineColor);
    }
  }

  void _edge(Canvas canvas, PrimitivePaintContext ctx, List<Offset> points, Color? color) {
    if (color == null || points.length < 2) return;
    final path = Path()..addPolygon(points, false);
    canvas.drawPath(
      dashPath(path, dashPattern(_options.lineStyle, _options.lineWidth)),
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = _options.lineWidth
        ..strokeJoin = StrokeJoin.round,
    );
  }
}

// ---- price levels ----

enum PriceLevelLabelPosition { left, right }

/// A horizontal price level: a Fibonacci ratio, a pivot, a support or
/// resistance line.
class PriceLevel {
  const PriceLevel({
    required this.price,
    this.color = const Color(0xFF787B86),
    this.lineWidth = 1,
    this.lineStyle = LineStyle.solid,
    this.label,
    this.labelPosition = PriceLevelLabelPosition.left,
    this.fromTime,
    this.toTime,
    this.axisLabel = false,
    this.fillColorToNext,
    this.id,
  });

  final double price;
  final Color color;
  final double lineWidth;
  final LineStyle lineStyle;

  /// Text drawn just above the line.
  final String? label;
  final PriceLevelLabelPosition labelPosition;

  /// Limit the line to a time span; `null` extends it to that edge.
  final num? fromTime;
  final num? toTime;

  /// Also label the level on the price axis.
  final bool axisLabel;

  /// Fill between this level and the next one in the list (Fibonacci
  /// zones).
  final Color? fillColorToNext;

  /// Reported as `hoveredObjectId` when the line is hit.
  final Object? id;
}

class PriceLevelsPrimitive extends ChartPrimitive {
  PriceLevelsPrimitive({List<PriceLevel> levels = const [], this.fontSize = 10, this.hitTolerance = 4})
    : _levels = levels;

  List<PriceLevel> _levels;
  final double fontSize;

  /// How close (logical pixels) a pointer must be to hit a line with an id.
  final double hitTolerance;

  List<PriceLevel> get levels => _levels;

  set levels(List<PriceLevel> value) {
    _levels = value;
    requestUpdate();
  }

  (double, double)? _span(PrimitiveContext ctx, PriceLevel l) {
    final width = ctx.paneSize.width;
    final from = l.fromTime;
    final to = l.toTime;
    final left = from == null ? 0.0 : ctx.timeToCoordinate(from);
    final right = to == null ? width : ctx.timeToCoordinate(to);
    if (left == null || right == null) return null;
    final a = math.max(0.0, math.min(left, right)), b = math.min(width, math.max(left, right));
    return b <= a ? null : (a, b);
  }

  @override
  void paint(PrimitivePaintContext ctx) {
    final canvas = ctx.canvas;
    final pr = ctx.pixelRatio;
    for (var i = 0; i < _levels.length; i++) {
      final l = _levels[i];
      final y = ctx.priceToCoordinate(l.price);
      final span = _span(ctx, l);
      if (y == null || span == null) continue;
      final fill = l.fillColorToNext;
      if (fill != null && i + 1 < _levels.length) {
        final y2 = ctx.priceToCoordinate(_levels[i + 1].price);
        if (y2 != null) {
          canvas.drawRect(Rect.fromLTRB(span.$1, math.min(y, y2), span.$2, math.max(y, y2)), Paint()..color = fill);
        }
      }
      canvas.save();
      canvas.scale(1 / pr);
      drawHorizontalLine(
        canvas,
        Paint()..color = l.color,
        (y * pr).roundToDouble(),
        span.$1 * pr,
        span.$2 * pr,
        math.max(1, (l.lineWidth * pr).floorToDouble()),
        l.lineStyle,
      );
      canvas.restore();
      final text = l.label;
      if (text == null || text.isEmpty) continue;
      final tp = TextPainter(
        text: TextSpan(
          text: text,
          style: TextStyle(color: l.color, fontSize: fontSize, fontFamily: ctx.fontFamily),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      final x = l.labelPosition == PriceLevelLabelPosition.left ? span.$1 + 4 : span.$2 - tp.width - 4;
      tp.paint(canvas, Offset(x, y - tp.height - 1));
      tp.dispose();
    }
  }

  @override
  List<AxisLabel> priceAxisLabels(PrimitiveContext ctx) => [
    for (final l in _levels)
      if (l.axisLabel)
        if (ctx.priceToCoordinate(l.price) case final y?)
          AxisLabel(coordinate: y, text: l.label ?? l.price.toStringAsFixed(2), backgroundColor: l.color),
  ];

  @override
  PrimitiveHitTestResult? hitTest(PrimitiveContext ctx, double x, double y) {
    PrimitiveHitTestResult? best;
    for (final l in _levels) {
      if (l.id == null) continue;
      final ly = ctx.priceToCoordinate(l.price);
      final span = _span(ctx, l);
      if (ly == null || span == null || x < span.$1 || x > span.$2) continue;
      final distance = (ly - y).abs();
      if (distance > hitTolerance) continue;
      if (best == null || distance < best.distance) {
        best = PrimitiveHitTestResult(externalId: l.id, distance: distance, hitTestPriority: 1);
      }
    }
    return best;
  }
}

// ---- volume profile ----

/// Volume traded between [low] and [high]; [upVolume] is the part on
/// up bars (drawn in the up colour, the rest in the down colour).
class VolumeProfileBin {
  const VolumeProfileBin({required this.low, required this.high, required this.volume, this.upVolume});

  final double low;
  final double high;
  final double volume;
  final double? upVolume;
}

enum VolumeProfileSide { left, right }

class VolumeProfileOptions {
  const VolumeProfileOptions({
    this.side = VolumeProfileSide.right,
    this.widthFraction = 0.3,
    this.upColor = const Color(0x5526A69A),
    this.downColor = const Color(0x55EF5350),
    this.color = const Color(0x55787B86),
    this.pocColor = const Color(0xCCFFB300),
    this.gap = 1,
  });

  /// Edge of the pane the bars grow from.
  final VolumeProfileSide side;

  /// Width of the largest bar as a fraction of the pane width.
  final double widthFraction;
  final Color upColor;
  final Color downColor;

  /// Bars without [VolumeProfileBin.upVolume].
  final Color color;

  /// Point of control (the largest bin); `null` doesn't mark it.
  final Color? pocColor;

  /// Space between bars, in logical pixels.
  final double gap;
}

/// A volume-by-price histogram along a pane edge. Attach to the price
/// series so the bins line up with its scale.
class VolumeProfilePrimitive extends ChartPrimitive {
  VolumeProfilePrimitive({
    List<VolumeProfileBin> bins = const [],
    VolumeProfileOptions options = const VolumeProfileOptions(),
  }) : _bins = bins,
       _options = options;

  List<VolumeProfileBin> _bins;
  VolumeProfileOptions _options;

  List<VolumeProfileBin> get bins => _bins;

  set bins(List<VolumeProfileBin> value) {
    _bins = value;
    requestUpdate();
  }

  VolumeProfileOptions get options => _options;

  set options(VolumeProfileOptions value) {
    _options = value;
    requestUpdate();
  }

  @override
  PrimitiveZOrder get zOrder => PrimitiveZOrder.bottom;

  @override
  void paint(PrimitivePaintContext ctx) {
    if (_bins.isEmpty) return;
    final o = _options;
    final maxVolume = _bins.fold(0.0, (a, b) => math.max(a, b.volume));
    if (maxVolume <= 0) return;
    final width = ctx.paneSize.width;
    final full = width * o.widthFraction;
    final poc = o.pocColor == null ? null : _bins.reduce((a, b) => b.volume > a.volume ? b : a);
    final canvas = ctx.canvas;
    for (final b in _bins) {
      final y1 = ctx.priceToCoordinate(b.high);
      final y2 = ctx.priceToCoordinate(b.low);
      if (y1 == null || y2 == null) continue;
      final top = math.min(y1, y2) + o.gap / 2;
      final bottom = math.max(y1, y2) - o.gap / 2;
      if (bottom <= top) continue;
      final len = full * b.volume / maxVolume;
      Rect bar(double from, double length) => o.side == VolumeProfileSide.right
          ? Rect.fromLTRB(width - from - length, top, width - from, bottom)
          : Rect.fromLTRB(from, top, from + length, bottom);
      final up = b.upVolume;
      if (identical(b, poc)) {
        canvas.drawRect(bar(0, len), Paint()..color = o.pocColor!);
      } else if (up == null) {
        canvas.drawRect(bar(0, len), Paint()..color = o.color);
      } else {
        final upLen = full * up.clamp(0, b.volume) / maxVolume;
        canvas.drawRect(bar(0, upLen), Paint()..color = o.upColor);
        canvas.drawRect(bar(upLen, len - upLen), Paint()..color = o.downColor);
      }
    }
  }
}
