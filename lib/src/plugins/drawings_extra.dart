// Still more drawing tools: trend angle and info line, range volume
// profiles, harmonic and head-and-shoulders patterns, sine and cyclic
// lines, time cycles, Fibonacci fan and arcs, icon marks and price labels.
part of 'drawings.dart';

/// Line colors of the Fibonacci tools, level by level.
const _levelColors = [
  Color(0xFF787B86),
  Color(0xFFF23645),
  Color(0xFFFF9800),
  Color(0xFF4CAF50),
  Color(0xFF089981),
  Color(0xFF00BCD4),
  Color(0xFF787B86),
  Color(0xFF2962FF),
  Color(0xFFE91E63),
];

double? _near(double d, double tolerance) => d <= tolerance ? d : null;

// ---- lines ----

/// A trend line with its angle against the horizontal.
class TrendAngleDrawing extends TrendLineDrawing {
  TrendAngleDrawing({required super.id, required super.anchors, super.style});

  @override
  void paint(Canvas canvas, DrawingContext c) {
    super.paint(canvas, c);
    if (c.points.length < 2) return;
    final a = c.points[0], b = c.points[1];
    final angle = math.atan2(a.dy - b.dy, b.dx - a.dx);
    final r = math.min(40.0, (b - a).distance);
    final thin = style.copyWith(lineWidth: 1);
    _strokeLine(canvas, thin.copyWith(lineStyle: LineStyle.dashed), a, a + Offset(r + 10, 0));
    canvas.drawArc(Rect.fromCircle(center: a, radius: r * 0.8), 0, -angle, false, thin.stroke());
    final deg = angle * 180 / math.pi;
    final tp = _text('${deg.toStringAsFixed(1)}°', style.copyWith(fontSize: 11), weight: FontWeight.w600);
    tp.paint(canvas, a + Offset(r + 4, deg >= 0 ? -tp.height - 2 : 2));
  }
}

/// A trend line labelled with its price change, bars and angle.
class InfoLineDrawing extends TrendLineDrawing {
  InfoLineDrawing({required super.id, required super.anchors, super.style, this.barsLabel});

  /// Word after the bar count; `null` for [DrawingLabels.current]'s.
  String? barsLabel;

  @override
  void paint(Canvas canvas, DrawingContext c) {
    super.paint(canvas, c);
    if (anchors.length < 2 || c.points.length < 2) return;
    final a = anchors[0], b = anchors[1];
    final pa = c.points[0], pb = c.points[1];
    final deg = math.atan2(pa.dy - pb.dy, pb.dx - pa.dx) * 180 / math.pi;
    final change = b.price - a.price;
    final text = [
      '${change >= 0 ? '+' : ''}${c.formatPrice(change)}${a.price == 0 ? '' : ' (${_percent(change / a.price)})'}',
      '${(b.logical - a.logical).round()} ${barsLabel ?? DrawingLabels.current.bars}',
      '${deg.toStringAsFixed(1)}°',
    ].join('  ');
    _labelBox(
      canvas,
      text,
      style.copyWith(fontSize: 11),
      pb + Offset(0, pb.dy < pa.dy ? -16 : 16),
      style.color.withValues(alpha: 0.9),
    );
  }
}

// ---- volume profile ----

/// Volume by price over the bars between two anchors (fixed range) or from
/// one anchor to the last bar ([anchored]): [rows] price rows, the up bars'
/// share in [upColor] and the rest in [downColor], and the busiest row (the
/// point of control) as a line across. Reads [source] and [volume]; without
/// a volume series every bar weighs the same.
class RangeVolumeProfileDrawing extends Drawing {
  RangeVolumeProfileDrawing({
    required super.id,
    required super.anchors,
    super.style,
    this.source,
    this.volume,
    this.anchored = false,
    this.rows = 24,
    this.upColor = const Color(0x5526A69A),
    this.downColor = const Color(0x55EF5350),
    this.pocColor = const Color(0xCCFFB300),
  });

  SeriesApi? source;
  SeriesApi? volume;
  bool anchored;
  int rows;
  Color upColor;
  Color downColor;
  Color pocColor;

