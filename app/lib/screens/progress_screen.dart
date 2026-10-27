import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../state/app_state.dart';
import '../util.dart';

class ProgressScreen extends StatelessWidget {
  const ProgressScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final p = state.progress;
    final total = (p?['totalSessions'] as num?)?.toInt() ?? 0;

    if (p == null || total == 0) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text('Noch keine Einheiten protokolliert. Starte ein Training im Plan, dann erscheinen hier deine Fortschritte.',
              textAlign: TextAlign.center),
        ),
      );
    }

    final weekly = asMapList(p['weekly']);
    final exercises = asMapList(p['exercises']);

    return RefreshIndicator(
      onRefresh: () => context.read<AppState>().refresh(),
      child: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          Card(
            child: ListTile(
              leading: const Icon(Icons.emoji_events),
              title: Text('$total Einheiten insgesamt'),
            ),
          ),
          if (weekly.isNotEmpty) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 12, 4, 4),
              child: Text('Pro Woche', style: Theme.of(context).textTheme.titleMedium),
            ),
            for (final w in weekly.reversed.take(8))
              ListTile(
                dense: true,
                title: Text('Woche ab ${germanDate(w['weekStart'].toString())}'),
                subtitle: Text('${w['sessions']} Einheiten · ${w['minutes']} Min'
                    '${(w['avgRpe'] as num? ?? 0) > 0 ? ' · Ø RPE ${(w['avgRpe'] as num).toStringAsFixed(1)}' : ''}'),
              ),
          ],
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 12, 4, 4),
            child: Text('Übungen', style: Theme.of(context).textTheme.titleMedium),
          ),
          for (final e in exercises)
            ExpansionTile(
              title: Text(e['name'].toString()),
              subtitle: Text('${e['sessions']} Einheiten · beste Last ${e['bestLoadKg']} kg'),
              children: [
                for (final pt in asMapList(e['points']).reversed)
                  ListTile(
                    dense: true,
                    title: Text(germanDate(pt['date'].toString())),
                    subtitle: Text('Top-Last ${pt['topLoadKg']} kg · ${pt['totalReps']} Wdh. · ${pt['totalDistanceM']} m'),
                  ),
              ],
            ),
        ],
      ),
    );
  }
}
