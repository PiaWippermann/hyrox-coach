import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../api/api_client.dart';
import '../state/app_state.dart';
import '../util.dart';

class _SetEntry {
  _SetEntry({int? reps, double? loadKg, double? distanceM, int? durationSec})
      : reps = TextEditingController(text: reps?.toString() ?? ''),
        load = TextEditingController(text: loadKg == null ? '' : _fmt(loadKg)),
        distance = TextEditingController(text: distanceM == null ? '' : _fmt(distanceM)),
        duration = TextEditingController(text: durationSec?.toString() ?? '');

  final TextEditingController reps;
  final TextEditingController load;
  final TextEditingController distance;
  final TextEditingController duration;
  bool done = false;

  static String _fmt(double d) => d == d.roundToDouble() ? d.round().toString() : d.toString();

  void dispose() {
    reps.dispose();
    load.dispose();
    distance.dispose();
    duration.dispose();
  }

  Map<String, dynamic> toJson() {
    double? d(String s) => double.tryParse(s.trim().replaceAll(',', '.'));
    return {
      'reps': int.tryParse(reps.text.trim()),
      'loadKg': d(load.text),
      'distanceM': d(distance.text),
      'durationSec': int.tryParse(duration.text.trim()),
    };
  }
}

class _ExerciseEntry {
  _ExerciseEntry(this.data, this.blockName) {
    final sets = (data['sets'] as num?)?.round() ?? 1;
    for (var i = 0; i < sets; i++) {
      this.sets.add(_SetEntry(
        reps: (data['reps'] as num?)?.round(),
        loadKg: (data['loadKg'] as num?)?.toDouble(),
        distanceM: (data['distanceM'] as num?)?.toDouble(),
        durationSec: (data['durationSec'] as num?)?.round(),
      ));
    }
  }

  final Map<String, dynamic> data;
  final String blockName;
  final List<_SetEntry> sets = [];
  bool skipped = false;

  String get name => data['name'].toString();
}

class WorkoutScreen extends StatefulWidget {
  const WorkoutScreen({super.key, required this.day, required this.variant, required this.planId});

  final Map<String, dynamic> day;
  final Map<String, dynamic> variant;
  final String planId;

  @override
  State<WorkoutScreen> createState() => _WorkoutScreenState();
}