  @override
  int get anchorCount => anchored ? 1 : 2;

  @override
  int get hitPriority => 0;

  @override
  List<double> get selectedAxisPrices => const [];

  (int, int)? _span() {
    final src = source;
    if (src == null || anchors.isEmpty) return null;
    final last = src.data().length - 1;
    if (last < 0) return null;
    final a = anchors.first.logical.round();
    final b = anchored || anchors.length < 2 ? last : anchors[1].logical.round();
    final from = math.max(0, math.min(a, b)), to = math.min(last, math.max(a, b));
    return to > from ? (from, to) : null;
  }

  /// Each bar in the span as (open, high, low, close, volume).
  List<(double, double, double, double, double)> _bars(int from, int to) => [
    for (var i = from; i <= to; i++)
      if (source?.dataByIndex(i) case final d?)
        if (switch (d) {
              OhlcData() => (d.open, d.high, d.low, d.close),
              SingleValueData() => (d.value, d.value, d.value, d.value),
              _ => null,
            }
            case (final o, final h, final l, final cl))
          (
            o,
            h,
            l,
            cl,
            switch (volume?.dataByIndex(i)) {
              SingleValueData(:final value) => value,
              _ => volume == null ? 1.0 : 0.0,
            },
          ),
  ];

  @override
  void paint(Canvas canvas, DrawingContext c) {
    final span = _span();
    if (span == null || rows < 1) return;
    final (from, to) = span;
    final bars = _bars(from, to);
    if (bars.isEmpty) return;
    var lo = double.infinity, hi = -double.infinity;
    for (final (_, h, l, _, _) in bars) {
      lo = math.min(lo, l);
      hi = math.max(hi, h);
    }
    if (!(hi > lo)) return;
    final step = (hi - lo) / rows;
    final vol = List.filled(rows, 0.0), up = List.filled(rows, 0.0);
    for (final (o, _, _, close, v) in bars) {
      final k = ((close - lo) / step).floor().clamp(0, rows - 1);
      vol[k] += v;
      if (close >= o) up[k] += v;
    }
    final maxVol = vol.reduce(math.max);
    if (maxVol <= 0) return;
    final x0 = c.x(from.toDouble()), x1 = c.x(to.toDouble());
    final yTop = c.y(hi), yBot = c.y(lo);
    if (yTop == null || yBot == null) return;
    canvas.drawRect(Rect.fromLTRB(x0, yTop, x1, yBot), Paint()..color = style.color.withValues(alpha: 0.05));
    final width = (x1 - x0) * 0.4;
    final poc = vol.indexOf(maxVol);
    for (var k = 0; k < rows; k++) {
      final ya = c.y(lo + k * step), yb = c.y(lo + (k + 1) * step);
      if (ya == null || yb == null) continue;
      final w = width * vol[k] / maxVol;
      final wu = vol[k] == 0 ? 0.0 : w * up[k] / vol[k];
      final top = math.min(ya, yb) + 0.5, bottom = math.max(ya, yb) - 0.5;
      canvas.drawRect(Rect.fromLTRB(x0, top, x0 + wu, bottom), Paint()..color = upColor);
      canvas.drawRect(Rect.fromLTRB(x0 + wu, top, x0 + w, bottom), Paint()..color = downColor);
      if (k == poc) {
        _strokeLine(
          canvas,
          style.copyWith(color: pocColor, lineWidth: 1),
          Offset(x0, (ya + yb) / 2),
          Offset(x1, (ya + yb) / 2),
        );
      }
    }
  }

  @override
  double? hitDistance(DrawingContext c, Offset p, double tolerance) {
    final span = _span();
    if (span == null) return null;
    final x0 = c.x(span.$1.toDouble()), x1 = c.x(span.$2.toDouble());
    return p.dx >= x0 - tolerance && p.dx <= x1 + tolerance ? 0 : null;
  }
}

// ---- patterns ----

