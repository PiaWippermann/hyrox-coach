import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../api/api_client.dart';
import '../state/app_state.dart';
import '../util.dart';

const _stationKeys = {
  'skierg': 'SkiErg',
  'sled_push': 'Sled Push',
  'sled_pull': 'Sled Pull',
  'burpee_broad_jump': 'Burpee Broad Jumps',
  'rowing': 'Rudern',
  'farmers_carry': 'Farmers Carry',
  'sandbag_lunges': 'Sandbag Lunges',
  'wall_balls': 'Wall Balls',
};

const _ratingKeys = {
  'running': 'Laufen',
  'strength': 'Kraft',
  'endurance': 'Grundlagenausdauer',
  ..._stationKeys,
};

const _stationNames = [
  'SkiErg', 'Sled Push', 'Sled Pull', 'Burpee Broad Jumps',
  'Rudern', 'Farmers Carry', 'Sandbag Lunges', 'Wall Balls',
];

const _homeEquipment = [
  'Kettlebell', 'Kurzhanteln', 'Klimmzugstange', 'Widerstandsbänder', 'Springseil',
  'Laufband', 'Rad/Bike', 'Wall Ball / Medizinball', 'Sandbag', 'Rudergerät', 'SkiErg',
];

const _gymEquipment = [
  'Langhantel', 'Kurzhanteln', 'Kettlebells', 'Sled', 'SkiErg', 'Rudergerät', 'Assault Bike',
  'Laufband', 'Wall Balls', 'Sandbag', 'Klimmzugstange', 'Kabelzug', 'Farmers-Carry-Griffe', 'Plyo-Box',
];

const _steps = [
  'Person', 'Ziel', 'Ergebnisse', 'Selbsteinschätzung', 'Training', 'Equipment', 'Einschränkungen', 'Fokus & Plan',
];

class AnamneseScreen extends StatefulWidget {
  const AnamneseScreen({super.key});

  @override
  State<AnamneseScreen> createState() => _AnamneseScreenState();
}

class _AnamneseScreenState extends State<AnamneseScreen> {
  int _step = 0;
  late Map<String, dynamic> _a;

  // Ergebnis-Eingabe (optional)
  String _eventName = '';
  String _resultDate = '';
  String _roxzone = '';
  final List<String> _runs = List.filled(8, '');
  final List<String> _stations = List.filled(8, '');
  bool _resultSaved = false;

  // Fokus & Plan
  List<Map<String, dynamic>> _suggestions = [];
  final Set<String> _chosen = {};
  String _customFocus = '';
  int _weeks = 4;
  DateTime _startDate = DateTime.now().add(const Duration(days: 1));

