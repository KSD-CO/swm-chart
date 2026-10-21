import 'dart:ui' show Color;

/// Style of a line (grid, crosshair, price line, line series).
enum LineStyle { solid, dotted, dashed, largeDashed, sparseDotted }

/// How the line series connects its points.
enum LineType { simple, withSteps }

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

/// Type of a time scale tick mark, passed to [TickMarkFormatter].
enum TickMarkType { year, month, dayOfMonth, time, timeWithSeconds }

/// Formats a tick mark label. [time] is a UTC timestamp in seconds.
/// Return `null` to fall back to the default formatter.
typedef TickMarkFormatter = String? Function(int time, TickMarkType type);

/// Formats a time for the crosshair label. [time] is a UTC timestamp in seconds.
typedef TimeFormatter = String Function(int time);

/// Formats a price.
typedef PriceFormatterFn = String Function(double price);

class LayoutOptions {
  const LayoutOptions({
    this.backgroundColor = const Color(0xFFFFFFFF),
    this.textColor = const Color(0xFF191919),
    this.fontSize = 12,
    this.fontFamily,
  });

  final Color backgroundColor;
  final Color textColor;
  final double fontSize;
  final String? fontFamily;

  LayoutOptions copyWith({
    Color? backgroundColor,
    Color? textColor,
    double? fontSize,
    String? fontFamily,
  }) {
    return LayoutOptions(
      backgroundColor: backgroundColor ?? this.backgroundColor,
      textColor: textColor ?? this.textColor,
      fontSize: fontSize ?? this.fontSize,
      fontFamily: fontFamily ?? this.fontFamily,
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
    this.invertScale = false,
    this.visible = true,
    this.borderVisible = true,
    this.borderColor = const Color(0xFF2B2B43),
    this.scaleMargins = const ScaleMargins(),
    this.entireTextOnly = false,
    this.tickMarkDensity = 2.5,
    this.minimumWidth = 0,
  });

  final bool autoScale;
  final bool invertScale;

  /// Only meaningful for the `right` price scale. Overlay scales are never drawn.
  final bool visible;
  final bool borderVisible;
  final Color borderColor;
  final ScaleMargins scaleMargins;
  final bool entireTextOnly;
  final double tickMarkDensity;
  final double minimumWidth;

  PriceScaleOptions copyWith({
    bool? autoScale,
    bool? invertScale,
    bool? visible,
    bool? borderVisible,
    Color? borderColor,
    ScaleMargins? scaleMargins,
    bool? entireTextOnly,
    double? tickMarkDensity,
    double? minimumWidth,
  }) {
    return PriceScaleOptions(
      autoScale: autoScale ?? this.autoScale,
      invertScale: invertScale ?? this.invertScale,
      visible: visible ?? this.visible,
      borderVisible: borderVisible ?? this.borderVisible,
      borderColor: borderColor ?? this.borderColor,
      scaleMargins: scaleMargins ?? this.scaleMargins,
      entireTextOnly: entireTextOnly ?? this.entireTextOnly,
      tickMarkDensity: tickMarkDensity ?? this.tickMarkDensity,
      minimumWidth: minimumWidth ?? this.minimumWidth,
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
  });

  /// Drag the pane to scroll the time scale.
  final bool handleScroll;

  /// Pinch to zoom the time scale.
  final bool handleScale;

  /// Keep scrolling after a fling.
  final bool kineticScroll;

  /// Drag the price/time axis to scale it.
  final bool axisDragScale;
}

class ChartOptions {
  const ChartOptions({
    this.layout = const LayoutOptions(),
    this.grid = const GridOptions(),
    this.crosshair = const CrosshairOptions(),
    this.rightPriceScale = const PriceScaleOptions(),
    this.timeScale = const TimeScaleOptions(),
    this.localization = const LocalizationOptions(),
    this.interaction = const InteractionOptions(),
  });

  final LayoutOptions layout;
  final GridOptions grid;
  final CrosshairOptions crosshair;
  final PriceScaleOptions rightPriceScale;
  final TimeScaleOptions timeScale;
  final LocalizationOptions localization;
  final InteractionOptions interaction;

