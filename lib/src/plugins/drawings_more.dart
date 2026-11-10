// More drawing tools: long / short positions, Fibonacci extension and time
// zones, pitchforks, Gann fans, anchored VWAP, regression trends, callouts,
// and date and price ranges.
part of 'drawings.dart';

String _trimRatio(double r) => r.toStringAsFixed(3).replaceFirst(RegExp(r'\.?0+$'), '');

String _percent(double fraction) => '${fraction >= 0 ? '+' : ''}${(fraction * 100).toStringAsFixed(2)}%';

/// A label box: [text] in [color] on [background], centered on [center].
Rect _labelBox(Canvas canvas, String text, DrawingStyle s, Offset center, Color background, {Color? color}) {
  final tp = _text(text, s, color: color ?? const Color(0xFFFFFFFF), weight: FontWeight.w600);
  final box = Rect.fromCenter(center: center, width: tp.width + 12, height: tp.height + 6);
  canvas.drawRRect(RRect.fromRectAndRadius(box, const Radius.circular(3)), Paint()..color = background);
  tp.paint(canvas, box.topLeft + const Offset(6, 3));
  return box;
}

double _polylineDistance(List<Offset> pts, Offset p) {
  var best = double.infinity;
  for (var i = 1; i < pts.length; i++) {
    best = math.min(best, _distanceToSegment(p, pts[i - 1], pts[i]));
  }
  return best;
}

// ---- long / short position ----

/// A long or short position: entry, target and stop, with the profit and
/// loss zones, the risk / reward ratio and, with a [quantity], the amounts.
///
/// Anchors: the entry (its bar is the left edge), the target (its bar is
/// the right edge) and the stop. The target and stop sit on their sides of
/// the entry whichever way the anchors are dragged — above and below for a
/// long, the other way for a [short]. Placed with two points (entry, then
/// target); the stop starts at half the target's distance (R:R 2).
class PositionDrawing extends Drawing {
  PositionDrawing({
    required super.id,
    required super.anchors,
    super.style = const DrawingStyle(color: Color(0xFF787B86), lineWidth: 1),
    this.short = false,
    this.quantity,
    this.profitColor = const Color(0xFF089981),
    this.lossColor = const Color(0xFFF23645),
    this.defaultWidth = 20,
  });

  /// A short position: the target below the entry, the stop above.
  bool short;

  /// Position size; shows the amounts at target and stop.
  double? quantity;
  Color profitColor;
  Color lossColor;

  /// Width in bars when placed with both points on one bar.
  double defaultWidth;

  @override
  int get anchorCount => 2;

  @override
  int get hitPriority => 0;

  double get entry => anchors[0].price;

  double get _targetDistance => anchors.length < 2 ? 0 : (anchors[1].price - entry).abs();

  double get _stopDistance => anchors.length < 3 ? _targetDistance / 2 : (anchors[2].price - entry).abs();

  double get target => short ? entry - _targetDistance : entry + _targetDistance;

  double get stop => short ? entry + _stopDistance : entry - _stopDistance;

  /// Reward over risk; `null` without a stop distance.
  double? get riskReward => _stopDistance == 0 ? null : _targetDistance / _stopDistance;

  @override
  void completed() {
    if (anchors.length < 2) return;
    final a = anchors[0], b = anchors[1];
    if ((b.logical - a.logical).abs() < 1) anchors[1] = DrawingAnchor(a.logical + defaultWidth, b.price);
    if ((anchors[1].price - a.price).abs() < 1e-12) {
      anchors[1] = DrawingAnchor(anchors[1].logical, a.price * (short ? 0.98 : 1.02));
    }
    if (anchors.length < 3) anchors.add(DrawingAnchor(anchors[1].logical, stop));
  }

  @override
  List<double> get selectedAxisPrices => anchors.length < 2 ? [entry] : [entry, target, stop];

  @override
  List<double> pricesAt(double logical) {
    if (anchors.length < 2 || !_within(anchors[0], anchors[1], logical)) return const [];
    return [entry, target, stop];
  }

  (double, double) _xs(DrawingContext c) {
    final x0 = c.points[0].dx, x1 = c.points.length > 1 ? c.points[1].dx : x0;
    return (math.min(x0, x1), math.max(x0, x1));
  }

  @override
  List<Offset> handles(DrawingContext c) {
    if (c.points.length < 2) return c.points;
    final x1 = c.points[1].dx;
    return [
      c.points[0],
      Offset(x1, c.y(target) ?? c.points[1].dy),
      if (anchors.length > 2) Offset(x1, c.y(stop) ?? c.points[0].dy),
    ];
  }

