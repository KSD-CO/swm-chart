// Drawing tools: trend lines, levels, shapes, Fibonacci, channels, text,
// measurements, multi-point patterns and freehand, plus an editor that
// creates, selects, moves and reshapes them with the pointer. Upstream
// leaves all of this to plugins; this is one built on the primitives and
// pointer APIs.
import 'dart:math' as math;

import 'package:flutter/painting.dart';
import 'package:flutter/services.dart' show SystemMouseCursors;

import '../api/chart_controller.dart';
import '../options.dart';
import '../renderers/draw_utils.dart';
import 'primitive.dart';

/// A point of a drawing: a fractional logical index (so it can sit between
/// bars or past the last one) and a price on the pane's default scale.
class DrawingAnchor {
  const DrawingAnchor(this.logical, this.price);

  final double logical;
  final double price;

  DrawingAnchor shift(double dLogical, double dPrice) => DrawingAnchor(logical + dLogical, price + dPrice);

  @override
  bool operator ==(Object other) => other is DrawingAnchor && other.logical == logical && other.price == price;

  @override
  int get hashCode => Object.hash(logical, price);

  @override
  String toString() => 'DrawingAnchor($logical, $price)';
}

class DrawingStyle {
  const DrawingStyle({
    this.color = const Color(0xFF2962FF),
    this.lineWidth = 1.5,
    this.lineStyle = LineStyle.solid,
    this.fillColor,
    this.textColor,
    this.fontSize = 12,
  });

  final Color color;
  final double lineWidth;
  final LineStyle lineStyle;

  /// Fill of closed shapes, channels and zones; `null` draws none.
  final Color? fillColor;

  /// `null` uses [color].
  final Color? textColor;
  final double fontSize;

  DrawingStyle copyWith({
    Color? color,
    double? lineWidth,
    LineStyle? lineStyle,
    Color? fillColor,
    Color? textColor,
    double? fontSize,
  }) => DrawingStyle(
    color: color ?? this.color,
    lineWidth: lineWidth ?? this.lineWidth,
    lineStyle: lineStyle ?? this.lineStyle,
    fillColor: fillColor ?? this.fillColor,
    textColor: textColor ?? this.textColor,
    fontSize: fontSize ?? this.fontSize,
  );

  Paint stroke() => Paint()
    ..color = color
    ..style = PaintingStyle.stroke
    ..strokeWidth = lineWidth
    ..strokeCap = StrokeCap.round
    ..strokeJoin = StrokeJoin.round;
}

/// What a drawing gets to paint or hit-test itself: its anchors in pane
/// coordinates and the conversions behind them.
class DrawingContext {
  DrawingContext(this.chart, this.points, this.formatPrice);

  final PrimitiveContext chart;

  /// The drawing's anchors in pane coordinates, in order.
  final List<Offset> points;

  final String Function(double price) formatPrice;

  Size get size => chart.paneSize;

  double x(double logical) => chart.logicalToCoordinate(logical);

  double? y(double price) => chart.priceToCoordinate(price);
}

/// Base class of every drawing. Subclass it for a tool the built-ins don't
/// cover: give the number of anchors it takes, paint it and say how far a
/// point is from it.
abstract class Drawing {
  Drawing({required this.id, required List<DrawingAnchor> anchors, this.style = const DrawingStyle()})
    : anchors = List.of(anchors);

  /// Reported in [DrawingHit] and the editor's callbacks.
  final Object id;

  List<DrawingAnchor> anchors;
  DrawingStyle style;

  /// Hidden drawings are neither painted nor hit.
  bool visible = true;

  /// Locked drawings can be selected but not moved or reshaped.
  bool locked = false;

  /// Anchors the tool places when created; 0 for an open-ended stroke
  /// collected while dragging (freehand).
  int get anchorCount;

  void paint(Canvas canvas, DrawingContext c);

  /// Distance in logical pixels from [p] to the drawing, or `null` when it
  /// isn't within [tolerance].
  double? hitDistance(DrawingContext c, Offset p, double tolerance);

  /// 0 for areas, 1 for lines, 2 for points, like [PrimitiveHitTestResult.hitTestPriority].
  int get hitPriority => 1;

  /// Where the selected drawing shows its drag handles; by default its
  /// anchors. Indices map to [anchors].
  List<Offset> handles(DrawingContext c) => c.points;

  /// Prices labelled on the price axis while unselected.
  List<double> get axisPrices => const [];
}

/// What [DrawingsPrimitive.hitTest] reports as `hoveredObjectId`.
class DrawingHit {
  const DrawingHit(this.layer, this.drawingId, [this.handle]);

  final DrawingsPrimitive layer;
  final Object drawingId;

  /// Index of the anchor whose handle was hit, `null` for the body.
  final int? handle;

  @override
  bool operator ==(Object other) =>
      other is DrawingHit && other.layer == layer && other.drawingId == drawingId && other.handle == handle;

  @override
  int get hashCode => Object.hash(layer, drawingId, handle);
}

/// Paints a list of drawings with handles on the selected one. Attach it to
/// a pane (`PaneApi.attachPrimitive`) so anchors use the pane's default
/// price scale, the one pointer events report prices on. [DrawingEditor]
/// does this for you.
class DrawingsPrimitive extends ChartPrimitive {
  DrawingsPrimitive({
    List<Drawing> drawings = const [],
    this.hitTolerance = 6,
    this.handleRadius = 5,
    this.formatPrice = _defaultFormat,
  }) : _drawings = List.of(drawings);

