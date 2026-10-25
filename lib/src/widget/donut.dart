import 'dart:math' as math;

import 'package:flutter/widgets.dart';

/// One slice of a [SwmDonut]: its share is [value] over the sum of all
/// slices.
class SwmDonutSlice {
  const SwmDonutSlice({required this.value, required this.color});

  final double value;
  final Color color;
}

/// A donut (ring) chart for shares of a whole — portfolio allocation and
/// the like. Slices run clockwise from 12 o'clock with a small [gap]
/// between them; touching one reports it through [onSelect] (and null on
/// release), and a [selected] slice is drawn thicker. [center] sits in the
/// hole.
///
/// Non-positive and non-finite values are left out.
class SwmDonut extends StatelessWidget {
  const SwmDonut({
    super.key,
    required this.slices,
    this.size = 120,
    this.innerRadius = 36,
    this.thickness = 22,
    this.selectedThickness,
    this.gap = 2,
    this.selected,
    this.onSelect,
    this.center,
    this.semanticsLabel,
  });

  final List<SwmDonutSlice> slices;

  /// Width and height of the chart.
  final double size;

  /// Radius of the hole.
  final double innerRadius;

  /// Width of the ring.
  final double thickness;

  /// Width of the [selected] slice; defaults to [thickness] + 6.
  final double? selectedThickness;

  /// Space between slices, in logical pixels at the middle of the ring.
  final double gap;

  /// Index into [slices] of the highlighted slice.
  final int? selected;

  /// Called with the slice under a touch, and null when it ends or misses.
  final ValueChanged<int?>? onSelect;

  /// Shown in the hole, e.g. a total or the selected slice's label.
  final Widget? center;

  /// Read by screen readers; nothing is announced when null.
  final String? semanticsLabel;

  double get _selectedThickness => selectedThickness ?? thickness + 6;

  /// The slice at [local] (relative to the chart's top-left), or null.
  int? sliceAt(Offset local) {
    final c = Offset(size / 2, size / 2);
    final d = local - c;
    final r = d.distance;
    if (r < innerRadius || r > innerRadius + math.max(thickness, _selectedThickness)) return null;
    // Clockwise from 12 o'clock, in [0, 2π).
    var a = math.atan2(d.dy, d.dx) + math.pi / 2;
    if (a < 0) a += 2 * math.pi;
    final total = _total(slices);
    if (total <= 0) return null;
    var start = 0.0;
    for (var i = 0; i < slices.length; i++) {
      final v = slices[i].value;
      if (!(v.isFinite && v > 0)) continue;
      final sweep = 2 * math.pi * v / total;
      if (a >= start && a < start + sweep) return i;
      start += sweep;
    }
    return null;
  }

  static double _total(List<SwmDonutSlice> slices) =>
      slices.fold(0.0, (a, s) => s.value.isFinite && s.value > 0 ? a + s.value : a);

  @override
  Widget build(BuildContext context) {
    Widget chart = SizedBox.square(
      dimension: size,
      child: CustomPaint(
        painter: SwmDonutPainter(
          slices: slices,
          innerRadius: innerRadius,
          thickness: thickness,
          selectedThickness: _selectedThickness,
          gap: gap,
          selected: selected,
        ),
        child: center == null ? null : Center(child: center),
      ),
    );
    final select = onSelect;
    if (select != null) {
      chart = GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: (d) => select(sliceAt(d.localPosition)),
        onTapUp: (_) => select(null),
        onTapCancel: () => select(null),
        onPanDown: (d) => select(sliceAt(d.localPosition)),
        onPanUpdate: (d) => select(sliceAt(d.localPosition)),
        onPanEnd: (_) => select(null),
        onPanCancel: () => select(null),
        child: chart,
      );
    }
    final label = semanticsLabel;
    return label == null ? chart : Semantics(label: label, image: true, child: chart);
  }
}

/// Paints a [SwmDonut].
class SwmDonutPainter extends CustomPainter {
  SwmDonutPainter({
    required this.slices,
    required this.innerRadius,
    required this.thickness,
    required this.selectedThickness,
    this.gap = 2,
    this.selected,
  });

  final List<SwmDonutSlice> slices;
  final double innerRadius;
  final double thickness;
  final double selectedThickness;
  final double gap;
  final int? selected;

  @override
  void paint(Canvas canvas, Size size) {
    final total = SwmDonut._total(slices);
    if (total <= 0) return;
    final c = size.center(Offset.zero);
    final count = slices.where((s) => s.value.isFinite && s.value > 0).length;
    var start = -math.pi / 2;
    for (var i = 0; i < slices.length; i++) {
      final s = slices[i];
      if (!(s.value.isFinite && s.value > 0)) continue;
      final sweep = 2 * math.pi * s.value / total;
      final w = i == selected ? selectedThickness : thickness;
      final mid = innerRadius + w / 2;
      // The gap as an angle at the middle of the ring; none for one slice.
      final gapAngle = count > 1 ? gap / mid : 0.0;
      final drawn = sweep - gapAngle;
      if (drawn > 0) {
        final paint = Paint()
          ..color = s.color
          ..style = PaintingStyle.stroke
          ..strokeWidth = w;
        if (count == 1) {
          canvas.drawCircle(c, mid, paint);
        } else {
          canvas.drawArc(Rect.fromCircle(center: c, radius: mid), start + gapAngle / 2, drawn, false, paint);
        }
      }
      start += sweep;
    }
  }

  @override
  bool shouldRepaint(SwmDonutPainter old) =>
      old.innerRadius != innerRadius ||
      old.thickness != thickness ||
      old.selectedThickness != selectedThickness ||
      old.gap != gap ||
      old.selected != selected ||
      !_sameSlices(old.slices, slices);

  static bool _sameSlices(List<SwmDonutSlice> a, List<SwmDonutSlice> b) {
    if (identical(a, b)) return true;
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i].value != b[i].value || a[i].color != b[i].color) return false;
    }
    return true;
  }
}