  @override
  void paint(Canvas canvas, DrawingContext c) {
    if (c.points.length < 2) return;
    final (left, right) = _xs(c);
    final ye = c.y(entry), yt = c.y(target), ys = c.y(stop);
    if (ye == null || yt == null || ys == null) return;
    canvas.drawRect(
      Rect.fromLTRB(left, math.min(ye, yt), right, math.max(ye, yt)),
      Paint()..color = profitColor.withValues(alpha: 0.2),
    );
    canvas.drawRect(
      Rect.fromLTRB(left, math.min(ye, ys), right, math.max(ye, ys)),
      Paint()..color = lossColor.withValues(alpha: 0.2),
    );
    drawHorizontalLine(canvas, style.stroke(), ye, left, right, style.lineWidth, LineStyle.solid);

    final cx = (left + right) / 2;
    String amount(double distance) {
      final q = quantity;
      return q == null ? '' : ', ${c.formatPrice(distance * q)}';
    }

    final above = yt < ye;
    final words = DrawingLabels.current;
    final targetText =
        '${words.target}: ${c.formatPrice(target)} (${_percent((target - entry) / entry)}${amount(_targetDistance)})';
    final stopText =
        '${words.stop}: ${c.formatPrice(stop)} (${_percent((stop - entry) / entry)}${amount(_stopDistance)})';
    _labelBox(canvas, targetText, style, Offset(cx, yt + (above ? -12 : 12)), profitColor);
    _labelBox(canvas, stopText, style, Offset(cx, ys + (above ? 12 : -12)), lossColor);
    final rr = riskReward;
    final q = quantity;
    final entryText = [
      short ? words.short : words.long,
      if (q != null) '${words.quantity} ${q == q.roundToDouble() ? q.toStringAsFixed(0) : q}',
      if (rr != null) '${words.riskReward} ${rr.toStringAsFixed(2)}',
    ].join(' · ');
    _labelBox(canvas, entryText, style, Offset(cx, ye), short ? lossColor : profitColor);
  }

  @override
  double? hitDistance(DrawingContext c, Offset p, double tolerance) {
    if (c.points.length < 2) return null;
    final (left, right) = _xs(c);
    final ys = [c.y(entry), c.y(target), c.y(stop)].nonNulls;
    if (ys.isEmpty) return null;
    final r = Rect.fromLTRB(left, ys.reduce(math.min), right, ys.reduce(math.max));
    return r.inflate(tolerance).contains(p) ? 0 : null;
  }
}

// ---- Fibonacci ----

void _paintFibLevels(
  Canvas canvas,
  DrawingContext c,
  DrawingStyle style,
  List<FibLevel> levels,
  double Function(double ratio) priceAt,
  double left,
  double right,
  double fillOpacity,
  bool showPrices,
) {
  final shown = [
    for (final l in levels)
      if (l.visible) l,
  ];
  double? prevY;
  for (final l in shown) {
    final y = c.y(priceAt(l.ratio));
    if (y == null) continue;
    if (prevY != null && fillOpacity > 0) {
      canvas.drawRect(
        Rect.fromLTRB(left, math.min(prevY, y), right, math.max(prevY, y)),
        Paint()..color = l.color.withValues(alpha: fillOpacity),
      );
    }
    prevY = y;
  }
  for (final l in shown) {
    final price = priceAt(l.ratio);
    final y = c.y(price);
    if (y == null) continue;
    drawHorizontalLine(canvas, Paint()..color = l.color, y, left, right, style.lineWidth, style.lineStyle);
    final ratio = _trimRatio(l.ratio);
    final tp = _text(showPrices ? '$ratio (${c.formatPrice(price)})' : ratio, style, color: l.color);
    tp.paint(canvas, Offset(left + 2, y - tp.height - 1));
  }
}

double? _fibHit(
  DrawingContext c,
  Offset p,
  double tolerance,
  List<FibLevel> levels,
  double Function(double) priceAt,
  double left,
  double right,
) {
  if (p.dx < left - tolerance || p.dx > right + tolerance) return null;
  double? best;
  for (final l in levels) {
    if (!l.visible) continue;
    final y = c.y(priceAt(l.ratio));
    if (y == null) continue;
    final d = (p.dy - y).abs();
    if (d <= tolerance && (best == null || d < best)) best = d;
  }
  return best;
}

