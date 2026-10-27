import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../state/app_state.dart';
import '../util.dart';
import 'anamnese_screen.dart';
import 'day_detail_screen.dart';

class PlanScreen extends StatelessWidget {
  const PlanScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final plan = state.plan;

    if (plan == null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('Noch kein Plan vorhanden.'),
              const SizedBox(height: 12),
              FilledButton(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const AnamneseScreen()),
                ),
                child: const Text('Anamnese öffnen und Plan erstellen'),
              ),
            ],
          ),
        ),
      );
    }

    final planId = state.planEnvelope!['id'].toString();
    final done = state.workoutDates;
    final today = isoDate(DateTime.now());
    final weeks = asMapList(plan['weeks']);
    final focus = plan['focus'] is Map ? Map<String, dynamic>.from(plan['focus'] as Map) : <String, dynamic>{};

    return RefreshIndicator(
      onRefresh: () => context.read<AppState>().refresh(),
      child: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(plan['title']?.toString() ?? 'Trainingsplan', style: Theme.of(context).textTheme.titleLarge),
                  const SizedBox(height: 6),
                  Text(plan['summary']?.toString() ?? ''),
                  if (focus['primary'] != null) ...[
                    const SizedBox(height: 8),
                    Text('Fokus: ${focus['primary']}', style: const TextStyle(fontWeight: FontWeight.w600)),
                    if (focus['rationale'] != null) Text(focus['rationale'].toString()),
                  ],
                ],
              ),
            ),
          ),
          for (final week in weeks)
            ExpansionTile(
              initiallyExpanded: asMapList(week['days']).any((d) => d['date'] == today) ||
                  (weeks.first == week && !weeks.any((w) => asMapList(w['days']).any((d) => d['date'] == today))),
              title: Text('Woche ${week['weekNumber']}: ${week['theme']}'),
              children: [
                for (final day in asMapList(week['days']))
                  _DayTile(day: day, planId: planId, isDone: done.contains(day['date']), isToday: day['date'] == today),
              ],
            ),
        ],
      ),
    );
  }
}

class _DayTile extends StatelessWidget {
  const _DayTile({required this.day, required this.planId, required this.isDone, required this.isToday});

  final Map<String, dynamic> day;
  final String planId;
  final bool isDone;
  final bool isToday;

  @override
  Widget build(BuildContext context) {
    final type = day['dayType'].toString();
    final isRest = type == 'rest';
    final variants = asMapList(day['variants']);
    final places = variants.map((v) => v['location'] == 'gym' ? 'Gym' : 'Zuhause').join(' / ');

    return ListTile(
      enabled: !isRest,
      tileColor: isToday ? Theme.of(context).colorScheme.primaryContainer.withOpacity(0.35) : null,
      leading: isDone
          ? const Icon(Icons.check_circle, color: Colors.green)
          : Icon(isRest ? Icons.hotel : Icons.fitness_center),
      title: Text('${germanDate(day['date'].toString())}  ${day['title']}'),
      subtitle: Text(isRest
          ? 'Ruhetag'
          : '${dayTypeLabels[type] ?? type} · ${day['durationMin']} Min · $places'),
      trailing: isRest ? null : const Icon(Icons.chevron_right),
      onTap: isRest
          ? null
          : () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => DayDetailScreen(day: day, planId: planId)),
              ),
    );
  }
}
