import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../api/api_client.dart';
import '../state/app_state.dart';
import '../util.dart';
import '../widgets/goal_editor.dart';
import 'plan_ready_screen.dart';

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

// Arbeitsgewicht für ca. 5 saubere Wiederholungen; daraus leitet die KI die Gewichte im Plan ab
const _workingWeightKeys = {
  'back_squat': 'Kniebeuge (Langhantel)',
  'deadlift': 'Kreuzheben',
  'bench_press': 'Bankdrücken',
  'overhead_press': 'Schulterdrücken (Langhantel)',
  'barbell_row': 'Rudern vorgebeugt (Langhantel)',
  'dumbbell': 'Kurzhantel je Hand (z. B. Ausfallschritte)',
  'kettlebell_swing': 'Kettlebell Swing',
  'wall_ball': 'Wall Ball (Ballgewicht)',
};

// Schnellauswahl für den Schwerpunkt eines Trainingstags (freie Eingabe ist auch möglich)
const _focusPresets = [
  'Oberkörper Push', 'Oberkörper Pull', 'Unterkörper', 'Ganzkörper', 'Laufen locker', 'Intervalle',
  'Hyrox-Stationen', 'Mobility',
];

// Art eines festen Termins → dayType (bestimmt Farbe und wie die KI die Belastung einordnet)
const _fixedTypes = {
  'recovery': 'Yoga / Mobility',
  'hyrox_sim': 'Hyrox-Kurs',
  'strength': 'Kraft-Kurs',
  'run': 'Lauftreff',
  'mixed': 'Sonstiges',
};