/// A harmonic pattern (XABCD, Cypher): five points with the XAB and BCD
/// triangles filled and their XB and BD legs dashed.
class HarmonicDrawing extends PathDrawing {
  HarmonicDrawing({required super.id, required super.anchors, super.style})
    : super(labels: const ['X', 'A', 'B', 'C', 'D']);

  @override
  void paint(Canvas canvas, DrawingContext c) {
    final p = c.points, fill = style.fillColor;
    if (fill != null) {
      if (p.length >= 3) canvas.drawPath(Path()..addPolygon([p[0], p[1], p[2]], true), Paint()..color = fill);
      if (p.length >= 5) canvas.drawPath(Path()..addPolygon([p[2], p[3], p[4]], true), Paint()..color = fill);
    }
    final dashed = style.copyWith(lineWidth: 1, lineStyle: LineStyle.dashed);
    for (final (i, j) in [(0, 2), (2, 4)]) {
      if (p.length > j) _strokeLine(canvas, dashed, p[i], p[j]);
    }
    super.paint(canvas, c);
  }
}

/// Head and shoulders: seven points (left shoulder, head, right shoulder
/// and the troughs between) with the neckline through the two inner
/// troughs.
class HeadAndShouldersDrawing extends PathDrawing {
  HeadAndShouldersDrawing({required super.id, required super.anchors, super.style})
    : super(labels: const ['', 'LS', '', 'H', '', 'RS', '']);

  @override
  void paint(Canvas canvas, DrawingContext c) {
    final p = c.points;
    if (p.length >= 5) {
      final a = p[2], b = p[4];
      final dx = b.dx - a.dx;
      if (dx.abs() > 1) {
        final slope = (b.dy - a.dy) / dx;
        final left = p.first.dx, right = p.length >= 7 ? p[6].dx : b.dx;
        _strokeLine(
          canvas,
          style.copyWith(lineStyle: LineStyle.dashed),
          Offset(left, a.dy + slope * (left - a.dx)),
          Offset(right, a.dy + slope * (right - a.dx)),
        );
      }
    }
    super.paint(canvas, c);
  }
}

// ---- cycles ----

/// A sine wave through two points: the first a crest (or trough), the
/// second the next trough (or crest), repeated across the pane.
class SineLineDrawing extends Drawing {
  SineLineDrawing({required super.id, required super.anchors, super.style});

  @override
  int get anchorCount => 2;

  List<Offset> _wave(DrawingContext c) {
    if (c.points.length < 2) return c.points;
    final a = c.points[0], b = c.points[1];
    final half = b.dx - a.dx;
    if (half.abs() < 2) return [a, b];
    final mid = (a.dy + b.dy) / 2, amp = (a.dy - b.dy) / 2;
    return [for (var x = 0.0; x <= c.size.width; x += 3) Offset(x, mid + amp * math.cos(math.pi * (x - a.dx) / half))];
  }

  @override
  void paint(Canvas canvas, DrawingContext c) {
    final w = _wave(c);
    if (w.length > 1) _strokePath(canvas, style, Path()..addPolygon(w, false));
  }

  @override
  double? hitDistance(DrawingContext c, Offset p, double tolerance) {
    final w = _wave(c);
    var best = double.infinity;
    for (var i = 1; i < w.length; i++) {
      if ((w[i].dx - p.dx).abs() > 6) continue;
      best = math.min(best, _distanceToSegment(p, w[i - 1], w[i]));
    }
    return _near(best, tolerance);
  }
}

/// Vertical lines repeating at the distance between two bars.
class CyclicLinesDrawing extends Drawing {
  CyclicLinesDrawing({required super.id, required super.anchors, super.style});

  @override
  int get anchorCount => 2;

  List<double> _xs(DrawingContext c) {
    if (c.points.length < 2) return [c.points.first.dx];
    final x0 = c.points[0].dx, d = c.points[1].dx - x0;
    if (d.abs() < 3) return [x0];
    return [for (var x = x0; d > 0 ? x <= c.size.width : x >= 0; x += d) x];
  }

  @override
  void paint(Canvas canvas, DrawingContext c) {
    for (final x in _xs(c)) {
      _strokeLine(canvas, style, Offset(x, 0), Offset(x, c.size.height));
    }
  }

