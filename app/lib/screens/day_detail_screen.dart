import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../api/api_client.dart';
import '../state/app_state.dart';
import '../util.dart';
import 'workout_screen.dart';

/// Tagesansicht: hier wählt man pro Trainingstag zwischen Gym- und Home-Variante.
/// Beide Varianten stecken schon im Plan, die Auswahl braucht keinen KI-Aufruf.
class DayDetailScreen extends StatefulWidget {
  const DayDetailScreen({super.key, required this.day, required this.planId});

  final Map<String, dynamic> day;
  final String planId;

  @override
  State<DayDetailScreen> createState() => _DayDetailScreenState();
}

class _DayDetailScreenState extends State<DayDetailScreen> {
  late String _location;

  /// Aktueller Stand des Tages aus dem Plan (kann sich durch den Coach-Chat ändern), sonst der übergebene Tag.
  Map<String, dynamic> get _day {
    final date = widget.day['date'];
    for (final w in asMapList(context.read<AppState>().plan?['weeks'])) {
      for (final d in asMapList(w['days'])) {
        if (d['date'] == date) return d;
      }
    }
    return widget.day;
  }

  List<Map<String, dynamic>> get _variants => asMapList(_day['variants']);

  @override
  void initState() {
    super.initState();
    // Tage ohne Variante (Ruhetag, Renntag) zeigt build() als Hinweis an
    _location = _variants.isEmpty ? 'gym' : _variants.first['location'].toString();
  }

  Map<String, dynamic> get _selected =>
      _variants.firstWhere((v) => v['location'] == _location, orElse: () => _variants.first);

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final blocks = asMapList(_selected['blocks']);
    if (_variants.isEmpty) {
      // Der Coach hat den Tag zum Ruhetag gemacht
      return Scaffold(
        appBar: AppBar(title: Text(germanDate(_day['date'].toString()))),
        body: const Center(child: Text('An diesem Tag ist kein Training mehr geplant.')),
      );
    }
    if (!_variants.any((v) => v['location'] == _location)) _location = _variants.first['location'].toString();
    final both = _variants.length > 1;
    final type = _day['dayType'].toString();
    final color = dayTypeColor(type);
    final meters = plannedRunMeters(_day, _location);
    final text = Theme.of(context).textTheme;
    final isRun = type == 'run';

    return Scaffold(
      appBar: AppBar(
        backgroundColor: color,
        foregroundColor: Colors.white,
        title: Text(germanDate(_day['date'].toString())),
        actions: [
          IconButton(
            tooltip: 'Einheit anpassen',
            icon: const Icon(Icons.edit_note),
            onPressed: () => showModalBottomSheet<void>(
              context: context,
              isScrollControlled: true,
              builder: (_) => _AdjustSheet(day: _day),
            ),
          ),
        ],
      ),
      body: ListView(
        padding: EdgeInsets.zero,
        children: [
          Container(
            color: color,
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  Icon(dayTypeIcon(type), color: Colors.white70, size: 18),
                  const SizedBox(width: 6),
                  Text((dayTypeLabels[type] ?? type).toUpperCase(),
                      style: const TextStyle(color: Colors.white70, fontWeight: FontWeight.w700, letterSpacing: 0.8)),
                ]),
                const SizedBox(height: 6),
                Text(_day['title'].toString(),
                    style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.w700)),
                const SizedBox(height: 12),
                Row(children: [
                  _HeaderStat(value: '${_day['durationMin']}', unit: 'Min'),
                  if (meters != null) _HeaderStat(value: formatKm(meters).replaceAll(' km', ''), unit: 'km'),
                  _HeaderStat(value: '${blocks.length}', unit: 'Blöcke'),
                ]),
                if (_day['intent'] != null) ...[
                  const SizedBox(height: 12),
                  Text(_day['intent'].toString(), style: const TextStyle(color: Colors.white)),
                ],
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: both
                ? SegmentedButton<String>(
                    segments: const [
                      ButtonSegment(value: 'gym', label: Text('Gym'), icon: Icon(Icons.fitness_center)),
                      ButtonSegment(value: 'home', label: Text('Zuhause'), icon: Icon(Icons.home)),
                    ],
                    selected: {_location},
                    onSelectionChanged: (s) => setState(() => _location = s.first),
                  )
                : Row(children: [
                    Icon(_location == 'gym' ? Icons.fitness_center : Icons.home, size: 18),
                    const SizedBox(width: 6),
                    Text(_location == 'gym' ? 'Im Gym' : 'Zuhause'),
                  ]),
          ),
          for (final block in blocks)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: Card(
                margin: EdgeInsets.zero,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(children: [
                        Expanded(child: Text(block['name'].toString(), style: text.titleMedium)),
                        if (block['rounds'] != null && block['rounds'] != 1)
                          Chip(label: Text('${block['rounds']} Runden'), visualDensity: VisualDensity.compact),
                      ]),
                      if (block['notes'] != null)
                        Text(block['notes'].toString(), style: text.bodySmall),
                      for (final ex in asMapList(block['exercises']))
                        _ExerciseRow(ex: ex, lastSets: state.lastSetsFor(ex['name'].toString())),
                    ],
                  ),
                ),
              ),
            ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
              child: _StartButton(day: _day, variant: _selected, planId: widget.planId, color: color, isRun: isRun),
            ),
          ),
        ],
      ),
    );
  }
}

