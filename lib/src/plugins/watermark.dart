// Port of lightweight-charts src/plugins/text-watermark and image-watermark.
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';

import '../api/chart_controller.dart';
import 'primitive.dart';

enum WatermarkHorzAlign { left, center, right }

enum WatermarkVertAlign { top, center, bottom }

class TextWatermarkLine {
  const TextWatermarkLine({
    required this.text,
    this.color = const Color(0x80000000),
    this.fontSize = 48,
    this.fontFamily,
    this.fontWeight = FontWeight.normal,
    this.fontStyle = FontStyle.normal,
  });

  final String text;
  final Color color;
  final double fontSize;
  final String? fontFamily;
  final FontWeight fontWeight;
  final FontStyle fontStyle;
}

class TextWatermarkOptions {
  const TextWatermarkOptions({
    this.visible = true,
    this.horzAlign = WatermarkHorzAlign.center,
    this.vertAlign = WatermarkVertAlign.center,
    this.lines = const [],
  });

  final bool visible;
  final WatermarkHorzAlign horzAlign;
  final WatermarkVertAlign vertAlign;
  final List<TextWatermarkLine> lines;
}

class TextWatermarkPrimitive extends ChartPrimitive {
  TextWatermarkPrimitive(this._options);

  TextWatermarkOptions _options;

  TextWatermarkOptions get options => _options;

  void applyOptions(TextWatermarkOptions options) {
    _options = options;
    requestUpdate();
  }

  @override
  PrimitiveZOrder get zOrder => PrimitiveZOrder.bottom;

  @override
  void paint(PrimitivePaintContext ctx) {
    if (!_options.visible) return;
    final size = ctx.paneSize;
    final painters = <(TextPainter, double, double)>[];
    var textHeight = 0.0;
    for (final line in _options.lines) {
      if (line.text.isEmpty) continue;
      final tp = TextPainter(
        text: TextSpan(
          text: line.text,
          style: TextStyle(
            color: line.color,
            fontSize: line.fontSize,
            fontFamily: line.fontFamily ?? ctx.fontFamily,
            fontWeight: line.fontWeight,
            fontStyle: line.fontStyle,
            height: 1,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      // Shrink lines wider than the pane, like upstream's `zoom`.
      final zoom = tp.width > size.width ? size.width / tp.width : 1.0;
      final lineHeight = line.fontSize * 1.2;
      painters.add((tp, zoom, lineHeight));
      textHeight += lineHeight * zoom;
    }

    var vertOffset = switch (_options.vertAlign) {
      WatermarkVertAlign.top => 0.0,
      WatermarkVertAlign.center => math.max((size.height - textHeight) / 2, 0.0),
      WatermarkVertAlign.bottom => math.max(size.height - textHeight, 0.0),
    };

    final canvas = ctx.canvas;
    for (final (tp, zoom, lineHeight) in painters) {
      final width = tp.width * zoom;
      final x = switch (_options.horzAlign) {
        WatermarkHorzAlign.left => lineHeight / 2,
        WatermarkHorzAlign.center => (size.width - width) / 2,
        WatermarkHorzAlign.right => size.width - 1 - lineHeight / 2 - width,
      };
      canvas.save();
      canvas.translate(x, vertOffset + (lineHeight - tp.height) * zoom / 2);
      canvas.scale(zoom);
      tp.paint(canvas, Offset.zero);
      canvas.restore();
      tp.dispose();
      vertOffset += lineHeight * zoom;
    }
  }
}

class ImageWatermarkOptions {
  const ImageWatermarkOptions({this.maxWidth, this.maxHeight, this.padding = 0, this.alpha = 1});

  final double? maxWidth;
  final double? maxHeight;
  final double padding;
  final double alpha;
}

class ImageWatermarkPrimitive extends ChartPrimitive {
  ImageWatermarkPrimitive(this.image, this._options);

  final ui.Image image;
  ImageWatermarkOptions _options;

  ImageWatermarkOptions get options => _options;

  void applyOptions(ImageWatermarkOptions options) {
    _options = options;
    requestUpdate();
  }

  @override
  PrimitiveZOrder get zOrder => PrimitiveZOrder.bottom;

  @override
  void paint(PrimitivePaintContext ctx) {
    final size = ctx.paneSize;
    var availableWidth = size.width - 2 * _options.padding;
    var availableHeight = size.height - 2 * _options.padding;
    if (_options.maxHeight != null) availableHeight = math.min(availableHeight, _options.maxHeight!);
    if (_options.maxWidth != null) availableWidth = math.min(availableWidth, _options.maxWidth!);
    if (availableWidth <= 0 || availableHeight <= 0) return;
    final scale = math.min(availableWidth / image.width, availableHeight / image.height);
    final w = image.width * scale, h = image.height * scale;
    final dst = Rect.fromLTWH((size.width - w) / 2, (size.height - h) / 2, w, h);
    final src = Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble());
    ctx.canvas.drawImageRect(
      image,
      src,
      dst,
      Paint()
        ..filterQuality = FilterQuality.medium
        ..color = Color.fromRGBO(0, 0, 0, _options.alpha),
    );
  }
}

/// Handle of a watermark attached to a pane.
class WatermarkPlugin<P extends ChartPrimitive> {
  WatermarkPlugin._(this._pane, this.primitive);

  final PaneApi _pane;
  final P primitive;

  void detach() => _pane.detachPrimitive(primitive);
}

/// Text watermark on [pane], like lightweight-charts' `createTextWatermark`.
WatermarkPlugin<TextWatermarkPrimitive> createTextWatermark(PaneApi pane, TextWatermarkOptions options) {
  final primitive = TextWatermarkPrimitive(options);
  pane.attachPrimitive(primitive);
  return WatermarkPlugin._(pane, primitive);
}

/// Image watermark on [pane], like lightweight-charts' `createImageWatermark`.
WatermarkPlugin<ImageWatermarkPrimitive> createImageWatermark(
  PaneApi pane,
  ui.Image image, [
  ImageWatermarkOptions options = const ImageWatermarkOptions(),
]) {
  final primitive = ImageWatermarkPrimitive(image, options);
  pane.attachPrimitive(primitive);
  return WatermarkPlugin._(pane, primitive);
}