  static String _defaultFormat(double price) => price.toStringAsFixed(2);

  final List<Drawing> _drawings;
  Object? _selectedId;
  Drawing? _draft;

  final double hitTolerance;
  final double handleRadius;
  final String Function(double price) formatPrice;

  List<Drawing> get drawings => List.unmodifiable(_drawings);

  set drawings(List<Drawing> value) {
    _drawings
      ..clear()
      ..addAll(value);
    requestUpdate();
  }

  void add(Drawing drawing) {
    _drawings.add(drawing);
    requestUpdate();
  }

  Drawing? remove(Object id) {
    final i = _drawings.indexWhere((d) => d.id == id);
    if (i < 0) return null;
    if (_selectedId == id) _selectedId = null;
    final d = _drawings.removeAt(i);
    requestUpdate();
    return d;
  }

  Drawing? byId(Object id) {
    for (final d in _drawings) {
      if (d.id == id) return d;
    }
    return _draft?.id == id ? _draft : null;
  }

  Object? get selectedId => _selectedId;

  set selectedId(Object? id) {
    _selectedId = id;
    requestUpdate();
  }

  /// A drawing being created, painted on top as selected.
  Drawing? get draft => _draft;

  set draft(Drawing? value) {
    _draft = value;
    requestUpdate();
  }

  Iterable<Drawing> get _all sync* {
    yield* _drawings;
    if (_draft != null) yield _draft!;
  }

  DrawingContext? _context(PrimitiveContext ctx, Drawing d) {
    final points = <Offset>[];
    for (final a in d.anchors) {
      final y = ctx.priceToCoordinate(a.price);
      if (y == null || !y.isFinite) return null;
      points.add(Offset(ctx.logicalToCoordinate(a.logical), y));
    }
    return DrawingContext(ctx, points, formatPrice);
  }

  bool _isSelected(Drawing d) => d == _draft || d.id == _selectedId;

  @override
  void paint(PrimitivePaintContext ctx) {
    final canvas = ctx.canvas;
    for (final d in _all) {
      if (!d.visible || d.anchors.isEmpty) continue;
      final c = _context(ctx, d);
      if (c == null) continue;
      d.paint(canvas, c);
      if (_isSelected(d)) _paintHandles(canvas, d, c, ctx.backgroundColor);
    }
  }

  void _paintHandles(Canvas canvas, Drawing d, DrawingContext c, Color background) {
    final fill = Paint()..color = background;
    final ring = Paint()
      ..color = d.style.color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    for (final h in d.handles(c)) {
      canvas.drawCircle(h, handleRadius, fill);
      canvas.drawCircle(h, handleRadius, ring);
    }
  }

  @override
  List<AxisLabel> priceAxisLabels(PrimitiveContext ctx) {
    final labels = <AxisLabel>[];
    for (final d in _all) {
      if (!d.visible) continue;
      final prices = _isSelected(d) ? [for (final a in d.anchors) a.price] : d.axisPrices;
      for (final p in prices) {
        final y = ctx.priceToCoordinate(p);
        if (y == null) continue;
        labels.add(AxisLabel(coordinate: y, text: formatPrice(p), backgroundColor: d.style.color));
      }
    }
    return labels;
  }

  @override
  PrimitiveHitTestResult? hitTest(PrimitiveContext ctx, double x, double y) {
    final p = Offset(x, y);
    PrimitiveHitTestResult? best;
    var bestPriority = -1;
    // Later drawings are on top: walk them last to first.
    for (final d in _all.toList().reversed) {
      if (!d.visible || d.anchors.isEmpty) continue;
      final c = _context(ctx, d);
      if (c == null) continue;
      if (_isSelected(d)) {
        final handles = d.handles(c);
        for (var i = 0; i < handles.length; i++) {
          final dist = (handles[i] - p).distance;
          if (dist <= handleRadius + hitTolerance) {
            return PrimitiveHitTestResult(
              externalId: DrawingHit(this, d.id, i),
              distance: dist,
              hitTestPriority: 2,
              cursor: d.locked ? null : SystemMouseCursors.move,
            );
          }
        }
      }
      final dist = d.hitDistance(c, p, hitTolerance);
      if (dist == null || d.hitPriority <= bestPriority) continue;
      bestPriority = d.hitPriority;
      best = PrimitiveHitTestResult(
        externalId: DrawingHit(this, d.id),
        distance: dist,
        hitTestPriority: d.hitPriority,
        cursor: d.locked ? SystemMouseCursors.click : SystemMouseCursors.grab,
      );
      if (bestPriority >= 1) break;
    }
    return best;
  }
}

// ---- the editor ----

/// Creates a drawing for a tool from its first anchors.
typedef DrawingFactory = Drawing Function(Object id, List<DrawingAnchor> anchors);

