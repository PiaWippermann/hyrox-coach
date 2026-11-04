import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../api/api_client.dart';
import '../state/active_workout.dart';
import '../state/app_state.dart';
import '../util.dart';
import 'run_tracker_screen.dart';
import 'workout_summary_screen.dart';
import '../theme/app_colors.dart';

/// Laufendes Training. Der Zustand liegt in AppState.active und wird bei jeder Änderung gespeichert:
/// Zurück führt nur zur Übersicht, das Training läuft weiter. Es endet erst mit „Beenden“ oder „Abbrechen“.
class WorkoutScreen extends StatefulWidget {
  const WorkoutScreen({super.key});

  @override
  State<WorkoutScreen> createState() => _WorkoutScreenState();
}

/// Textfelder eines Satzes. Sie schreiben jede Eingabe direkt ins Modell.
class _SetControllers {
  _SetControllers(ActiveSet s, VoidCallback onEdit)
      : reps = TextEditingController(text: s.reps),
        load = TextEditingController(text: s.load),
        distance = TextEditingController(text: s.distance),
        time = TextEditingController(text: s.time) {
    reps.addListener(() => _sync(s, onEdit));
    load.addListener(() => _sync(s, onEdit));
    distance.addListener(() => _sync(s, onEdit));
    time.addListener(() => _sync(s, onEdit));
  }

  final TextEditingController reps;
  final TextEditingController load;
  final TextEditingController distance;
  final TextEditingController time;

  void _sync(ActiveSet s, VoidCallback onEdit) {
    if (s.reps == reps.text && s.load == load.text && s.distance == distance.text && s.time == time.text) return;
    s
      ..reps = reps.text
      ..load = load.text
      ..distance = distance.text
      ..time = time.text;
    onEdit();
  }

  /// Übernimmt Werte, die außerhalb geändert wurden (z. B. vom Lauf-Timer).
  void pull(ActiveSet s) {
    if (reps.text != s.reps) reps.text = s.reps;
    if (load.text != s.load) load.text = s.load;
    if (distance.text != s.distance) distance.text = s.distance;
    if (time.text != s.time) time.text = s.time;
  }

  void dispose() {
    reps.dispose();
    load.dispose();
    distance.dispose();
    time.dispose();
  }
}