/// Trend-based Fibonacci extension: the move from the first anchor to the
/// second, projected from the third. Level `r` is at
/// `third + (second − first) × r`.
class FibExtensionDrawing extends Drawing {
  FibExtensionDrawing({
    required super.id,
    required super.anchors,
    super.style = const DrawingStyle(color: Color(0xFF787B86), lineWidth: 1),
    this.levels = defaultLevels,
    this.extendRight = false,
    this.fillOpacity = 0.1,
    this.showPrices = true,
  });

  static const defaultLevels = [
    FibLevel(0, Color(0xFF787B86)),
    FibLevel(0.382, Color(0xFFF23645)),
    FibLevel(0.618, Color(0xFFFF9800)),
    FibLevel(1, Color(0xFF4CAF50)),
    FibLevel(1.272, Color(0xFF089981)),
    FibLevel(1.618, Color(0xFF00BCD4)),
    FibLevel(2, Color(0xFF2962FF)),
    FibLevel(2.618, Color(0xFFF23645)),
    FibLevel(3.618, Color(0xFF9C27B0), visible: false),
  ];

  List<FibLevel> levels;
  bool extendRight;
  double fillOpacity;
  bool showPrices;

  @override
  int get anchorCount => 3;

  double priceAt(double ratio) {
    final base = anchors.length > 2 ? anchors[2].price : anchors.last.price;
    final move = anchors.length > 1 ? anchors[1].price - anchors[0].price : 0;
    return base + move * ratio;
  }

  (double, double)? _span(DrawingContext c) {
    if (c.points.length < 3) return null;
    final x = c.points[2].dx;
    final width = math.max((c.points[1].dx - c.points[0].dx).abs(), 40.0);
    return (x, extendRight ? c.size.width : x + width);
  }

  @override
  List<double> pricesAt(double logical) {
    if (anchors.length < 3 || logical < anchors[2].logical) return const [];
    final width = (anchors[1].logical - anchors[0].logical).abs();
    if (!extendRight && logical > anchors[2].logical + width) return const [];
    return [
      for (final l in levels)
        if (l.visible) priceAt(l.ratio),
    ];
  }

  @override
  void paint(Canvas canvas, DrawingContext c) {
    final dashed = style.copyWith(lineStyle: LineStyle.dashed, lineWidth: 1);
    for (var i = 1; i < c.points.length; i++) {
      _strokeLine(canvas, dashed, c.points[i - 1], c.points[i]);
    }
    final span = _span(c);
    if (span == null) return;
    _paintFibLevels(canvas, c, style, levels, priceAt, span.$1, span.$2, fillOpacity, showPrices);
  }

  @override
  double? hitDistance(DrawingContext c, Offset p, double tolerance) {
    final span = _span(c);
    final d = span == null ? null : _fibHit(c, p, tolerance, levels, priceAt, span.$1, span.$2);
    if (d != null) return d;
    final path = _polylineDistance(c.points, p);
    return path <= tolerance ? path : null;
  }
}

/// Fibonacci time zones: vertical lines at 0, 1, 2, 3, 5, 8, 13… times the
/// distance between the two anchors.
class FibTimeZoneDrawing extends Drawing {
  FibTimeZoneDrawing({
    required super.id,
    required super.anchors,
    super.style = const DrawingStyle(color: Color(0xFF2962FF), lineWidth: 1),
    this.zones = defaultZones,
  });

  static const defaultZones = [0, 1, 2, 3, 5, 8, 13, 21, 34, 55, 89];

  List<int> zones;

  @override
  int get anchorCount => 2;

  /// The logical index of each zone line.
  List<double> get logicals {
    if (anchors.length < 2) return [anchors.first.logical];
    final unit = anchors[1].logical - anchors[0].logical;
    return [for (final z in zones) anchors[0].logical + unit * z];
  }

  @override
  void paint(Canvas canvas, DrawingContext c) {
    final paint = style.stroke();
    for (final (i, logical) in logicals.indexed) {
      final x = c.x(logical);
      if (x < -1 || x > c.size.width + 1) continue;
      drawVerticalLine(canvas, paint, x, 0, c.size.height, style.lineWidth, style.lineStyle);
      final tp = _text('${zones[i]}', style);
      tp.paint(canvas, Offset(x + 3, c.size.height - tp.height - 4));
    }
    if (c.points.length > 1) {
      _strokeLine(canvas, style.copyWith(lineStyle: LineStyle.dashed), c.points[0], c.points[1]);
    }
  }