/// Creates, selects, moves and reshapes drawings in one pane with the
/// pointer.
///
/// * With a tool set ([tool]), taps place the drawing's anchors one by one;
///   a drag places the first and drags out the next (a two-point tool is
///   done in one drag; freehand collects the stroke). The chart doesn't
///   scroll meanwhile.
/// * Without one, a tap selects the drawing under it (or clears the
///   selection), dragging a drawing moves it, and dragging a handle of the
///   selected drawing moves that anchor. Drags elsewhere scroll the chart.
///
/// Turn [TrackingModeOptions.longPressCrosshair] off to edit with long
/// presses too.
class DrawingEditor {
  DrawingEditor(
    this.chart, {
    this.paneIndex = 0,
    DrawingsPrimitive? layer,
    this.snap,
    this.keepTool = false,
    this.onCreated,
    this.onChanged,
    this.onSelectionChanged,
    Object Function()? newId,
  }) : layer = layer ?? DrawingsPrimitive(),
       _newId = newId {
    chart.panes()[paneIndex].attachPrimitive(this.layer);
    chart.subscribePointer(_onPointer);
    chart.subscribeClick(_onClick);
  }

  final ChartController chart;
  final int paneIndex;
  final DrawingsPrimitive layer;

  /// Adjusts each anchor the pointer places (e.g. a magnet to OHLC values).
  DrawingAnchor Function(DrawingAnchor anchor)? snap;

  /// Keep [tool] after a drawing is finished instead of clearing it.
  bool keepTool;

  void Function(Drawing drawing)? onCreated;

  /// After a drag moved or reshaped a drawing.
  void Function(Drawing drawing)? onChanged;
  void Function(Drawing? drawing)? onSelectionChanged;

  final Object Function()? _newId;
  var _counter = 0;

  DrawingFactory? _tool;

  // Anchors of the draft placed so far; the rest are following the pointer.
  var _placed = 0;
  int? _dragAnchor;

  // Moving a whole drawing: where the drag started and the anchors then.
  DrawingAnchor? _moveStart;
  List<DrawingAnchor>? _moveFrom;
  Drawing? _moving;
  bool _moved = false;

  /// The tool new drawings come from; `null` for selecting and editing.
  DrawingFactory? get tool => _tool;

  set tool(DrawingFactory? value) {
    _tool = value;
    layer.draft = null;
    _placed = 0;
    _dragAnchor = null;
    if (value != null) select(null);
  }

  /// Whether a drawing is half placed.
  bool get isDrawing => layer.draft != null;

  List<Drawing> get drawings => layer.drawings;

  Drawing? get selected {
    final id = layer.selectedId;
    return id == null ? null : layer.byId(id);
  }

  void select(Object? id) {
    if (layer.selectedId == id) return;
    layer.selectedId = id;
    onSelectionChanged?.call(selected);
  }

  void add(Drawing drawing) => layer.add(drawing);

  Drawing? remove(Object id) {
    final wasSelected = layer.selectedId == id;
    final d = layer.remove(id);
    if (wasSelected) onSelectionChanged?.call(null);
    return d;
  }

  Drawing? deleteSelected() {
    final id = layer.selectedId;
    return id == null ? null : remove(id);
  }

  void clear() {
    layer.drawings = const [];
    select(null);
  }

  /// Drops a half-placed drawing.
  void cancel() => tool = keepTool ? _tool : null;

  void dispose() {
    chart.unsubscribePointer(_onPointer);
    chart.unsubscribeClick(_onClick);
    final panes = chart.panes();
    if (paneIndex < panes.length) panes[paneIndex].detachPrimitive(layer);
  }

  Object _nextId() => _newId?.call() ?? 'drawing-${_counter++}';

  DrawingAnchor? _anchorAt(double logical, double? price) {
    if (price == null || !price.isFinite) return null;
    final a = DrawingAnchor(logical, price);
    return snap?.call(a) ?? a;
  }

  DrawingHit? _hitOf(Object? id) => id is DrawingHit && id.layer == layer ? id : null;

  void _finish() {
    final d = layer.draft!;
    layer.draft = null;
    _placed = 0;
    _dragAnchor = null;
    if (!keepTool) _tool = null;
    layer.add(d);
    onCreated?.call(d);
    if (!keepTool) select(d.id);
  }

  bool _onPointer(ChartPointerEvent e) {
    if (e.paneIndex != paneIndex) return false;
    final tool = _tool;
    if (tool != null) return _onToolPointer(tool, e);
    switch (e.phase) {
      case ChartPointerPhase.down:
        final hit = _hitOf(e.hoveredInfo?.objectId);
        final d = hit == null ? null : layer.byId(hit.drawingId);
        final start = _anchorAt(e.logical, e.price);
        if (d == null || start == null) return false;
        select(d.id);
        if (d.locked) return true;
        _moving = d;
        _moved = false;
        _dragAnchor = hit!.handle;
        _moveStart = DrawingAnchor(e.logical, e.price!);
        _moveFrom = List.of(d.anchors);
        return true;
      case ChartPointerPhase.move:
        final d = _moving;
        if (d == null || e.price == null) return true;
        final handle = _dragAnchor;
        if (handle != null) {
          final a = _anchorAt(e.logical, e.price);
          if (a != null) d.anchors[handle] = a;
        } else {
          final dl = e.logical - _moveStart!.logical, dp = e.price! - _moveStart!.price;
          d.anchors = [for (final a in _moveFrom!) a.shift(dl, dp)];
        }
        _moved = true;
        layer.requestUpdate();
        return true;
      case ChartPointerPhase.up:
      case ChartPointerPhase.cancel:
        final d = _moving;
        if (d != null && e.phase == ChartPointerPhase.cancel) {
          d.anchors = _moveFrom!;
          layer.requestUpdate();
        } else if (d != null && _moved) {
          onChanged?.call(d);
        }
        _moving = null;
        _dragAnchor = null;
        _moveFrom = null;
        return true;
    }
  }