/// Start, Fortsetzen oder Hinweis, dass schon ein anderes Training läuft.
class _StartButton extends StatelessWidget {
  const _StartButton({
    required this.day,
    required this.variant,
    required this.planId,
    required this.color,
    required this.isRun,
  });

  final Map<String, dynamic> day;
  final Map<String, dynamic> variant;
  final String planId;
  final Color color;
  final bool isRun;

  void _open(BuildContext context) =>
      Navigator.of(context).push(MaterialPageRoute(builder: (_) => const WorkoutScreen()));

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final active = state.active;
    final style = FilledButton.styleFrom(backgroundColor: color, minimumSize: const Size.fromHeight(52));

    if (active != null && active.date == day['date'] && active.title == day['title']) {
      return FilledButton.icon(
        style: style,
        icon: const Icon(Icons.play_circle),
        label: Text('Training fortsetzen (${formatSec(active.elapsedSec)})'),
        onPressed: () => _open(context),
      );
    }

    if (active != null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Es läuft bereits ein Training: ${active.title}. Beende oder verwirf es, bevor du ein neues startest.',
              style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(52)),
            icon: const Icon(Icons.directions_run),
            label: const Text('Zum laufenden Training'),
            onPressed: () => _open(context),
          ),
        ],
      );
    }

    return FilledButton.icon(
      style: style,
      icon: Icon(isRun ? Icons.directions_run : Icons.play_arrow),
      label: Text(isRun ? 'Lauf starten' : 'Training starten'),
      onPressed: () async {
        await context.read<AppState>().startWorkout(day, variant, planId);
        if (context.mounted) _open(context);
      },
    );
  }
}

class _HeaderStat extends StatelessWidget {
  const _HeaderStat({required this.value, required this.unit});

  final String value;
  final String unit;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 24),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.baseline,
        textBaseline: TextBaseline.alphabetic,
        children: [
          Text(value, style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w700)),
          const SizedBox(width: 4),
          Text(unit, style: const TextStyle(color: Colors.white70)),
        ],
      ),
    );
  }
}

class _ExerciseRow extends StatelessWidget {
  const _ExerciseRow({required this.ex, required this.lastSets});

  final Map<String, dynamic> ex;
  final List<Map<String, dynamic>> lastSets;

