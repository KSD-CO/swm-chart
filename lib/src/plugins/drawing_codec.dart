// Saving drawings and loading them back: JSON-ready maps with the anchors
// stored by time, since a bar's logical index shifts when history is paged
// in or the data reloads.

import 'dart:ui';

import '../options.dart';
import 'drawings.dart';

/// How one kind of drawing is saved: its name, how to make it back, and
/// the fields of its own besides anchors and style.
class DrawingKind<T extends Drawing> {
  const DrawingKind({required this.name, required this.create, this.props});

  /// Saved as `"kind"`.
  final String name;

  /// Makes the drawing from its id, anchors, style and saved [props].
  final T Function(Object id, List<DrawingAnchor> anchors, DrawingStyle style, Map<String, Object?> props) create;

  /// Its own fields, JSON-ready.
  final Map<String, Object?> Function(T drawing)? props;

  bool matches(Drawing d) => d is T;

  Map<String, Object?> _props(Drawing d) => props?.call(d as T) ?? const {};
}

/// Saves drawings as JSON-ready maps and reads them back. The built-in
/// drawings are known; give a [DrawingKind] for each custom one.
///
/// ```dart
/// final codec = DrawingCodec();
/// final saved = jsonEncode(codec.encodeAll(editor.drawings, chart.timeScale().logicalToTime));
/// // later, after the data is loaded:
/// editor.layer.drawings = codec.decodeAll(jsonDecode(saved), chart.timeScale().timeToLogical);
/// ```
class DrawingCodec {
  DrawingCodec({List<DrawingKind> custom = const []}) : _kinds = [...custom, ...builtIns];

  // Custom kinds first, so a subclass of a built-in drawing is saved as
  // itself.
  final List<DrawingKind> _kinds;

  /// The built-in drawings.
  static final List<DrawingKind> builtIns = [
    DrawingKind<TrendLineDrawing>(
      name: 'trendLine',
      create: (id, a, s, p) => TrendLineDrawing(
        id: id,
        anchors: a,
        style: s,
        extendLeft: p['extendLeft'] == true,
        extendRight: p['extendRight'] == true,
        arrow: p['arrow'] == true,
      ),
      props: (d) => {'extendLeft': d.extendLeft, 'extendRight': d.extendRight, 'arrow': d.arrow},
    ),
    DrawingKind<HorizontalLineDrawing>(
      name: 'horizontalLine',
      create: (id, a, s, p) => HorizontalLineDrawing(
        id: id,
        anchors: a,
        style: s,
        ray: p['ray'] == true,
        axisLabel: p['axisLabel'] != false,
        label: p['label'] as String?,
      ),
      props: (d) => {'ray': d.ray, 'axisLabel': d.axisLabel, 'label': d.label},
    ),
    DrawingKind<VerticalLineDrawing>(
      name: 'verticalLine',
      create: (id, a, s, p) => VerticalLineDrawing(id: id, anchors: a, style: s),
    ),
    DrawingKind<CrossLineDrawing>(
      name: 'crossLine',
      create: (id, a, s, p) => CrossLineDrawing(id: id, anchors: a, style: s),
    ),
    DrawingKind<RectangleDrawing>(
      name: 'rectangle',
      create: (id, a, s, p) => RectangleDrawing(id: id, anchors: a, style: s),
    ),
    DrawingKind<EllipseDrawing>(
      name: 'ellipse',
      create: (id, a, s, p) => EllipseDrawing(id: id, anchors: a, style: s),
    ),
    DrawingKind<ParallelChannelDrawing>(
      name: 'parallelChannel',
      create: (id, a, s, p) =>
          ParallelChannelDrawing(id: id, anchors: a, style: s, middleLine: p['middleLine'] != false),
      props: (d) => {'middleLine': d.middleLine},
    ),
    DrawingKind<FibRetracementDrawing>(
      name: 'fibRetracement',
      create: (id, a, s, p) => FibRetracementDrawing(
        id: id,
        anchors: a,
        style: s,
        levels: switch (p['levels']) {
          final List<Object?> levels => [
            for (final l in levels.cast<Map<String, Object?>>())
              FibLevel((l['ratio'] as num).toDouble(), Color(l['color'] as int), visible: l['visible'] != false),
          ],
          _ => FibRetracementDrawing.defaultLevels,
        },
        extendLeft: p['extendLeft'] == true,
        extendRight: p['extendRight'] == true,
        fillOpacity: (p['fillOpacity'] as num?)?.toDouble() ?? 0.12,
        showPrices: p['showPrices'] != false,
      ),
      props: (d) => {
        'levels': [
          for (final l in d.levels) {'ratio': l.ratio, 'color': l.color.toARGB32(), 'visible': l.visible},
        ],
        'extendLeft': d.extendLeft,
        'extendRight': d.extendRight,
        'fillOpacity': d.fillOpacity,
        'showPrices': d.showPrices,
      },
    ),
    DrawingKind<TextDrawing>(
      name: 'text',
      create: (id, a, s, p) => TextDrawing(
        id: id,
        anchors: a,
        style: s,
        text: p['text'] as String? ?? '',
        backgroundColor: _color(p['backgroundColor']),
      ),
      props: (d) => {'text': d.text, 'backgroundColor': d.backgroundColor?.toARGB32()},
    ),
    DrawingKind<MeasureDrawing>(
      name: 'measure',
      create: (id, a, s, p) => MeasureDrawing(
        id: id,
        anchors: a,
        style: s,
        upColor: _color(p['upColor']) ?? const Color(0xFF2962FF),
        downColor: _color(p['downColor']) ?? const Color(0xFFF23645),
        barsLabel: p['barsLabel'] as String? ?? 'bars',
      ),
      props: (d) => {'upColor': d.upColor.toARGB32(), 'downColor': d.downColor.toARGB32(), 'barsLabel': d.barsLabel},
    ),
    DrawingKind<PathDrawing>(
      name: 'path',
      create: (id, a, s, p) => PathDrawing(
        id: id,
        anchors: a,
        style: s,
        labels: [for (final l in (p['labels'] as List<Object?>? ?? const [])) '$l'],
        pointCount: (p['pointCount'] as num?)?.toInt(),
        closed: p['closed'] == true,
      ),
      props: (d) => {'labels': d.labels, 'pointCount': d.anchorCount, 'closed': d.closed},
    ),
    DrawingKind<FreehandDrawing>(
      name: 'freehand',
      create: (id, a, s, p) => FreehandDrawing(id: id, anchors: a, style: s),
    ),
  ];