  bool _onToolPointer(DrawingFactory tool, ChartPointerEvent e) {
    final a = _anchorAt(e.logical, e.price);
    switch (e.phase) {
      case ChartPointerPhase.down:
        if (a == null) return false;
        var d = layer.draft;
        if (d == null) {
          d = tool(_nextId(), [a]);
          _placed = 1;
          layer.draft = d;
          if (d.anchorCount == 1) {
            _dragAnchor = 0;
            return true;
          }
          if (d.anchorCount == 0) return true;
        }
        d.anchors.add(a);
        _dragAnchor = d.anchors.length - 1;
        layer.requestUpdate();
        return true;
      case ChartPointerPhase.move:
        final d = layer.draft;
        if (d == null || a == null) return true;
        if (d.anchorCount == 0) {
          // Freehand: a point every couple of pixels is plenty.
          final last = d.anchors.last;
          final dx =
              (chart.timeScale().logicalToCoordinate(a.logical) - chart.timeScale().logicalToCoordinate(last.logical))
                  .abs();
          final pane = chart.panes()[paneIndex];
          final y0 = pane.priceToCoordinate(last.price), y1 = pane.priceToCoordinate(a.price);
          final dy = y0 == null || y1 == null ? 0.0 : (y1 - y0).abs();
          if (dx + dy < 2) return true;
          d.anchors.add(a);
        } else if (_dragAnchor != null) {
          d.anchors[_dragAnchor!] = a;
        }
        layer.requestUpdate();
        return true;
      case ChartPointerPhase.up:
        final d = layer.draft;
        if (d == null) return true;
        _dragAnchor = null;
        _placed = d.anchors.length;
        if (d.anchorCount == 0 ? d.anchors.length > 1 : _placed >= d.anchorCount) {
          _finish();
        } else if (d.anchorCount == 0) {
          layer.draft = null;
        }
        return true;
      case ChartPointerPhase.cancel:
        final d = layer.draft;
        if (d != null && _dragAnchor != null && d.anchorCount != 1) {
          d.anchors.removeAt(_dragAnchor!);
        }
        _dragAnchor = null;
        if (d != null && (d.anchors.isEmpty || d.anchorCount <= 1)) layer.draft = null;
        _placed = layer.draft?.anchors.length ?? 0;
        layer.requestUpdate();
        return true;
    }
  }

  void _onClick(ChartEventParams p) {
    if (p.paneIndex != paneIndex || p.point == null) return;
    final tool = _tool;
    if (tool == null) {
      final hit = _hitOf(p.hoveredObjectId);
      select(hit?.drawingId);
      return;
    }
    final a = _anchorAt(chart.timeScale().coordinateToLogical(p.point!.dx), p.price);
    if (a == null) return;
    final d = layer.draft;
    if (d == null) {
      final created = tool(_nextId(), [a]);
      if (created.anchorCount == 0) return;
      layer.draft = created;
      _placed = 1;
      if (created.anchorCount <= 1) _finish();
      return;
    }
    d.anchors.add(a);
    _placed = d.anchors.length;
    layer.requestUpdate();
    if (_placed >= d.anchorCount) _finish();
  }
}

// ---- geometry ----

double _distanceToSegment(Offset p, Offset a, Offset b) {
  final d = b - a;
  final len2 = d.dx * d.dx + d.dy * d.dy;
  if (len2 == 0) return (p - a).distance;
  final t = (((p.dx - a.dx) * d.dx + (p.dy - a.dy) * d.dy) / len2).clamp(0.0, 1.0);
  return (p - (a + d * t)).distance;
}

/// The part of the line through [a] and [b] inside [r], with the ends
/// pushed out past [a] ([left]) and past [b] ([right]); `null` when it
/// misses [r].
(Offset, Offset)? _extendedSegment(Offset a, Offset b, Rect r, {bool left = false, bool right = false}) {
  final d = b - a;
  if (d.distanceSquared < 1e-9) return (a, b);
  var lo = left ? double.negativeInfinity : 0.0;
  var hi = right ? double.infinity : 1.0;
  // Liang–Barsky against the four edges.
  for (final (pk, qk) in [
    (-d.dx, a.dx - r.left),
    (d.dx, r.right - a.dx),
    (-d.dy, a.dy - r.top),
    (d.dy, r.bottom - a.dy),
  ]) {
    if (pk == 0) {
      if (qk < 0) return null;
      continue;
    }
    final t = qk / pk;
    if (pk < 0) {
      lo = math.max(lo, t);
    } else {
      hi = math.min(hi, t);
    }
  }
  if (!left) lo = math.max(lo, 0);
  if (!right) hi = math.min(hi, 1);
  if (lo > hi) return null;
  return (a + d * lo, a + d * hi);
}

void _strokeLine(Canvas canvas, DrawingStyle s, Offset a, Offset b) {
  final path = Path()
    ..moveTo(a.dx, a.dy)
    ..lineTo(b.dx, b.dy);
  canvas.drawPath(dashPath(path, dashPattern(s.lineStyle, s.lineWidth)), s.stroke());
}

void _strokePath(Canvas canvas, DrawingStyle s, Path path) =>
    canvas.drawPath(dashPath(path, dashPattern(s.lineStyle, s.lineWidth)), s.stroke());

