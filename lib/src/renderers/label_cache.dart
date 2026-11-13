import 'package:flutter/painting.dart';

/// Laid-out text kept between frames: a panned or zoomed chart draws the
/// same marker texts, drawing labels and legend lines frame after frame,
/// and laying text out is much of a frame's cost. Keyed by the text with
/// its style and layout limits; past [capacity] the least recently used is
/// dropped (and disposed). Painters it hands out belong to it — don't
/// dispose them.
class LabelCache {
  LabelCache({this.capacity = 256});

  final int capacity;

  // Insertion-ordered: a hit moves to the end, the first is the oldest.
  final _painters = <(InlineSpan, double, int?, String?), TextPainter>{};

  /// [text] laid out (to [maxWidth], at most [maxLines] lines, with
  /// [ellipsis] when cut).
  TextPainter get(InlineSpan text, {double maxWidth = double.infinity, int? maxLines, String? ellipsis}) {
    final key = (text, maxWidth, maxLines, ellipsis);
    final hit = _painters.remove(key);
    if (hit != null) return _painters[key] = hit;
    if (_painters.length >= capacity) {
      _painters.remove(_painters.keys.first)!.dispose();
    }
    final painter = TextPainter(text: text, textDirection: TextDirection.ltr, maxLines: maxLines, ellipsis: ellipsis)
      ..layout(maxWidth: maxWidth);
    return _painters[key] = painter;
  }

  /// One run of [text] in [style].
  TextPainter text(String text, TextStyle style) => get(TextSpan(text: text, style: style));

  int get length => _painters.length;

  void clear() {
    for (final p in _painters.values) {
      p.dispose();
    }
    _painters.clear();
  }
}