  @override
  double? hitDistance(DrawingContext c, Offset p, double tolerance) {
    double? best;
    for (final logical in logicals) {
      final d = (p.dx - c.x(logical)).abs();
      if (d <= tolerance && (best == null || d < best)) best = d;
    }
    return best;
  }
}

// ---- pitchfork and Gann fan ----

enum PitchforkVariant {
  /// The median line starts at the first anchor.
  andrews,

  /// Starts halfway between the first two anchors' prices, at the first's bar.
  schiff,

  /// Starts halfway between the first two anchors.
  modifiedSchiff,
}

/// Andrews' pitchfork: a median line from the first anchor through the
/// middle of the second and third, and parallel tines through those two,
/// all extended to the right.
class PitchforkDrawing extends Drawing {
  PitchforkDrawing({
    required super.id,
    required super.anchors,
    super.style = const DrawingStyle(color: Color(0xFFE91E63), fillColor: Color(0x14E91E63)),
    this.variant = PitchforkVariant.andrews,
  });

  PitchforkVariant variant;

  @override
  int get anchorCount => 3;

  DrawingAnchor _start() {
    final a = anchors[0], b = anchors[1];
    return switch (variant) {
      PitchforkVariant.andrews => a,
      PitchforkVariant.schiff => DrawingAnchor(a.logical, (a.price + b.price) / 2),
      PitchforkVariant.modifiedSchiff => DrawingAnchor((a.logical + b.logical) / 2, (a.price + b.price) / 2),
    };
  }

  DrawingAnchor _mid() =>
      DrawingAnchor((anchors[1].logical + anchors[2].logical) / 2, (anchors[1].price + anchors[2].price) / 2);

  /// The median line and the two tines at [logical], from their start on.
  @override
  List<double> pricesAt(double logical) {
    if (anchors.length < 3) return const [];
    final s = _start(), m = _mid();
    final dl = m.logical - s.logical;
    if (dl.abs() < 1e-12) return const [];
    final slope = (m.price - s.price) / dl;
    return [
      if (logical >= s.logical) s.price + slope * (logical - s.logical),
      for (final q in [anchors[1], anchors[2]])
        if (logical >= q.logical) q.price + slope * (logical - q.logical),
    ];
  }

  // The three lines in pane coordinates, extended right; `null` when the
  // median has no direction.
  List<(Offset, Offset)>? _lines(DrawingContext c) {
    if (c.points.length < 3) return null;
    final s = _start(), m = _mid();
    final sy = c.y(s.price), my = c.y(m.price);
    if (sy == null || my == null) return null;
    final start = Offset(c.x(s.logical), sy), mid = Offset(c.x(m.logical), my);
    final dir = mid - start;
    if (dir.distance < 1e-6) return null;
    final r = Offset.zero & c.size;
    return [
      for (final from in [start, c.points[1], c.points[2]]) ?_extendedSegment(from, from + dir, r, right: true),
    ];
  }

  @override
  void paint(Canvas canvas, DrawingContext c) {
    if (c.points.length > 1) _strokeLine(canvas, style, c.points[0], c.points[1]);
    if (c.points.length < 3) return;
    _strokeLine(canvas, style, c.points[1], c.points[2]);
    final lines = _lines(c);
    if (lines == null || lines.length < 3) return;
    final fill = style.fillColor;
    if (fill != null) {
      canvas.drawPath(
        Path()..addPolygon([lines[1].$1, lines[1].$2, lines[2].$2, lines[2].$1], true),
        Paint()..color = fill,
      );
    }
    for (final (a, b) in lines) {
      _strokeLine(canvas, style, a, b);
    }
  }

  @override
  double? hitDistance(DrawingContext c, Offset p, double tolerance) {
    var best = _polylineDistance(c.points, p);
    for (final (a, b) in _lines(c) ?? const <(Offset, Offset)>[]) {
      best = math.min(best, _distanceToSegment(p, a, b));
    }
    return best <= tolerance ? best : null;
  }
}

/// A Gann fan from the first anchor: the 1×1 line through the second, and
/// the 1×8 … 8×1 lines around it, as rays to the right.
class GannFanDrawing extends Drawing {
  GannFanDrawing({
    required super.id,
    required super.anchors,
    super.style = const DrawingStyle(lineWidth: 1),
    this.ratios = defaultRatios,
  });

