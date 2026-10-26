import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:swm_chart/swm_chart.dart';

class _Holding {
  const _Holding(this.symbol, this.name, this.share, this.color);

  final String symbol;
  final String name;
  final double share;
  final Color color;
}

const _holdings = [
  _Holding('AAPL', 'Apple', 32, Color(0xFF2962FF)),
  _Holding('MSFT', 'Microsoft', 24, Color(0xFF26A69A)),
  _Holding('NVDA', 'NVIDIA', 18, Color(0xFF7E57C2)),
  _Holding('TSLA', 'Tesla', 12, Color(0xFFFF9800)),
  _Holding('BTC', 'Bitcoin', 9, Color(0xFFF7931A)),
  _Holding('GLD', 'Gold', 5, Color(0xFFB0A060)),
];

/// A portfolio donut and a watchlist of sparklines.
class WatchlistScreen extends StatefulWidget {
  const WatchlistScreen({super.key});

  @override
  State<WatchlistScreen> createState() => _WatchlistScreenState();
}

class _WatchlistScreenState extends State<WatchlistScreen> {
  int? _selected = 0;

  /// Intraday prices per symbol: a seeded random walk with a drift.
  late final Map<String, List<double>> _prices = {
    for (final (i, h) in _holdings.indexed) h.symbol: _walk(i, 100 + 37.0 * i, i.isEven ? 0.15 : -0.12),
  };

  static List<double> _walk(int seed, double start, double drift) {
    final r = math.Random(seed + 11);
    var v = start;
    return [for (var i = 0; i < 48; i++) v = math.max(1, v + (r.nextDouble() - 0.5 + drift) * start * 0.01)];
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final selected = _selected == null ? null : _holdings[_selected!];
    return ListView(
      padding: const EdgeInsets.symmetric(vertical: 12),
      children: [
        Center(
          child: SwmDonut(
            size: 200,
            innerRadius: 62,
            thickness: 26,
            slices: [for (final h in _holdings) SwmDonutSlice(value: h.share, color: h.color)],
            selected: _selected,
            onSelect: (i) => setState(() => _selected = i),
            center: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(selected?.symbol ?? 'Portfolio', style: theme.textTheme.titleMedium),
                Text(
                  selected == null ? r'$124,800' : '${selected.share.toStringAsFixed(0)}%',
                  style: theme.textTheme.bodySmall,
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        for (final h in _holdings) _row(context, h),
      ],
    );
  }

  Widget _row(BuildContext context, _Holding h) {
    final theme = Theme.of(context);
    final prices = _prices[h.symbol]!;
    final change = (prices.last - prices.first) / prices.first * 100;
    final up = change >= 0;
    final color = up ? kSparklineUpColor : kSparklineDownColor;
    return ListTile(
      leading: CircleAvatar(radius: 6, backgroundColor: h.color),
      minLeadingWidth: 12,
      title: Text(h.symbol, style: const TextStyle(fontWeight: FontWeight.w600)),
      subtitle: Text(h.name),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SwmSparkline(values: prices, width: 90, height: 32, baseline: prices.first, curved: true),
          const SizedBox(width: 12),
          SizedBox(
            width: 72,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(prices.last.toStringAsFixed(2), style: theme.textTheme.bodyMedium),
                Text(
                  '${up ? '+' : ''}${change.toStringAsFixed(2)}%',
                  style: theme.textTheme.bodySmall?.copyWith(color: color),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