  /// [d] as a JSON-ready map, its anchors at the times [timeOf] gives
  /// (e.g. `chart.timeScale().logicalToTime`). `null` for a drawing of a
  /// kind this codec doesn't know, or with an anchor that has no time.
  Map<String, Object?>? encode(Drawing d, num? Function(double logical) timeOf) {
    final kind = _kinds.where((k) => k.matches(d)).firstOrNull;
    if (kind == null) return null;
    final anchors = <List<num>>[];
    for (final a in d.anchors) {
      final time = timeOf(a.logical);
      if (time == null) return null;
      anchors.add([time, a.price]);
    }
    return {
      'kind': kind.name,
      'id': d.id is String || d.id is num ? d.id : '${d.id}',
      'anchors': anchors,
      'style': _style(d.style),
      if (!d.visible) 'visible': false,
      if (d.locked) 'locked': true,
      'props': kind._props(d),
    };
  }

  /// The drawing [json] describes, its anchors placed at the logical
  /// indices [logicalOf] gives (e.g. `chart.timeScale().timeToLogical`).
  /// `null` for an unknown kind or an anchor that can't be placed.
  Drawing? decode(Map<String, Object?> json, double? Function(num time) logicalOf) {
    final name = json['kind'];
    final kind = _kinds.where((k) => k.name == name).firstOrNull;
    if (kind == null) return null;
    final anchors = <DrawingAnchor>[];
    for (final a in (json['anchors'] as List<Object?>? ?? const []).cast<List<Object?>>()) {
      final logical = logicalOf(a[0] as num);
      if (logical == null) return null;
      anchors.add(DrawingAnchor(logical, (a[1] as num).toDouble()));
    }
    final d = kind.create(
      json['id'] ?? Object(),
      anchors,
      _readStyle(json['style']),
      (json['props'] as Map?)?.cast<String, Object?>() ?? const {},
    );
    d.visible = json['visible'] != false;
    d.locked = json['locked'] == true;
    return d;
  }

  /// [encode] for each of [drawings], skipping those it can't save.
  List<Map<String, Object?>> encodeAll(List<Drawing> drawings, num? Function(double logical) timeOf) => [
    for (final d in drawings) ?encode(d, timeOf),
  ];

  /// [decode] for each entry of [json], skipping those it can't read.
  List<Drawing> decodeAll(List<Object?> json, double? Function(num time) logicalOf) => [
    for (final j in json)
      if (j is Map) ?decode(j.cast<String, Object?>(), logicalOf),
  ];

  static Map<String, Object?> _style(DrawingStyle s) => {
    'color': s.color.toARGB32(),
    'lineWidth': s.lineWidth,
    'lineStyle': s.lineStyle.name,
    if (s.fillColor != null) 'fillColor': s.fillColor!.toARGB32(),
    if (s.textColor != null) 'textColor': s.textColor!.toARGB32(),
    'fontSize': s.fontSize,
  };

  static DrawingStyle _readStyle(Object? json) {
    if (json is! Map) return const DrawingStyle();
    const d = DrawingStyle();
    return DrawingStyle(
      color: _color(json['color']) ?? d.color,
      lineWidth: (json['lineWidth'] as num?)?.toDouble() ?? d.lineWidth,
      lineStyle: LineStyle.values.where((v) => v.name == json['lineStyle']).firstOrNull ?? d.lineStyle,
      fillColor: _color(json['fillColor']),
      textColor: _color(json['textColor']),
      fontSize: (json['fontSize'] as num?)?.toDouble() ?? d.fontSize,
    );
  }

  static Color? _color(Object? v) => v is int ? Color(v) : null;
}
