import 'dart:ui' show Color;

import 'model/time_utils.dart' show englishLongMonthNames, englishShortMonthNames;

/// Style of a line (grid, crosshair, price line, line series).
enum LineStyle { solid, dotted, dashed, largeDashed, sparseDotted }

/// How the line series connects its points.
enum LineType { simple, withSteps, curved }

/// Crosshair behaviour.
enum CrosshairMode {
  /// The crosshair moves freely.
  normal,

  /// The horizontal line snaps to the closest close/value of the series on
  /// the default (right) price scale.
  magnet,

  /// Like [magnet] but candidates are open, high, low and close.
  magnetOhlc,

  /// The crosshair is not drawn.
  hidden,
}

/// Price scale mode.
enum PriceScaleMode {
  normal,
  logarithmic,

  /// Values relative to the first visible value, in percent.
  percentage,

  /// Like [percentage], but the first visible value is 100.
  indexedTo100,
}

/// Pulsing animation of the last price for line-like series.
enum LastPriceAnimationMode { disabled, continuous, onDataUpdate }

/// Which bar the price line and last value label follow.
enum PriceLineSource { lastBar, lastVisible }

/// Type of a time scale tick mark, passed to [TickMarkFormatter].
enum TickMarkType { year, month, dayOfMonth, time, timeWithSeconds }

/// Formats a tick mark label. [time] is the horizontal value (UTC seconds on
/// a time chart). Return `null` to fall back to the default formatter.
typedef TickMarkFormatter = String? Function(num time, TickMarkType type, String locale);

/// Formats the horizontal value for the crosshair label.
typedef TimeFormatter = String Function(num time);

/// Formats a price.
typedef PriceFormatterFn = String Function(double price);

/// Formats all tick mark prices of a price axis at once.
typedef TickmarksPriceFormatterFn = List<String> Function(List<double> prices);

class PaneOptions {
  const PaneOptions({
    this.separatorColor = const Color(0xFFE0E3EB),
    this.separatorHoverColor = const Color(0x33B2B5BD),
    this.enableResize = true,
  });

  final Color separatorColor;

  /// Color of the separator while it is being dragged.
  final Color separatorHoverColor;
  final bool enableResize;
}

class LayoutOptions {
  const LayoutOptions({
    this.backgroundColor = const Color(0xFFFFFFFF),
    this.textColor = const Color(0xFF191919),
    this.fontSize = 12,
    this.fontFamily,
    this.panes = const PaneOptions(),
    this.backgroundBottomColor,
    this.attributionLogo = false,
  });

  /// Background, or the top color of a vertical gradient when
  /// [backgroundBottomColor] is set.
  final Color backgroundColor;

  /// Bottom color of a vertical background gradient.
  final Color? backgroundBottomColor;

  /// Show the TradingView attribution logo at the bottom left of the last
  /// pane. Off by default; the Apache 2.0 NOTICE of Lightweight Charts still
  /// requires crediting TradingView (with a link to tradingview.com)
  /// somewhere in your app, e.g. an About screen.
  final bool attributionLogo;
  final Color textColor;
  final double fontSize;
  final String? fontFamily;
  final PaneOptions panes;

  LayoutOptions copyWith({
    Color? backgroundColor,
    Color? textColor,
    double? fontSize,
    String? fontFamily,
    PaneOptions? panes,
    Color? backgroundBottomColor,
    bool? attributionLogo,
  }) {
    return LayoutOptions(
      backgroundBottomColor: backgroundBottomColor ?? this.backgroundBottomColor,
      attributionLogo: attributionLogo ?? this.attributionLogo,
      backgroundColor: backgroundColor ?? this.backgroundColor,
      textColor: textColor ?? this.textColor,
      fontSize: fontSize ?? this.fontSize,
      fontFamily: fontFamily ?? this.fontFamily,
      panes: panes ?? this.panes,
    );
  }
}