  @override
  Widget build(BuildContext context) {
    final kind = exerciseKind(ex);
    final icon = switch (kind) {
      ExerciseKind.run => Icons.directions_run,
      ExerciseKind.cardio => Icons.rowing,
      ExerciseKind.weighted => Icons.fitness_center,
      ExerciseKind.bodyweight => Icons.accessibility_new,
      ExerciseKind.timed => Icons.timer_outlined,
    };
    final lastKg = lastSets.map((s) => s['loadKg']).whereType<num>().fold<num?>(null, (m, v) => m == null || v > m ? v : m);
    final hint = kind == ExerciseKind.weighted && ex['loadKg'] == null && lastKg != null
        ? 'Zuletzt: ${lastKg.toString().replaceAll('.0', '')} kg'
        : null;

    return ListTile(
      dense: true,
      contentPadding: EdgeInsets.zero,
      leading: Icon(icon, size: 20),
      minLeadingWidth: 24,
      title: Text(ex['name'].toString()),
      subtitle: Text([
        describeExercise(ex),
        if (hint != null) hint,
        if (ex['notes'] != null) ex['notes'].toString(),
      ].where((s) => s.isNotEmpty).join('\n')),
    );
  }
}


/// Wunsch zu genau dieser Einheit an den Coach schicken („ich hätte gerne Übung XY drin“).
/// Läuft über den Coach-Chat, damit der Verlauf dort sichtbar bleibt.
class _AdjustSheet extends StatefulWidget {
  const _AdjustSheet({required this.day});
  final Map<String, dynamic> day;

  @override
  State<_AdjustSheet> createState() => _AdjustSheetState();
}

class _AdjustSheetState extends State<_AdjustSheet> {
  final _input = TextEditingController();
  bool _sending = false;
  String? _reply;
  String? _error;

  static const _suggestions = [
    'Bitte Wall Balls einbauen',
    'Mehr Oberkörper',
    'Kürzer, maximal 30 Minuten',
    'Ohne Sprünge',
    'Lieber Kettlebell statt Langhantel',
  ];

  @override
  void dispose() {
    _input.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final text = _input.text.trim();
    if (text.isEmpty) return;
    setState(() {
      _sending = true;
      _error = null;
    });
    try {
      final reply = await context.read<AppState>().sendChat(
            '[Einheit am ${widget.day['date']} „${widget.day['title']}“] $text',
          );
      if (mounted) setState(() => _reply = reply['text']?.toString());
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 20, 20, 20 + MediaQuery.of(context).viewInsets.bottom),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Einheit anpassen', style: text.titleLarge),
            Text('${germanDate(widget.day['date'].toString())} · ${widget.day['title']}', style: text.bodySmall),
            const SizedBox(height: 12),
            if (_reply != null) ...[
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(_reply!),
              ),
              const SizedBox(height: 12),
              Align(
                alignment: Alignment.centerRight,
                child: FilledButton(onPressed: () => Navigator.pop(context), child: const Text('Fertig')),
              ),
            ] else ...[
              Wrap(spacing: 6, runSpacing: 4, children: [
                for (final s in _suggestions)
                  ActionChip(label: Text(s), onPressed: _sending ? null : () => setState(() => _input.text = s)),
              ]),
              const SizedBox(height: 12),
              TextField(
                controller: _input,
                autofocus: true,
                minLines: 2,
                maxLines: 4,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(
                  labelText: 'Was soll anders sein?',
                  hintText: 'z. B. Ich hätte gerne Klimmzüge und Sled Pull drin',
                ),
              ),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
                ),
              const SizedBox(height: 12),
              Row(children: [
                if (_sending) ...[
                  const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
                  const SizedBox(width: 10),
                  const Expanded(child: Text('Coach passt die Einheit an …')),
                ] else
                  const Spacer(),
                FilledButton.icon(
                  icon: const Icon(Icons.auto_fix_high),
                  label: const Text('Anpassen'),
                  onPressed: _sending ? null : _send,
                ),
              ]),
            ],
          ],
        ),
      ),
    );
  }
}
