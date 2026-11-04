import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../state/app_state.dart';
import '../util.dart';
import 'chat_screen.dart';

/// Wird direkt nach der Planerstellung gezeigt: Überblick über den neuen Plan, danach loslegen oder im Chat anpassen.
class PlanReadyScreen extends StatelessWidget {
  const PlanReadyScreen({super.key});

  @override
  Widget build(BuildContext context) {
    // Der neue Plan startet am nächsten Montag und ist bis dahin als Folgeblock („upcoming“) gespeichert
    final state = context.watch<AppState>();
    final plan = state.upcomingPlan ?? state.plan;
    if (plan == null) return const Scaffold(body: Center(child: Text('Kein Plan vorhanden.')));

    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final weeks = asMapList(plan['weeks']);
    final allDays = weeks.expand((w) => asMapList(w['days'])).toList();
    final sessions = allDays.where((d) => d['dayType'] != 'rest').toList();
    final hours = sessions.fold<int>(0, (s, d) => s + ((d['durationMin'] as num?)?.toInt() ?? 0)) / 60;
    final meters = sessions.fold<double>(0, (s, d) => s + (plannedRunMeters(d) ?? 0));
    final focus = plan['focus'] is Map ? Map<String, dynamic>.from(plan['focus'] as Map) : <String, dynamic>{};
    final secondary = (focus['secondary'] as List?)?.map((e) => e.toString()).toList() ?? const <String>[];

    final typeCounts = <String, int>{};
    for (final d in sessions) {
      final t = d['dayType'].toString();
      typeCounts[t] = (typeCounts[t] ?? 0) + 1;
    }

    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 24, 20, 24),
          children: [
            Icon(Icons.celebration, size: 40, color: scheme.primary),
            const SizedBox(height: 8),
            Text('Dein Plan ist fertig', style: text.headlineMedium?.copyWith(fontWeight: FontWeight.w800)),
            const SizedBox(height: 4),
            Text(plan['title']?.toString() ?? '', style: text.titleMedium),
            const SizedBox(height: 16),
            Row(children: [
              _Big('${weeks.length}', 'Wochen'),
              _Big('${sessions.length}', 'Einheiten'),
              _Big(hours.toStringAsFixed(0), 'Stunden'),
              if (meters > 0) _Big((meters / 1000).toStringAsFixed(0), 'km Laufen'),
            ]),
            const SizedBox(height: 16),
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: [
                for (final e in typeCounts.entries)
                  Chip(
                    avatar: Icon(dayTypeIcon(e.key), size: 16, color: dayTypeColor(e.key)),
                    label: Text('${e.value}× ${dayTypeLabels[e.key] ?? e.key}'),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            Card(
              margin: EdgeInsets.zero,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (focus['primary'] != null) ...[
                      Text('Fokus: ${focus['primary']}', style: text.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
                      if (secondary.isNotEmpty) Text('Außerdem: ${secondary.join(', ')}', style: text.bodySmall),
                      const SizedBox(height: 8),
                    ],
                    Text(plan['summary']?.toString() ?? ''),
                    if (focus['rationale'] != null) ...[
                      const SizedBox(height: 8),
                      Text(focus['rationale'].toString(), style: text.bodySmall),
                    ],
                  ],
                ),
              ),
            ),
            const SizedBox(height: 20),
            Text('So sieht dein Block aus', style: text.titleMedium),
            const SizedBox(height: 8),
            for (final (i, w) in calendarWeeks(plan).indexed) _WeekRow(week: w, number: i + 1),
            const SizedBox(height: 24),
            FilledButton.icon(
              style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
              icon: const Icon(Icons.check),
              label: const Text('Passt, los geht\'s'),
              onPressed: () => Navigator.of(context).popUntil((r) => r.isFirst),
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(52)),
              icon: const Icon(Icons.chat_bubble_outline),
              label: const Text('Mit dem Coach anpassen'),
              onPressed: () => Navigator.of(context).pushReplacement(
                MaterialPageRoute(builder: (_) => const ChatScreen()),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Big extends StatelessWidget {
  const _Big(this.value, this.label);
  final String value;
  final String label;

  @override
  Widget build(BuildContext context) => Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(value, style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800)),
            Text(label, style: Theme.of(context).textTheme.bodySmall),
          ],
        ),
      );
}

class _WeekRow extends StatelessWidget {
  const _WeekRow({required this.week, required this.number});
  final CalendarWeek week;
  final int number;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Woche $number${week.theme == null ? '' : ': ${week.theme}'}',
              style: Theme.of(context).textTheme.bodyMedium),
          const SizedBox(height: 6),
          Row(
            children: [
              for (final (i, d) in week.days.indexed)
                Expanded(
                  child: Column(
                    children: [
                      if (d == null)
                        Container(
                          width: 32,
                          height: 32,
                          decoration:
                              BoxDecoration(shape: BoxShape.circle, border: Border.all(color: scheme.outlineVariant)),
                        )
                      else
                        Container(
                          width: 32,
                          height: 32,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: d['dayType'] == 'rest'
                                ? scheme.surfaceContainerHighest
                                : dayTypeColor(d['dayType'].toString()).withValues(alpha: 0.18),
                          ),
                          child: Icon(
                            dayTypeIcon(d['dayType'].toString()),
                            size: 16,
                            color: d['dayType'] == 'rest' ? scheme.outline : dayTypeColor(d['dayType'].toString()),
                          ),
                        ),
                      Text(weekdayShort[i], style: Theme.of(context).textTheme.labelSmall),
                    ],
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
