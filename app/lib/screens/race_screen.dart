import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../race_prediction.dart';
import '../state/app_state.dart';
import '../theme/app_colors.dart';
import '../util.dart';

const _stationNames = [
  'SkiErg', 'Sled Push', 'Sled Pull', 'Burpee Broad Jumps', 'Rudern', 'Farmers Carry', 'Sandbag Lunges', 'Wall Balls',
];

const _checklist = [
  'Startnummer, Ausweis, Anmeldebestätigung',
  'Laufschuhe (eingelaufen) + Wechselschuhe',
  'Handschuhe für Sled und Farmers Carry',
  'Uhr geladen, Training eingestellt',
  'Frühstück 3 Std. vorher, nichts Neues ausprobieren',
  'Getränk und ggf. Gel/Riegel',
  'Warme Kleidung für vor und nach dem Rennen',
  'Anreise geplant, 60–90 Min vor Start vor Ort',
  'Split-Plan als Screenshot gespeichert',
];

const _warmup = [
  ('8–10 Min', 'Locker einlaufen, Puls langsam hoch'),
  ('5 Min', 'Mobilisation: Hüfte, Sprunggelenke, Schultern, Brustwirbelsäule'),
  ('3 × 20 s', 'Steigerungsläufe bis Renntempo, locker zurück'),
  ('2 × 10', 'Air Squats und Ausfallschritte, dynamisch'),
  ('1–2 ×', 'Kurz Wall-Ball-Bewegung oder Liegestütze, nicht ermüden'),
  ('5 Min vor Start', 'Zwei kurze Antritte, dann ruhig atmen und Plan für Lauf 1 im Kopf: kontrolliert loslaufen'),
];

/// Renntag-Modus: Countdown, Prognose, Split-Plan, Checkliste und Aufwärmen für ein Rennen.
class RaceScreen extends StatefulWidget {
  const RaceScreen({super.key, required this.race});
  final Map<String, dynamic> race;

  @override
  State<RaceScreen> createState() => _RaceScreenState();
}

class _RaceScreenState extends State<RaceScreen> {
  Set<int> _checked = {};
  bool _useTarget = false;

  String get _prefsKey => 'raceChecklist_${widget.race['id'] ?? widget.race['date']}';

  @override
  void initState() {
    super.initState();
    _useTarget = parseTimeSec(widget.race['targetTime']?.toString() ?? '') != null;
    SharedPreferences.getInstance().then((p) {
      final saved = p.getStringList(_prefsKey) ?? [];
      if (mounted) setState(() => _checked = saved.map(int.parse).toSet());
    });
  }

