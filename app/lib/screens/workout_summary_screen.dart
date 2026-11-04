import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../api/api_client.dart';
import '../state/app_state.dart';
import '../theme/app_colors.dart';
import '../util.dart';

/// Zusammenfassung direkt nach dem Training (wie bei Strava): Kennzahlen und kurzes Coach-Feedback.
class WorkoutSummaryScreen extends StatefulWidget {
  const WorkoutSummaryScreen({super.key, required this.log});
  final Map<String, dynamic> log;

  @override
  State<WorkoutSummaryScreen> createState() => _WorkoutSummaryScreenState();
}

class _WorkoutSummaryScreenState extends State<WorkoutSummaryScreen> {
  late Future<String> _feedback;

  @override
  void initState() {
    super.initState();
    _feedback = context.read<AppState>().workoutFeedback(widget.log['id'].toString());
  }

  @override
  Widget build(BuildContext context) {
    final log = widget.log;
    final type = log['dayType']?.toString();
    final color = dayTypeColor(type);
    final exercises = asMapList(log['exercises']).where((e) => e['skipped'] != true).toList();
    final sets = exercises.fold<int>(0, (n, e) => n + asMapList(e['sets']).length);
    var volume = 0.0;
    var meters = 0.0;
    var runSec = 0;
    for (final e in exercises) {
      final isRun = exerciseKind({'name': e['name'], 'station': e['station']}) == ExerciseKind.run;
      for (final s in asMapList(e['sets'])) {
        final kg = (s['loadKg'] as num?)?.toDouble() ?? 0;
        volume += kg * ((s['reps'] as num?)?.toDouble() ?? 1);
        if (isRun) {
          meters += (s['distanceM'] as num?)?.toDouble() ?? 0;
          runSec += (s['durationSec'] as num?)?.toInt() ?? 0;
        }
      }
    }
    final text = Theme.of(context).textTheme;

    return Scaffold(
      appBar: AppBar(backgroundColor: color, foregroundColor: Colors.white, title: const Text('Geschafft!')),
      body: ListView(
        padding: EdgeInsets.zero,
        children: [
          Container(
            color: color,
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(log['dayTitle']?.toString() ?? 'Training',
                  style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.w800)),
              Text(germanDate(log['date'].toString()), style: const TextStyle(color: Colors.white70)),
              const SizedBox(height: 16),
              Wrap(spacing: 28, runSpacing: 12, children: [
                _Stat('${log['durationMin'] ?? 0}', 'Minuten'),
                _Stat('$sets', 'Sätze'),
                if (meters > 0) _Stat(formatKm(meters), 'Laufen'),
                if (meters > 0 && formatPace(runSec, meters) != null) _Stat(formatPace(runSec, meters)!, 'Ø Pace'),
                if (volume > 0) _Stat('${volume.round()} kg', 'Volumen'),
                if (log['rpe'] != null) _Stat('${log['rpe']}/10', 'RPE'),
              ]),
            ]),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Card(
              margin: EdgeInsets.zero,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Row(children: [
                    Icon(Icons.sports, color: AppColors.blue),
                    SizedBox(width: 8),
                    Text('Dein Coach', style: TextStyle(fontWeight: FontWeight.w700)),
                  ]),
                  const SizedBox(height: 8),
                  FutureBuilder<String>(
                    future: _feedback,
                    builder: (context, snap) {
                      if (snap.hasData) return Text(snap.data!);
                      if (snap.hasError) {
                        final e = snap.error;
                        return Text(e is ApiException ? 'Kein Feedback möglich: ${e.message}' : 'Kein Feedback möglich.',
                            style: text.bodySmall);
                      }
                      return const Row(children: [
                        SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
                        SizedBox(width: 10),
                        Text('Coach schaut sich dein Training an …'),
                      ]);
                    },
                  ),
                ]),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: FilledButton(
              style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Fertig'),
            ),
          ),
        ],
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat(this.value, this.label);
  final String value;
  final String label;

  @override
  Widget build(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(value, style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w800)),
        Text(label, style: const TextStyle(color: Colors.white70)),
      ]);
}