  @override
  double? hitDistance(DrawingContext c, Offset p, double tolerance) =>
      _near(_xs(c).map((x) => (x - p.dx).abs()).reduce(math.min), tolerance);
}

/// Half circles repeating at the distance between two bars.
class TimeCyclesDrawing extends Drawing {
  TimeCyclesDrawing({required super.id, required super.anchors, super.style});

  @override
  int get anchorCount => 2;

  @override
  void paint(Canvas canvas, DrawingContext c) {
    if (c.points.length < 2) return;
    final a = c.points[0];
    final d = c.points[1].dx - a.dx;
    if (d.abs() < 3) return;
    final r = d.abs() / 2;
    for (var x = a.dx; d > 0 ? x <= c.size.width : x >= 0; x += d) {
      canvas.drawArc(
        Rect.fromCircle(center: Offset(x + d / 2, a.dy), radius: r),
        math.pi,
        math.pi,
        false,
        style.stroke(),
      );
    }
  }

  @override
  double? hitDistance(DrawingContext c, Offset p, double tolerance) {
    if (c.points.length < 2) return null;
    final a = c.points[0];
    final d = c.points[1].dx - a.dx;
    if (d.abs() < 3 || p.dy > a.dy + tolerance) return null;
    final k = ((p.dx - a.dx) / d).floor();
    if (k < 0) return null;
    final center = Offset(a.dx + d * k + d / 2, a.dy);
    return _near(((p - center).distance - d.abs() / 2).abs(), tolerance);
  }
}

// ---- Fibonacci ----

/// Fan lines from the first point through the Fibonacci [levels] of the
/// second point's height.
class FibFanDrawing extends Drawing {
  FibFanDrawing({
    required super.id,
    required super.anchors,
    super.style = const DrawingStyle(color: Color(0xFF787B86), lineWidth: 1),
    this.levels = defaultLevels,
  });

  static const defaultLevels = [0.236, 0.382, 0.5, 0.618, 0.786, 1.0];

  List<double> levels;

  @override
  int get anchorCount => 2;

  List<(Offset, Offset, double)> _rays(DrawingContext c) {
    if (c.points.length < 2) return const [];
    final a = c.points[0], b = c.points[1];
    final dx = b.dx - a.dx;
    if (dx.abs() < 2) return const [];
    final edge = dx > 0 ? c.size.width : 0.0;
    return [
      for (final r in levels)
        if ((b.dy + (a.dy - b.dy) * (1 - r) - a.dy) / dx case final slope)
          (a, Offset(edge, a.dy + slope * (edge - a.dx)), r),
    ];
  }

  @override
  void paint(Canvas canvas, DrawingContext c) {
    for (final (i, (a, b, r)) in _rays(c).indexed) {
      final s = style.copyWith(color: _levelColors[(i + 1) % _levelColors.length]);
      _strokeLine(canvas, s, a, b);
      _text(_trimRatio(r), s.copyWith(fontSize: 10)).paint(canvas, Offset.lerp(a, b, 0.3)! + const Offset(2, -12));
    }
  }

  @override
  double? hitDistance(DrawingContext c, Offset p, double tolerance) {
    final rays = _rays(c);
    if (rays.isEmpty) return null;
    return _near(rays.map((r) => _distanceToSegment(p, r.$1, r.$2)).reduce(math.min), tolerance);
  }
}

/// Arcs around the second point at Fibonacci fractions of its distance
/// from the first, opening away from it.
class FibArcDrawing extends Drawing {
  FibArcDrawing({
    required super.id,
    required super.anchors,
    super.style = const DrawingStyle(color: Color(0xFF787B86), lineWidth: 1),
    this.levels = defaultLevels,
  });

  static const defaultLevels = [0.382, 0.5, 0.618, 1.0];

  List<double> levels;

  @override
  int get anchorCount => 2;

