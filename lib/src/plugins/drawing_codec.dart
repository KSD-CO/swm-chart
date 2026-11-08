// Saving drawings and loading them back: JSON-ready maps with the anchors
// stored by time, since a bar's logical index shifts when history is paged
// in or the data reloads.

import 'dart:ui';

import 'package:flutter/widgets.dart' show IconData;

import '../api/chart_controller.dart';
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
/// Drawings that read the chart's data ([AnchoredVwapDrawing],
/// [RegressionTrendDrawing]) are loaded over [source] (and [volume]).
///
/// ```dart
/// final codec = DrawingCodec();
/// final saved = jsonEncode(codec.encodeAll(editor.drawings, chart.timeScale().logicalToTime));
/// // later, after the data is loaded:
/// editor.layer.drawings = codec.decodeAll(jsonDecode(saved), chart.timeScale().timeToLogical);
/// ```
class DrawingCodec {
  DrawingCodec({List<DrawingKind> custom = const [], this.source, this.volume, this.icons = const {}})
    : _kinds = [...custom, ...builtIns, ..._dataKinds(source, volume), _iconKind(icons)];

  /// The series loaded data drawings read.
  final SeriesApi? source;
  final SeriesApi? volume;

  /// The icons [IconMarkDrawing]s are saved by, under their keys; one whose
  /// key isn't here loads as [IconMarkDrawing.fallbackIcon]. (Icons are
  /// saved by key, not code point: icon fonts are tree-shaken down to the
  /// constant icons an app uses.)
  final Map<String, IconData> icons;

  // Custom kinds first, so a subclass of a built-in drawing is saved as
  // itself.
  final List<DrawingKind> _kinds;

  /// The built-in drawings.
  static final List<DrawingKind> builtIns = [
    // Subclasses before their base, so each is saved as itself.
    DrawingKind<TrendAngleDrawing>(
      name: 'trendAngle',
      create: (id, a, s, p) => TrendAngleDrawing(id: id, anchors: a, style: s),
    ),
    DrawingKind<InfoLineDrawing>(
      name: 'infoLine',
      create: (id, a, s, p) =>
          InfoLineDrawing(id: id, anchors: a, style: s, barsLabel: p['barsLabel'] as String? ?? 'bars'),
      props: (d) => {'barsLabel': d.barsLabel},
    ),
    DrawingKind<HarmonicDrawing>(
      name: 'harmonic',
      create: (id, a, s, p) => HarmonicDrawing(id: id, anchors: a, style: s),
    ),
    DrawingKind<HeadAndShouldersDrawing>(
      name: 'headAndShoulders',
      create: (id, a, s, p) => HeadAndShouldersDrawing(id: id, anchors: a, style: s),
    ),
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
        levels: _readLevels(p['levels']) ?? FibRetracementDrawing.defaultLevels,
        extendLeft: p['extendLeft'] == true,
        extendRight: p['extendRight'] == true,
        fillOpacity: (p['fillOpacity'] as num?)?.toDouble() ?? 0.12,
        showPrices: p['showPrices'] != false,
      ),
      props: (d) => {
        'levels': _levels(d.levels),
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
    DrawingKind<PositionDrawing>(
      name: 'position',
      create: (id, a, s, p) => PositionDrawing(
        id: id,
        anchors: a,
        style: s,
        short: p['short'] == true,
        quantity: (p['quantity'] as num?)?.toDouble(),
        profitColor: _color(p['profitColor']) ?? const Color(0xFF089981),
        lossColor: _color(p['lossColor']) ?? const Color(0xFFF23645),
      ),
      props: (d) => {
        'short': d.short,
        'quantity': d.quantity,
        'profitColor': d.profitColor.toARGB32(),
        'lossColor': d.lossColor.toARGB32(),
      },
    ),
    DrawingKind<FibExtensionDrawing>(
      name: 'fibExtension',
      create: (id, a, s, p) => FibExtensionDrawing(
        id: id,
        anchors: a,
        style: s,
        levels: _readLevels(p['levels']) ?? FibExtensionDrawing.defaultLevels,
        extendRight: p['extendRight'] == true,
        fillOpacity: (p['fillOpacity'] as num?)?.toDouble() ?? 0.1,
        showPrices: p['showPrices'] != false,
      ),
      props: (d) => {
        'levels': _levels(d.levels),
        'extendRight': d.extendRight,
        'fillOpacity': d.fillOpacity,
        'showPrices': d.showPrices,
      },
    ),
    DrawingKind<FibTimeZoneDrawing>(
      name: 'fibTimeZone',
      create: (id, a, s, p) => FibTimeZoneDrawing(
        id: id,
        anchors: a,
        style: s,
        zones: switch (p['zones']) {
          final List<Object?> z => [for (final v in z) (v as num).toInt()],
          _ => FibTimeZoneDrawing.defaultZones,
        },
      ),
      props: (d) => {'zones': d.zones},
    ),
    DrawingKind<PitchforkDrawing>(
      name: 'pitchfork',
      create: (id, a, s, p) => PitchforkDrawing(
        id: id,
        anchors: a,
        style: s,
        variant: PitchforkVariant.values.where((v) => v.name == p['variant']).firstOrNull ?? PitchforkVariant.andrews,
      ),
      props: (d) => {'variant': d.variant.name},
    ),
    DrawingKind<GannFanDrawing>(
      name: 'gannFan',
      create: (id, a, s, p) => GannFanDrawing(id: id, anchors: a, style: s),
    ),
    DrawingKind<CalloutDrawing>(
      name: 'callout',
      create: (id, a, s, p) => CalloutDrawing(id: id, anchors: a, style: s, text: p['text'] as String? ?? ''),
      props: (d) => {'text': d.text},
    ),
    DrawingKind<DateRangeDrawing>(
      name: 'dateRange',
      create: (id, a, s, p) =>
          DateRangeDrawing(id: id, anchors: a, style: s, barsLabel: p['barsLabel'] as String? ?? 'bars'),
      props: (d) => {'barsLabel': d.barsLabel},
    ),
    DrawingKind<SineLineDrawing>(
      name: 'sineLine',
      create: (id, a, s, p) => SineLineDrawing(id: id, anchors: a, style: s),
    ),
    DrawingKind<CyclicLinesDrawing>(
      name: 'cyclicLines',
      create: (id, a, s, p) => CyclicLinesDrawing(id: id, anchors: a, style: s),
    ),
    DrawingKind<TimeCyclesDrawing>(
      name: 'timeCycles',
      create: (id, a, s, p) => TimeCyclesDrawing(id: id, anchors: a, style: s),
    ),
    DrawingKind<FibFanDrawing>(
      name: 'fibFan',
      create: (id, a, s, p) =>
          FibFanDrawing(id: id, anchors: a, style: s, levels: _ratios(p['levels']) ?? FibFanDrawing.defaultLevels),
      props: (d) => {'levels': d.levels},
    ),
    DrawingKind<FibArcDrawing>(
      name: 'fibArc',
      create: (id, a, s, p) =>
          FibArcDrawing(id: id, anchors: a, style: s, levels: _ratios(p['levels']) ?? FibArcDrawing.defaultLevels),
      props: (d) => {'levels': d.levels},
    ),
    DrawingKind<PriceLabelDrawing>(
      name: 'priceLabel',
      create: (id, a, s, p) => PriceLabelDrawing(id: id, anchors: a, style: s),
    ),
    DrawingKind<PriceRangeDrawing>(
      name: 'priceRange',
      create: (id, a, s, p) => PriceRangeDrawing(
        id: id,
        anchors: a,
        style: s,
        upColor: _color(p['upColor']) ?? const Color(0xFF2962FF),
        downColor: _color(p['downColor']) ?? const Color(0xFFF23645),
      ),
      props: (d) => {'upColor': d.upColor.toARGB32(), 'downColor': d.downColor.toARGB32()},
    ),
  ];