class GridLineOptions {
  const GridLineOptions({
    this.color = const Color(0xFFD6DCDE),
    this.style = LineStyle.solid,
    this.visible = true,
  });

  final Color color;
  final LineStyle style;
  final bool visible;

  GridLineOptions copyWith({Color? color, LineStyle? style, bool? visible}) {
    return GridLineOptions(
      color: color ?? this.color,
      style: style ?? this.style,
      visible: visible ?? this.visible,
    );
  }
}

class GridOptions {
  const GridOptions({
    this.vertLines = const GridLineOptions(),
    this.horzLines = const GridLineOptions(),
  });

  final GridLineOptions vertLines;
  final GridLineOptions horzLines;

  GridOptions copyWith({GridLineOptions? vertLines, GridLineOptions? horzLines}) {
    return GridOptions(
      vertLines: vertLines ?? this.vertLines,
      horzLines: horzLines ?? this.horzLines,
    );
  }
}

class CrosshairLineOptions {
  const CrosshairLineOptions({
    this.color = const Color(0xFF9598A1),
    this.width = 1,
    this.style = LineStyle.largeDashed,
    this.visible = true,
    this.labelVisible = true,
    this.labelBackgroundColor = const Color(0xFF131722),
  });

  final Color color;
  final double width;
  final LineStyle style;
  final bool visible;
  final bool labelVisible;
  final Color labelBackgroundColor;

  CrosshairLineOptions copyWith({
    Color? color,
    double? width,
    LineStyle? style,
    bool? visible,
    bool? labelVisible,
    Color? labelBackgroundColor,
  }) {
    return CrosshairLineOptions(
      color: color ?? this.color,
      width: width ?? this.width,
      style: style ?? this.style,
      visible: visible ?? this.visible,
      labelVisible: labelVisible ?? this.labelVisible,
      labelBackgroundColor: labelBackgroundColor ?? this.labelBackgroundColor,
    );
  }
}

class CrosshairOptions {
  const CrosshairOptions({
    this.vertLine = const CrosshairLineOptions(),
    this.horzLine = const CrosshairLineOptions(),
    this.mode = CrosshairMode.magnet,
    this.doNotSnapToHiddenSeriesIndices = false,
  });

  final CrosshairLineOptions vertLine;
  final CrosshairLineOptions horzLine;
  final CrosshairMode mode;

  /// Snap only to bars of visible series.
  final bool doNotSnapToHiddenSeriesIndices;

  CrosshairOptions copyWith({
    CrosshairLineOptions? vertLine,
    CrosshairLineOptions? horzLine,
    CrosshairMode? mode,
    bool? doNotSnapToHiddenSeriesIndices,
  }) {
    return CrosshairOptions(
      vertLine: vertLine ?? this.vertLine,
      horzLine: horzLine ?? this.horzLine,
      mode: mode ?? this.mode,
      doNotSnapToHiddenSeriesIndices: doNotSnapToHiddenSeriesIndices ?? this.doNotSnapToHiddenSeriesIndices,
    );
  }
}

/// Margins of a price scale as fractions of its height (0..1).
class ScaleMargins {
  const ScaleMargins({this.top = 0.2, this.bottom = 0.1});

  final double top;
  final double bottom;
}

class PriceScaleOptions {
  const PriceScaleOptions({
    this.autoScale = true,
    this.mode = PriceScaleMode.normal,
    this.invertScale = false,
    this.visible = true,
    this.borderVisible = true,
    this.borderColor = const Color(0xFF2B2B43),
    this.scaleMargins = const ScaleMargins(),
    this.entireTextOnly = false,
    this.tickMarkDensity = 2.5,
    this.minimumWidth = 0,
    this.alignLabels = true,
    this.ticksVisible = false,
    this.ensureEdgeTickMarksVisible = false,
  });

  final bool autoScale;
  final PriceScaleMode mode;
  final bool invertScale;