class _WorkoutScreenState extends State<WorkoutScreen> {
  final List<_ExerciseEntry> _exercises = [];
  final DateTime _startedAt = DateTime.now();
  late final Stream<int> _ticker;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _ticker = Stream.periodic(const Duration(seconds: 1), (i) => i);
    for (final block in asMapList(widget.variant['blocks'])) {
      for (final ex in asMapList(block['exercises'])) {
        _exercises.add(_ExerciseEntry(ex, block['name'].toString()));
      }
    }
  }

  @override
  void dispose() {
    for (final e in _exercises) {
      for (final s in e.sets) {
        s.dispose();
      }
    }
    super.dispose();
  }

  Future<void> _finish() async {
    var rpe = 7.0;
    final notes = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          title: const Text('Training beenden'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Wie anstrengend war es? RPE ${rpe.round()} von 10'),
              Slider(value: rpe, min: 1, max: 10, divisions: 9, onChanged: (v) => setLocal(() => rpe = v)),
              TextField(
                controller: notes,
                maxLines: 3,
                decoration: const InputDecoration(labelText: 'Notizen (optional)', border: OutlineInputBorder()),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Zurück')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Speichern')),
          ],
        ),
      ),
    );
    final noteText = notes.text.trim();
    notes.dispose();
    if (confirmed != true || !mounted) return;

    final finished = DateTime.now();
    final exercises = _exercises.map((e) {
      final doneSets = e.sets.where((s) => s.done).map((s) => s.toJson()).toList();
      return {
        'name': e.name,
        if (e.data['station'] != null) 'station': e.data['station'],
        'skipped': e.skipped || doneSets.isEmpty,
        'sets': doneSets,
      };
    }).toList();

    setState(() => _saving = true);
    try {
      await context.read<AppState>().postWorkout({
        'date': isoDate(_startedAt),
        'planId': widget.planId,
        'dayTitle': widget.day['title'],
        'location': widget.variant['location'],
        'startedAt': _startedAt.toUtc().toIso8601String(),
        'finishedAt': finished.toUtc().toIso8601String(),
        'durationMin': finished.difference(_startedAt).inMinutes,
        'rpe': rpe.round(),
        if (noteText.isNotEmpty) 'notes': noteText,
        'exercises': exercises,
      });
      if (!mounted) return;
      Navigator.of(context).popUntil((r) => r.isFirst);
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Training gespeichert.')));
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  Future<bool> _confirmLeave() async {
    final leave = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Training abbrechen?'),
        content: const Text('Nicht gespeicherte Eingaben gehen verloren.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Weitermachen')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Abbrechen')),
        ],
      ),
    );
    return leave == true;
  }

  @override
  Widget build(BuildContext context) {
    String? lastBlock;
    return PopScope(
      canPop: false,
      onPopInvoked: (didPop) async {
        if (didPop) return;
        final leave = await _confirmLeave();
        if (leave && context.mounted) Navigator.of(context).pop();
      },
      child: Scaffold(
        appBar: AppBar(
          title: StreamBuilder<int>(
            stream: _ticker,
            builder: (_, __) {
              final s = DateTime.now().difference(_startedAt).inSeconds;
              return Text('${widget.day['title']}  ·  ${formatSec(s)}');
            },
          ),
        ),
        body: ListView(
          padding: const EdgeInsets.all(12),
          children: [
            for (var i = 0; i < _exercises.length; i++) ...[
              if (_exercises[i].blockName != lastBlock)
                Padding(
                  padding: const EdgeInsets.fromLTRB(4, 12, 4, 4),
                  child: Text((lastBlock = _exercises[i].blockName), style: Theme.of(context).textTheme.titleMedium),
                ),
              _ExerciseCard(
                entry: _exercises[i],
                onChanged: () => setState(() {}),
              ),
            ],
            const SizedBox(height: 16),
            FilledButton.icon(
              icon: _saving
                  ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.flag),
              label: const Text('Training beenden'),
              onPressed: _saving ? null : _finish,
            ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }
}

class _ExerciseCard extends StatelessWidget {
  const _ExerciseCard({required this.entry, required this.onChanged});

  final _ExerciseEntry entry;
  final VoidCallback onChanged;

  Widget _field(TextEditingController c, String label, {bool decimal = false}) {
    return SizedBox(
      width: 74,
      child: TextField(
        controller: c,
        enabled: !entry.skipped,
        keyboardType: TextInputType.numberWithOptions(decimal: decimal),
        decoration: InputDecoration(labelText: label, isDense: true, border: const OutlineInputBorder()),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final plan = describeExercise(entry.data);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(entry.name, style: Theme.of(context).textTheme.titleSmall),
                      if (plan.isNotEmpty) Text(plan, style: Theme.of(context).textTheme.bodySmall),
                      if (entry.data['notes'] != null)
                        Text(entry.data['notes'].toString(), style: Theme.of(context).textTheme.bodySmall),
                    ],
                  ),
                ),
                TextButton(
                  onPressed: () {
                    entry.skipped = !entry.skipped;
                    onChanged();
                  },
                  child: Text(entry.skipped ? 'Doch machen' : 'Überspringen'),
                ),
              ],
            ),
            if (!entry.skipped) ...[
              for (var i = 0; i < entry.sets.length; i++)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Row(
                    children: [
                      Checkbox(
                        value: entry.sets[i].done,
                        onChanged: (v) {
                          entry.sets[i].done = v ?? false;
                          onChanged();
                        },
                      ),
                      Wrap(
                        spacing: 6,
                        children: [
                          _field(entry.sets[i].reps, 'Wdh.'),
                          _field(entry.sets[i].load, 'kg', decimal: true),
                          _field(entry.sets[i].distance, 'm', decimal: true),
                          _field(entry.sets[i].duration, 'Sek.'),
                        ],
                      ),
                    ],
                  ),
                ),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  icon: const Icon(Icons.add),
                  label: const Text('Satz hinzufügen'),
                  onPressed: () {
                    final last = entry.sets.isNotEmpty ? entry.sets.last : null;
                    final s = _SetEntry();
                    if (last != null) {
                      s.reps.text = last.reps.text;
                      s.load.text = last.load.text;
                      s.distance.text = last.distance.text;
                      s.duration.text = last.duration.text;
                    }
                    entry.sets.add(s);
                    onChanged();
                  },
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