void _arrowHead(Canvas canvas, DrawingStyle s, Offset from, Offset tip) {
  final d = tip - from;
  if (d.distance < 1) return;
  final u = d / d.distance;
  final size = 6 + s.lineWidth * 2;
  final n = Offset(-u.dy, u.dx);
  final base = tip - u * size;
  canvas.drawPath(
    Path()..addPolygon([tip, base + n * size * 0.5, base - n * size * 0.5], true),
    Paint()..color = s.color,
  );
}

TextPainter _text(String text, DrawingStyle s, {Color? color, FontWeight? weight, Color? background}) => TextPainter(
  text: TextSpan(
    text: text,
    style: TextStyle(
      color: color ?? s.textColor ?? s.color,
      fontSize: s.fontSize,
      fontWeight: weight,
      backgroundColor: background,
    ),
  ),
  textDirection: TextDirection.ltr,
)..layout();

Rect _rectOf(DrawingContext c) => Rect.fromPoints(c.points[0], c.points.length > 1 ? c.points[1] : c.points[0]);

// ---- built-in drawings ----

/// A line through two points; extend it for a ray or an infinite line.
class TrendLineDrawing extends Drawing {
  TrendLineDrawing({
    required super.id,
    required super.anchors,
    super.style,
    this.extendLeft = false,
    this.extendRight = false,
    this.arrow = false,
  });

  bool extendLeft;
  bool extendRight;

  /// An arrow head at the second point.
  bool arrow;

  @override
  int get anchorCount => 2;

  (Offset, Offset)? _segment(DrawingContext c) {
    if (c.points.length < 2) return null;
    return _extendedSegment(c.points[0], c.points[1], Offset.zero & c.size, left: extendLeft, right: extendRight);
  }

  @override
  void paint(Canvas canvas, DrawingContext c) {
    final seg = _segment(c);
    if (seg == null) return;
    _strokeLine(canvas, style, seg.$1, seg.$2);
    if (arrow && !extendRight) _arrowHead(canvas, style, c.points[0], c.points[1]);
  }

  @override
  double? hitDistance(DrawingContext c, Offset p, double tolerance) {
    final seg = _segment(c);
    if (seg == null) return null;
    final d = _distanceToSegment(p, seg.$1, seg.$2);
    return d <= tolerance ? d : null;
  }
}

/// A horizontal line at a price, across the pane or, as a ray, from its
/// anchor to the right.
class HorizontalLineDrawing extends Drawing {
  HorizontalLineDrawing({
    required super.id,
    required super.anchors,
    super.style,
    this.ray = false,
    this.axisLabel = true,
    this.label,
  });

  bool ray;
  bool axisLabel;

  /// Text drawn above the line at its right end.
  String? label;

  @override
  int get anchorCount => 1;

  @override
  List<double> get axisPrices => axisLabel && anchors.isNotEmpty ? [anchors.first.price] : const [];

  @override
  void paint(Canvas canvas, DrawingContext c) {
    final p = c.points.first;
    final left = ray ? p.dx : 0.0;
    drawHorizontalLine(canvas, style.stroke(), p.dy, left, c.size.width, style.lineWidth, style.lineStyle);
    final text = label;
    if (text != null && text.isNotEmpty) {
      final tp = _text(text, style);
      tp.paint(canvas, Offset(c.size.width - tp.width - 4, p.dy - tp.height - 2));
    }
  }

  @override
  double? hitDistance(DrawingContext c, Offset p, double tolerance) {
    final a = c.points.first;
    if (ray && p.dx < a.dx - tolerance) return null;
    final d = (p.dy - a.dy).abs();
    return d <= tolerance ? d : null;
  }
}

/// A vertical line at a bar.
class VerticalLineDrawing extends Drawing {
  VerticalLineDrawing({required super.id, required super.anchors, super.style});

  @override
  int get anchorCount => 1;

  @override
  List<Offset> handles(DrawingContext c) => [Offset(c.points.first.dx, c.size.height / 2)];

  @override
  void paint(Canvas canvas, DrawingContext c) =>
      drawVerticalLine(canvas, style.stroke(), c.points.first.dx, 0, c.size.height, style.lineWidth, style.lineStyle);

  @override
  double? hitDistance(DrawingContext c, Offset p, double tolerance) {
    final d = (p.dx - c.points.first.dx).abs();
    return d <= tolerance ? d : null;
  }
}

/// A horizontal and a vertical line crossing at a point.
class CrossLineDrawing extends Drawing {
  CrossLineDrawing({required super.id, required super.anchors, super.style});

  @override
  int get anchorCount => 1;

  @override
  void paint(Canvas canvas, DrawingContext c) {
    final p = c.points.first;
    final paint = style.stroke();
    drawHorizontalLine(canvas, paint, p.dy, 0, c.size.width, style.lineWidth, style.lineStyle);
    drawVerticalLine(canvas, paint, p.dx, 0, c.size.height, style.lineWidth, style.lineStyle);
  }

  @override
  double? hitDistance(DrawingContext c, Offset p, double tolerance) {
    final a = c.points.first;
    final d = math.min((p.dx - a.dx).abs(), (p.dy - a.dy).abs());
    return d <= tolerance ? d : null;
  }
}

/// A rectangle between two corners.
class RectangleDrawing extends Drawing {
  RectangleDrawing({required super.id, required super.anchors, super.style});

  @override
  int get anchorCount => 2;

  @override
  int get hitPriority => style.fillColor == null ? 1 : 0;