  /// Only meaningful for the `left`/`right` price scales. Overlay scales are never drawn.
  final bool visible;
  final bool borderVisible;
  final Color borderColor;
  final ScaleMargins scaleMargins;
  final bool entireTextOnly;
  final double tickMarkDensity;
  final double minimumWidth;

  /// Push overlapping axis labels apart.
  final bool alignLabels;

  /// Draw small ticks next to the labels.
  final bool ticksVisible;

  /// Always label the top and bottom of the scale (autoscale only).
  final bool ensureEdgeTickMarksVisible;

  PriceScaleOptions copyWith({
    bool? autoScale,
    PriceScaleMode? mode,
    bool? invertScale,
    bool? visible,
    bool? borderVisible,
    Color? borderColor,
    ScaleMargins? scaleMargins,
    bool? entireTextOnly,
    double? tickMarkDensity,
    double? minimumWidth,
    bool? alignLabels,
    bool? ticksVisible,
    bool? ensureEdgeTickMarksVisible,
  }) {
    return PriceScaleOptions(
      autoScale: autoScale ?? this.autoScale,
      mode: mode ?? this.mode,
      invertScale: invertScale ?? this.invertScale,
      visible: visible ?? this.visible,
      borderVisible: borderVisible ?? this.borderVisible,
      borderColor: borderColor ?? this.borderColor,
      scaleMargins: scaleMargins ?? this.scaleMargins,
      entireTextOnly: entireTextOnly ?? this.entireTextOnly,
      tickMarkDensity: tickMarkDensity ?? this.tickMarkDensity,
      minimumWidth: minimumWidth ?? this.minimumWidth,
      alignLabels: alignLabels ?? this.alignLabels,
      ticksVisible: ticksVisible ?? this.ticksVisible,
      ensureEdgeTickMarksVisible: ensureEdgeTickMarksVisible ?? this.ensureEdgeTickMarksVisible,
    );
  }
}

class TimeScaleOptions {
  const TimeScaleOptions({
    this.rightOffset = 0,
    this.rightOffsetPixels,
    this.barSpacing = 6,
    this.minBarSpacing = 0.5,
    this.maxBarSpacing = 0,
    this.fixLeftEdge = false,
    this.fixRightEdge = false,
    this.lockVisibleTimeRangeOnResize = false,
    this.rightBarStaysOnScroll = false,
    this.visible = true,
    this.borderVisible = true,
    this.borderColor = const Color(0xFF2B2B43),
    this.timeVisible = false,
    this.secondsVisible = true,
    this.shiftVisibleRangeOnNewBar = true,
    this.allowShiftVisibleRangeOnWhitespaceReplacement = false,
    this.ticksVisible = false,
    this.tickMarkMaxCharacterLength = 8,
    this.uniformDistribution = false,
    this.minimumHeight = 0,
    this.allowBoldLabels = true,
    this.ignoreWhitespaceIndices = false,
    this.enableConflation = false,
    this.conflationThresholdFactor = 1,
    this.tickMarkFormatter,
  });

  /// Margin from the last bar to the right edge, in bars.
  final double rightOffset;
  /// Margin from the last bar to the right edge in pixels; overrides [rightOffset].
  final double? rightOffsetPixels;
  /// Distance between bars in logical pixels.
  final double barSpacing;
  final double minBarSpacing;
  /// 0 means "half of the chart width".
  final double maxBarSpacing;
  final bool fixLeftEdge;
  final bool fixRightEdge;
  /// Keep the visible range (not the bar spacing) when the chart is resized.
  final bool lockVisibleTimeRangeOnResize;
  final bool rightBarStaysOnScroll;
  final bool visible;
  final bool borderVisible;
  final Color borderColor;
  final bool timeVisible;
  final bool secondsVisible;
  /// Keep following the last bar when a new one arrives (only while it is visible).
  final bool shiftVisibleRangeOnNewBar;
  /// Also follow when a whitespace point at the end is replaced by data.
  final bool allowShiftVisibleRangeOnWhitespaceReplacement;
  /// Draw small ticks at the labels.
  final bool ticksVisible;
  final int tickMarkMaxCharacterLength;
  /// Only keep tick marks evenly spaced.
  final bool uniformDistribution;
  /// Minimum height of the time axis.
  final double minimumHeight;
  /// Draw the heaviest tick marks (e.g. a new day) in bold.
  final bool allowBoldLabels;
  /// The crosshair and tick marks skip whitespace points.
  final bool ignoreWhitespaceIndices;
  /// Merge bars that would be narrower than a device pixel, for speed with large data sets.
  final bool enableConflation;
  /// Values above 1 conflate earlier (smoother sparklines).
  final double conflationThresholdFactor;
  final TickMarkFormatter? tickMarkFormatter;