const _steps = [
  'Person', 'Ziel', 'Ergebnisse', 'Selbsteinschätzung', 'Zeit & Termine', 'Equipment', 'Einschränkungen', 'Fokus & Plan',
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

  final _customHome = TextEditingController();
  final _customGym = TextEditingController();

  bool _busy = false;
  String? _error;

  // Bildauswertung: erhöht sich nach jedem Import, damit die Felder die neuen Werte anzeigen
  int _formVersion = 0;
  bool _importing = false;

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
    selfAssessment['workingWeights'] = Map<String, dynamic>.from((selfAssessment['workingWeights'] as Map?) ?? {});
    final schedule = sub('schedule', {'daysPerWeek': 4, 'frequencyMode': 'count'});
    schedule['days'] = asMapList(schedule['days']);
    schedule['fixedSessions'] = asMapList(schedule['fixedSessions']);
    final equipment = sub('equipment', {});
    equipment['home'] = List<dynamic>.from((equipment['home'] as List?) ?? []);
    equipment['gym'] = List<dynamic>.from((equipment['gym'] as List?) ?? []);

    final goal = sub('goal', {'category': 'single', 'priority': 'improve'});
    GoalEditor.normalize(goal);

    return {
      'profile': sub('profile', {}),
      'goal': goal,
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
  List<Map<String, dynamic>> get _races => (_goal['races'] as List).cast<Map<String, dynamic>>();
  Map<String, dynamic> get _self => _a['selfAssessment'] as Map<String, dynamic>;
  Map<String, dynamic> get _ratings => _self['ratings'] as Map<String, dynamic>;
  Map<String, dynamic> get _schedule => _a['schedule'] as Map<String, dynamic>;
  List<Map<String, dynamic>> get _days => _schedule['days'] as List<Map<String, dynamic>>;
  List<Map<String, dynamic>> get _fixed => _schedule['fixedSessions'] as List<Map<String, dynamic>>;
  Map<String, dynamic> get _equipment => _a['equipment'] as Map<String, dynamic>;

  // ---------- Eingabe-Widgets ----------
  Widget _pad(Widget w) => Padding(padding: const EdgeInsets.only(bottom: 12), child: w);

  Widget _numField(String label, Map<String, dynamic> m, String key, {bool decimal = false, String? suffix}) {
    return _pad(TextFormField(
      key: ValueKey('$label-$_step-$_formVersion'),
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
      key: ValueKey('$label-$_step-$_formVersion'),
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
        _importCard(),
        _title('Über dich', 'Alles optional. Hilft, den Plan realistischer zu machen.'),
        _numField('Alter', _profile, 'age'),
        _numField('Größe', _profile, 'heightCm', suffix: 'cm'),
        _numField('Gewicht', _profile, 'weightKg', decimal: true, suffix: 'kg'),
      ]);

  Widget _stepGoal() {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _title('Dein Ziel'),
      GoalEditor(goal: _goal, onChanged: () => setState(() {})),
      const Divider(height: 32),
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
          key: ValueKey('$label-$i-$_step-$_formVersion'),
          initialValue: list[i],
          decoration: InputDecoration(labelText: label, isDense: true, border: const OutlineInputBorder(), hintText: 'mm:ss'),
          keyboardType: TextInputType.datetime,
          onChanged: (v) => list[i] = v,
        ),
      );

  Widget _stepResults() => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        _importCard(),
        _title(
          'Letzter Hyrox (optional)',
          'Trage die Splits deines letzten Hyrox ein, daraus erkennt die App z. B. einen Einbruch beim Laufen. '
              'Das automatische Abrufen kommt später. Ohne Ergebnis einfach überspringen.',
        ),
        _pad(TextFormField(
          key: ValueKey('event-$_step-$_formVersion'),
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
            key: ValueKey('rox-$_step-$_formVersion'),
            initialValue: _roxzone,
            decoration: const InputDecoration(labelText: 'Roxzone gesamt', isDense: true, border: OutlineInputBorder(), hintText: 'mm:ss'),
            onChanged: (v) => _roxzone = v,
          ),
        )),
      ]);

  Widget _stepSelf() {
    final exp = _self['strengthExperience'].toString();
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _importCard(),
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
      const SizedBox(height: 8),
      _title('Deine Kraftwerte', 'Gewicht, mit dem du ca. 5 saubere Wiederholungen schaffst. Daraus werden die Gewichte '
          'im Plan vorausgewählt. Lass leer, was du nicht weißt – dann wird vorsichtig geschätzt.'),
      for (final e in _workingWeightKeys.entries)
        _numField(e.value, _self['workingWeights'] as Map<String, dynamic>, e.key, decimal: true, suffix: 'kg'),
    ]);
  }

  Map<String, dynamic>? _dayFor(int wd) {
    for (final d in _days) {
      if (d['weekday'] == wd) return d;
    }
    return null;
  }

  static const _modeLabels = {'gym': 'Gym', 'home': 'Zuhause', 'ask': 'Gym oder Zuhause'};

  Widget _section(String title, [String? sub]) => Padding(
        padding: const EdgeInsets.only(top: 20, bottom: 8),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
          if (sub != null) Text(sub, style: Theme.of(context).textTheme.bodySmall),
        ]),
      );

  /// Zeit & Termine: nur Rahmenbedingungen. Wann genau trainiert wird, entscheidet die KI.
  Widget _stepSchedule() {
    final available = _days.length;
    final perWeek = ((_schedule['daysPerWeek'] as num?)?.toInt() ?? 4);
    final freq = _schedule['frequencyMode']?.toString() ?? 'count';
    final wishes = _days.where((d) => (d['focus'] ?? '').toString().isNotEmpty).toList();

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _title('Zeit & Termine', 'Erzähl uns deine Rahmenbedingungen. Wann genau trainiert wird, plant die KI daraus – '
          'mit Blick auf Erholung, deine Kurse und Rennen.'),

      // 1. Wie oft
      _section('Wie möchtest du die Häufigkeit festlegen?', 'Feste Kurse zählen nicht mit.'),
      RadioGroup<String>(
        groupValue: freq,
        onChanged: (v) => setState(() => _schedule['frequencyMode'] = v),
        child: Column(children: [
          for (final (value, title, sub) in const [
            ('auto', 'So oft wie sinnvoll', 'Die KI wählt Anzahl und Tage passend zu Ziel, Form und Erholung.'),
            ('count', 'Feste Anzahl pro Woche', 'Du sagst wie oft, die KI verteilt die Einheiten auf deine freien Tage.'),
            ('fixed', 'Feste Tage', 'Du trainierst genau an den Tagen, die du auswählst.'),
          ])
            RadioListTile<String>(
              contentPadding: EdgeInsets.zero,
              dense: true,
              value: value,
              title: Text(title),
              subtitle: Text(sub),
            ),
        ]),
      ),
      if (freq == 'count') ...[
        const SizedBox(height: 4),
        Wrap(spacing: 6, children: [
          for (var n = 1; n <= 7; n++)
            ChoiceChip(
              label: Text('$n×'),
              selected: perWeek == n,
              onSelected: available > 0 && n > available ? null : (_) => setState(() => _schedule['daysPerWeek'] = n),
            ),
        ]),
      ],

      // 2. Verfügbarkeit bzw. feste Tage
      freq == 'fixed'
          ? _section('An welchen Tagen trainierst du?', 'Genau diese Tage werden Trainingstage.')
          : _section('An welchen Tagen hast du grundsätzlich Zeit?',
              'Wähle lieber ein paar Tage mehr – die KI sucht sich daraus die passenden aus.'),
      Wrap(spacing: 6, children: [
        for (var wd = 1; wd <= 7; wd++)
          FilterChip(
            label: Text(weekdayShort[wd - 1]),
            selected: _dayFor(wd) != null,
            onSelected: (on) => setState(() {
              if (on) {
                _days.add({'weekday': wd, 'mode': 'ask', 'maxDurationMin': 60});
                _days.sort((x, y) => (x['weekday'] as int).compareTo(y['weekday'] as int));
              } else {
                _days.removeWhere((d) => d['weekday'] == wd);
                if (perWeek > _days.length && _days.isNotEmpty) _schedule['daysPerWeek'] = _days.length;
              }
            }),
          ),
      ]),
      const SizedBox(height: 8),
      for (final d in _days)
        Card(
          margin: const EdgeInsets.only(bottom: 6),
          child: ListTile(
            dense: true,
            title: Text(weekdayLong[(d['weekday'] as int) - 1]),
            subtitle: Text('bis ${d['maxDurationMin']} Min · ${_modeLabels[d['mode']] ?? d['mode']}'),
            trailing: const Icon(Icons.edit_outlined, size: 20),
            onTap: () => _editAvailability(d),
          ),
        ),
      if (freq == 'count' && available > 0 && perWeek > available)
        Text('Du willst $perWeek× trainieren, hast aber nur $available Tage Zeit.',
            style: TextStyle(color: Theme.of(context).colorScheme.error)),

      // 3. Feste Termine
      _section('Feste Kurse & Termine', 'Z. B. Yoga montags 18:00. Erscheinen im Kalender zum Abhaken und werden bei der '
          'Belastung berücksichtigt – geplant werden sie nicht.'),
      for (final f in _fixed)
        Card(
          margin: const EdgeInsets.only(bottom: 6),
          child: ListTile(
            dense: true,
            leading: Icon(Icons.event_available, color: dayTypeColor(f['dayType']?.toString())),
            title: Text('${f['title']}'),
            subtitle: Text('${weekdayLong[(f['weekday'] as int) - 1]}, ${f['time']} · ${f['durationMin']} Min'),
            trailing: IconButton(
              icon: const Icon(Icons.delete_outline),
              onPressed: () => setState(() => _fixed.remove(f)),
            ),
            onTap: () => _editFixed(f),
          ),
        ),
      OutlinedButton.icon(
        icon: const Icon(Icons.add),
        label: const Text('Kurs oder Termin hinzufügen'),
        onPressed: () => _editFixed(null),
      ),

      // 4. Wünsche
      _section('Wünsche für bestimmte Tage (optional)', 'Nur wenn dir etwas wichtig ist, z. B. „Dienstag: Oberkörper Push '
          'zu Hause“. Diese Tage sind dann gesetzt, den Rest plant die KI.'),
      for (final d in wishes)
        Card(
          margin: const EdgeInsets.only(bottom: 6),
          child: ListTile(
            dense: true,
            leading: const Icon(Icons.push_pin_outlined),
            title: Text('${weekdayLong[(d['weekday'] as int) - 1]}: ${d['focus']}'),
            trailing: IconButton(
              icon: const Icon(Icons.delete_outline),
              onPressed: () => setState(() => d.remove('focus')),
            ),
            onTap: () => _editWish(d),
          ),
        ),
      OutlinedButton.icon(
        icon: const Icon(Icons.add),
        label: const Text('Wunsch hinzufügen'),
        onPressed: available == 0 ? null : () => _editWish(null),
      ),

      _section('Sonstiges (optional)'),
      _textField('Was sollte die KI noch wissen?', _schedule, 'otherSports',
          hint: 'z. B. Radfahren am Wochenende, Schichtdienst, Mittwoch nur morgens'),
    ]);
  }

  /// Zeit und Ort für einen verfügbaren Tag.
  Future<void> _editAvailability(Map<String, dynamic> d) async {
    await showModalBottomSheet<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(weekdayLong[(d['weekday'] as int) - 1], style: Theme.of(ctx).textTheme.titleLarge),
              const SizedBox(height: 12),
              const Text('Wie viel Zeit hast du höchstens?'),
              const SizedBox(height: 6),
              Wrap(spacing: 6, children: [
                for (final m in const [30, 45, 60, 75, 90, 120])
                  ChoiceChip(
                    label: Text('$m Min'),
                    selected: d['maxDurationMin'] == m,
                    onSelected: (_) => setLocal(() => d['maxDurationMin'] = m),
                  ),
              ]),
              const SizedBox(height: 16),
              const Text('Wo kannst du trainieren?'),
              const SizedBox(height: 6),
              SegmentedButton<String>(
                segments: const [
                  ButtonSegment(value: 'gym', label: Text('Gym')),
                  ButtonSegment(value: 'home', label: Text('Zuhause')),
                  ButtonSegment(value: 'ask', label: Text('Beides')),
                ],
                selected: {d['mode'].toString()},
                onSelectionChanged: (sel) => setLocal(() => d['mode'] = sel.first),
              ),
              const SizedBox(height: 4),
              Text('„Beides“: Der Plan enthält eine Gym- und eine Home-Variante, du entscheidest am Tag.',
                  style: Theme.of(ctx).textTheme.bodySmall),
              const SizedBox(height: 12),
              Align(
                alignment: Alignment.centerRight,
                child: FilledButton(onPressed: () => Navigator.pop(ctx), child: const Text('Fertig')),
              ),
            ]),
          ),
        ),
      ),
    );
    if (mounted) setState(() {});
  }

  /// Wunsch für einen Tag: [existing] bearbeiten oder neuen Tag wählen.
  Future<void> _editWish(Map<String, dynamic>? existing) async {
    final result = await showModalBottomSheet<(int, String)>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _WishSheet(
        availableDays: [for (final d in _days) d['weekday'] as int],
        initialDay: existing?['weekday'] as int?,
        initialFocus: existing?['focus']?.toString(),
      ),
    );
    if (result == null || !mounted) return;
    setState(() {
      existing?.remove('focus');
      final day = _dayFor(result.$1);
      if (day != null) day['focus'] = result.$2;
    });
  }

  /// Termin anlegen ([existing] == null) oder bearbeiten.
  Future<void> _editFixed(Map<String, dynamic>? existing) async {
    final result = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _FixedSessionSheet(initial: existing),
    );
    if (result == null || !mounted) return;
    setState(() {
      if (existing != null) {
        existing
          ..clear()
          ..addAll(result);
      } else {
        _fixed.add(result);
      }
      _fixed.sort((a, b) => '${a['weekday']}${a['time']}'.compareTo('${b['weekday']}${b['time']}'));
    });
  }

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
          key: ValueKey('custom-focus-$_step-$_formVersion'),
          initialValue: _customFocus,
          decoration: const InputDecoration(labelText: 'Eigener Fokus (optional)', border: OutlineInputBorder()),
          onChanged: (v) => _customFocus = v,
        )),
        const Divider(),
        const SizedBox(height: 8),
        Card(
          margin: const EdgeInsets.only(bottom: 12),
          color: Theme.of(context).colorScheme.primaryContainer,
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('So entsteht dein Plan', style: TextStyle(fontWeight: FontWeight.w700)),
              const SizedBox(height: 6),
              Text('Er startet am Montag, ${germanDate(isoDate(nextMonday(DateTime.now())))}, und wird in Blöcken von 2–4 Wochen '
                  'geplant – so lang, dass ein Block mit deinem Rennen bzw. Peak endet. Kurz vor Ende eines Blocks erstellt '
                  'der Coach automatisch den nächsten, angepasst an deine Ergebnisse.'),
            ]),
          ),
        ),
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

  // ---------- Bildauswertung ----------
  Future<void> _importImages(ImageSource source) async {
    final picker = ImagePicker();
    final files = source == ImageSource.camera
        ? [if (await picker.pickImage(source: source, maxWidth: 2000, maxHeight: 2000, imageQuality: 85) case final f?) f]
        : await picker.pickMultiImage(maxWidth: 2000, maxHeight: 2000, imageQuality: 85, limit: 4);
    if (files.isEmpty || !mounted) return;

    final state = context.read<AppState>();
    setState(() {
      _importing = true;
      _error = null;
    });
    try {
      final images = [
        for (final f in files.take(4))
          (mediaType: f.name.toLowerCase().endsWith('.png') ? 'image/png' : 'image/jpeg', bytes: await f.readAsBytes()),
      ];
      final extracted = await state.extractFromImages(images);
      if (!mounted) return;
      final filled = _applyExtracted(extracted);
      await _showImportResult(extracted['summary']?.toString() ?? '', filled);
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _importing = false);
    }
  }

  /// Übernimmt erkannte Werte in das Formular und gibt eine Liste der befüllten Felder zurück.
  List<String> _applyExtracted(Map<String, dynamic> x) {
    final filled = <String>[];
    void put(Map<String, dynamic> target, String key, dynamic value, String label, [String suffix = '']) {
      if (value == null || (value is String && value.trim().isEmpty)) return;
      target[key] = value is String ? value.trim() : value;
      filled.add('$label: ${value is num ? fmtNum(value.toDouble()) : value}$suffix');
    }

    Map<String, dynamic> sub(String k) => x[k] is Map ? Map<String, dynamic>.from(x[k] as Map) : {};
    final profile = sub('profile');
    final goal = sub('goal');
    final self = sub('selfAssessment');
    final result = sub('hyroxResult');
    bool isDate(dynamic v) => v is String && RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(v);

    put(_profile, 'age', (profile['age'] as num?)?.round(), 'Alter');
    put(_profile, 'heightCm', (profile['heightCm'] as num?)?.round(), 'Größe', ' cm');
    put(_profile, 'weightKg', (profile['weightKg'] as num?)?.toDouble(), 'Gewicht', ' kg');
    put(_profile, 'sex', profile['sex'], 'Geschlecht');
    if (isDate(goal['raceDate']) && !_races.any((r) => r['date'] == goal['raceDate'])) {
      _races.add({
        'id': DateTime.now().microsecondsSinceEpoch.toString(),
        'name': (result['eventName'] ?? 'Rennen').toString(),
        'date': goal['raceDate'],
        'priority': 'A',
        'category': goal['category'] ?? _goal['category'] ?? 'single',
      });
      _goal['mode'] = 'race';
      filled.add('Rennen: ${germanDate(goal['raceDate'].toString())}');
    }
    put(_goal, 'category', goal['category'], 'Kategorie');
    put(_goal, 'division', goal['division'] ?? result['division'], 'Division');
    put(_goal, 'targetTime', goal['targetTime'], 'Zielzeit');
    put(_self, 'runWeeklyKm', (self['runWeeklyKm'] as num?)?.toDouble(), 'Laufumfang', ' km/Woche');
    put(_self, 'run5kTime', self['run5kTime'], 'Bestzeit 5 km');
    put(_self, 'run10kTime', self['run10kTime'], 'Bestzeit 10 km');
    final weights = self['workingWeights'] is Map ? Map<String, dynamic>.from(self['workingWeights'] as Map) : {};
    for (final e in weights.entries) {
      final label = _workingWeightKeys[e.key];
      if (label != null && e.value is num) {
        put(_self['workingWeights'] as Map<String, dynamic>, e.key, (e.value as num).toDouble(), label, ' kg');
      }
    }

    final runs = (result['runs'] as List?)?.map((e) => e.toString()).toList();
    final stations = (result['stations'] as List?)?.map((e) => e.toString()).toList();
    if (runs != null && runs.length == 8 && stations != null && stations.length == 8) {
      _runs.setAll(0, runs);
      _stations.setAll(0, stations);
      if (result['eventName'] != null) _eventName = result['eventName'].toString();
      if (isDate(result['date'])) _resultDate = result['date'].toString();
      if (result['roxzone'] != null) _roxzone = result['roxzone'].toString();
      _resultSaved = false;
      filled.add('Hyrox-Ergebnis${result['eventName'] != null ? ' ${result['eventName']}' : ''}: '
          '8 Läufe, 8 Stationen${result['totalTime'] != null ? ', gesamt ${result['totalTime']}' : ''}');
    }

    setState(() => _formVersion++);
    return filled;
  }

  Future<void> _showImportResult(String summary, List<String> filled) => showModalBottomSheet<void>(
        context: context,
        builder: (ctx) => SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(filled.isEmpty ? 'Nichts übernommen' : '${filled.length} Werte übernommen',
                    style: Theme.of(ctx).textTheme.titleLarge),
                if (summary.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text(summary),
                ],
                const SizedBox(height: 12),
                for (final f in filled)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 2),
                    child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      const Icon(Icons.check, size: 18),
                      const SizedBox(width: 8),
                      Expanded(child: Text(f)),
                    ]),
                  ),
                const SizedBox(height: 12),
                Text('Bitte prüf die Werte in den einzelnen Schritten. Gespeichert wird erst mit „Speichern und weiter“.',
                    style: Theme.of(ctx).textTheme.bodySmall),
                const SizedBox(height: 12),
                Align(
                  alignment: Alignment.centerRight,
                  child: FilledButton(onPressed: () => Navigator.pop(ctx), child: const Text('OK')),
                ),
              ],
            ),
          ),
        ),
      );

  Widget _importCard() => Card(
        margin: const EdgeInsets.only(bottom: 16),
        color: Theme.of(context).colorScheme.primaryContainer,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                Icon(Icons.document_scanner_outlined, color: Theme.of(context).colorScheme.onPrimaryContainer),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text('Aus Screenshot ausfüllen', style: TextStyle(fontWeight: FontWeight.w700)),
                ),
              ]),
              const SizedBox(height: 6),
              const Text('Hyrox-Ergebnis, Strava- oder Garmin-Statistik, Hevy-Log, Waage … '
                  'Bis zu 4 Bilder, die erkannten Werte werden vorausgefüllt.'),
              const SizedBox(height: 10),
              if (_importing)
                const Row(children: [
                  SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
                  SizedBox(width: 10),
                  Expanded(child: Text('Wird ausgewertet …')),
                ])
              else
                Wrap(spacing: 8, runSpacing: 8, children: [
                  FilledButton.icon(
                    icon: const Icon(Icons.photo_library_outlined),
                    label: const Text('Bilder wählen'),
                    onPressed: _busy ? null : () => _importImages(ImageSource.gallery),
                  ),
                  OutlinedButton.icon(
                    icon: const Icon(Icons.photo_camera_outlined),
                    label: const Text('Foto aufnehmen'),
                    onPressed: _busy ? null : () => _importImages(ImageSource.camera),
                  ),
                ]),
            ],
          ),
        ),
      );

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

    if (_step == 4 && _days.isEmpty) {
      setState(() => _error = 'Bitte wähle mindestens einen Tag, an dem du Zeit hast.');
      return;
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
      // Gewünschte Anzahl darf die verfügbaren Tage nicht übersteigen
      final perWeek = (_schedule['daysPerWeek'] as num?)?.toInt() ?? 4;
      _schedule['daysPerWeek'] = perWeek.clamp(1, _days.length);
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
      await state.generatePlan();
      if (!mounted) return;
      Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => const PlanReadyScreen()));
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