  static List<DrawingKind> _dataKinds(SeriesApi? source, SeriesApi? volume) => [
    DrawingKind<AnchoredVwapDrawing>(
      name: 'anchoredVwap',
      create: (id, a, s, p) => AnchoredVwapDrawing(
        id: id,
        anchors: a,
        style: s,
        source: source,
        volume: volume,
        bandMultipliers: [for (final v in (p['bands'] as List<Object?>? ?? const [])) (v as num).toDouble()],
      ),
      props: (d) => {'bands': d.bandMultipliers},
    ),
    DrawingKind<RegressionTrendDrawing>(
      name: 'regressionTrend',
      create: (id, a, s, p) => RegressionTrendDrawing(
        id: id,
        anchors: a,
        style: s,
        source: source,
        deviations: (p['deviations'] as num?)?.toDouble() ?? 2,
        extendRight: p['extendRight'] == true,
      ),
      props: (d) => {'deviations': d.deviations, 'extendRight': d.extendRight},
    ),
    DrawingKind<RangeVolumeProfileDrawing>(
      name: 'rangeVolumeProfile',
      create: (id, a, s, p) => RangeVolumeProfileDrawing(
        id: id,
        anchors: a,
        style: s,
        source: source,
        volume: volume,
        anchored: p['anchored'] == true,
        rows: (p['rows'] as num?)?.toInt() ?? 24,
      ),
      props: (d) => {'anchored': d.anchored, 'rows': d.rows},
    ),
  ];

  static DrawingKind<IconMarkDrawing> _iconKind(Map<String, IconData> icons) => DrawingKind<IconMarkDrawing>(
    name: 'iconMark',
    create: (id, a, s, p) {
      final key = p['icon'] as String?;
      return IconMarkDrawing(
        id: id,
        anchors: a,
        style: s,
        icon: icons[key] ?? IconMarkDrawing.fallbackIcon,
        iconKey: key,
        anchorAtBase: p['anchorAtBase'] == true,
      );
    },
    props: (d) => {'icon': d.iconKey, 'anchorAtBase': d.anchorAtBase},
  );

  static List<double>? _ratios(Object? json) => switch (json) {
    final List<Object?> l => [for (final v in l) (v as num).toDouble()],
    _ => null,
  };

  static List<Map<String, Object?>> _levels(List<FibLevel> levels) => [
    for (final l in levels) {'ratio': l.ratio, 'color': l.color.toARGB32(), 'visible': l.visible},
  ];

  static List<FibLevel>? _readLevels(Object? json) => switch (json) {
    final List<Object?> levels => [
      for (final l in levels.cast<Map<String, Object?>>())
        FibLevel((l['ratio'] as num).toDouble(), Color(l['color'] as int), visible: l['visible'] != false),
    ],
    _ => null,
  };

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