  Future<void> _toggle(int i) async {
    setState(() => _checked.contains(i) ? _checked.remove(i) : _checked.add(i));
    final p = await SharedPreferences.getInstance();
    await p.setStringList(_prefsKey, _checked.map((e) => '$e').toList());
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final race = widget.race;
    final prediction = RacePrediction.build(anamnese: state.anamnese, results: state.results, workouts: state.workouts);
    final target = parseTimeSec(race['targetTime']?.toString() ?? '');
    final plan = _useTarget && target != null ? prediction.scaledTo(target) : prediction;
    final days = parseIso(race['date'].toString()).difference(DateTime(
      DateTime.now().year,
      DateTime.now().month,
      DateTime.now().day,
    )).inDays;
    final text = Theme.of(context).textTheme;

    return Scaffold(
      appBar: AppBar(
        backgroundColor: AppColors.race,
        foregroundColor: Colors.white,
        title: Text(race['name'].toString()),
      ),
      body: ListView(
        padding: EdgeInsets.zero,
        children: [
          Container(
            color: AppColors.race,
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(
                days > 1 ? 'in $days Tagen' : (days == 1 ? 'morgen' : (days == 0 ? 'HEUTE' : 'vorbei')),
                style: const TextStyle(color: Colors.white, fontSize: 32, fontWeight: FontWeight.w800),
              ),
              Text(
                '${germanDate(race['date'].toString())} ${race['date'].toString().substring(0, 4)} · '
                '${racePriorityLabels[race['priority']] ?? ''}${race['division'] != null ? ' · ${race['division']}' : ''}',
                style: const TextStyle(color: Colors.white70),
              ),
              if (days >= 0 && days <= 10) ...[
                const SizedBox(height: 10),
                Text(
                  days <= 1
                      ? 'Vortag/Renntag: nur kurz aktivieren, viel trinken, früh schlafen.'
                      : 'Taper-Phase: weniger Umfang, kurze knackige Reize. Mehr Training bringt jetzt nichts mehr.',
                  style: const TextStyle(color: Colors.white),
                ),
              ],
            ]),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Prognose', style: text.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
              const SizedBox(height: 4),
              Text(formatSec(prediction.totalSec), style: text.displaySmall?.copyWith(fontWeight: FontWeight.w800)),
              Text('Spanne ${formatSec(prediction.lowSec)} – ${formatSec(prediction.highSec)} · Sicherheit ${prediction.confidence}',
                  style: text.bodySmall),
              const SizedBox(height: 8),
              for (final b in prediction.basis)
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Text('• $b', style: text.bodySmall),
                ),
              const SizedBox(height: 20),
              Row(children: [
                Expanded(child: Text('Split-Plan', style: text.titleMedium?.copyWith(fontWeight: FontWeight.w700))),
                if (target != null)
                  SegmentedButton<bool>(
                    segments: [
                      const ButtonSegment(value: false, label: Text('Prognose')),
                      ButtonSegment(value: true, label: Text('Ziel ${race['targetTime']}')),
                    ],
                    selected: {_useTarget},
                    onSelectionChanged: (s) => setState(() => _useTarget = s.first),
                  ),
              ]),
              const SizedBox(height: 8),
              _SplitTable(plan: plan),
              const SizedBox(height: 24),
              Text('Checkliste', style: text.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
              for (var i = 0; i < _checklist.length; i++)
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  value: _checked.contains(i),
                  onChanged: (_) => _toggle(i),
                  title: Text(_checklist[i]),
                ),
              const SizedBox(height: 16),
              Text('Aufwärmen (ca. 25 Min)', style: text.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
              const SizedBox(height: 8),
              for (final (dur, what) in _warmup)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    SizedBox(width: 110, child: Text(dur, style: const TextStyle(fontWeight: FontWeight.w700))),
                    Expanded(child: Text(what)),
                  ]),
                ),
            ]),
          ),
        ],
      ),
    );
  }
}

/// Lauf/Station abwechselnd mit Soll-Zeit und kumulierter Zwischenzeit (Roxzone gleichmäßig verteilt).
class _SplitTable extends StatelessWidget {
  const _SplitTable({required this.plan});
  final RacePrediction plan;

  @override
  Widget build(BuildContext context) {
    final rows = <(String, int, bool)>[];
    final roxPer = plan.roxzoneSec ~/ 16; // 16 Wechsel
    for (var i = 0; i < 8; i++) {
      rows.add(('Lauf ${i + 1}', plan.runsSec[i] + roxPer, true));
      rows.add((_stationNames[i], plan.stationsSec[i] + roxPer, false));
    }
    var cum = 0;
    final text = Theme.of(context).textTheme;
    return Column(children: [
      for (final (label, sec, isRun) in rows)
        Builder(builder: (_) {
          cum += sec;
          return Container(
            padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 8),
            color: isRun ? AppColors.run.withValues(alpha: 0.06) : null,
            child: Row(children: [
              Icon(isRun ? Icons.directions_run : Icons.fitness_center, size: 16,
                  color: isRun ? AppColors.run : AppColors.hyroxSim),
              const SizedBox(width: 8),
              Expanded(child: Text(label)),
              SizedBox(
                  width: 64,
                  child: Text(formatSec(sec), textAlign: TextAlign.right, style: const TextStyle(fontWeight: FontWeight.w700))),
              SizedBox(width: 80, child: Text(formatSec(cum), textAlign: TextAlign.right, style: text.bodySmall)),
            ]),
          );
        }),
      Padding(
        padding: const EdgeInsets.only(top: 6),
        child: Text('Zeiten inkl. anteiliger Roxzone; rechts die Zwischenzeit ab Start.', style: text.bodySmall),
      ),
    ]);
  }
}