class _WorkoutScreenState extends State<WorkoutScreen> {
  final Map<ActiveSet, _SetControllers> _controllers = {};
  late final AppState _state;
  Timer? _ticker;
  Timer? _saveDebounce;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _state = context.read<AppState>();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    if (_saveDebounce?.isActive ?? false) {
      _saveDebounce!.cancel();
      _state.saveActive(notify: false); // letzte Eingabe nicht verlieren
    }
    for (final c in _controllers.values) {
      c.dispose();
    }
    super.dispose();
  }


  _SetControllers _ctrl(ActiveSet s) => _controllers.putIfAbsent(s, () => _SetControllers(s, _onEdit));

  void _onEdit() {
    _saveDebounce?.cancel();
    _saveDebounce = Timer(const Duration(milliseconds: 400), () => _state.saveActive(notify: false));
  }

  Future<void> _changed() async {
    setState(() {});
    await _state.saveActive();
  }

  Future<void> _openRun(ActiveWorkout w, int index) async {
    if (w.run != null && w.run!.exercise != index) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Es läuft schon ein Lauf: ${w.exercises[w.run!.exercise].name}.')),
      );
      return;
    }
    await Navigator.of(context).push(
      MaterialPageRoute(fullscreenDialog: true, builder: (_) => RunTrackerScreen(exerciseIndex: index)),
    );
    if (!mounted) return;
    for (final s in w.exercises[index].sets) {
      _controllers[s]?.pull(s);
    }
    setState(() {});
  }

  Future<void> _finish(ActiveWorkout w) async {
    if (w.run != null && w.run!.phase != 'done') {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Bitte zuerst den laufenden Lauf beenden.')),
      );
      return;
    }
    final result = await showModalBottomSheet<_FinishResult>(
      context: context,
      isScrollControlled: true,
      builder: (_) => const _FinishSheet(),
    );
    if (result == null || !mounted) return;

    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _saving = true);
    try {
      final log = await _state.finishActive(rpe: result.rpe, notes: result.notes);
      navigator.popUntil((r) => r.isFirst);
      navigator.push(MaterialPageRoute(builder: (_) => WorkoutSummaryScreen(log: log)));
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      messenger.showSnackBar(SnackBar(content: Text('${e.message} – das Training läuft weiter, versuch es gleich nochmal.')));
    }
  }

  Future<void> _cancel() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Training abbrechen?'),
        content: const Text('Das Training wird verworfen und nicht gespeichert.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Weitermachen')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: Theme.of(ctx).colorScheme.error),
            child: const Text('Verwerfen'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    final navigator = Navigator.of(context);
    await _state.cancelActive();
    navigator.popUntil((r) => r.isFirst);
  }

  @override
  Widget build(BuildContext context) {
    final w = context.watch<AppState>().active;
    if (w == null) {
      // Training wurde beendet, während der Screen noch offen war
      return Scaffold(appBar: AppBar(), body: const Center(child: Text('Kein laufendes Training.')));
    }
    final color = dayTypeColor(w.day['dayType']?.toString());
    String? lastBlock;

    return Scaffold(
      appBar: AppBar(
        backgroundColor: color,
        foregroundColor: Colors.white,
        title: Text(w.title, overflow: TextOverflow.ellipsis),
        actions: [
          TextButton(
            onPressed: _saving ? null : _cancel,
            style: TextButton.styleFrom(foregroundColor: Colors.white),
            child: const Text('Abbrechen'),
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(56),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: Row(
              children: [
                const Icon(Icons.timer_outlined, color: Colors.white70),
                const SizedBox(width: 6),
                Text(formatSec(w.elapsedSec),
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 24,
                      fontWeight: FontWeight.w700,
                      fontFeatures: [FontFeature.tabularFigures()],
                    )),
                const Spacer(),
                Text('${w.doneSets} / ${w.totalSets} erledigt', style: const TextStyle(color: Colors.white)),
              ],
            ),
          ),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
        children: [
          for (var i = 0; i < w.exercises.length; i++) ...[
            if (w.exercises[i].blockName != lastBlock)
              Padding(
                padding: const EdgeInsets.fromLTRB(4, 12, 4, 6),
                child: Text((lastBlock = w.exercises[i].blockName).toUpperCase(),
                    style: Theme.of(context).textTheme.labelLarge?.copyWith(letterSpacing: 0.8)),
              ),
            _ExerciseCard(
              entry: w.exercises[i],
              runActive: w.run?.exercise == i && w.run!.phase != 'done',
              controllers: _ctrl,
              onChanged: _changed,
              onStartRun: () => _openRun(w, i),
            ),
          ],
          const SizedBox(height: 16),
          FilledButton.icon(
            style: FilledButton.styleFrom(backgroundColor: color, minimumSize: const Size.fromHeight(52)),
            icon: _saving
                ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : const Icon(Icons.flag),
            label: const Text('Training beenden'),
            onPressed: _saving ? null : () => _finish(w),
          ),
        ],
      ),
    );
  }
}

class _ExerciseCard extends StatelessWidget {
  const _ExerciseCard({
    required this.entry,
    required this.runActive,
    required this.controllers,
    required this.onChanged,
    required this.onStartRun,
  });

  final ActiveExercise entry;
  final bool runActive;
  final _SetControllers Function(ActiveSet) controllers;
  final VoidCallback onChanged;
  final VoidCallback onStartRun;