  /// Price units per time unit of each line, relative to the 1×1, and its
  /// color.
  static const defaultRatios = [
    (8.0, '8/1', Color(0xFFF23645)),
    (4.0, '4/1', Color(0xFFFF9800)),
    (3.0, '3/1', Color(0xFFFFB300)),
    (2.0, '2/1', Color(0xFF4CAF50)),
    (1.0, '1/1', Color(0xFF089981)),
    (1 / 2, '1/2', Color(0xFF00BCD4)),
    (1 / 3, '1/3', Color(0xFF2962FF)),
    (1 / 4, '1/4', Color(0xFF7E57C2)),
    (1 / 8, '1/8', Color(0xFF9C27B0)),
  ];

  List<(double, String, Color)> ratios;

  @override
  int get anchorCount => 2;

  @override
  List<double> pricesAt(double logical) {
    if (anchors.length < 2) return const [];
    final o = anchors[0], b = anchors[1];
    final dl = b.logical - o.logical;
    if (dl.abs() < 1e-12 || (logical - o.logical) * dl < 0) return const [];
    final slope = (b.price - o.price) / dl;
    return [for (final (r, _, _) in ratios) o.price + slope * r * (logical - o.logical)];
  }

  List<(Offset, Offset, Offset, String, Color)> _rays(DrawingContext c) {
    if (c.points.length < 2) return const [];
    final o = c.points[0], d = c.points[1] - c.points[0];
    if (d.distance < 1e-6) return const [];
    final r = Offset.zero & c.size;
    return [
      for (final (k, label, color) in ratios)
        if (_extendedSegment(o, o + Offset(d.dx, d.dy * k), r, right: true) case (final a, final b))
          (a, b, o + Offset(d.dx, d.dy * k), label, color),
    ];
  }

  @override
  void paint(Canvas canvas, DrawingContext c) {
    for (final (a, b, at, label, color) in _rays(c)) {
      final s = style.copyWith(color: color);
      _strokeLine(canvas, s, a, b);
      final tp = _text(label, s);
      tp.paint(canvas, at + const Offset(3, -14));
    }
  }

  @override
  double? hitDistance(DrawingContext c, Offset p, double tolerance) {
    var best = double.infinity;
    for (final (a, b, _, _, _) in _rays(c)) {
      best = math.min(best, _distanceToSegment(p, a, b));
    }
    return best <= tolerance ? best : null;
  }
}

// ---- drawings that read the series' data ----

double? _priceOf(SeriesData? d) => switch (d) {
  OhlcData() => (d.high + d.low + d.close) / 3,
  SingleValueData() => d.value,
  _ => null,
};

double? _closeOf(SeriesData? d) => switch (d) {
  OhlcData() => d.close,
  SingleValueData() => d.value,
  _ => null,
};

/// VWAP from a bar on: the volume-weighted average of the typical price
/// (high + low + close) / 3 since the anchor's bar, with optional bands at
/// [bandMultipliers] standard deviations. Reads [source] (and volumes from
/// [volume]; without one every bar weighs the same).
class AnchoredVwapDrawing extends Drawing {
  AnchoredVwapDrawing({
    required super.id,
    required super.anchors,
    super.style = const DrawingStyle(color: Color(0xFF2962FF), lineWidth: 2),
    this.source,
    this.volume,
    this.bandMultipliers = const [],
  });

  /// The price series; nothing is drawn without it.
  SeriesApi? source;
  SeriesApi? volume;

  /// Bands above and below the VWAP, in standard deviations.
  List<double> bandMultipliers;

  @override
  int get anchorCount => 1;

  // VWAP and standard deviation from the anchor's bar on, by logical index.
  List<(int, double, double)> _values(int to) {
    final src = source;
    if (src == null || anchors.isEmpty) return const [];
    final from = anchors[0].logical.round();
    final out = <(int, double, double)>[];
    var pv = 0.0, pv2 = 0.0, vol = 0.0;
    for (var i = math.max(0, from); i <= to; i++) {
      final d = src.dataByIndex(i);
      final p = _priceOf(d);
      if (p == null) continue;
      final v = switch (volume?.dataByIndex(i)) {
        SingleValueData(:final value) when value > 0 => value,
        _ => volume == null ? 1.0 : 0.0,
      };
      pv += p * v;
      pv2 += p * p * v;
      vol += v;
      if (vol <= 0) continue;
      final mean = pv / vol;
      out.add((i, mean, math.sqrt(math.max(0, pv2 / vol - mean * mean))));
    }
    return out;
  }