  @override
  void paint(Canvas canvas, DrawingContext c) {
    final r = _rectOf(c);
    final fill = style.fillColor;
    if (fill != null) canvas.drawRect(r, Paint()..color = fill);
    _strokePath(canvas, style, Path()..addRect(r));
  }

  @override
  double? hitDistance(DrawingContext c, Offset p, double tolerance) {
    final r = _rectOf(c);
    final edge = [
      _distanceToSegment(p, r.topLeft, r.topRight),
      _distanceToSegment(p, r.topRight, r.bottomRight),
      _distanceToSegment(p, r.bottomRight, r.bottomLeft),
      _distanceToSegment(p, r.bottomLeft, r.topLeft),
    ].reduce(math.min);
    if (edge <= tolerance) return edge;
    if (style.fillColor != null && r.contains(p)) return 0;
    return null;
  }
}

/// An ellipse inscribed in the rectangle between two corners.
class EllipseDrawing extends Drawing {
  EllipseDrawing({required super.id, required super.anchors, super.style});

  @override
  int get anchorCount => 2;

  @override
  int get hitPriority => style.fillColor == null ? 1 : 0;

  @override
  void paint(Canvas canvas, DrawingContext c) {
    final r = _rectOf(c);
    final fill = style.fillColor;
    if (fill != null) canvas.drawOval(r, Paint()..color = fill);
    _strokePath(canvas, style, Path()..addOval(r));
  }

  @override
  double? hitDistance(DrawingContext c, Offset p, double tolerance) {
    final r = _rectOf(c);
    final rx = r.width / 2, ry = r.height / 2;
    if (rx < 1 || ry < 1) {
      final d = _distanceToSegment(p, r.topLeft, r.bottomRight);
      return d <= tolerance ? d : null;
    }
    final dx = (p.dx - r.center.dx) / rx, dy = (p.dy - r.center.dy) / ry;
    final k = math.sqrt(dx * dx + dy * dy);
    // Radial distance to the outline, close enough for picking.
    final d = (k - 1).abs() * math.min(rx, ry);
    if (d <= tolerance) return d;
    if (style.fillColor != null && k < 1) return 0;
    return null;
  }
}

/// Two parallel lines: the first two anchors set one, the third sets the
/// other's offset. Filled between, with a dashed middle line.
class ParallelChannelDrawing extends Drawing {
  ParallelChannelDrawing({required super.id, required super.anchors, super.style, this.middleLine = true});

  bool middleLine;

  @override
  int get anchorCount => 3;

  @override
  int get hitPriority => style.fillColor == null ? 1 : 0;

  // The second line as an offset from the first.
  Offset _offset(DrawingContext c) {
    final a = c.points[0], b = c.points[1], p = c.points[2];
    if ((b.dx - a.dx).abs() < 1e-6) return Offset(p.dx - a.dx, 0);
    final yOnLine = a.dy + (b.dy - a.dy) * (p.dx - a.dx) / (b.dx - a.dx);
    return Offset(0, p.dy - yOnLine);
  }

  @override
  List<Offset> handles(DrawingContext c) {
    if (c.points.length < 3) return c.points;
    final o = _offset(c);
    // The third handle sits midway along the second line.
    return [c.points[0], c.points[1], Offset.lerp(c.points[0], c.points[1], 0.5)! + o];
  }

  @override
  void paint(Canvas canvas, DrawingContext c) {
    if (c.points.length < 2) return;
    final a = c.points[0], b = c.points[1];
    _strokeLine(canvas, style, a, b);
    if (c.points.length < 3) return;
    final o = _offset(c);
    final fill = style.fillColor;
    if (fill != null) {
      canvas.drawPath(Path()..addPolygon([a, b, b + o, a + o], true), Paint()..color = fill);
    }
    _strokeLine(canvas, style, a + o, b + o);
    if (middleLine) {
      final half = o / 2;
      final mid = Path()
        ..moveTo((a + half).dx, (a + half).dy)
        ..lineTo((b + half).dx, (b + half).dy);
      canvas.drawPath(
        dashPath(mid, dashPattern(LineStyle.dashed, style.lineWidth)),
        style.stroke()..strokeWidth = math.max(1, style.lineWidth - 0.5),
      );
    }
  }

  @override
  double? hitDistance(DrawingContext c, Offset p, double tolerance) {
    if (c.points.length < 2) return null;
    final a = c.points[0], b = c.points[1];
    var d = _distanceToSegment(p, a, b);
    if (c.points.length >= 3) {
      final o = _offset(c);
      d = math.min(d, _distanceToSegment(p, a + o, b + o));
      if (d > tolerance && style.fillColor != null) {
        final inside = Path()..addPolygon([a, b, b + o, a + o], true);
        if (inside.contains(p)) return 0;
      }
    }
    return d <= tolerance ? d : null;
  }
}

/// One level of a [FibRetracementDrawing].
class FibLevel {
  const FibLevel(this.ratio, this.color, {this.visible = true});

  final double ratio;
  final Color color;
  final bool visible;
}

/// Fibonacci retracement between two anchors: level 1 at the first, 0 at
/// the second.
class FibRetracementDrawing extends Drawing {
  FibRetracementDrawing({
    required super.id,
    required super.anchors,
    super.style = const DrawingStyle(color: Color(0xFF787B86), lineWidth: 1),
    this.levels = defaultLevels,
    this.extendLeft = false,
    this.extendRight = false,
    this.fillOpacity = 0.12,
    this.showPrices = true,
  });

