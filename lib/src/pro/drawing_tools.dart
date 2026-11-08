// The drawing tools of the pro chart's toolbar, in groups.
import 'package:flutter/material.dart';

import '../plugins/drawings.dart';
import '../options.dart';
import 'pro_chart_controller.dart';

/// A drawing tool: makes a drawing from the anchors the pointer places.
class DrawingToolSpec {
  const DrawingToolSpec({required this.id, required this.label, required this.icon, required this.create});

  final String id;
  final String label;
  final IconData icon;

  /// The drawing for [pro]'s chart (tools that read data use its price
  /// series).
  final Drawing Function(ProChartController pro, Object id, List<DrawingAnchor> anchors) create;
}

/// Tools shown under one toolbar button.
class DrawingToolGroup {
  const DrawingToolGroup(this.label, this.tools);

  final String label;
  final List<DrawingToolSpec> tools;
}

/// The built-in tools, grouped like TradingView's toolbar — the same set
/// and groups as Stock World Monitor's chart.
abstract final class DrawingTools {
  static final List<DrawingToolGroup> groups = [
    DrawingToolGroup('Lines', [
      DrawingToolSpec(
        id: 'trendLine',
        label: 'Trend line',
        icon: Icons.show_chart,
        create: (_, id, a) => TrendLineDrawing(id: id, anchors: a),
      ),
      DrawingToolSpec(
        id: 'ray',
        label: 'Ray',
        icon: Icons.call_made,
        create: (_, id, a) => TrendLineDrawing(id: id, anchors: a, extendRight: true),
      ),
      DrawingToolSpec(
        id: 'extendedLine',
        label: 'Extended line',
        icon: Icons.open_in_full,
        create: (_, id, a) => TrendLineDrawing(id: id, anchors: a, extendLeft: true, extendRight: true),
      ),
      DrawingToolSpec(
        id: 'arrow',
        label: 'Arrow',
        icon: Icons.arrow_right_alt,
        create: (_, id, a) => TrendLineDrawing(id: id, anchors: a, arrow: true),
      ),
      DrawingToolSpec(
        id: 'trendAngle',
        label: 'Trend angle',
        icon: Icons.architecture,
        create: (_, id, a) => TrendAngleDrawing(id: id, anchors: a),
      ),
      DrawingToolSpec(
        id: 'infoLine',
        label: 'Info line',
        icon: Icons.info_outline,
        create: (_, id, a) => InfoLineDrawing(id: id, anchors: a),
      ),
      DrawingToolSpec(
        id: 'horizontalLine',
        label: 'Horizontal line',
        icon: Icons.horizontal_rule,
        create: (_, id, a) => HorizontalLineDrawing(id: id, anchors: a),
      ),
      DrawingToolSpec(
        id: 'horizontalRay',
        label: 'Horizontal ray',
        icon: Icons.east,
        create: (_, id, a) => HorizontalLineDrawing(id: id, anchors: a, ray: true),
      ),
      DrawingToolSpec(
        id: 'verticalLine',
        label: 'Vertical line',
        icon: Icons.border_vertical,
        create: (_, id, a) => VerticalLineDrawing(id: id, anchors: a),
      ),
      DrawingToolSpec(
        id: 'crossLine',
        label: 'Cross line',
        icon: Icons.add,
        create: (_, id, a) => CrossLineDrawing(id: id, anchors: a),
      ),
    ]),
    DrawingToolGroup('Channels and pitchforks', [
      DrawingToolSpec(
        id: 'parallelChannel',
        label: 'Parallel channel',
        icon: Icons.view_stream_outlined,
        create: (_, id, a) => ParallelChannelDrawing(
          id: id,
          anchors: a,
          style: const DrawingStyle(fillColor: Color(0x142962FF)),
        ),
      ),
      DrawingToolSpec(
        id: 'regressionTrend',
        label: 'Regression trend',
        icon: Icons.stacked_line_chart,
        create: (pro, id, a) => RegressionTrendDrawing(id: id, anchors: a, source: pro.mainSeries),
      ),
      DrawingToolSpec(
        id: 'pitchfork',
        label: 'Pitchfork',
        icon: Icons.call_split,
        create: (_, id, a) => PitchforkDrawing(id: id, anchors: a),
      ),
      DrawingToolSpec(
        id: 'schiffPitchfork',
        label: 'Schiff pitchfork',
        icon: Icons.alt_route,
        create: (_, id, a) => PitchforkDrawing(id: id, anchors: a, variant: PitchforkVariant.schiff),
      ),
    ]),
    DrawingToolGroup('Fibonacci and Gann', [
      DrawingToolSpec(
        id: 'fibRetracement',
        label: 'Fib retracement',
        icon: Icons.format_line_spacing,
        create: (_, id, a) => FibRetracementDrawing(id: id, anchors: a),
      ),
      DrawingToolSpec(
        id: 'fibExtension',
        label: 'Trend-based Fib extension',
        icon: Icons.expand,
        create: (_, id, a) => FibExtensionDrawing(id: id, anchors: a),
      ),
      DrawingToolSpec(
        id: 'fibFan',
        label: 'Fib speed fan',
        icon: Icons.change_history,
        create: (_, id, a) => FibFanDrawing(id: id, anchors: a),
      ),
      DrawingToolSpec(
        id: 'fibTimeZone',
        label: 'Fib time zone',
        icon: Icons.view_week_outlined,
        create: (_, id, a) => FibTimeZoneDrawing(id: id, anchors: a),
      ),
      DrawingToolSpec(
        id: 'fibArc',
        label: 'Fib arcs',
        icon: Icons.blur_circular,
        create: (_, id, a) => FibArcDrawing(id: id, anchors: a),
      ),
      DrawingToolSpec(
        id: 'gannFan',
        label: 'Gann fan',
        icon: Icons.flare,
        create: (_, id, a) => GannFanDrawing(id: id, anchors: a),
      ),
    ]),
    DrawingToolGroup('Patterns', [
      DrawingToolSpec(
        id: 'xabcd',
        label: 'XABCD pattern',
        icon: Icons.hub,
        create: (_, id, a) => HarmonicDrawing(id: id, anchors: a, style: _pattern),
      ),
      DrawingToolSpec(
        id: 'cypher',
        label: 'Cypher pattern',
        icon: Icons.auto_graph,
        create: (_, id, a) => HarmonicDrawing(id: id, anchors: a, style: _pattern),
      ),
      DrawingToolSpec(
        id: 'abcd',
        label: 'ABCD pattern',
        icon: Icons.polyline,
        create: (_, id, a) => PathDrawing(id: id, anchors: a, labels: const ['A', 'B', 'C', 'D']),
      ),
      DrawingToolSpec(
        id: 'headAndShoulders',
        label: 'Head and shoulders',
        icon: Icons.landscape,
        create: (_, id, a) => HeadAndShouldersDrawing(id: id, anchors: a, style: _pattern),
      ),
      DrawingToolSpec(
        id: 'trianglePattern',
        label: 'Triangle pattern',
        icon: Icons.change_history,
        create: (_, id, a) => PathDrawing(
          id: id,
          anchors: a,
          labels: const ['A', 'B', 'C', 'D'],
          style: const DrawingStyle(fillColor: Color(0x1A2962FF)),
        ),
      ),
      DrawingToolSpec(
        id: 'threeDrives',
        label: 'Three drives pattern',
        icon: Icons.moving,
        create: (_, id, a) => PathDrawing(id: id, anchors: a, labels: const ['0', '1', 'A', '2', 'B', '3']),
      ),
      DrawingToolSpec(
        id: 'elliottImpulse',
        label: 'Elliott impulse wave',
        icon: Icons.waves,
        create: (_, id, a) => PathDrawing.elliottImpulse(id: id, anchors: a),
      ),
      DrawingToolSpec(
        id: 'elliottCorrection',
        label: 'Elliott correction wave',
        icon: Icons.water,
        create: (_, id, a) => PathDrawing.elliottCorrection(id: id, anchors: a),
      ),
      DrawingToolSpec(
        id: 'elliottTriangle',
        label: 'Elliott triangle wave',
        icon: Icons.insights,
        create: (_, id, a) => PathDrawing(id: id, anchors: a, labels: const ['0', 'A', 'B', 'C', 'D', 'E']),
      ),
      DrawingToolSpec(
        id: 'elliottDoubleCombo',
        label: 'Elliott double combo wave',
        icon: Icons.stacked_line_chart,
        create: (_, id, a) => PathDrawing(id: id, anchors: a, labels: const ['0', 'W', 'X', 'Y']),
      ),
      DrawingToolSpec(
        id: 'elliottTripleCombo',
        label: 'Elliott triple combo wave',
        icon: Icons.graphic_eq,
        create: (_, id, a) => PathDrawing(id: id, anchors: a, labels: const ['0', 'W', 'X', 'Y', 'X', 'Z']),
      ),
      DrawingToolSpec(
        id: 'sineLine',
        label: 'Sine line',
        icon: Icons.ssid_chart,
        create: (_, id, a) => SineLineDrawing(id: id, anchors: a),
      ),
      DrawingToolSpec(
        id: 'cyclicLines',
        label: 'Cyclic lines',
        icon: Icons.repeat,
        create: (_, id, a) => CyclicLinesDrawing(id: id, anchors: a),
      ),
      DrawingToolSpec(
        id: 'timeCycles',
        label: 'Time cycles',
        icon: Icons.track_changes,
        create: (_, id, a) => TimeCyclesDrawing(id: id, anchors: a),
      ),
    ]),
    DrawingToolGroup('Forecasting and measuring', [
      DrawingToolSpec(
        id: 'longPosition',
        label: 'Long position',
        icon: Icons.trending_up,
        create: (_, id, a) => PositionDrawing(id: id, anchors: a),
      ),
      DrawingToolSpec(
        id: 'shortPosition',
        label: 'Short position',
        icon: Icons.trending_down,
        create: (_, id, a) => PositionDrawing(id: id, anchors: a, short: true),
      ),
      DrawingToolSpec(
        id: 'priceRange',
        label: 'Price range',
        icon: Icons.height,
        create: (_, id, a) => PriceRangeDrawing(id: id, anchors: a),
      ),
      DrawingToolSpec(
        id: 'dateRange',
        label: 'Date range',
        icon: Icons.date_range,
        create: (_, id, a) => DateRangeDrawing(id: id, anchors: a),
      ),
      DrawingToolSpec(
        id: 'measure',
        label: 'Date and price range',
        icon: Icons.straighten,
        create: (_, id, a) => MeasureDrawing(id: id, anchors: a),
      ),
      DrawingToolSpec(
        id: 'anchoredVwap',
        label: 'Anchored VWAP',
        icon: Icons.anchor,
        create: (pro, id, a) =>
            AnchoredVwapDrawing(id: id, anchors: a, source: pro.mainSeries, volume: pro.volumeSeries),
      ),
      DrawingToolSpec(
        id: 'fixedRangeVolumeProfile',
        label: 'Fixed range volume profile',
        icon: Icons.bar_chart,
        create: (pro, id, a) =>
            RangeVolumeProfileDrawing(id: id, anchors: a, source: pro.mainSeries, volume: pro.volumeSeries),
      ),
      DrawingToolSpec(
        id: 'anchoredVolumeProfile',
        label: 'Anchored volume profile',
        icon: Icons.equalizer,
        create: (pro, id, a) => RangeVolumeProfileDrawing(
          id: id,
          anchors: a,
          source: pro.mainSeries,
          volume: pro.volumeSeries,
          anchored: true,
        ),
      ),
    ]),
    DrawingToolGroup('Shapes', [
      DrawingToolSpec(
        id: 'rectangle',
        label: 'Rectangle',
        icon: Icons.crop_square,
        create: (_, id, a) => RectangleDrawing(
          id: id,
          anchors: a,
          style: const DrawingStyle(fillColor: Color(0x222962FF)),
        ),
      ),
      DrawingToolSpec(
        id: 'ellipse',
        label: 'Ellipse',
        icon: Icons.circle_outlined,
        create: (_, id, a) => EllipseDrawing(
          id: id,
          anchors: a,
          style: const DrawingStyle(fillColor: Color(0x222962FF)),
        ),
      ),
      DrawingToolSpec(
        id: 'brush',
        label: 'Brush',
        icon: Icons.brush,
        create: (_, id, a) => FreehandDrawing(id: id, anchors: a, style: const DrawingStyle(lineWidth: 2)),
      ),
      DrawingToolSpec(
        id: 'highlighter',
        label: 'Highlighter',
        icon: Icons.border_color,
        create: (_, id, a) => FreehandDrawing(
          id: id,
          anchors: a,
          style: const DrawingStyle(color: Color(0x66FFEB3B), lineWidth: 12),
        ),
      ),
    ]),
    DrawingToolGroup('Annotations', [
      DrawingToolSpec(
        id: 'text',
        label: 'Text',
        icon: Icons.title,
        create: (_, id, a) => TextDrawing(id: id, anchors: a, text: 'Text'),
      ),
      DrawingToolSpec(
        id: 'callout',
        label: 'Callout',
        icon: Icons.chat_bubble_outline,
        create: (_, id, a) => CalloutDrawing(id: id, anchors: a, text: 'Note'),
      ),
      DrawingToolSpec(
        id: 'priceLabel',
        label: 'Price label',
        icon: Icons.sell_outlined,
        create: (_, id, a) => PriceLabelDrawing(id: id, anchors: a),
      ),
      DrawingToolSpec(
        id: 'flag',
        label: 'Flag mark',
        icon: Icons.outlined_flag,
        create: (_, id, a) => IconMarkDrawing(
          id: id,
          anchors: a,
          style: const DrawingStyle(color: Color(0xFFF23645), fontSize: 22),
          icon: Icons.flag_rounded,
          iconKey: 'flag',
          anchorAtBase: true,
        ),
      ),
      DrawingToolSpec(
        id: 'emoji',
        label: 'Emoji',
        icon: Icons.emoji_emotions_outlined,
        create: (_, id, a) => IconMarkDrawing(
          id: id,
          anchors: a,
          style: const DrawingStyle(color: Color(0xFFFFB300), fontSize: 24),
          icon: Icons.sentiment_satisfied_alt,
          iconKey: 'smile',
        ),
      ),
    ]),
  ];

  /// The patterns' teal outline and fill.
  static const _pattern = DrawingStyle(color: Color(0xFF26A69A), fillColor: Color(0x2226A69A));

  /// The icons the icon-mark tools place, by the key they're saved under
  /// (pass them to [DrawingCodec.icons]).
  static const icons = <String, IconData>{'flag': Icons.flag_rounded, 'smile': Icons.sentiment_satisfied_alt};

  static DrawingToolSpec? byId(String id) {
    for (final g in groups) {
      for (final t in g.tools) {
        if (t.id == id) return t;
      }
    }
    return null;
  }

  /// Colors offered for drawings and indicator lines.
  static const palette = [
    Color(0xFF2962FF),
    Color(0xFF00BCD4),
    Color(0xFF089981),
    Color(0xFF4CAF50),
    Color(0xFFFFEB3B),
    Color(0xFFFF9800),
    Color(0xFFF23645),
    Color(0xFFE91E63),
    Color(0xFF9C27B0),
    Color(0xFF7E57C2),
    Color(0xFF787B86),
    Color(0xFF131722),
    Color(0xFFFFFFFF),
  ];

  /// Line styles offered for drawings.
  static const lineStyles = [LineStyle.solid, LineStyle.dashed, LineStyle.dotted];
}