  int _lastIndex(DrawingContext c) => (c.chart.visibleLogicalRange?.to ?? anchors[0].logical).ceil();

  @override
  List<double> pricesAt(double logical) {
    final i = logical.round();
    for (final (j, mean, sd) in _values(i).reversed) {
      if (j != i) break;
      return [
        mean,
        for (final k in bandMultipliers) ...[mean + k * sd, mean - k * sd],
      ];
    }
    return const [];
  }

  @override
  List<double> get selectedAxisPrices => const [];

  List<List<Offset>> _lines(DrawingContext c) {
    final values = _values(_lastIndex(c));
    final lines = [
      <Offset>[],
      for (final _ in bandMultipliers) ...[<Offset>[], <Offset>[]],
    ];
    for (final (i, mean, sd) in values) {
      final x = c.x(i.toDouble());
      final ys = [
        c.y(mean),
        for (final k in bandMultipliers) ...[c.y(mean + k * sd), c.y(mean - k * sd)],
      ];
      for (final (l, y) in ys.indexed) {
        if (y != null) lines[l].add(Offset(x, y));
      }
    }
    return lines;
  }

  @override
  List<Offset> handles(DrawingContext c) {
    final lines = _lines(c);
    return lines.first.isEmpty ? c.points : [lines.first.first];
  }

  @override
  void paint(Canvas canvas, DrawingContext c) {
    for (final (l, pts) in _lines(c).indexed) {
      if (pts.length < 2) continue;
      final s = l == 0 ? style : style.copyWith(lineWidth: 1, lineStyle: LineStyle.dashed);
      _strokePath(canvas, s, Path()..addPolygon(pts, false));
    }
  }

  @override
  double? hitDistance(DrawingContext c, Offset p, double tolerance) {
    final lines = _lines(c);
    if (lines.first.length == 1) {
      final d = (lines.first.first - p).distance;
      return d <= tolerance ? d : null;
    }
    final d = _polylineDistance(lines.first, p);
    return d <= tolerance ? d : null;
  }
}

/// A linear regression channel over the bars between two anchors: the
/// least-squares line through their closes and lines [deviations] standard
/// deviations of the residuals above and below. Reads [source].
class RegressionTrendDrawing extends Drawing {
  RegressionTrendDrawing({
    required super.id,
    required super.anchors,
    super.style = const DrawingStyle(color: Color(0xFF2962FF), fillColor: Color(0x142962FF)),
    this.source,
    this.deviations = 2,
    this.extendRight = false,
  });

  SeriesApi? source;

  /// Distance of the outer lines, in standard deviations.
  double deviations;
  bool extendRight;

  @override
  int get anchorCount => 2;

  /// Slope, intercept (at logical 0) and standard deviation; `null` with
  /// fewer than two bars.
  (double, double, double)? get fit {
    final src = source;
    if (src == null || anchors.length < 2) return null;
    final a = math.min(anchors[0].logical, anchors[1].logical).round();
    final b = math.max(anchors[0].logical, anchors[1].logical).round();
    var n = 0, sx = 0.0, sy = 0.0, sxx = 0.0, sxy = 0.0;
    final points = <(int, double)>[];
    for (var i = math.max(0, a); i <= b; i++) {
      final y = _closeOf(src.dataByIndex(i));
      if (y == null) continue;
      points.add((i, y));
      n++;
      sx += i;
      sy += y;
      sxx += i * i.toDouble();
      sxy += i * y;
    }
    if (n < 2) return null;
    final den = n * sxx - sx * sx;
    if (den == 0) return null;
    final slope = (n * sxy - sx * sy) / den;
    final intercept = (sy - slope * sx) / n;
    var ss = 0.0;
    for (final (i, y) in points) {
      final r = y - (intercept + slope * i);
      ss += r * r;
    }
    return (slope, intercept, math.sqrt(ss / n));
  }

  double get _left => math.min(anchors[0].logical, anchors[1].logical);
  double get _right => math.max(anchors[0].logical, anchors[1].logical);

  @override
  List<double> pricesAt(double logical) {
    final f = fit;
    if (f == null || logical < _left || (!extendRight && logical > _right)) return const [];
    final mid = f.$2 + f.$1 * logical;
    return [mid, mid + deviations * f.$3, mid - deviations * f.$3];
  }