  String? _previousFor(int i) {
    if (i >= entry.previous.length) return null;
    final p = entry.previous[i];
    final kg = p['loadKg'] as num?;
    final reps = p['reps'] as num?;
    final dist = p['distanceM'] as num?;
    final sec = p['durationSec'] as num?;
    switch (entry.kind) {
      case ExerciseKind.weighted:
        if (kg == null && reps == null) return null;
        return '${kg == null ? '–' : fmtNum(kg.toDouble())} × ${reps ?? '–'}';
      case ExerciseKind.bodyweight:
        return reps?.toString();
      case ExerciseKind.run:
        return sec == null ? null : formatPace(sec.round(), dist?.toDouble()) ?? formatSec(sec.round());
      case ExerciseKind.cardio:
      case ExerciseKind.timed:
        return sec == null ? null : formatSec(sec.round());
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final plan = describeExercise(entry.data);
    final isRun = entry.kind == ExerciseKind.run;

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: entry.allDone ? const BorderSide(color: AppColors.success, width: 1.5) : BorderSide.none,
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 10, 6, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(children: [
                        Flexible(child: Text(entry.name, style: text.titleMedium?.copyWith(fontWeight: FontWeight.w700))),
                        if (_benchmark) ...[
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(color: AppColors.race, borderRadius: BorderRadius.circular(6)),
                            child: const Text('BENCHMARK',
                                style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w800)),
                          ),
                        ],
                      ]),
                      if (plan.isNotEmpty) Text(plan, style: text.bodySmall),
                      if (entry.data['notes'] != null) Text(entry.data['notes'].toString(), style: text.bodySmall),
                    ],
                  ),
                ),
                PopupMenuButton<String>(
                  onSelected: (v) {
                    if (v == 'skip') entry.skipped = !entry.skipped;
                    onChanged();
                  },
                  itemBuilder: (_) => [
                    PopupMenuItem(value: 'skip', child: Text(entry.skipped ? 'Doch machen' : 'Überspringen')),
                  ],
                ),
              ],
            ),
            if (entry.skipped)
              Padding(
                padding: const EdgeInsets.only(top: 4, bottom: 4),
                child: Text('Übersprungen', style: text.bodySmall?.copyWith(color: scheme.outline)),
              )
            else ...[
              if (isRun)
                Padding(
                  padding: const EdgeInsets.only(top: 8, right: 8),
                  child: FilledButton.tonalIcon(
                    style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(44)),
                    icon: Icon(runActive ? Icons.directions_run : Icons.play_arrow),
                    label: Text(runActive
                        ? 'Lauf läuft – öffnen'
                        : (entry.sets.length > 1 ? '${entry.sets.length} Intervalle starten' : 'Lauf starten')),
                    onPressed: onStartRun,
                  ),
                ),
              const SizedBox(height: 6),
              _headerRow(context),
              for (var i = 0; i < entry.sets.length; i++) _setRow(context, i),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  icon: const Icon(Icons.add, size: 18),
                  label: Text(isRun ? 'Intervall hinzufügen' : 'Satz hinzufügen'),
                  onPressed: () {
                    entry.sets.add(entry.sets.isNotEmpty ? entry.sets.last.copy() : ActiveSet());
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

  bool get _benchmark => entry.data['benchmark'] == true;

  /// Benchmark-Tests brauchen immer eine Zeit, auch bei Kraft- oder Wiederholungsübungen.
  bool get _extraTime => _benchmark && (entry.kind == ExerciseKind.weighted || entry.kind == ExerciseKind.bodyweight);
  double get _fieldWidth => _extraTime && entry.kind == ExerciseKind.weighted ? 62 : 72;

  List<String> get _columns => [
        ...switch (entry.kind) {
          ExerciseKind.weighted => ['kg', 'Wdh.'],
          ExerciseKind.bodyweight => ['Wdh.'],
          ExerciseKind.run => ['km', 'Zeit'],
          ExerciseKind.cardio => ['Meter', 'Zeit'],
          ExerciseKind.timed => ['Zeit'],
        },
        if (_extraTime) 'Zeit',
      ];

  Widget _headerRow(BuildContext context) {
    final style = Theme.of(context).textTheme.labelSmall?.copyWith(color: Theme.of(context).colorScheme.outline);
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: Row(
        children: [
          SizedBox(width: 36, child: Text(entry.kind == ExerciseKind.run ? '#' : 'Satz', style: style)),
          Expanded(child: Text('Vorher', style: style)),
          for (final c in _columns) SizedBox(width: _fieldWidth, child: Center(child: Text(c, style: style))),
          const SizedBox(width: 48),
        ],
      ),
    );
  }

  Widget _setRow(BuildContext context, int i) {
    final s = entry.sets[i];
    final c = controllers(s);
    final scheme = Theme.of(context).colorScheme;
    final fields = [
      ...switch (entry.kind) {
        ExerciseKind.weighted => [(c.load, true), (c.reps, false)],
        ExerciseKind.bodyweight => [(c.reps, false)],
        ExerciseKind.run || ExerciseKind.cardio => [(c.distance, true), (c.time, false)],
        ExerciseKind.timed => [(c.time, false)],
      },
      if (_extraTime) (c.time, false),
    ];

    return Container(
      margin: const EdgeInsets.only(top: 4, right: 8),
      decoration: BoxDecoration(
        color: s.done ? AppColors.success.withValues(alpha: 0.12) : null,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 36,
            child: Text('${i + 1}', style: const TextStyle(fontWeight: FontWeight.w700), textAlign: TextAlign.center),
          ),
          Expanded(
            child: Text(_previousFor(i) ?? '–', style: TextStyle(color: scheme.outline, fontSize: 13)),
          ),
          for (final (controller, decimal) in fields)
            SizedBox(
              width: _fieldWidth,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: TextField(
                  controller: controller,
                  textAlign: TextAlign.center,
                  keyboardType: controller == c.time
                      ? TextInputType.datetime
                      : TextInputType.numberWithOptions(decimal: decimal),
                  style: const TextStyle(fontWeight: FontWeight.w600),
                  decoration: InputDecoration(
                    isDense: true,
                    filled: true,
                    fillColor: scheme.surfaceContainerHighest,
                    hintText: controller == c.time ? 'mm:ss' : null,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
                    contentPadding: const EdgeInsets.symmetric(vertical: 8),
                  ),
                ),
              ),
            ),
          SizedBox(
            width: 48,
            child: IconButton(
              onPressed: () {
                HapticFeedback.lightImpact();
                s.done = !s.done;
                onChanged();
              },
              icon: Icon(
                s.done ? Icons.check_box : Icons.check_box_outline_blank,
                color: s.done ? AppColors.success : scheme.outline,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _FinishResult {
  const _FinishResult(this.rpe, this.notes);
  final int rpe;
  final String notes;
}

/// Eigenes Widget, damit der Notiz-Controller sauber mit dem Sheet entsorgt wird.
class _FinishSheet extends StatefulWidget {
  const _FinishSheet();

  @override
  State<_FinishSheet> createState() => _FinishSheetState();
}

class _FinishSheetState extends State<_FinishSheet> {
  double _rpe = 7;
  final _notes = TextEditingController();

  static const _rpeLabels = {
    1: 'Sehr locker', 3: 'Locker', 5: 'Moderat', 7: 'Hart', 9: 'Sehr hart', 10: 'Maximal',
  };

  @override
  void dispose() {
    _notes.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final rpe = _rpe.round();
    final label = _rpeLabels.entries.lastWhere((e) => e.key <= rpe).value;
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 20, 20, 20 + MediaQuery.of(context).viewInsets.bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Training beenden', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 16),
          Text('Wie anstrengend war es?  $rpe/10 · $label'),
          Slider(value: _rpe, min: 1, max: 10, divisions: 9, onChanged: (v) => setState(() => _rpe = v)),
          TextField(
            controller: _notes,
            maxLines: 3,
            decoration: const InputDecoration(
              labelText: 'Wie lief es? (optional)',
              hintText: 'z. B. Sled lief gut, Wall Balls zäh',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 16),
          SafeArea(
            top: false,
            child: Row(
              children: [
                TextButton(onPressed: () => Navigator.pop(context), child: const Text('Zurück')),
                const Spacer(),
                FilledButton(
                  onPressed: () => Navigator.pop(context, _FinishResult(rpe, _notes.text.trim())),
                  child: const Text('Speichern'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