/// Formular für einen festen Termin. Eigenes Widget, damit der Titel-Controller sauber entsorgt wird.
class _FixedSessionSheet extends StatefulWidget {
  const _FixedSessionSheet({this.initial});
  final Map<String, dynamic>? initial;

  @override
  State<_FixedSessionSheet> createState() => _FixedSessionSheetState();
}

class _FixedSessionSheetState extends State<_FixedSessionSheet> {
  late final TextEditingController _title = TextEditingController(text: widget.initial?['title']?.toString() ?? '');
  late int _weekday = (widget.initial?['weekday'] as int?) ?? 1;
  late String _time = widget.initial?['time']?.toString() ?? '18:00';
  late String _type = widget.initial?['dayType']?.toString() ?? 'recovery';
  late int _duration = (widget.initial?['durationMin'] as num?)?.toInt() ?? 60;

  @override
  void dispose() {
    _title.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final parts = _time.split(':');
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 20, 20, 20 + MediaQuery.of(context).viewInsets.bottom),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(widget.initial == null ? 'Fester Termin' : 'Termin bearbeiten', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 12),
            TextField(
              controller: _title,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(labelText: 'Bezeichnung', hintText: 'z. B. Yoga-Kurs'),
            ),
            const SizedBox(height: 12),
            Wrap(spacing: 6, runSpacing: 4, children: [
              for (final e in _fixedTypes.entries)
                ChoiceChip(
                  label: Text(e.value),
                  selected: _type == e.key,
                  onSelected: (_) => setState(() => _type = e.key),
                ),
            ]),
            const SizedBox(height: 12),
            Wrap(spacing: 6, children: [
              for (var wd = 1; wd <= 7; wd++)
                ChoiceChip(
                  label: Text(weekdayShort[wd - 1]),
                  selected: _weekday == wd,
                  onSelected: (_) => setState(() => _weekday = wd),
                ),
            ]),
            const SizedBox(height: 12),
            Row(children: [
              OutlinedButton.icon(
                icon: const Icon(Icons.schedule),
                label: Text('$_time Uhr'),
                onPressed: () async {
                  final picked = await showTimePicker(
                    context: context,
                    initialTime: TimeOfDay(hour: int.tryParse(parts.first) ?? 18, minute: int.tryParse(parts.last) ?? 0),
                  );
                  if (picked != null) {
                    setState(() => _time =
                        '${picked.hour.toString().padLeft(2, '0')}:${picked.minute.toString().padLeft(2, '0')}');
                  }
                },
              ),
              const SizedBox(width: 12),
              Expanded(
                child: DropdownButtonFormField<int>(
                  initialValue: _duration,
                  decoration: const InputDecoration(labelText: 'Dauer', isDense: true),
                  items: [
                    for (final m in const [30, 45, 60, 75, 90, 120]) DropdownMenuItem(value: m, child: Text('$m Min')),
                  ],
                  onChanged: (v) => setState(() => _duration = v ?? _duration),
                ),
              ),
            ]),
            const SizedBox(height: 16),
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton(
                onPressed: () {
                  final title = _title.text.trim().isEmpty ? (_fixedTypes[_type] ?? 'Termin') : _title.text.trim();
                  Navigator.pop(context, {
                    'weekday': _weekday,
                    'time': _time,
                    'title': title,
                    'dayType': _type,
                    'durationMin': _duration,
                  });
                },
                child: const Text('Übernehmen'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}


/// Wunsch für einen bestimmten Tag: Tag aus den verfügbaren wählen, Schwerpunkt per Schnellauswahl oder Freitext.
class _WishSheet extends StatefulWidget {
  const _WishSheet({required this.availableDays, this.initialDay, this.initialFocus});
  final List<int> availableDays;
  final int? initialDay;
  final String? initialFocus;

  @override
  State<_WishSheet> createState() => _WishSheetState();
}

class _WishSheetState extends State<_WishSheet> {
  late int _day = widget.initialDay ?? widget.availableDays.first;
  late final _custom = TextEditingController(
    text: _focusPresets.contains(widget.initialFocus) ? '' : (widget.initialFocus ?? ''),
  );
  late String? _preset = _focusPresets.contains(widget.initialFocus) ? widget.initialFocus : null;

  @override
  void dispose() {
    _custom.dispose();
    super.dispose();
  }

  String get _focus => _custom.text.trim().isNotEmpty ? _custom.text.trim() : (_preset ?? '');

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 20, 20, 20 + MediaQuery.of(context).viewInsets.bottom),
      child: SafeArea(
        top: false,
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Wunsch für einen Tag', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 12),
          Wrap(spacing: 6, children: [
            for (final wd in widget.availableDays)
              ChoiceChip(
                label: Text(weekdayShort[wd - 1]),
                selected: _day == wd,
                onSelected: (_) => setState(() => _day = wd),
              ),
          ]),
          const SizedBox(height: 12),
          Wrap(spacing: 6, runSpacing: 4, children: [
            for (final f in _focusPresets)
              ChoiceChip(
                label: Text(f),
                selected: _preset == f && _custom.text.trim().isEmpty,
                onSelected: (_) => setState(() {
                  _preset = f;
                  _custom.clear();
                }),
              ),
          ]),
          const SizedBox(height: 8),
          TextField(
            controller: _custom,
            onChanged: (_) => setState(() {}),
            decoration: const InputDecoration(labelText: 'Oder eigener Wunsch', hintText: 'z. B. Oberkörper Push mit Kurzhanteln'),
          ),
          const SizedBox(height: 16),
          Align(
            alignment: Alignment.centerRight,
            child: FilledButton(
              onPressed: _focus.isEmpty ? null : () => Navigator.pop(context, (_day, _focus)),
              child: const Text('Übernehmen'),
            ),
          ),
        ]),
      ),
    );
  }
}
