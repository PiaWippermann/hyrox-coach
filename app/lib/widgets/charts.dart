import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Ein Balken aus gestapelten Segmenten (Wert, Farbe).
class BarData {
  const BarData(this.label, this.segments, {this.highlight = false});
  final String label;
  final List<(double, Color)> segments;
  final bool highlight;
  double get total => segments.fold(0, (s, x) => s + x.$1);
}

/// Einfaches gestapeltes Säulendiagramm mit Wert über dem markierten Balken.
class StackedBarChart extends StatelessWidget {
  const StackedBarChart({super.key, required this.bars, required this.format, this.height = 140});

  final List<BarData> bars;
  final String Function(double) format;
  final double height;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final small = Theme.of(context).textTheme.labelSmall;
    final maxV = bars.fold<double>(0, (m, b) => math.max(m, b.total));
    // Platz für Wert über dem Balken und Beschriftung darunter; die Balken selbst sind höchstens [height] hoch
    return SizedBox(
      height: height + 48,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          for (final b in bars)
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 3),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    if (b.highlight && b.total > 0)
                      FittedBox(child: Text(format(b.total), style: small?.copyWith(fontWeight: FontWeight.w700))),
                    const SizedBox(height: 2),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: Column(
                        children: [
                          if (b.total == 0)
                            Container(height: 3, color: scheme.surfaceContainerHighest)
                          else
                            for (final seg in b.segments.reversed)
                              if (seg.$1 > 0)
                                Container(height: maxV == 0 ? 0 : seg.$1 / maxV * height, color: seg.$2),
                        ],
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(b.label,
                        style: small?.copyWith(
                          color: b.highlight ? scheme.primary : scheme.outline,
                          fontWeight: b.highlight ? FontWeight.w700 : null,
                        )),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class LineSeries {
  const LineSeries(this.label, this.values, this.color, {this.fill = false});
  final String label;
  final List<double> values;
  final Color color;
  final bool fill;
}

/// Linienchart für Verläufe (Fitness/Ermüdung, 1RM-Entwicklung).
class SimpleLineChart extends StatelessWidget {
  const SimpleLineChart({super.key, required this.series, this.height = 140, this.startLabel, this.endLabel});

  final List<LineSeries> series;
  final double height;
  final String? startLabel;
  final String? endLabel;

  @override
  Widget build(BuildContext context) {
    final small = Theme.of(context).textTheme.labelSmall?.copyWith(color: Theme.of(context).colorScheme.outline);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          height: height,
          width: double.infinity,
          child: CustomPaint(painter: _LinePainter(series, Theme.of(context).colorScheme.outlineVariant)),
        ),
        if (startLabel != null || endLabel != null)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Row(children: [Text(startLabel ?? '', style: small), const Spacer(), Text(endLabel ?? '', style: small)]),
          ),
        if (series.length > 1)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Wrap(spacing: 16, children: [
              for (final s in series)
                Row(mainAxisSize: MainAxisSize.min, children: [
                  Container(width: 12, height: 3, color: s.color),
                  const SizedBox(width: 4),
                  Text(s.label, style: Theme.of(context).textTheme.labelSmall),
                ]),
            ]),
          ),
      ],
    );
  }
}

class _LinePainter extends CustomPainter {
  _LinePainter(this.series, this.gridColor);
  final List<LineSeries> series;
  final Color gridColor;

  @override
  void paint(Canvas canvas, Size size) {
    final grid = Paint()
      ..color = gridColor
      ..strokeWidth = 1;
    for (var i = 0; i <= 3; i++) {
      final y = size.height * i / 3;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), grid);
    }

    final all = series.expand((s) => s.values);
    if (all.isEmpty) return;
    final maxV = all.reduce(math.max);
    final minV = math.min(0.0, all.reduce(math.min));
    final range = (maxV - minV) == 0 ? 1 : maxV - minV;

    for (final s in series) {
      if (s.values.isEmpty) continue;
      final n = s.values.length;
      Offset pt(int i) => Offset(
            n == 1 ? size.width / 2 : size.width * i / (n - 1),
            size.height - (s.values[i] - minV) / range * size.height,
          );
      final path = Path()..moveTo(pt(0).dx, pt(0).dy);
      for (var i = 1; i < n; i++) {
        path.lineTo(pt(i).dx, pt(i).dy);
      }
      if (s.fill && n > 1) {
        final area = Path.from(path)
          ..lineTo(pt(n - 1).dx, size.height)
          ..lineTo(pt(0).dx, size.height)
          ..close();
        canvas.drawPath(area, Paint()..color = s.color.withValues(alpha: 0.15));
      }
      canvas.drawPath(
        path,
        Paint()
          ..color = s.color
          ..strokeWidth = 2.5
          ..style = PaintingStyle.stroke
          ..strokeJoin = StrokeJoin.round,
      );
      if (n <= 12) {
        for (var i = 0; i < n; i++) {
          canvas.drawCircle(pt(i), 3.5, Paint()..color = s.color);
        }
      }
    }
  }

  @override
  bool shouldRepaint(covariant _LinePainter old) => old.series != series;
}