  TimeScaleOptions copyWith({
    double? rightOffset,
    double? rightOffsetPixels,
    double? barSpacing,
    double? minBarSpacing,
    double? maxBarSpacing,
    bool? fixLeftEdge,
    bool? fixRightEdge,
    bool? lockVisibleTimeRangeOnResize,
    bool? rightBarStaysOnScroll,
    bool? visible,
    bool? borderVisible,
    Color? borderColor,
    bool? timeVisible,
    bool? secondsVisible,
    bool? shiftVisibleRangeOnNewBar,
    bool? allowShiftVisibleRangeOnWhitespaceReplacement,
    bool? ticksVisible,
    int? tickMarkMaxCharacterLength,
    bool? uniformDistribution,
    double? minimumHeight,
    bool? allowBoldLabels,
    bool? ignoreWhitespaceIndices,
    bool? enableConflation,
    double? conflationThresholdFactor,
    TickMarkFormatter? tickMarkFormatter,
  }) {
    return TimeScaleOptions(
      rightOffset: rightOffset ?? this.rightOffset,
      rightOffsetPixels: rightOffsetPixels ?? this.rightOffsetPixels,
      barSpacing: barSpacing ?? this.barSpacing,
      minBarSpacing: minBarSpacing ?? this.minBarSpacing,
      maxBarSpacing: maxBarSpacing ?? this.maxBarSpacing,
      fixLeftEdge: fixLeftEdge ?? this.fixLeftEdge,
      fixRightEdge: fixRightEdge ?? this.fixRightEdge,
      lockVisibleTimeRangeOnResize: lockVisibleTimeRangeOnResize ?? this.lockVisibleTimeRangeOnResize,
      rightBarStaysOnScroll: rightBarStaysOnScroll ?? this.rightBarStaysOnScroll,
      visible: visible ?? this.visible,
      borderVisible: borderVisible ?? this.borderVisible,
      borderColor: borderColor ?? this.borderColor,
      timeVisible: timeVisible ?? this.timeVisible,
      secondsVisible: secondsVisible ?? this.secondsVisible,
      shiftVisibleRangeOnNewBar: shiftVisibleRangeOnNewBar ?? this.shiftVisibleRangeOnNewBar,
      allowShiftVisibleRangeOnWhitespaceReplacement: allowShiftVisibleRangeOnWhitespaceReplacement ?? this.allowShiftVisibleRangeOnWhitespaceReplacement,
      ticksVisible: ticksVisible ?? this.ticksVisible,
      tickMarkMaxCharacterLength: tickMarkMaxCharacterLength ?? this.tickMarkMaxCharacterLength,
      uniformDistribution: uniformDistribution ?? this.uniformDistribution,
      minimumHeight: minimumHeight ?? this.minimumHeight,
      allowBoldLabels: allowBoldLabels ?? this.allowBoldLabels,
      ignoreWhitespaceIndices: ignoreWhitespaceIndices ?? this.ignoreWhitespaceIndices,
      enableConflation: enableConflation ?? this.enableConflation,
      conflationThresholdFactor: conflationThresholdFactor ?? this.conflationThresholdFactor,
      tickMarkFormatter: tickMarkFormatter ?? this.tickMarkFormatter,
    );
  }
}