  final _customHome = TextEditingController();
  final _customGym = TextEditingController();

  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final existing = context.read<AppState>().anamnese;
    _a = _normalize(existing == null ? <String, dynamic>{} : Map<String, dynamic>.from(existing));
    _chosen.addAll((_a['focusChosen'] as List).map((e) => e.toString()));
  }

  @override
  void dispose() {
    _customHome.dispose();
    _customGym.dispose();
    super.dispose();
  }

  // ---------- Daten-Helfer ----------
  Map<String, dynamic> _normalize(Map<String, dynamic> src) {
    Map<String, dynamic> sub(String k, Map<String, dynamic> fallback) {
      final v = src[k];
      return {...fallback, if (v is Map) ...Map<String, dynamic>.from(v)};
    }

    final selfAssessment = sub('selfAssessment', {'strengthExperience': 'some', 'runnerType': 'balanced'});
    selfAssessment['ratings'] = Map<String, dynamic>.from((selfAssessment['ratings'] as Map?) ?? {});
    final schedule = sub('schedule', {'daysPerWeek': 4});
    schedule['days'] = asMapList(schedule['days']);
    final equipment = sub('equipment', {});
    equipment['home'] = List<dynamic>.from((equipment['home'] as List?) ?? []);
    equipment['gym'] = List<dynamic>.from((equipment['gym'] as List?) ?? []);

    return {
      'profile': sub('profile', {}),
      'goal': sub('goal', {'category': 'single', 'priority': 'improve'}),
      'selfAssessment': selfAssessment,
      'schedule': schedule,
      'equipment': equipment,
      'restrictions': src['restrictions'] ?? '',
      'focusChosen': List<dynamic>.from((src['focusChosen'] as List?) ?? []),
      'focusConfirmed': src['focusConfirmed'] ?? false,
    };
  }

  Map<String, dynamic> get _profile => _a['profile'] as Map<String, dynamic>;
  Map<String, dynamic> get _goal => _a['goal'] as Map<String, dynamic>;
  Map<String, dynamic> get _self => _a['selfAssessment'] as Map<String, dynamic>;
  Map<String, dynamic> get _ratings => _self['ratings'] as Map<String, dynamic>;
  Map<String, dynamic> get _schedule => _a['schedule'] as Map<String, dynamic>;
  List<Map<String, dynamic>> get _days => _schedule['days'] as List<Map<String, dynamic>>;
  Map<String, dynamic> get _equipment => _a['equipment'] as Map<String, dynamic>;

  // ---------- Eingabe-Widgets ----------
  Widget _pad(Widget w) => Padding(padding: const EdgeInsets.only(bottom: 12), child: w);

  Widget _numField(String label, Map<String, dynamic> m, String key, {bool decimal = false, String? suffix}) {
    return _pad(TextFormField(
      key: ValueKey('$label-$_step'),
      initialValue: m[key]?.toString() ?? '',
      decoration: InputDecoration(labelText: label, suffixText: suffix, border: const OutlineInputBorder()),
      keyboardType: TextInputType.numberWithOptions(decimal: decimal),
      onChanged: (v) {
        final t = v.trim().replaceAll(',', '.');
        if (t.isEmpty) {
          m.remove(key);
        } else {
          m[key] = decimal ? double.tryParse(t) : int.tryParse(t);
        }
      },
    ));
  }

  Widget _textField(String label, Map<String, dynamic> m, String key, {int lines = 1, String? hint}) {
    return _pad(TextFormField(
      key: ValueKey('$label-$_step'),
      initialValue: m[key]?.toString() ?? '',
      maxLines: lines,
      decoration: InputDecoration(labelText: label, hintText: hint, border: const OutlineInputBorder()),
      onChanged: (v) => m[key] = v.trim().isEmpty ? null : v.trim(),
    ));
  }

  Widget _title(String t, [String? sub]) => Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(t, style: Theme.of(context).textTheme.titleLarge),
            if (sub != null) Padding(padding: const EdgeInsets.only(top: 4), child: Text(sub)),
          ],
        ),
      );

  // ---------- Schritte ----------
  Widget _stepPerson() => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        _title('Über dich', 'Alles optional. Hilft, den Plan realistischer zu machen.'),
        _numField('Alter', _profile, 'age'),
        _numField('Größe', _profile, 'heightCm', suffix: 'cm'),
        _numField('Gewicht', _profile, 'weightKg', decimal: true, suffix: 'kg'),
      ]);

  Widget _stepGoal() {
    final raceDate = _goal['raceDate']?.toString();
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _title('Dein Ziel'),
      _pad(OutlinedButton.icon(
        icon: const Icon(Icons.event),
        label: Text(raceDate == null ? 'Wettkampftermin wählen (optional)' : 'Wettkampf: ${germanDate(raceDate)} ${raceDate.substring(0, 4)}'),
        onPressed: () async {
          final picked = await showDatePicker(
            context: context,
            initialDate: raceDate == null ? DateTime.now().add(const Duration(days: 90)) : parseIso(raceDate),
            firstDate: DateTime.now(),
            lastDate: DateTime.now().add(const Duration(days: 800)),
          );
          if (picked != null) setState(() => _goal['raceDate'] = isoDate(picked));
        },
      )),
      if (raceDate != null)
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton(onPressed: () => setState(() => _goal.remove('raceDate')), child: const Text('Termin entfernen')),
        ),
      const Text('Kategorie'),
      _pad(SegmentedButton<String>(
        segments: const [
          ButtonSegment(value: 'single', label: Text('Single')),
          ButtonSegment(value: 'doubles', label: Text('Doubles')),
          ButtonSegment(value: 'relay', label: Text('Relay')),
        ],
        selected: {_goal['category'].toString()},
        onSelectionChanged: (s) => setState(() => _goal['category'] = s.first),
      )),
      _textField('Division / Klasse', _goal, 'division', hint: 'z. B. Open, Pro, Altersklasse'),
      _textField('Zielzeit', _goal, 'targetTime', hint: 'z. B. 1:25:00'),
      const Text('Priorität'),
      _pad(SegmentedButton<String>(
        segments: const [
          ButtonSegment(value: 'finish', label: Text('Ankommen')),
          ButtonSegment(value: 'improve', label: Text('Verbessern')),
          ButtonSegment(value: 'podium', label: Text('Podium')),
        ],
        selected: {_goal['priority'].toString()},
        onSelectionChanged: (s) => setState(() => _goal['priority'] = s.first),
      )),
      if (_goal['category'] != 'single') _textField('Partner/in', _goal, 'partnerName'),
    ]);
  }

  Widget _timeField(String label, List<String> list, int i) => SizedBox(
        width: 110,
        child: TextFormField(
          key: ValueKey('$label-$i-$_step'),
          initialValue: list[i],
          decoration: InputDecoration(labelText: label, isDense: true, border: const OutlineInputBorder(), hintText: 'mm:ss'),
          keyboardType: TextInputType.datetime,
          onChanged: (v) => list[i] = v,
        ),
      );

  Widget _stepResults() => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        _title(
          'Letzter Hyrox (optional)',
          'Trage die Splits deines letzten Hyrox ein, daraus erkennt die App z. B. einen Einbruch beim Laufen. '
              'Das automatische Abrufen kommt später. Ohne Ergebnis einfach überspringen.',
        ),
        _pad(TextFormField(
          key: ValueKey('event-$_step'),
          initialValue: _eventName,
          decoration: const InputDecoration(labelText: 'Veranstaltung', border: OutlineInputBorder()),
          onChanged: (v) => _eventName = v,
        )),
        _pad(OutlinedButton.icon(
          icon: const Icon(Icons.event),
          label: Text(_resultDate.isEmpty ? 'Datum des Rennens wählen' : germanDate(_resultDate)),
          onPressed: () async {
            final picked = await showDatePicker(
              context: context,
              initialDate: _resultDate.isEmpty ? DateTime.now() : parseIso(_resultDate),
              firstDate: DateTime.now().subtract(const Duration(days: 365 * 6)),
              lastDate: DateTime.now(),
            );
            if (picked != null) setState(() => _resultDate = isoDate(picked));
          },
        )),
        Text('Läufe (je 1 km)', style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(height: 8),
        Wrap(spacing: 8, runSpacing: 8, children: [for (var i = 0; i < 8; i++) _timeField('Lauf ${i + 1}', _runs, i)]),
        const SizedBox(height: 16),
        Text('Stationen', style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(height: 8),
        Wrap(spacing: 8, runSpacing: 8, children: [for (var i = 0; i < 8; i++) _timeField(_stationNames[i], _stations, i)]),
        const SizedBox(height: 16),
        _pad(SizedBox(
          width: 160,
          child: TextFormField(
            key: ValueKey('rox-$_step'),
            initialValue: _roxzone,
            decoration: const InputDecoration(labelText: 'Roxzone gesamt', isDense: true, border: OutlineInputBorder(), hintText: 'mm:ss'),
            onChanged: (v) => _roxzone = v,
          ),
        )),
      ]);

  Widget _stepSelf() {
    final exp = _self['strengthExperience'].toString();
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _title('Selbsteinschätzung', 'Ehrlich einschätzen: 1 = große Schwäche, 5 = große Stärke.'),
      for (final entry in _ratingKeys.entries)
        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('${entry.value}: ${(_ratings[entry.key] ?? 3)}'),
          Slider(
            value: ((_ratings[entry.key] ?? 3) as num).toDouble(),
            min: 1,
            max: 5,
            divisions: 4,
            onChanged: (v) => setState(() => _ratings[entry.key] = v.round()),
          ),
        ]),
      const SizedBox(height: 8),
      const Text('Läufertyp'),
      _pad(SegmentedButton<String>(
        segments: const [
          ButtonSegment(value: 'strong_runner', label: Text('Starker Läufer')),
          ButtonSegment(value: 'balanced', label: Text('Ausgewogen')),
          ButtonSegment(value: 'weak_runner', label: Text('Laufen schwach')),
        ],
        selected: {_self['runnerType'].toString()},
        onSelectionChanged: (s) => setState(() => _self['runnerType'] = s.first),
      )),
      const Text('Krafttraining-Erfahrung'),
      _pad(Wrap(spacing: 8, children: [
        for (final e in const {'none': 'Keine', 'some': 'Etwas', 'regular': 'Regelmäßig', 'advanced': 'Fortgeschritten'}.entries)
          ChoiceChip(
            label: Text(e.value),
            selected: exp == e.key,
            onSelected: (_) => setState(() => _self['strengthExperience'] = e.key),
          ),
      ])),
      _numField('Laufumfang pro Woche', _self, 'runWeeklyKm', decimal: true, suffix: 'km'),
      _textField('Bestzeit 5 km', _self, 'run5kTime', hint: 'z. B. 24:30'),
      _textField('Bestzeit 10 km', _self, 'run10kTime', hint: 'z. B. 51:00'),
      _textField('Wo geht dir im Rennen die Luft aus?', _self, 'limiter', lines: 2, hint: 'z. B. Arme nach Sled Pull, Beine bei Wall Balls'),
    ]);
  }

  Map<String, dynamic>? _dayFor(int wd) {
    for (final d in _days) {
      if (d['weekday'] == wd) return d;
    }
    return null;
  }

  Widget _stepSchedule() => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        _title('Trainingstage', 'Wähle deine Tage. Pro Tag legst du fest, wo du trainierst. "Entscheide ich am Tag" bekommt beide Varianten im Plan, die du beim Start wählst.'),
        for (var wd = 1; wd <= 7; wd++) ...[
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(weekdayLong[wd - 1]),
            value: _dayFor(wd) != null,
            onChanged: (on) => setState(() {
              if (on) {
                _days.add({'weekday': wd, 'mode': 'ask', 'maxDurationMin': 60});
                _days.sort((x, y) => (x['weekday'] as int).compareTo(y['weekday'] as int));
              } else {
                _days.removeWhere((d) => d['weekday'] == wd);
              }
            }),
          ),
          if (_dayFor(wd) case final d?)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                SegmentedButton<String>(
                  segments: const [
                    ButtonSegment(value: 'gym', label: Text('Gym')),
                    ButtonSegment(value: 'home', label: Text('Zuhause')),
                    ButtonSegment(value: 'ask', label: Text('Entscheide ich')),
                  ],
                  selected: {d['mode'].toString()},
                  onSelectionChanged: (s) => setState(() => d['mode'] = s.first),
                ),
                const SizedBox(height: 8),
                Wrap(spacing: 6, children: [
                  for (final m in const [30, 45, 60, 75, 90, 120])
                    ChoiceChip(
                      label: Text('$m Min'),
                      selected: d['maxDurationMin'] == m,
                      onSelected: (_) => setState(() => d['maxDurationMin'] = m),
                    ),
                ]),
              ]),
            ),
        ],
        _textField('Andere Sportarten (optional)', _schedule, 'otherSports', hint: 'z. B. Yoga am Mittwoch, Radfahren am Wochenende'),
      ]);

  Widget _equipmentBlock(String title, String key, List<String> presets, TextEditingController custom) {
    final selected = (_equipment[key] as List).map((e) => e.toString()).toList();
    final all = [...presets, ...selected.where((s) => !presets.contains(s))];
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(title, style: Theme.of(context).textTheme.titleMedium),
      const SizedBox(height: 8),
      Wrap(spacing: 6, runSpacing: 6, children: [
        for (final item in all)
          FilterChip(
            label: Text(item),
            selected: selected.contains(item),
            onSelected: (on) => setState(() {
              final list = _equipment[key] as List;
              if (on) {
                list.add(item);
              } else {
                list.remove(item);
              }
            }),
          ),
      ]),
      const SizedBox(height: 8),
      TextField(
        controller: custom,
        decoration: InputDecoration(
          labelText: 'Weiteres Equipment hinzufügen',
          border: const OutlineInputBorder(),
          suffixIcon: IconButton(
            icon: const Icon(Icons.add),
            onPressed: () => _addCustom(key, custom),
          ),
        ),
        onSubmitted: (_) => _addCustom(key, custom),
      ),
      const SizedBox(height: 24),
    ]);
  }

  void _addCustom(String key, TextEditingController c) {
    final v = c.text.trim();
    if (v.isEmpty) return;
    setState(() {
      final list = _equipment[key] as List;
      if (!list.contains(v)) list.add(v);
      c.clear();
    });
  }

  Widget _stepEquipment() => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        _title('Equipment', 'Zwei Profile: was du zu Hause hast und was im Gym verfügbar ist. Der Plan nutzt pro Ort nur das, was du hier ankreuzt.'),
        _equipmentBlock('Zu Hause', 'home', _homeEquipment, _customHome),
        _equipmentBlock('Im Gym', 'gym', _gymEquipment, _customGym),
      ]);

  Widget _stepRestrictions() => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        _title('Einschränkungen (optional)',
            'Verletzungen, Beschwerden oder Übungen, die du vermeiden willst. Der Text wird nur für die Planerstellung an die KI übermittelt. Gib nur an, was für den Plan nötig ist.'),
        _textField('Einschränkungen', _a, 'restrictions', lines: 4, hint: 'z. B. keine Sprünge wegen Knie'),
      ]);

  Widget _stepFocus() => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        _title('Fokus und Plan', 'Aus deinen Angaben und Splits schlägt die App einen Fokus vor. Bestätige oder ändere ihn.'),
        for (final s in _suggestions)
          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(s['label'].toString()),
            subtitle: Text(s['reason'].toString()),
            value: _chosen.contains(s['label'].toString()),
            onChanged: (v) => setState(() {
              final label = s['label'].toString();
              if (v == true) {
                _chosen.add(label);
              } else {
                _chosen.remove(label);
              }
            }),
          ),
        const SizedBox(height: 8),
        _pad(TextFormField(
          key: ValueKey('custom-focus-$_step'),
          initialValue: _customFocus,
          decoration: const InputDecoration(labelText: 'Eigener Fokus (optional)', border: OutlineInputBorder()),
          onChanged: (v) => _customFocus = v,
        )),
        const Divider(),
        const SizedBox(height: 8),
        const Text('Planlänge'),
        _pad(SegmentedButton<int>(
          segments: const [
            ButtonSegment(value: 2, label: Text('2 Wochen')),
            ButtonSegment(value: 3, label: Text('3 Wochen')),
            ButtonSegment(value: 4, label: Text('4 Wochen')),
          ],
          selected: {_weeks},
          onSelectionChanged: (s) => setState(() => _weeks = s.first),
        )),
        _pad(OutlinedButton.icon(
          icon: const Icon(Icons.event),
          label: Text('Start: ${germanDate(isoDate(_startDate))}'),
          onPressed: () async {
            final picked = await showDatePicker(
              context: context,
              initialDate: _startDate,
              firstDate: DateTime.now(),
              lastDate: DateTime.now().add(const Duration(days: 180)),
            );
            if (picked != null) setState(() => _startDate = picked);
          },
        )),
        if (context.read<AppState>().plan != null)
          const Text('Achtung: Ein neuer Plan ersetzt den aktuellen.', style: TextStyle(fontStyle: FontStyle.italic)),
        const SizedBox(height: 8),
        FilledButton.icon(
          icon: _busy
              ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2))
              : const Icon(Icons.auto_awesome),
          label: Text(_busy ? 'Plan wird erstellt (kann bis zu 2 Minuten dauern)' : 'Plan mit KI erstellen'),
          onPressed: _busy ? null : _generate,
        ),
      ]);

  // ---------- Logik ----------
  Map<String, dynamic>? _buildResult() {
    final anyFilled = _runs.any((s) => s.trim().isNotEmpty) ||
        _stations.any((s) => s.trim().isNotEmpty) ||
        _resultDate.isNotEmpty;
    if (!anyFilled) return null;

    if (_resultDate.isEmpty) throw ApiException(0, 'Bitte das Datum des Rennens wählen oder die Ergebnisse leeren.');
    final runs = _runs.map(parseTimeSec).toList();
    final stations = _stations.map(parseTimeSec).toList();
    if (runs.any((x) => x == null) || stations.any((x) => x == null)) {
      throw ApiException(0, 'Bitte alle 8 Läufe und 8 Stationen im Format mm:ss eintragen oder alle Felder leeren.');
    }
    return {
      if (_eventName.trim().isNotEmpty) 'eventName': _eventName.trim(),
      'date': _resultDate,
      if (_goal['division'] != null) 'category': _goal['division'],
      'totalTimeSec': 0,
      if (parseTimeSec(_roxzone) != null) 'roxzoneSec': parseTimeSec(_roxzone),
      'runsSec': runs.cast<int>(),
      'stationsSec': stations.cast<int>(),
    };
  }

  Future<void> _next() async {
    setState(() => _error = null);

    if (_step == 2) {
      try {
        _buildResult(); // nur prüfen
      } on ApiException catch (e) {
        setState(() => _error = e.message);
        return;
      }
    }

    if (_step == 6) {
      await _enterFocus();
      return;
    }
    setState(() => _step++);
  }

  Future<void> _enterFocus() async {
    final state = context.read<AppState>();
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final result = _buildResult();
      if (result != null && !_resultSaved) {
        await state.client!.post('/api/results', result);
        _resultSaved = true;
      }
      _schedule['daysPerWeek'] = _days.length;
      await state.saveAnamnese(_a);
      final suggestions = await state.loadSuggestions();
      if (!mounted) return;
      setState(() {
        _suggestions = suggestions;
        if (_chosen.isEmpty) {
          _chosen.addAll(suggestions.take(2).map((s) => s['label'].toString()));
        }
        _step = 7;
      });
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _generate() async {
    final state = context.read<AppState>();
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final focus = {..._chosen, if (_customFocus.trim().isNotEmpty) _customFocus.trim()}.toList();
      _a['focusChosen'] = focus;
      _a['focusConfirmed'] = true;
      await state.saveAnamnese(_a);
      await state.generatePlan(isoDate(_startDate), _weeks);
      if (!mounted) return;
      Navigator.of(context).pop();
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final pages = [
      _stepPerson, _stepGoal, _stepResults, _stepSelf, _stepSchedule, _stepEquipment, _stepRestrictions, _stepFocus,
    ];
    final isLast = _step == pages.length - 1;

    return Scaffold(
      appBar: AppBar(title: Text('Anamnese: ${_steps[_step]}')),
      body: Column(
        children: [
          LinearProgressIndicator(value: (_step + 1) / pages.length),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: pages[_step](),
            ),
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
            ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  if (_step > 0)
                    OutlinedButton(
                      onPressed: _busy ? null : () => setState(() => _step--),
                      child: const Text('Zurück'),
                    ),
                  const Spacer(),
                  if (!isLast)
                    FilledButton(
                      onPressed: _busy ? null : _next,
                      child: _busy && _step == 6
                          ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2))
                          : Text(_step == 6 ? 'Speichern und weiter' : 'Weiter'),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