  static const defaultLevels = [
    FibLevel(0, Color(0xFF787B86)),
    FibLevel(0.236, Color(0xFFF23645)),
    FibLevel(0.382, Color(0xFFFF9800)),
    FibLevel(0.5, Color(0xFF4CAF50)),
    FibLevel(0.618, Color(0xFF089981)),
    FibLevel(0.786, Color(0xFF00BCD4)),
    FibLevel(1, Color(0xFF787B86)),
    FibLevel(1.618, Color(0xFF2962FF), visible: false),
    FibLevel(2.618, Color(0xFFF23645), visible: false),
  ];

  List<FibLevel> levels;
  bool extendLeft;
  bool extendRight;

  /// Opacity of the zone fill between consecutive levels; 0 fills none.
  double fillOpacity;
  bool showPrices;

  @override
  int get anchorCount => 2;

  /// The price of [ratio].
  double priceAt(double ratio) {
    final a = anchors[0].price, b = anchors.length > 1 ? anchors[1].price : a;
    return b + (a - b) * ratio;
  }

  (double, double) _span(DrawingContext c) {
    final x0 = math.min(c.points[0].dx, c.points.last.dx);
    final x1 = math.max(c.points[0].dx, c.points.last.dx);
    return (extendLeft ? 0 : x0, extendRight ? c.size.width : x1);
  }

  @override
  void paint(Canvas canvas, DrawingContext c) {
    if (c.points.length < 2) return;
    _strokeLine(canvas, style.copyWith(lineStyle: LineStyle.dashed, lineWidth: 1), c.points[0], c.points[1]);
    final (left, right) = _span(c);
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
      final ratio = l.ratio.toStringAsFixed(3).replaceFirst(RegExp(r'\.?0+$'), '');
      final label = showPrices ? '$ratio (${c.formatPrice(price)})' : ratio;
      final tp = _text(label, style, color: l.color);
      tp.paint(canvas, Offset(left + 2, y - tp.height - 1));
    }
  }

  @override
  double? hitDistance(DrawingContext c, Offset p, double tolerance) {
    if (c.points.length < 2) return null;
    final (left, right) = _span(c);
    if (p.dx < left - tolerance || p.dx > right + tolerance) return null;
    double? best;
    for (final l in levels) {
      if (!l.visible) continue;
      final y = c.y(priceAt(l.ratio));
      if (y == null) continue;
      final d = (p.dy - y).abs();
      if (d <= tolerance && (best == null || d < best)) best = d;
    }
    best ??= _distanceToSegment(p, c.points[0], c.points[1]) <= tolerance ? tolerance : null;
    return best;
  }
}

/// Text at a point.
class TextDrawing extends Drawing {
  TextDrawing({required super.id, required super.anchors, super.style, required this.text, this.backgroundColor});

  String text;
  Color? backgroundColor;

  @override
  int get anchorCount => 1;

  @override
  int get hitPriority => 2;

  Rect _bounds(DrawingContext c, TextPainter tp) =>
      Rect.fromLTWH(c.points.first.dx, c.points.first.dy - tp.height, tp.width, tp.height).inflate(3);

  @override
  void paint(Canvas canvas, DrawingContext c) {
    final tp = _text(text, style);
    final bg = backgroundColor;
    if (bg != null) {
      canvas.drawRRect(RRect.fromRectAndRadius(_bounds(c, tp), const Radius.circular(3)), Paint()..color = bg);
    }
    tp.paint(canvas, Offset(c.points.first.dx, c.points.first.dy - tp.height));
  }

  @override
  double? hitDistance(DrawingContext c, Offset p, double tolerance) =>
      _bounds(c, _text(text, style)).inflate(tolerance).contains(p) ? 0 : null;
}

/// A price and time measurement between two points: the change, its
/// percentage and the number of bars.
class MeasureDrawing extends Drawing {
  MeasureDrawing({
    required super.id,
    required super.anchors,
    super.style = const DrawingStyle(),
    this.upColor = const Color(0xFF2962FF),
    this.downColor = const Color(0xFFF23645),
    this.barsLabel = 'bars',
  });

  Color upColor;
  Color downColor;

  /// Word after the bar count.
  String barsLabel;

  @override
  int get anchorCount => 2;

  @override
  int get hitPriority => 0;

  bool get _up => anchors.length < 2 || anchors[1].price >= anchors[0].price;

  /// Change from the first to the second anchor.
  double get change => anchors.length < 2 ? 0 : anchors[1].price - anchors[0].price;

  /// Change as a fraction of the first anchor's price.
  double? get changeFraction => anchors.isEmpty || anchors[0].price == 0 ? null : change / anchors[0].price;

  int get bars => anchors.length < 2 ? 0 : (anchors[1].logical - anchors[0].logical).round();