class LocalizationOptions {
  const LocalizationOptions({
    this.locale = 'en-US',
    this.dateFormat = "dd MMM 'yy",
    this.shortMonthNames = englishShortMonthNames,
    this.longMonthNames = englishLongMonthNames,
    this.timeFormatter,
    this.priceFormatter,
    this.tickmarksPriceFormatter,
    this.percentageFormatter,
    this.tickmarksPercentageFormatter,
  });

  /// Passed to [TimeScaleOptions.tickMarkFormatter].
  final String locale;

  /// Date part of the crosshair time label: `yyyy`, `yy`, `MMMM`, `MMM`,
  /// `MM` and `dd` are replaced.
  final String dateFormat;

  /// Month names used by `MMM` and month tick marks. Dart has no built-in
  /// locale data, so pass translated names for other locales.
  final List<String> shortMonthNames;

  /// Month names used by `MMMM`.
  final List<String> longMonthNames;

  /// Formats the time in the crosshair label.
  final TimeFormatter? timeFormatter;

  /// Overrides every series' price formatter.
  final PriceFormatterFn? priceFormatter;

  /// Formats the price axis tick marks (normal and log modes).
  final TickmarksPriceFormatterFn? tickmarksPriceFormatter;

  /// Formats percentages (percentage mode).
  final PriceFormatterFn? percentageFormatter;

  /// Formats the price axis tick marks in percentage mode.
  final TickmarksPriceFormatterFn? tickmarksPercentageFormatter;
}

/// Scrolling, like upstream's `HandleScrollOptions`.
class HandleScrollOptions {
  const HandleScrollOptions({
    this.mouseWheel = true,
    this.pressedMouseMove = true,
    this.horzTouchDrag = true,
    this.vertTouchDrag = true,
  });

  /// Shift + wheel / horizontal wheel scrolls the time scale.
  final bool mouseWheel;

  /// Dragging with the mouse scrolls.
  final bool pressedMouseMove;

  /// Horizontal touch drags scroll the time scale.
  final bool horzTouchDrag;

  /// Vertical touch drags scroll a manual price scale. Turn off to leave
  /// vertical drags to an enclosing scroll view.
  final bool vertTouchDrag;
}

class AxisInteractionOptions {
  const AxisInteractionOptions({this.time = true, this.price = true});

  final bool time;
  final bool price;
}

/// Scaling, like upstream's `HandleScaleOptions`.
class HandleScaleOptions {
  const HandleScaleOptions({
    this.mouseWheel = true,
    this.pinch = true,
    this.axisPressedMouseMove = const AxisInteractionOptions(),
    this.axisDoubleClickReset = const AxisInteractionOptions(),
  });

  final bool mouseWheel;
  final bool pinch;

  /// Dragging an axis scales it.
  final AxisInteractionOptions axisPressedMouseMove;

  /// Double-tapping an axis resets it.
  final AxisInteractionOptions axisDoubleClickReset;
}

/// Inertia after a fling.
class KineticScrollOptions {
  const KineticScrollOptions({this.touch = true, this.mouse = false});

  final bool touch;
  final bool mouse;
}

enum TrackingModeExitMode {
  /// The crosshair hides when the finger lifts.
  onTouchEnd,

  /// The crosshair stays until the next tap.
  onNextTap,
}

/// Touch crosshair behaviour after a long press.
class TrackingModeOptions {
  const TrackingModeOptions({this.exitMode = TrackingModeExitMode.onNextTap});

  final TrackingModeExitMode exitMode;
}

class ChartOptions {
  const ChartOptions({
    this.layout = const LayoutOptions(),
    this.grid = const GridOptions(),
    this.crosshair = const CrosshairOptions(),
    this.rightPriceScale = const PriceScaleOptions(),
    this.leftPriceScale = const PriceScaleOptions(visible: false),
    this.overlayPriceScales = const PriceScaleOptions(visible: false),
    this.timeScale = const TimeScaleOptions(),
    this.localization = const LocalizationOptions(),
    this.handleScroll = const HandleScrollOptions(),
    this.handleScale = const HandleScaleOptions(),
    this.kineticScroll = const KineticScrollOptions(),
    this.trackingMode = const TrackingModeOptions(),
    this.addDefaultPane = true,
    this.hoveredSeriesOnTop = true,
    this.defaultVisiblePriceScaleId = 'right',
  });