  @override
  void paint(Canvas canvas, DrawingContext c) {
    if (c.points.length < 2) return;
    final a = c.points[0], b = c.points[1];
    _strokeLine(canvas, style.copyWith(lineWidth: 1, lineStyle: LineStyle.dashed), a, b);
    final d = (b - a).distance;
    final start = a.dy < b.dy ? math.pi : 0.0;
    for (final (i, l) in levels.indexed) {
      final s = style.copyWith(color: _levelColors[(i + 2) % _levelColors.length]);
      canvas.drawArc(Rect.fromCircle(center: b, radius: d * l), start, math.pi, false, s.stroke());
    }
  }

  @override
  double? hitDistance(DrawingContext c, Offset p, double tolerance) {
    if (c.points.length < 2) return null;
    final a = c.points[0], b = c.points[1];
    final d = (b - a).distance, r = (p - b).distance;
    return _near([for (final l in levels) (r - d * l).abs(), _distanceToSegment(p, a, b)].reduce(math.min), tolerance);
  }
}

// ---- annotations ----

/// An icon at a point — an emoji-style mark, or a flag with [anchorAtBase]
/// (the anchor is then its pole's foot, not its center) — in the style's
/// color at its font size.
class IconMarkDrawing extends Drawing {
  IconMarkDrawing({
    required super.id,
    required super.anchors,
    super.style = const DrawingStyle(fontSize: 24),
    required this.icon,
    this.iconKey,
    this.anchorAtBase = false,
  });

  /// A flag, for an icon whose key a [DrawingCodec] doesn't know.
  static const fallbackIcon = IconData(0xe153, fontFamily: 'MaterialIcons');

  IconData icon;

  /// What [DrawingCodec] saves [icon] as (see [DrawingCodec.icons]).
  String? iconKey;
  bool anchorAtBase;

  @override
  int get anchorCount => 1;

  @override
  int get hitPriority => 2;

  Rect _rect(DrawingContext c) {
    final s = style.fontSize, p = c.points.first;
    return anchorAtBase
        ? Rect.fromLTWH(p.dx - s * 0.2, p.dy - s, s, s)
        : Rect.fromCenter(center: p, width: s, height: s);
  }

  @override
  void paint(Canvas canvas, DrawingContext c) {
    final tp = TextPainter(
      text: TextSpan(
        text: String.fromCharCode(icon.codePoint),
        style: TextStyle(
          fontSize: style.fontSize,
          fontFamily: icon.fontFamily,
          package: icon.fontPackage,
          color: style.color,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, _rect(c).topLeft);
  }

  @override
  double? hitDistance(DrawingContext c, Offset p, double tolerance) =>
      _rect(c).inflate(tolerance).contains(p) ? 0 : null;
}

/// The anchor's price in a bubble pointing down at it.
class PriceLabelDrawing extends Drawing {
  PriceLabelDrawing({required super.id, required super.anchors, super.style});

  @override
  int get anchorCount => 1;

  @override
  int get hitPriority => 2;

  Rect _box(DrawingContext c, TextPainter tp) {
    final p = c.points.first;
    return Rect.fromLTWH(p.dx - tp.width / 2 - 6, p.dy - tp.height - 16, tp.width + 12, tp.height + 6);
  }

  TextPainter _painter(DrawingContext c) => _text(
    c.formatPrice(anchors.first.price),
    style.copyWith(fontSize: 11),
    color: style.textColor ?? const Color(0xFFFFFFFF),
    weight: FontWeight.w600,
  );

  @override
  void paint(Canvas canvas, DrawingContext c) {
    final p = c.points.first;
    final tp = _painter(c);
    final box = _box(c, tp);
    final paint = Paint()..color = style.color;
    canvas.drawRRect(RRect.fromRectAndRadius(box, const Radius.circular(4)), paint);
    canvas.drawPath(Path()..addPolygon([Offset(p.dx - 5, box.bottom), Offset(p.dx + 5, box.bottom), p], true), paint);
    tp.paint(canvas, box.topLeft + const Offset(6, 3));
  }

  @override
  double? hitDistance(DrawingContext c, Offset p, double tolerance) =>
      _box(c, _painter(c)).inflate(tolerance).contains(p) || (p - c.points.first).distance <= tolerance ? 0 : null;
}
