import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';

/// Default color of a sparkline that ends at or above where it started.
const Color kSparklineUpColor = Color(0xFF26A69A);

/// Default color of a sparkline that ends below where it started.
const Color kSparklineDownColor = Color(0xFFEF5350);

/// A small, non-interactive line of values — for list rows, cards and
/// tiles where a full [SwmChart] would be too heavy: no axes, no scales, no
/// gestures, one [CustomPainter].
///
/// The line is green when the last value is at or above the first (or the
/// [baseline], when given) and red otherwise, unless [color] is set.
/// Non-finite values are skipped.
class SwmSparkline extends StatelessWidget {
  const SwmSparkline({
    super.key,
    required this.values,
    this.width,
    this.height = 40,
    this.color,
    this.upColor = kSparklineUpColor,
    this.downColor = kSparklineDownColor,
    this.lineWidth = 1.5,
    this.area = true,
    this.areaOpacity = 0.28,
    this.baseline,
    this.baselineColor,
    this.curved = false,
    this.lastPointDot = false,
    this.verticalPadding = 0.1,
    this.semanticsLabel,
  });

  /// The values, oldest first.
  final List<double> values;

  /// Size of the sparkline; a null [width] takes the width it is given.
  final double? width;
  final double height;

  /// A fixed line color, instead of [upColor] / [downColor].
  final Color? color;
  final Color upColor;
  final Color downColor;
  final double lineWidth;

  /// Fill a fading gradient under the line, from [areaOpacity] at the top.
  final bool area;
  final double areaOpacity;

  /// A reference level (e.g. the previous close) drawn as a dashed line;
  /// also what decides up or down.
  final double? baseline;
  final Color? baselineColor;

  /// Smooth the line through the points instead of straight segments.
  final bool curved;

  /// A dot on the last value.
  final bool lastPointDot;

  /// Share of the height left empty above the highest and below the lowest
  /// value.
  final double verticalPadding;

  /// Read by screen readers; nothing is announced when null.
  final String? semanticsLabel;

  @override
  Widget build(BuildContext context) {
    final painter = SwmSparklinePainter(
      values: values,
      color: color,
      upColor: upColor,
      downColor: downColor,
      lineWidth: lineWidth,
      area: area,
      areaOpacity: areaOpacity,
      baseline: baseline,
      baselineColor: baselineColor,
      curved: curved,
      lastPointDot: lastPointDot,
      verticalPadding: verticalPadding,
    );
    final child = RepaintBoundary(
      child: SizedBox(
        width: width ?? double.infinity,
        height: height,
        child: CustomPaint(painter: painter),
      ),
    );
    final label = semanticsLabel;
    return label == null ? ExcludeSemantics(child: child) : Semantics(label: label, image: true, child: child);
  }
}

/// Paints a [SwmSparkline] — usable on its own, e.g. to draw a sparkline
/// into an image with a [ui.PictureRecorder].
class SwmSparklinePainter extends CustomPainter {
  SwmSparklinePainter({
    required this.values,
    this.color,
    this.upColor = kSparklineUpColor,
    this.downColor = kSparklineDownColor,
    this.lineWidth = 1.5,
    this.area = true,
    this.areaOpacity = 0.28,
    this.baseline,
    this.baselineColor,
    this.curved = false,
    this.lastPointDot = false,
    this.verticalPadding = 0.1,
  });

  final List<double> values;
  final Color? color;
  final Color upColor;
  final Color downColor;
  final double lineWidth;
  final bool area;
  final double areaOpacity;
  final double? baseline;
  final Color? baselineColor;
  final bool curved;
  final bool lastPointDot;
  final double verticalPadding;

  /// The line color [values] resolve to.
  Color get resolvedColor {
    final c = color;
    if (c != null) return c;
    final v = values.where((x) => x.isFinite).toList();
    if (v.isEmpty) return upColor;
    return v.last >= (baseline ?? v.first) ? upColor : downColor;
  }

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final pts = <(int, double)>[
      for (var i = 0; i < values.length; i++)
        if (values[i].isFinite) (i, values[i]),
    ];
    if (pts.isEmpty) return;
    var lo = pts.map((p) => p.$2).reduce(math.min);
    var hi = pts.map((p) => p.$2).reduce(math.max);
    final base = baseline;
    if (base != null && base.isFinite) {
      lo = math.min(lo, base);
      hi = math.max(hi, base);
    }
    var span = hi - lo;
    if (span <= 0) span = hi.abs() > 0 ? hi.abs() * 0.02 : 1;
    final pad = span * verticalPadding.clamp(0.0, 0.45);
    lo -= pad;
    hi += pad;
    final inset = lineWidth / 2;
    final h = size.height - 2 * inset;
    // A lone value draws as a flat line across.
    final lastIndex = math.max(1, values.length - 1);
    double x(int i) => pts.length == 1 ? (i == 0 ? 0 : size.width) : i / lastIndex * size.width;
    double y(double v) => inset + (1 - (v - lo) / (hi - lo)) * h;
    final offsets = pts.length == 1
        ? [Offset(0, y(pts.first.$2)), Offset(size.width, y(pts.first.$2))]
        : [for (final (i, v) in pts) Offset(x(i), y(v))];

    final line = Path()..moveTo(offsets.first.dx, offsets.first.dy);
    for (var k = 1; k < offsets.length; k++) {
      final a = offsets[k - 1], b = offsets[k];
      if (curved) {
        final mx = (a.dx + b.dx) / 2;
        line.cubicTo(mx, a.dy, mx, b.dy, b.dx, b.dy);
      } else {
        line.lineTo(b.dx, b.dy);
      }
    }
    final ink = resolvedColor;
    if (area) {
      final fill = Path.from(line)
        ..lineTo(offsets.last.dx, size.height)
        ..lineTo(offsets.first.dx, size.height)
        ..close();
      canvas.drawPath(
        fill,
        Paint()
          ..shader = ui.Gradient.linear(Offset.zero, Offset(0, size.height), [
            ink.withValues(alpha: ink.a * areaOpacity),
            ink.withValues(alpha: 0),
          ]),
      );
    }
    if (base != null && base.isFinite) {
      final by = y(base);
      final dash = Paint()
        ..color = baselineColor ?? ink.withValues(alpha: ink.a * 0.5)
        ..strokeWidth = 1;
      for (var dx = 0.0; dx < size.width; dx += 6) {
        canvas.drawLine(Offset(dx, by), Offset(math.min(dx + 3, size.width), by), dash);
      }
    }
    canvas.drawPath(
      line,
      Paint()
        ..color = ink
        ..style = PaintingStyle.stroke
        ..strokeWidth = lineWidth
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );
    if (lastPointDot) {
      canvas.drawCircle(offsets.last, lineWidth + 1.5, Paint()..color = ink);
    }
  }

  @override
  bool shouldRepaint(SwmSparklinePainter old) =>
      !_sameValues(old.values, values) ||
      old.color != color ||
      old.upColor != upColor ||
      old.downColor != downColor ||
      old.lineWidth != lineWidth ||
      old.area != area ||
      old.areaOpacity != areaOpacity ||
      old.baseline != baseline ||
      old.baselineColor != baselineColor ||
      old.curved != curved ||
      old.lastPointDot != lastPointDot ||
      old.verticalPadding != verticalPadding;

  static bool _sameValues(List<double> a, List<double> b) {
    if (identical(a, b)) return true;
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}