  ChartOptions copyWith({
    LayoutOptions? layout,
    GridOptions? grid,
    CrosshairOptions? crosshair,
    PriceScaleOptions? rightPriceScale,
    TimeScaleOptions? timeScale,
    LocalizationOptions? localization,
    InteractionOptions? interaction,
  }) {
    return ChartOptions(
      layout: layout ?? this.layout,
      grid: grid ?? this.grid,
      crosshair: crosshair ?? this.crosshair,
      rightPriceScale: rightPriceScale ?? this.rightPriceScale,
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

/// Options shared by all series types.
abstract class SeriesOptions {
  const SeriesOptions({
    required this.title,
    required this.visible,
    required this.lastValueVisible,
    required this.priceLineVisible,
    required this.priceLineWidth,
    required this.priceLineColor,
    required this.priceLineStyle,
    required this.priceFormat,
    required this.priceScaleId,
  });

  final String title;
  final bool visible;

  /// Show the last value label on the price axis.
  final bool lastValueVisible;

  /// Show a horizontal line at the last value.
  final bool priceLineVisible;
  final double priceLineWidth;

  /// `null` means "use the series color".
  final Color? priceLineColor;
  final LineStyle priceLineStyle;
  final PriceFormat priceFormat;

  /// `right` for the visible price scale; any other id creates an invisible
  /// overlay price scale (e.g. for volume).
  final String priceScaleId;
}

class CandlestickSeriesOptions extends SeriesOptions {
  const CandlestickSeriesOptions({
    super.title = '',
    super.visible = true,
    super.lastValueVisible = true,
    super.priceLineVisible = true,
    super.priceLineWidth = 1,
    super.priceLineColor,
    super.priceLineStyle = LineStyle.dashed,
    super.priceFormat = const PriceFormat.price(),
    super.priceScaleId = 'right',
    this.upColor = const Color(0xFF26A69A),
    this.downColor = const Color(0xFFEF5350),
    this.wickVisible = true,
    this.borderVisible = true,
    this.borderUpColor = const Color(0xFF26A69A),
    this.borderDownColor = const Color(0xFFEF5350),
    this.wickUpColor = const Color(0xFF26A69A),
    this.wickDownColor = const Color(0xFFEF5350),
  });

  final Color upColor;
  final Color downColor;
  final bool wickVisible;
  final bool borderVisible;
  final Color borderUpColor;
  final Color borderDownColor;
  final Color wickUpColor;
  final Color wickDownColor;

  CandlestickSeriesOptions copyWith({
    String? title,
    bool? visible,
    bool? lastValueVisible,
    bool? priceLineVisible,
    double? priceLineWidth,
    Color? priceLineColor,
    LineStyle? priceLineStyle,
    PriceFormat? priceFormat,
    String? priceScaleId,
    Color? upColor,
    Color? downColor,
    bool? wickVisible,
    bool? borderVisible,
    Color? borderUpColor,
    Color? borderDownColor,
    Color? wickUpColor,
    Color? wickDownColor,
  }) {
    return CandlestickSeriesOptions(
      title: title ?? this.title,
      visible: visible ?? this.visible,
      lastValueVisible: lastValueVisible ?? this.lastValueVisible,
      priceLineVisible: priceLineVisible ?? this.priceLineVisible,
      priceLineWidth: priceLineWidth ?? this.priceLineWidth,
      priceLineColor: priceLineColor ?? this.priceLineColor,
      priceLineStyle: priceLineStyle ?? this.priceLineStyle,
      priceFormat: priceFormat ?? this.priceFormat,
      priceScaleId: priceScaleId ?? this.priceScaleId,
      upColor: upColor ?? this.upColor,
      downColor: downColor ?? this.downColor,
      wickVisible: wickVisible ?? this.wickVisible,
      borderVisible: borderVisible ?? this.borderVisible,
      borderUpColor: borderUpColor ?? this.borderUpColor,
      borderDownColor: borderDownColor ?? this.borderDownColor,
      wickUpColor: wickUpColor ?? this.wickUpColor,
      wickDownColor: wickDownColor ?? this.wickDownColor,
    );
  }
}

class LineSeriesOptions extends SeriesOptions {
  const LineSeriesOptions({
    super.title = '',
    super.visible = true,
    super.lastValueVisible = true,
    super.priceLineVisible = true,
    super.priceLineWidth = 1,
    super.priceLineColor,
    super.priceLineStyle = LineStyle.dashed,
    super.priceFormat = const PriceFormat.price(),
    super.priceScaleId = 'right',
    this.color = const Color(0xFF2196F3),
    this.lineWidth = 3,
    this.lineStyle = LineStyle.solid,
    this.lineType = LineType.simple,
    this.lineVisible = true,
    this.pointMarkersVisible = false,
    this.pointMarkersRadius,
    this.crosshairMarkerVisible = true,
    this.crosshairMarkerRadius = 4,
    this.crosshairMarkerBorderColor,
    this.crosshairMarkerBackgroundColor,
    this.crosshairMarkerBorderWidth = 2,
  });

  final Color color;
  final double lineWidth;
  final LineStyle lineStyle;
  final LineType lineType;
  final bool lineVisible;
  final bool pointMarkersVisible;
  final double? pointMarkersRadius;
  final bool crosshairMarkerVisible;
  final double crosshairMarkerRadius;

  /// `null` means the chart background color.
  final Color? crosshairMarkerBorderColor;

  /// `null` means the series color.
  final Color? crosshairMarkerBackgroundColor;
  final double crosshairMarkerBorderWidth;

  LineSeriesOptions copyWith({
    String? title,
    bool? visible,
    bool? lastValueVisible,
    bool? priceLineVisible,
    double? priceLineWidth,
    Color? priceLineColor,
    LineStyle? priceLineStyle,
    PriceFormat? priceFormat,
    String? priceScaleId,
    Color? color,
    double? lineWidth,
    LineStyle? lineStyle,
    LineType? lineType,
    bool? lineVisible,
    bool? pointMarkersVisible,
    double? pointMarkersRadius,
    bool? crosshairMarkerVisible,
    double? crosshairMarkerRadius,
    Color? crosshairMarkerBorderColor,
    Color? crosshairMarkerBackgroundColor,
    double? crosshairMarkerBorderWidth,
  }) {
    return LineSeriesOptions(
      title: title ?? this.title,
      visible: visible ?? this.visible,
      lastValueVisible: lastValueVisible ?? this.lastValueVisible,
      priceLineVisible: priceLineVisible ?? this.priceLineVisible,
      priceLineWidth: priceLineWidth ?? this.priceLineWidth,
      priceLineColor: priceLineColor ?? this.priceLineColor,
      priceLineStyle: priceLineStyle ?? this.priceLineStyle,
      priceFormat: priceFormat ?? this.priceFormat,
      priceScaleId: priceScaleId ?? this.priceScaleId,
      color: color ?? this.color,
      lineWidth: lineWidth ?? this.lineWidth,
      lineStyle: lineStyle ?? this.lineStyle,
      lineType: lineType ?? this.lineType,
      lineVisible: lineVisible ?? this.lineVisible,
      pointMarkersVisible: pointMarkersVisible ?? this.pointMarkersVisible,
      pointMarkersRadius: pointMarkersRadius ?? this.pointMarkersRadius,
      crosshairMarkerVisible: crosshairMarkerVisible ?? this.crosshairMarkerVisible,
      crosshairMarkerRadius: crosshairMarkerRadius ?? this.crosshairMarkerRadius,
      crosshairMarkerBorderColor: crosshairMarkerBorderColor ?? this.crosshairMarkerBorderColor,
      crosshairMarkerBackgroundColor: crosshairMarkerBackgroundColor ?? this.crosshairMarkerBackgroundColor,
      crosshairMarkerBorderWidth: crosshairMarkerBorderWidth ?? this.crosshairMarkerBorderWidth,
    );
  }
}

class HistogramSeriesOptions extends SeriesOptions {
  const HistogramSeriesOptions({
    super.title = '',
    super.visible = true,
    super.lastValueVisible = true,
    super.priceLineVisible = true,
    super.priceLineWidth = 1,
    super.priceLineColor,
    super.priceLineStyle = LineStyle.dashed,
    super.priceFormat = const PriceFormat.price(),
    super.priceScaleId = 'right',
    this.color = const Color(0xFF26A69A),
    this.base = 0,
  });

  final Color color;

  /// Value the columns grow from.
  final double base;

  HistogramSeriesOptions copyWith({
    String? title,
    bool? visible,
    bool? lastValueVisible,
    bool? priceLineVisible,
    double? priceLineWidth,
    Color? priceLineColor,
    LineStyle? priceLineStyle,
    PriceFormat? priceFormat,
    String? priceScaleId,
    Color? color,
    double? base,
  }) {
    return HistogramSeriesOptions(
      title: title ?? this.title,
      visible: visible ?? this.visible,
      lastValueVisible: lastValueVisible ?? this.lastValueVisible,
      priceLineVisible: priceLineVisible ?? this.priceLineVisible,
      priceLineWidth: priceLineWidth ?? this.priceLineWidth,
      priceLineColor: priceLineColor ?? this.priceLineColor,
      priceLineStyle: priceLineStyle ?? this.priceLineStyle,
      priceFormat: priceFormat ?? this.priceFormat,
      priceScaleId: priceScaleId ?? this.priceScaleId,
      color: color ?? this.color,
      base: base ?? this.base,
    );
  }
}
