import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../util.dart';

/// Ziel bearbeiten: konkrete Rennen (mehrere, mit Priorität), ein Zeithorizont ohne Rennen oder ein offener Aufbau.
/// Arbeitet direkt auf der übergebenen goal-Map und meldet Änderungen über [onChanged].
class GoalEditor extends StatefulWidget {
  const GoalEditor({super.key, required this.goal, required this.onChanged});

  final Map<String, dynamic> goal;
  final VoidCallback onChanged;

  /// Bringt eine goal-Map in die aktuelle Form (Liste der Rennen, Modus, altes Einzel-Renndatum übernommen).
  static void normalize(Map<String, dynamic> goal) {
    final races = asMapList(goal['races']);
    if (races.isEmpty && goal['raceDate'] != null) {
      races.add({
        'name': 'Rennen',
        'date': goal['raceDate'],
        'priority': 'A',
        'category': goal['category'] ?? 'single',
        if (goal['division'] != null) 'division': goal['division'],
        if (goal['targetTime'] != null) 'targetTime': goal['targetTime'],
      });
    }
    goal.remove('raceDate');
    goal['races'] = races;
    goal['mode'] ??= races.isNotEmpty ? 'race' : 'open';
  }

  @override
  State<GoalEditor> createState() => _GoalEditorState();
}

class _GoalEditorState extends State<GoalEditor> {
  Map<String, dynamic> get _goal => widget.goal;
  List<Map<String, dynamic>> get _races => (_goal['races'] as List).cast<Map<String, dynamic>>();

  void _changed() {
    setState(() {});
    widget.onChanged();
  }

  Future<void> _editRace(Map<String, dynamic>? existing) async {
    final result = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _RaceSheet(initial: existing, defaultCategory: _goal['category']?.toString() ?? 'single'),
    );
    if (result == null) return;
    if (existing != null) {
      existing
        ..clear()
        ..addAll(result);
    } else {
      _races.add(result);
    }
    _races.sort((a, b) => a['date'].toString().compareTo(b['date'].toString()));
    _changed();
  }

  @override
  Widget build(BuildContext context) {
    final mode = _goal['mode']?.toString() ?? 'open';
    final text = Theme.of(context).textTheme;
    final horizon = _goal['horizonDate']?.toString();
    final today = isoDate(DateTime.now());

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SegmentedButton<String>(
          segments: const [
            ButtonSegment(value: 'race', label: Text('Rennen'), icon: Icon(Icons.emoji_events_outlined)),
            ButtonSegment(value: 'horizon', label: Text('Zeitraum'), icon: Icon(Icons.date_range)),
            ButtonSegment(value: 'open', label: Text('Offen'), icon: Icon(Icons.all_inclusive)),
          ],
          selected: {mode},
          onSelectionChanged: (s) {
            _goal['mode'] = s.first;
            _changed();
          },
        ),
        const SizedBox(height: 8),
        Text(
          switch (mode) {
            'race' => 'Trag deine Rennen ein. Das Hauptrennen (A) bestimmt den Peak, B- und C-Rennen werden mit kurzem '
                'bzw. ohne Taper eingeplant.',
            'horizon' => 'Kein konkretes Rennen, aber bis zu diesem Datum willst du in Bestform sein. Der Plan baut darauf hin.',
            _ => 'Kein Zeitziel: Der Plan baut dich Schritt für Schritt auf und macht dich fit für Hyrox '
                '(3 Wochen steigern, 1 Woche entlasten).',
          },
          style: text.bodySmall,
        ),
        const SizedBox(height: 12),
        if (mode == 'race') ...[
          for (final r in _races)
            Opacity(
              opacity: r['date'].toString().compareTo(today) < 0 ? 0.5 : 1,
              child: Card(
                margin: const EdgeInsets.only(bottom: 8),
                child: ListTile(
                  leading: CircleAvatar(
                    backgroundColor: AppColors.race.withValues(alpha: r['priority'] == 'A' ? 1 : 0.25),
                    foregroundColor: r['priority'] == 'A' ? Colors.white : AppColors.race,
                    child: Text(r['priority'].toString(), style: const TextStyle(fontWeight: FontWeight.w800)),
                  ),
                  title: Text(r['name'].toString()),
                  subtitle: Text([
                    '${germanDate(r['date'].toString())} ${r['date'].toString().substring(0, 4)}',
                    racePriorityLabels[r['priority']] ?? '',
                    if (r['targetTime'] != null) 'Ziel ${r['targetTime']}',
                  ].join(' · ')),
                  trailing: IconButton(
                    icon: const Icon(Icons.delete_outline),
                    onPressed: () {
                      _races.remove(r);
                      _changed();
                    },
                  ),
                  onTap: () => _editRace(r),
                ),
              ),
            ),
          OutlinedButton.icon(
            icon: const Icon(Icons.add),
            label: const Text('Rennen hinzufügen'),
            onPressed: () => _editRace(null),
          ),
          if (_races.isNotEmpty && !_races.any((r) => r['priority'] == 'A'))
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text('Tipp: Markiere ein Rennen als Hauptrennen (A), damit der Plan darauf den Peak legt.',
                  style: text.bodySmall),
            ),
        ],
        if (mode == 'horizon')
          OutlinedButton.icon(
            icon: const Icon(Icons.event),
            label: Text(horizon == null
                ? 'Bestform bis … wählen'
                : 'Bestform bis ${germanDate(horizon)} ${horizon.substring(0, 4)}'),
            onPressed: () async {
              final picked = await showDatePicker(
                context: context,
                initialDate: horizon == null ? DateTime.now().add(const Duration(days: 120)) : parseIso(horizon),
                firstDate: DateTime.now(),
                lastDate: DateTime.now().add(const Duration(days: 800)),
              );
              if (picked != null) {
                _goal['horizonDate'] = isoDate(picked);
                _changed();
              }
            },
          ),
      ],
    );
  }
}