  /// Create the first pane up front; otherwise panes appear with series.
  final bool addDefaultPane;

  /// Draw the series under the pointer above the others in its pane.
  final bool hoveredSeriesOnTop;

  /// Price scale of series without a `priceScaleId`: `right` or `left`.
  final String defaultVisiblePriceScaleId;

  final LayoutOptions layout;
  final GridOptions grid;
  final CrosshairOptions crosshair;
  final PriceScaleOptions rightPriceScale;
  final PriceScaleOptions leftPriceScale;

  /// Defaults of overlay price scales (any `priceScaleId` other than
  /// `left`/`right`).
  final PriceScaleOptions overlayPriceScales;
  final TimeScaleOptions timeScale;
  final LocalizationOptions localization;
  final HandleScrollOptions handleScroll;
  final HandleScaleOptions handleScale;
  final KineticScrollOptions kineticScroll;
  final TrackingModeOptions trackingMode;

  ChartOptions copyWith({
    LayoutOptions? layout,
    GridOptions? grid,
    CrosshairOptions? crosshair,
    PriceScaleOptions? rightPriceScale,
    PriceScaleOptions? leftPriceScale,
    PriceScaleOptions? overlayPriceScales,
    TimeScaleOptions? timeScale,
    LocalizationOptions? localization,
    HandleScrollOptions? handleScroll,
    HandleScaleOptions? handleScale,
    KineticScrollOptions? kineticScroll,
    TrackingModeOptions? trackingMode,
    bool? addDefaultPane,
    bool? hoveredSeriesOnTop,
    String? defaultVisiblePriceScaleId,
  }) {
    return ChartOptions(
      layout: layout ?? this.layout,
      grid: grid ?? this.grid,
      crosshair: crosshair ?? this.crosshair,
      rightPriceScale: rightPriceScale ?? this.rightPriceScale,
      leftPriceScale: leftPriceScale ?? this.leftPriceScale,
      overlayPriceScales: overlayPriceScales ?? this.overlayPriceScales,
      timeScale: timeScale ?? this.timeScale,
      localization: localization ?? this.localization,
      handleScroll: handleScroll ?? this.handleScroll,
      handleScale: handleScale ?? this.handleScale,
      kineticScroll: kineticScroll ?? this.kineticScroll,
      trackingMode: trackingMode ?? this.trackingMode,
      addDefaultPane: addDefaultPane ?? this.addDefaultPane,
      hoveredSeriesOnTop: hoveredSeriesOnTop ?? this.hoveredSeriesOnTop,
      defaultVisiblePriceScaleId: defaultVisiblePriceScaleId ?? this.defaultVisiblePriceScaleId,
    );
  }
}

/// How prices of a series are formatted and how fine the price tick marks are.
class PriceFormat {
  /// Decimal price with [precision] digits, rounded to [minMove].
  const PriceFormat.price({this.precision = 2, this.minMove = 0.01})
      : type = PriceFormatType.price,
        formatter = null;

  /// Abbreviated volume (1.2K, 3.4M, 5B).
  const PriceFormat.volume({this.precision = 2})
      : type = PriceFormatType.volume,
        minMove = 1,
        formatter = null;

  /// Fully custom formatting.
  const PriceFormat.custom(PriceFormatterFn this.formatter, {this.minMove = 0.01})
      : type = PriceFormatType.custom,
        precision = 2;

  final PriceFormatType type;
  final int precision;
  final double minMove;
  final PriceFormatterFn? formatter;
}

enum PriceFormatType { price, volume, custom }