  @override
  void paint(Canvas canvas, DrawingContext c) {
    if (c.points.length < 2) return;
    final color = _up ? upColor : downColor;
    final r = _rectOf(c);
    canvas.drawRect(r, Paint()..color = color.withValues(alpha: 0.18));
    final s = style.copyWith(color: color);
    final a = c.points[0], b = c.points[1];
    final midX = r.center.dx, midY = r.center.dy;
    _strokeLine(canvas, s, Offset(midX, a.dy), Offset(midX, b.dy));
    _arrowHead(canvas, s, Offset(midX, a.dy), Offset(midX, b.dy));
    _strokeLine(canvas, s, Offset(a.dx, midY), Offset(b.dx, midY));
    _arrowHead(canvas, s, Offset(a.dx, midY), Offset(b.dx, midY));

    final pct = changeFraction;
    final sign = change >= 0 ? '+' : '';
    final lines = [
      '$sign${c.formatPrice(change)}${pct == null ? '' : ' ($sign${(pct * 100).toStringAsFixed(2)}%)'}',
      '$bars $barsLabel',
    ];
    final tp = _text(lines.join('\n'), style, color: const Color(0xFFFFFFFF), weight: FontWeight.w600);
    final box = Rect.fromCenter(
      center: Offset(midX, _up ? r.top - tp.height / 2 - 8 : r.bottom + tp.height / 2 + 8),
      width: tp.width + 12,
      height: tp.height + 8,
    );
    canvas.drawRRect(RRect.fromRectAndRadius(box, const Radius.circular(4)), Paint()..color = color);
    tp.paint(canvas, box.topLeft + const Offset(6, 4));
  }

  @override
  double? hitDistance(DrawingContext c, Offset p, double tolerance) {
    if (c.points.length < 2) return null;
    return _rectOf(c).inflate(tolerance).contains(p) ? 0 : null;
  }
}

/// A polyline through a fixed number of points with a label at each:
/// Elliott waves (0–5, A–C), XABCD harmonics, head and shoulders and the
/// like.
class PathDrawing extends Drawing {
  PathDrawing({
    required super.id,
    required super.anchors,
    super.style,
    required this.labels,
    int? pointCount,
    this.closed = false,
  }) : _pointCount = pointCount ?? labels.length;

  /// Elliott impulse wave 0–5.
  factory PathDrawing.elliottImpulse({required Object id, required List<DrawingAnchor> anchors, DrawingStyle? style}) =>
      PathDrawing(
        id: id,
        anchors: anchors,
        style: style ?? const DrawingStyle(),
        labels: const ['0', '1', '2', '3', '4', '5'],
      );

  /// Elliott correction 0, A, B, C.
  factory PathDrawing.elliottCorrection({
    required Object id,
    required List<DrawingAnchor> anchors,
    DrawingStyle? style,
  }) => PathDrawing(id: id, anchors: anchors, style: style ?? const DrawingStyle(), labels: const ['0', 'A', 'B', 'C']);

  /// Harmonic X, A, B, C, D.
  factory PathDrawing.xabcd({required Object id, required List<DrawingAnchor> anchors, DrawingStyle? style}) =>
      PathDrawing(
        id: id,
        anchors: anchors,
        style: style ?? const DrawingStyle(),
        labels: const ['X', 'A', 'B', 'C', 'D'],
      );

  /// One per point; missing or empty labels draw nothing.
  List<String> labels;
  bool closed;
  final int _pointCount;

  @override
  int get anchorCount => _pointCount;

  @override
  void paint(Canvas canvas, DrawingContext c) {
    final pts = c.points;
    if (pts.length > 1) {
      final path = Path()..addPolygon(pts, closed && pts.length == anchorCount);
      final fill = style.fillColor;
      if (fill != null && pts.length > 2) canvas.drawPath(Path()..addPolygon(pts, true), Paint()..color = fill);
      _strokePath(canvas, style, path);
    }
    for (var i = 0; i < pts.length && i < labels.length; i++) {
      if (labels[i].isEmpty) continue;
      // Above a local top, below a local bottom.
      final prev = i > 0 ? pts[i - 1].dy : null, next = i + 1 < pts.length ? pts[i + 1].dy : null;
      final neighbour = prev ?? next ?? pts[i].dy;
      final isTop = pts[i].dy <= neighbour && (next == null || pts[i].dy <= next);
      final tp = _text(labels[i], style, weight: FontWeight.w600);
      tp.paint(canvas, Offset(pts[i].dx - tp.width / 2, isTop ? pts[i].dy - tp.height - 4 : pts[i].dy + 4));
    }
  }

  @override
  double? hitDistance(DrawingContext c, Offset p, double tolerance) {
    final pts = c.points;
    if (pts.length == 1) {
      final d = (p - pts.first).distance;
      return d <= tolerance ? d : null;
    }
    var best = double.infinity;
    for (var i = 1; i < pts.length; i++) {
      best = math.min(best, _distanceToSegment(p, pts[i - 1], pts[i]));
    }
    if (closed && pts.length > 2) best = math.min(best, _distanceToSegment(p, pts.last, pts.first));
    return best <= tolerance ? best : null;
  }
}

/// A freehand stroke, collected while dragging.
class FreehandDrawing extends Drawing {
  FreehandDrawing({required super.id, required super.anchors, super.style});

  @override
  int get anchorCount => 0;

  /// Too many handles to be useful: the stroke moves as one.
  @override
  List<Offset> handles(DrawingContext c) => const [];

  @override
  void paint(Canvas canvas, DrawingContext c) {
    if (c.points.length < 2) return;
    _strokePath(canvas, style, Path()..addPolygon(c.points, false));
  }

  @override
  double? hitDistance(DrawingContext c, Offset p, double tolerance) {
    var best = double.infinity;
    for (var i = 1; i < c.points.length; i++) {
      best = math.min(best, _distanceToSegment(p, c.points[i - 1], c.points[i]));
    }
    return best <= tolerance ? best : null;
  }
}