class _RaceSheet extends StatefulWidget {
  const _RaceSheet({this.initial, required this.defaultCategory});
  final Map<String, dynamic>? initial;
  final String defaultCategory;

  @override
  State<_RaceSheet> createState() => _RaceSheetState();
}

class _RaceSheetState extends State<_RaceSheet> {
  late final _name = TextEditingController(text: widget.initial?['name']?.toString() ?? '');
  late final _division = TextEditingController(text: widget.initial?['division']?.toString() ?? '');
  late final _target = TextEditingController(text: widget.initial?['targetTime']?.toString() ?? '');
  late String? _date = widget.initial?['date']?.toString();
  late String _priority = widget.initial?['priority']?.toString() ?? 'A';
  late String _category = widget.initial?['category']?.toString() ?? widget.defaultCategory;

  @override
  void dispose() {
    _name.dispose();
    _division.dispose();
    _target.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 20, 20, 20 + MediaQuery.of(context).viewInsets.bottom),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(widget.initial == null ? 'Rennen hinzufügen' : 'Rennen bearbeiten',
                style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 12),
            TextField(
              controller: _name,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(labelText: 'Name', hintText: 'z. B. HYROX Hamburg'),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              icon: const Icon(Icons.event),
              label: Text(_date == null ? 'Datum wählen' : '${germanDate(_date!)} ${_date!.substring(0, 4)}'),
              onPressed: () async {
                final picked = await showDatePicker(
                  context: context,
                  initialDate: _date == null ? DateTime.now().add(const Duration(days: 60)) : parseIso(_date!),
                  firstDate: DateTime.now().subtract(const Duration(days: 365)),
                  lastDate: DateTime.now().add(const Duration(days: 800)),
                );
                if (picked != null) setState(() => _date = isoDate(picked));
              },
            ),
            const SizedBox(height: 12),
            SegmentedButton<String>(
              segments: const [
                ButtonSegment(value: 'A', label: Text('A · Haupt')),
                ButtonSegment(value: 'B', label: Text('B · Wichtig')),
                ButtonSegment(value: 'C', label: Text('C · Training')),
              ],
              selected: {_priority},
              onSelectionChanged: (s) => setState(() => _priority = s.first),
            ),
            const SizedBox(height: 12),
            SegmentedButton<String>(
              segments: const [
                ButtonSegment(value: 'single', label: Text('Single')),
                ButtonSegment(value: 'doubles', label: Text('Doubles')),
                ButtonSegment(value: 'relay', label: Text('Relay')),
              ],
              selected: {_category},
              onSelectionChanged: (s) => setState(() => _category = s.first),
            ),
            const SizedBox(height: 12),
            Row(children: [
              Expanded(
                child: TextField(
                  controller: _division,
                  decoration: const InputDecoration(labelText: 'Division', hintText: 'Open, Pro …'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextField(
                  controller: _target,
                  decoration: const InputDecoration(labelText: 'Zielzeit', hintText: '1:25:00'),
                ),
              ),
            ]),
            const SizedBox(height: 16),
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton(
                onPressed: _date == null
                    ? null
                    : () => Navigator.pop(context, {
                          'id': widget.initial?['id'] ?? DateTime.now().microsecondsSinceEpoch.toString(),
                          'name': _name.text.trim().isEmpty ? 'Rennen' : _name.text.trim(),
                          'date': _date,
                          'priority': _priority,
                          'category': _category,
                          if (_division.text.trim().isNotEmpty) 'division': _division.text.trim(),
                          if (_target.text.trim().isNotEmpty) 'targetTime': _target.text.trim(),
                        }),
                child: const Text('Übernehmen'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
