import 'dart:ui' show Color;

import '../options.dart';

/// Options of a custom price line, created with `SeriesApi.createPriceLine`.
class PriceLineOptions {
  const PriceLineOptions({
    required this.price,
    this.color = const Color(0xFF2196F3),
    this.lineWidth = 1,
    this.lineStyle = LineStyle.solid,
    this.lineVisible = true,
    this.axisLabelVisible = true,
    this.title = '',
    this.axisLabelColor,
    this.axisLabelTextColor,
  });

  final double price;
  final Color color;
  final double lineWidth;
  final LineStyle lineStyle;
  final bool lineVisible;
  final bool axisLabelVisible;

  /// Drawn next to the axis label, inside the pane.
  final String title;

  /// `null` means [color].
  final Color? axisLabelColor;

  /// `null` picks black or white for contrast.
  final Color? axisLabelTextColor;

  PriceLineOptions copyWith({
    double? price,
    Color? color,
    double? lineWidth,
    LineStyle? lineStyle,
    bool? lineVisible,
    bool? axisLabelVisible,
    String? title,
    Color? axisLabelColor,
    Color? axisLabelTextColor,
  }) {
    return PriceLineOptions(
      price: price ?? this.price,
      color: color ?? this.color,
      lineWidth: lineWidth ?? this.lineWidth,
      lineStyle: lineStyle ?? this.lineStyle,
      lineVisible: lineVisible ?? this.lineVisible,
      axisLabelVisible: axisLabelVisible ?? this.axisLabelVisible,
      title: title ?? this.title,
      axisLabelColor: axisLabelColor ?? this.axisLabelColor,
      axisLabelTextColor: axisLabelTextColor ?? this.axisLabelTextColor,
    );
  }
}

class PriceLine {
  PriceLine(this.options);

  PriceLineOptions options;
}
