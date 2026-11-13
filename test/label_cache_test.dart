import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:swm_chart/src/renderers/label_cache.dart';

void main() {
  const style = TextStyle(fontSize: 12, color: Color(0xFF000000));

  test('the same text and style is laid out once', () {
    final cache = LabelCache();
    final a = cache.text('Buy 3', style);
    expect(identical(cache.text('Buy 3', style), a), isTrue);
    expect(cache.text('Buy 3', style.copyWith(color: const Color(0xFFFF0000))), isNot(same(a)));
    expect(cache.text('Sell 2', style), isNot(same(a)));
    expect(cache.length, 3);
    // Layout limits are part of the key too.
    expect(cache.get(const TextSpan(text: 'Buy 3', style: style), maxWidth: 10), isNot(same(a)));
  });

  test('past its capacity the least recently used goes', () {
    final cache = LabelCache(capacity: 2);
    final a = cache.text('a', style);
    cache.text('b', style);
    cache.text('a', style); // a is now the most recent
    cache.text('c', style); // drops b
    expect(cache.length, 2);
    expect(identical(cache.text('a', style), a), isTrue);
    final b = cache.text('b', style); // laid out again
    expect(b.width, greaterThan(0));
    expect(cache.length, 2);
  });
}
