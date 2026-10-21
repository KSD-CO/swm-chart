import 'dart:math' as math;

import '../options.dart';

const String _minusSign = '−';

/// Formats prices of a series according to its [PriceFormat].
class PriceFormatter {
  PriceFormatter(this.format);

  final PriceFormat format;

  /// Base used by the price tick mark builder: `1 / minMove`.
  int get base {
    final minMove = format.minMove;
    if (minMove <= 0) return 100;
    return math.max(1, (1 / minMove).round());
  }

  String call(double price) {
    switch (format.type) {
      case PriceFormatType.custom:
        return format.formatter!(price);
      case PriceFormatType.volume:
        return _formatVolume(price);
      case PriceFormatType.price:
        return _formatPrice(price);
    }
  }

  String _formatPrice(double price) {
    final minMove = format.minMove;
    final rounded = minMove > 0 ? (price / minMove).round() * minMove : price;
    var text = rounded.abs().toStringAsFixed(format.precision);
    if (rounded < 0 && double.parse(text) != 0) {
      text = '$_minusSign$text';
    }
    return text;
  }

  String _formatVolume(double volume) {
    final sign = volume < 0 ? _minusSign : '';
    final v = volume.abs();
    if (v < 995) return '$sign${_trimZeros(v)}';
    if (v < 999995) return '$sign${_trimZeros(v / 1000)}K';
    if (v < 999999995) return '$sign${_trimZeros(v / 1000000)}M';
    return '$sign${_trimZeros(v / 1000000000)}B';
  }

  String _trimZeros(double v) {
    var text = v.toStringAsFixed(format.precision);
    if (text.contains('.')) {
      text = text.replaceFirst(RegExp(r'\.?0+$'), '');
    }
    return text;
  }
}