  @override
  List<double> get selectedAxisPrices {
    final f = fit;
    if (f == null) return const [];
    return [f.$2 + f.$1 * anchors[0].logical, f.$2 + f.$1 * anchors[1].logical];
  }

  // Center, upper and lower lines from the left anchor to the right one (or
  // the pane's edge).
  List<(Offset, Offset)>? _lines(DrawingContext c) {
    final f = fit;
    if (f == null) return null;
    final l = _left, r = extendRight ? math.max(_right, c.chart.visibleLogicalRange?.to ?? _right) : _right;
    final out = <(Offset, Offset)>[];
    for (final k in [0.0, deviations, -deviations]) {
      final y0 = c.y(f.$2 + f.$1 * l + k * f.$3), y1 = c.y(f.$2 + f.$1 * r + k * f.$3);
      if (y0 == null || y1 == null) return null;
      out.add((Offset(c.x(l), y0), Offset(c.x(r), y1)));
    }
    return out;
  }

  @override
  List<Offset> handles(DrawingContext c) {
    final f = fit;
    if (f == null) return c.points;
    return [for (final a in anchors.take(2)) Offset(c.x(a.logical), c.y(f.$2 + f.$1 * a.logical) ?? c.size.height / 2)];
  }

  @override
  void paint(Canvas canvas, DrawingContext c) {
    final lines = _lines(c);
    if (lines == null) {
      // No data under it yet: the span the anchors cover.
      if (c.points.length > 1) {
        _strokeLine(canvas, style.copyWith(lineStyle: LineStyle.dashed), c.points[0], c.points[1]);
      }
      return;
    }
    final fill = style.fillColor;
    if (fill != null) {
      canvas.drawPath(
        Path()..addPolygon([lines[1].$1, lines[1].$2, lines[2].$2, lines[2].$1], true),
        Paint()..color = fill,
      );
    }
    _strokeLine(canvas, style, lines[0].$1, lines[0].$2);
    final outer = style.copyWith(lineWidth: 1);
    _strokeLine(canvas, outer, lines[1].$1, lines[1].$2);
    _strokeLine(canvas, outer, lines[2].$1, lines[2].$2);
  }

  @override
  double? hitDistance(DrawingContext c, Offset p, double tolerance) {
    final lines = _lines(c);
    if (lines == null) {
      if (c.points.length < 2) return null;
      final d = _distanceToSegment(p, c.points[0], c.points[1]);
      return d <= tolerance ? d : null;
    }
    final d = lines.map((l) => _distanceToSegment(p, l.$1, l.$2)).reduce(math.min);
    if (d <= tolerance) return d;
    if (style.fillColor != null &&
        (Path()..addPolygon([lines[1].$1, lines[1].$2, lines[2].$2, lines[2].$1], true)).contains(p)) {
      return tolerance;
    }
    return null;
  }
}

// ---- annotations and ranges ----

/// A text box pointing at a spot: the first anchor is the spot, the second
/// the box.
class CalloutDrawing extends Drawing {
  CalloutDrawing({
    required super.id,
    required super.anchors,
    super.style = const DrawingStyle(color: Color(0xFF2962FF), textColor: Color(0xFFFFFFFF), fontSize: 13),
    required this.text,
  });

  String text;

  @override
  int get anchorCount => 2;

  @override
  int get hitPriority => 2;

  Rect? _box(DrawingContext c, TextPainter tp) {
    if (c.points.length < 2) return null;
    return Rect.fromCenter(center: c.points[1], width: tp.width + 16, height: tp.height + 10);
  }

  @override
  void paint(Canvas canvas, DrawingContext c) {
    final tp = _text(text, style);
    final box = _box(c, tp);
    if (box == null) return;
    final tip = c.points[0];
    // A wedge from the box to the spot.
    final mid = box.center, d = tip - mid;
    if (d.distance > 1) {
      final n = Offset(-d.dy, d.dx) / d.distance * math.min(8, box.shortestSide / 2);
      canvas.drawPath(
        Path()..addPolygon([mid + n, tip, mid - n], true),
        Paint()..color = style.fillColor ?? style.color,
      );
    }
    canvas.drawRRect(
      RRect.fromRectAndRadius(box, const Radius.circular(6)),
      Paint()..color = style.fillColor ?? style.color,
    );
    tp.paint(canvas, box.topLeft + const Offset(8, 5));
  }

