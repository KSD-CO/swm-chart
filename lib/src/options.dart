import 'dart:ui' show Color;

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

/// Formats a tick mark label. [time] is a UTC timestamp in seconds.
/// Return `null` to fall back to the default formatter.
typedef TickMarkFormatter = String? Function(int time, TickMarkType type);

/// Formats a time for the crosshair label. [time] is a UTC timestamp in seconds.
typedef TimeFormatter = String Function(int time);

/// Formats a price.
typedef PriceFormatterFn = String Function(double price);

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
  });

  final Color backgroundColor;
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
  }) {
    return LayoutOptions(
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
  });

  final CrosshairLineOptions vertLine;
  final CrosshairLineOptions horzLine;
  final CrosshairMode mode;

  CrosshairOptions copyWith({
    CrosshairLineOptions? vertLine,
    CrosshairLineOptions? horzLine,
    CrosshairMode? mode,
  }) {
    return CrosshairOptions(
      vertLine: vertLine ?? this.vertLine,
      horzLine: horzLine ?? this.horzLine,
      mode: mode ?? this.mode,
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
    );
  }
}

class TimeScaleOptions {
  const TimeScaleOptions({
    this.rightOffset = 0,
    this.barSpacing = 6,
    this.minBarSpacing = 0.5,
    this.maxBarSpacing = 0,
    this.fixLeftEdge = false,
    this.fixRightEdge = false,
    this.rightBarStaysOnScroll = false,
    this.visible = true,
    this.borderVisible = true,
    this.borderColor = const Color(0xFF2B2B43),
    this.timeVisible = false,
    this.secondsVisible = true,
    this.shiftVisibleRangeOnNewBar = true,
    this.tickMarkMaxCharacterLength = 8,
    this.tickMarkFormatter,
  });

  /// Margin from the last bar to the right edge, in bars.
  final double rightOffset;

  /// Distance between bars in logical pixels.
  final double barSpacing;
  final double minBarSpacing;

  /// 0 means "half of the chart width".
  final double maxBarSpacing;
  final bool fixLeftEdge;
  final bool fixRightEdge;
  final bool rightBarStaysOnScroll;
  final bool visible;
  final bool borderVisible;
  final Color borderColor;
  final bool timeVisible;
  final bool secondsVisible;

  /// Keep following the last bar when a new one arrives (only while it is visible).
  final bool shiftVisibleRangeOnNewBar;
  final int tickMarkMaxCharacterLength;
  final TickMarkFormatter? tickMarkFormatter;

  TimeScaleOptions copyWith({
    double? rightOffset,
    double? barSpacing,
    double? minBarSpacing,
    double? maxBarSpacing,
    bool? fixLeftEdge,
    bool? fixRightEdge,
    bool? rightBarStaysOnScroll,
    bool? visible,
    bool? borderVisible,
    Color? borderColor,
    bool? timeVisible,
    bool? secondsVisible,
    bool? shiftVisibleRangeOnNewBar,
    int? tickMarkMaxCharacterLength,
    TickMarkFormatter? tickMarkFormatter,
  }) {
    return TimeScaleOptions(
      rightOffset: rightOffset ?? this.rightOffset,
      barSpacing: barSpacing ?? this.barSpacing,
      minBarSpacing: minBarSpacing ?? this.minBarSpacing,
      maxBarSpacing: maxBarSpacing ?? this.maxBarSpacing,
      fixLeftEdge: fixLeftEdge ?? this.fixLeftEdge,
      fixRightEdge: fixRightEdge ?? this.fixRightEdge,
      rightBarStaysOnScroll: rightBarStaysOnScroll ?? this.rightBarStaysOnScroll,
      visible: visible ?? this.visible,
      borderVisible: borderVisible ?? this.borderVisible,
      borderColor: borderColor ?? this.borderColor,
      timeVisible: timeVisible ?? this.timeVisible,
      secondsVisible: secondsVisible ?? this.secondsVisible,
      shiftVisibleRangeOnNewBar: shiftVisibleRangeOnNewBar ?? this.shiftVisibleRangeOnNewBar,
      tickMarkMaxCharacterLength: tickMarkMaxCharacterLength ?? this.tickMarkMaxCharacterLength,
      tickMarkFormatter: tickMarkFormatter ?? this.tickMarkFormatter,
    );
  }
}

class LocalizationOptions {
  const LocalizationOptions({this.timeFormatter, this.priceFormatter});

  /// Formats the time in the crosshair label.
  final TimeFormatter? timeFormatter;

  /// Overrides every series' price formatter.
  final PriceFormatterFn? priceFormatter;
}

class InteractionOptions {
  const InteractionOptions({
    this.handleScroll = true,
    this.handleScale = true,
    this.kineticScroll = true,
    this.axisDragScale = true,
    this.axisDoubleTapReset = true,
  });

  /// Drag the pane to scroll the time scale.
  final bool handleScroll;

  /// Pinch to zoom the time scale.
  final bool handleScale;

  /// Keep scrolling after a fling.
  final bool kineticScroll;

  /// Drag the price/time axis to scale it.
  final bool axisDragScale;

  /// Double-tap an axis to reset it.
  final bool axisDoubleTapReset;
}

class ChartOptions {
  const ChartOptions({
    this.layout = const LayoutOptions(),
    this.grid = const GridOptions(),
    this.crosshair = const CrosshairOptions(),
    this.rightPriceScale = const PriceScaleOptions(),
    this.leftPriceScale = const PriceScaleOptions(visible: false),
    this.timeScale = const TimeScaleOptions(),
    this.localization = const LocalizationOptions(),
    this.interaction = const InteractionOptions(),
  });

  final LayoutOptions layout;
  final GridOptions grid;
  final CrosshairOptions crosshair;
  final PriceScaleOptions rightPriceScale;
  final PriceScaleOptions leftPriceScale;
  final TimeScaleOptions timeScale;
  final LocalizationOptions localization;
  final InteractionOptions interaction;

  ChartOptions copyWith({
    LayoutOptions? layout,
    GridOptions? grid,
    CrosshairOptions? crosshair,
    PriceScaleOptions? rightPriceScale,
    PriceScaleOptions? leftPriceScale,
    TimeScaleOptions? timeScale,
    LocalizationOptions? localization,
    InteractionOptions? interaction,
  }) {
    return ChartOptions(
      layout: layout ?? this.layout,
      grid: grid ?? this.grid,
      crosshair: crosshair ?? this.crosshair,
      rightPriceScale: rightPriceScale ?? this.rightPriceScale,
      leftPriceScale: leftPriceScale ?? this.leftPriceScale,
      timeScale: timeScale ?? this.timeScale,
      localization: localization ?? this.localization,
      interaction: interaction ?? this.interaction,
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
