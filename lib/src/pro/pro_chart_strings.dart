// The words on the pro chart's screens, so an app can show them in its
// own language.
import 'package:flutter/widgets.dart';

import '../indicators/catalog.dart';
import '../options.dart';
import 'drawing_tools.dart';
import 'pro_chart_controller.dart';

/// Every label, tooltip and message of [SwmProChart] and its sheets. The
/// defaults are English; pass your own (from your app's localizations) to
/// `SwmProChart.strings` or put a [ProChartStringsScope] above the parts
/// you use on their own.
///
/// ```dart
/// SwmProChart(
///   controller: pro,
///   strings: ProChartStrings(
///     indicators: l10n.indicators,
///     undo: l10n.undo,
///     indicatorTitle: (spec) => l10n.indicatorName(spec.id) ?? spec.title,
///   ),
/// )
/// ```
///
/// The function fields name the catalog's and toolbar's items; leave them
/// `null` to keep the built-in English names.
class ProChartStrings {
  const ProChartStrings({
    this.interval = 'Interval',
    this.chartType = 'Chart type',
    this.indicators = 'Indicators',
    this.undo = 'Undo',
    this.redo = 'Redo',
    this.chartSettings = 'Chart settings',
    this.logScale = 'Log scale',
    this.percentScale = 'Percent scale',
    this.volume = 'Volume',
    this.chartDisplay = 'Chart display',
    this.gridLines = 'Grid lines',
    this.symbolInBackground = 'Symbol in background',
    this.crosshair = 'Crosshair',
    this.cursor = 'Cursor',
    this.drawingTools = 'Drawing tools',
    this.magnet = 'Magnet',
    this.keepDrawing = 'Keep drawing',
    this.showDrawings = 'Show drawings',
    this.hideDrawings = 'Hide drawings',
    this.removeDrawings = 'Remove drawings',
    this.color = 'Color',
    this.width = 'Width',
    this.lineStyle = 'Line style',
    this.text = 'Text',
    this.lock = 'Lock',
    this.unlock = 'Unlock',
    this.duplicate = 'Duplicate',
    this.delete = 'Delete',
    this.cancel = 'Cancel',
    this.ok = 'OK',
    this.reset = 'Reset',
    this.searchIndicators = 'Search indicators',
    this.onTheChart = 'On the chart',
    this.hide = 'Hide',
    this.show = 'Show',
    this.settings = 'Settings',
    this.remove = 'Remove',
    this.needsVolume = 'Needs volume',
    this.inputsMustBeNumbers = 'Inputs must be numbers',
    this.inputs = 'Inputs',
    this.style = 'Style',
    this.defaults = 'Defaults',
    this.replay = 'Bar replay',
    this.replayPickStart = 'Tap a bar to replay from',
    this.play = 'Play',
    this.pause = 'Pause',
    this.stepForward = 'Next bar',
    this.replaySpeed = 'Speed',
    this.exitReplay = 'Exit replay',
    this.saveAsDefault = 'Save as default style',
    this.resetDefault = 'Reset default style',
    this.added,
    this.lineStyleName,
    this.chartTypeName,
    this.groupName,
    this.indicatorTitle,
    this.paramLabel,
    this.toolLabel,
    this.toolGroupLabel,
  });

  final String interval;
  final String chartType;
  final String indicators;
  final String undo;
  final String redo;
  final String chartSettings;
  final String logScale;
  final String percentScale;
  final String volume;
  final String chartDisplay;
  final String gridLines;
  final String symbolInBackground;
  final String crosshair;
  final String cursor;

  /// The pencil that opens the floating drawing toolbar.
  final String drawingTools;
  final String magnet;
  final String keepDrawing;
  final String showDrawings;
  final String hideDrawings;
  final String removeDrawings;
  final String color;
  final String width;
  final String lineStyle;
  final String text;
  final String lock;
  final String unlock;
  final String duplicate;
  final String replay;
  final String replayPickStart;
  final String play;
  final String pause;
  final String stepForward;
  final String replaySpeed;
  final String exitReplay;
  final String saveAsDefault;
  final String resetDefault;
  final String delete;
  final String cancel;
  final String ok;
  final String reset;
  final String searchIndicators;
  final String onTheChart;
  final String hide;
  final String show;
  final String settings;
  final String remove;
  final String needsVolume;
  final String inputsMustBeNumbers;
  final String inputs;
  final String style;
  final String defaults;

  /// The message after adding an indicator; by default "`title` added".
  final String Function(String title)? added;

  final String Function(LineStyle style)? lineStyleName;
  final String Function(ProChartType type)? chartTypeName;
  final String Function(IndicatorGroup group)? groupName;
  final String Function(IndicatorSpec spec)? indicatorTitle;
  final String Function(IndicatorSpec spec, IndicatorParam param)? paramLabel;
  final String Function(DrawingToolSpec tool)? toolLabel;
  final String Function(DrawingToolGroup group)? toolGroupLabel;

  /// The strings of the nearest [ProChartStringsScope], or the English
  /// defaults.
  static ProChartStrings of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<ProChartStringsScope>()?.strings ?? const ProChartStrings();

  String addedMessage(String title) => added?.call(title) ?? '$title added';

  String lineStyleLabel(LineStyle s) =>
      lineStyleName?.call(s) ??
      switch (s) {
        LineStyle.solid => 'Solid',
        LineStyle.dotted => 'Dotted',
        LineStyle.dashed => 'Dashed',
        LineStyle.largeDashed => 'Long dashes',
        LineStyle.sparseDotted => 'Sparse dots',
      };

  String chartTypeLabel(ProChartType t) => chartTypeName?.call(t) ?? t.label;

  String groupLabel(IndicatorGroup g) => groupName?.call(g) ?? g.label;

  String titleOf(IndicatorSpec spec) => indicatorTitle?.call(spec) ?? spec.title;

  String paramLabelOf(IndicatorSpec spec, IndicatorParam p) => paramLabel?.call(spec, p) ?? p.label;

  String toolLabelOf(DrawingToolSpec t) => toolLabel?.call(t) ?? t.label;

  String toolGroupLabelOf(DrawingToolGroup g) => toolGroupLabel?.call(g) ?? g.label;
}

/// Gives the pro chart's widgets below it [strings]. [SwmProChart] puts one
/// up itself; use it for [ProChartTopBar], [DrawingToolbar] and the like
/// on their own.
class ProChartStringsScope extends InheritedWidget {
  const ProChartStringsScope({super.key, required this.strings, required super.child});

  final ProChartStrings strings;

  @override
  bool updateShouldNotify(ProChartStringsScope old) => old.strings != strings;
}