  @override
  double? hitDistance(DrawingContext c, Offset p, double tolerance) {
    final box = _box(c, _text(text, style));
    if (box == null) return null;
    if (box.inflate(tolerance).contains(p)) return 0;
    final d = _distanceToSegment(p, box.center, c.points[0]);
    return d <= tolerance ? d : null;
  }
}

/// How long [seconds] is, as `3d 4h`, `2h 15m` or `45m` (in
/// [DrawingLabels.current]'s units).
String formatDuration(num seconds) {
  final u = DrawingLabels.current;
  final s = seconds.abs().round();
  final d = s ~/ 86400, h = s % 86400 ~/ 3600, m = s % 3600 ~/ 60;
  if (d > 0) return h > 0 ? '$d${u.days} $h${u.hours}' : '$d${u.days}';
  if (h > 0) return m > 0 ? '$h${u.hours} $m${u.minutes}' : '$h${u.hours}';
  if (m > 0) return '$m${u.minutes}';
  return '$s${u.seconds}';
}

/// A date range: the bars between two anchors and the time they span.
class DateRangeDrawing extends Drawing {
  DateRangeDrawing({
    required super.id,
    required super.anchors,
    super.style = const DrawingStyle(color: Color(0xFF2962FF), fillColor: Color(0x262962FF)),
    this.barsLabel,
  });

  /// Word after the bar count; `null` for [DrawingLabels.current]'s.
  String? barsLabel;

  @override
  int get anchorCount => 2;

  @override
  int get hitPriority => 0;

  int get bars => anchors.length < 2 ? 0 : (anchors[1].logical - anchors[0].logical).round();

  @override
  void paint(Canvas canvas, DrawingContext c) {
    if (c.points.length < 2) return;
    final r = _rectOf(c);
    canvas.drawRect(r, Paint()..color = style.fillColor ?? style.color.withValues(alpha: 0.15));
    final a = c.points[0], b = c.points[1];
    _strokeLine(canvas, style, Offset(a.dx, r.center.dy), Offset(b.dx, r.center.dy));
    _arrowHead(canvas, style, Offset(a.dx, r.center.dy), Offset(b.dx, r.center.dy));
    final t0 = c.timeOf?.call(anchors[0].logical), t1 = c.timeOf?.call(anchors[1].logical);
    final text = [
      '$bars ${barsLabel ?? DrawingLabels.current.bars}',
      if (t0 != null && t1 != null) '${t1 < t0 ? '−' : ''}${formatDuration(t1 - t0)}',
    ].join(', ');
    _labelBox(canvas, text, style, Offset(r.center.dx, r.bottom + 14), style.color);
  }

  @override
  double? hitDistance(DrawingContext c, Offset p, double tolerance) =>
      c.points.length < 2 ? null : (_rectOf(c).inflate(tolerance).contains(p) ? 0 : null);
}

/// A price range: the change between two anchors' prices, in price and
/// percent.
class PriceRangeDrawing extends Drawing {
  PriceRangeDrawing({
    required super.id,
    required super.anchors,
    super.style = const DrawingStyle(),
    this.upColor = const Color(0xFF2962FF),
    this.downColor = const Color(0xFFF23645),
  });

  Color upColor;
  Color downColor;

  @override
  int get anchorCount => 2;

  @override
  int get hitPriority => 0;

  double get change => anchors.length < 2 ? 0 : anchors[1].price - anchors[0].price;

  @override
  void paint(Canvas canvas, DrawingContext c) {
    if (c.points.length < 2) return;
    final color = change >= 0 ? upColor : downColor;
    final r = _rectOf(c);
    canvas.drawRect(r, Paint()..color = color.withValues(alpha: 0.15));
    final s = style.copyWith(color: color);
    final a = c.points[0], b = c.points[1];
    _strokeLine(canvas, s, Offset(r.center.dx, a.dy), Offset(r.center.dx, b.dy));
    _arrowHead(canvas, s, Offset(r.center.dx, a.dy), Offset(r.center.dx, b.dy));
    final base = anchors[0].price;
    final text = '${change >= 0 ? '+' : ''}${c.formatPrice(change)}${base == 0 ? '' : ' (${_percent(change / base)})'}';
    final up = b.dy <= a.dy;
    _labelBox(canvas, text, s, Offset(r.center.dx, up ? r.top - 14 : r.bottom + 14), color);
  }

  @override
  double? hitDistance(DrawingContext c, Offset p, double tolerance) =>
      c.points.length < 2 ? null : (_rectOf(c).inflate(tolerance).contains(p) ? 0 : null);
}
