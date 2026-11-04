import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../progress_stats.dart';
import '../race_prediction.dart';
import '../state/app_state.dart';
import '../util.dart';
import '../widgets/charts.dart';
import 'race_screen.dart';
import '../theme/app_colors.dart';

/// Fortschritt nach dem Vorbild von Strava, Runna und Hevy:
/// Wochenüberblick, Trainingszeit, Belastung & Form, Laufen, Kraft-Rekorde, Hyrox-Rennen, Verlauf.
class ProgressScreen extends StatelessWidget {
  const ProgressScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final stats = ProgressStats.build(state.workouts, state.plan, DateTime.now(), anamnese: state.anamnese);

    return RefreshIndicator(
      onRefresh: () => context.read<AppState>().refresh(),
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          _ThisWeek(stats: stats),
          const SizedBox(height: 12),
          _Highlights(stats: stats),
          if (stats.recentBests.isNotEmpty) ...[
            const SizedBox(height: 12),
            _Bests(stats: stats),
          ],
          _Section(
            title: 'Trainingszeit pro Woche',
            child: _TimeChart(stats: stats),
          ),
          _Section(
            title: 'Belastung & Form',
            info: 'Belastung = Anstrengung (RPE) × Minuten. Fitness ist der Schnitt der letzten 6 Wochen, '
                'Ermüdung der letzten 7 Tage. Form = Fitness − Ermüdung.',
            child: _LoadSection(stats: stats),
          ),
          _Section(title: 'Laufen', child: _RunSection(stats: stats)),
          _Section(title: 'Kraft & Rekorde', child: _StrengthSection(stats: stats)),
          _Section(title: 'Benchmarks', child: _BenchmarkSection(stats: stats)),
          _Section(
            title: 'Rennprognose',
            info: 'Berechnet aus deinem letzten Rennergebnis, neueren Benchmark-Tests (SkiErg, Rudern, Wall Balls) '
                'und deinen Laufzeiten. Ohne Rennergebnis sind es grobe Richtwerte mit breiter Spanne.',
            child: _PredictionCard(state: state),
          ),
          if (state.results.isNotEmpty)
            _Section(title: 'Hyrox-Rennen', child: _RaceSection(results: state.results)),
          _Section(title: 'Verlauf', child: _History(stats: stats)),
        ],
      ),
    );
  }
}

// ---------- Bausteine ----------

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.child, this.info});
  final String title;
  final Widget child;
  final String? info;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Expanded(child: Text(title, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700))),
            if (info != null)
              IconButton(
                visualDensity: VisualDensity.compact,
                icon: const Icon(Icons.info_outline, size: 20),
                onPressed: () => showDialog<void>(
                  context: context,
                  builder: (ctx) => AlertDialog(
                    title: Text(title),
                    content: Text(info!),
                    actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('OK'))],
                  ),
                ),
              ),
          ]),
          const SizedBox(height: 8),
          child,
        ],
      ),
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Text(text, style: Theme.of(context).textTheme.bodySmall),
      );
}

class _Tile extends StatelessWidget {
  const _Tile(this.value, this.label, {this.icon});
  final String value;
  final String label;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (icon != null) Icon(icon, size: 18, color: Theme.of(context).colorScheme.primary),
          FittedBox(child: Text(value, style: text.titleLarge?.copyWith(fontWeight: FontWeight.w800))),
          Text(label, style: text.bodySmall),
        ],
      ),
    );
  }
}

String _hours(int minutes) =>
    minutes < 60 ? '$minutes Min' : '${(minutes / 60).toStringAsFixed(1).replaceAll('.', ',')} h';

// ---------- Diese Woche ----------

class _ThisWeek extends StatelessWidget {
  const _ThisWeek({required this.stats});
  final ProgressStats stats;

  @override
  Widget build(BuildContext context) {
    final w = stats.thisWeek;
    final scheme = Theme.of(context).colorScheme;
    final planned = stats.plannedThisWeek;
    return Card(
      margin: EdgeInsets.zero,
      color: scheme.primaryContainer,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Diese Woche', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 10),
            Row(children: [
              _Tile(planned > 0 ? '${w.sessions}/$planned' : '${w.sessions}', 'Einheiten'),
              _Tile(_hours(w.minutes), 'Zeit'),
              _Tile(w.runMeters > 0 ? formatKm(w.runMeters) : '–', 'Laufen'),
              _Tile('${w.load}', 'Belastung'),
            ]),
            if (planned > 0) ...[
              const SizedBox(height: 10),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(value: (w.sessions / planned).clamp(0, 1), minHeight: 6),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _Highlights extends StatelessWidget {
  const _Highlights({required this.stats});
  final ProgressStats stats;

  @override
  Widget build(BuildContext context) {
    return Row(children: [
      _Tile('${stats.streakWeeks}', stats.streakWeeks == 1 ? 'Woche in Folge' : 'Wochen in Folge',
          icon: Icons.local_fire_department),
      _Tile(stats.plannedSoFar == 0 ? '–' : '${(stats.adherence * 100).round()} %', 'Plan umgesetzt',
          icon: Icons.task_alt),
      _Tile('${stats.sessions.length}', 'Einheiten gesamt', icon: Icons.emoji_events_outlined),
    ]);
  }
}

class _Bests extends StatelessWidget {
  const _Bests({required this.stats});
  final ProgressStats stats;

  @override
  Widget build(BuildContext context) {
    final bests = stats.recentBests.reversed.take(3);
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(children: [
              Icon(Icons.military_tech, color: AppColors.warning),
              SizedBox(width: 6),
              Text('Neue Bestleistungen', style: TextStyle(fontWeight: FontWeight.w700)),
            ]),
            for (final b in bests)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Row(children: [
                  Expanded(child: Text(b.label)),
                  Text(b.value, style: const TextStyle(fontWeight: FontWeight.w700)),
                  const SizedBox(width: 8),
                  Text(germanDate(b.date), style: Theme.of(context).textTheme.bodySmall),
                ]),
              ),
          ],
        ),
      ),
    );
  }
}

// ---------- Trainingszeit ----------

const _typeOrder = ['run', 'strength', 'hyrox_sim', 'mixed', 'recovery'];

class _TimeChart extends StatelessWidget {
  const _TimeChart({required this.stats});
  final ProgressStats stats;

  @override
  Widget build(BuildContext context) {
    final weeks = stats.weeks.sublist(stats.weeks.length - 8);
    final present = _typeOrder.where((t) => weeks.any((w) => (w.minutesByType[t] ?? 0) > 0)).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        StackedBarChart(
          format: (v) => _hours(v.round()),
          bars: [
            for (final w in weeks)
              BarData(
                '${w.monday.day}.${w.monday.month}.',
                [for (final t in _typeOrder) ((w.minutesByType[t] ?? 0).toDouble(), dayTypeColor(t))],
                highlight: w == weeks.last,
              ),
          ],
        ),
        if (present.isNotEmpty)
          Wrap(spacing: 12, children: [
            for (final t in present)
              Row(mainAxisSize: MainAxisSize.min, children: [
                Container(width: 10, height: 10, decoration: BoxDecoration(color: dayTypeColor(t), shape: BoxShape.circle)),
                const SizedBox(width: 4),
                Text(dayTypeLabels[t] ?? t, style: Theme.of(context).textTheme.labelSmall),
              ]),
          ]),
      ],
    );
  }
}

// ---------- Belastung ----------

class _LoadSection extends StatelessWidget {
  const _LoadSection({required this.stats});
  final ProgressStats stats;

  @override
  Widget build(BuildContext context) {
    if (stats.sessions.isEmpty) {
      return const _Empty('Sobald du Einheiten mit Anstrengung (RPE) speicherst, siehst du hier deine Belastung, '
          'Fitness und Ermüdung – wie bei Strava „Fitness & Form“.');
    }
    final weeks = stats.weeks.sublist(stats.weeks.length - 8);
    final curve = stats.loadCurve;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(children: [
          _Tile(stats.fitness.round().toString(), 'Fitness'),
          _Tile(stats.fatigue.round().toString(), 'Ermüdung'),
          _Tile((stats.form >= 0 ? '+' : '') + stats.form.round().toString(), 'Form'),
        ]),
        const SizedBox(height: 4),
        Text(stats.formLabel, style: const TextStyle(fontWeight: FontWeight.w600)),
        const SizedBox(height: 12),
        if (curve.length > 1)
          SimpleLineChart(
            series: [
              LineSeries('Fitness', curve.map((p) => p.fitness).toList(), AppColors.blue, fill: true),
              LineSeries('Ermüdung', curve.map((p) => p.fatigue).toList(), AppColors.hyroxSim),
            ],
            startLabel: germanDate(isoDate(curve.first.day)),
            endLabel: 'heute',
          ),
        const SizedBox(height: 16),
        Text('Belastung pro Woche', style: Theme.of(context).textTheme.labelLarge),
        const SizedBox(height: 4),
        StackedBarChart(
          height: 90,
          format: (v) => v.round().toString(),
          bars: [
            for (final w in weeks)
              BarData('${w.monday.day}.${w.monday.month}.', [(w.load.toDouble(), Theme.of(context).colorScheme.primary)],
                  highlight: w == weeks.last),
          ],
        ),
        if (stats.sessions.length < 6)
          const Padding(
            padding: EdgeInsets.only(top: 8),
            child: _Empty('Die Kurven werden nach 2–3 Wochen Training aussagekräftig.'),
          ),
      ],
    );
  }
}

// ---------- Laufen ----------

class _RunSection extends StatelessWidget {
  const _RunSection({required this.stats});
  final ProgressStats stats;

  @override
  Widget build(BuildContext context) {
    final runs = stats.sessions.where((s) => s.runMeters > 0).toList();
    if (runs.isEmpty) {
      return const _Empty('Noch keine Läufe mit Distanz gespeichert. Starte einen Lauf über „Lauf starten“ – '
          'Zeit und Distanz landen dann hier mit Pace und Wochen-km.');
    }
    final weeks = stats.weeks.sublist(stats.weeks.length - 8);
    final paced = runs.where((r) => r.pace != null).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(children: [
          _Tile(formatKm(stats.totalRunMeters), 'gesamt'),
          _Tile(formatKm(stats.longestRunMeters), 'längster Lauf'),
          _Tile(
            stats.bestPaceSec == null
                ? '–'
                : '${stats.bestPaceSec! ~/ 60}:${(stats.bestPaceSec! % 60).toString().padLeft(2, '0')}',
            'beste Pace /km',
          ),
        ]),
        const SizedBox(height: 12),
        StackedBarChart(
          height: 100,
          format: (v) => formatKm(v),
          bars: [
            for (final w in weeks)
              BarData('${w.monday.day}.${w.monday.month}.', [(w.runMeters, dayTypeColor('run'))], highlight: w == weeks.last),
          ],
        ),
        if (paced.length >= 2) ...[
          const SizedBox(height: 12),
          Text('Ø Pace je Lauf (niedriger = schneller)', style: Theme.of(context).textTheme.labelLarge),
          const SizedBox(height: 4),
          SimpleLineChart(
            height: 100,
            series: [
              LineSeries('Pace', paced.map((r) => r.runSec / (r.runMeters / 1000) / 60).toList(), dayTypeColor('run')),
            ],
            startLabel: germanDate(paced.first.date),
            endLabel: germanDate(paced.last.date),
          ),
        ],
      ],
    );
  }
}

// ---------- Kraft ----------

class _StrengthSection extends StatelessWidget {
  const _StrengthSection({required this.stats});
  final ProgressStats stats;

  @override
  Widget build(BuildContext context) {
    final records = stats.strengthRecords;
    if (records.isEmpty) {
      return const _Empty('Hake Kraftsätze mit Gewicht ab, dann siehst du hier pro Übung dein bestes Gewicht, '
          'das geschätzte 1RM und die Entwicklung – wie in Hevy oder Strong.');
    }
    return Column(
      children: [
        for (final r in records.take(12))
          Card(
            margin: const EdgeInsets.only(bottom: 8),
            child: ListTile(
              leading: const Icon(Icons.fitness_center),
              title: Text(r.name),
              subtitle: Text([
                'Bestes: ${formatKg(r.bestKg)} × ${r.bestKgReps}',
                if (r.bestE1rm > 0) '1RM ≈ ${formatKg(r.bestE1rm.roundToDouble())}',
              ].join('  ·  ')),
              trailing: r.history.length >= 2
                  ? SizedBox(
                      width: 64,
                      height: 32,
                      child: SimpleLineChart(
                        height: 32,
                        series: [LineSeries('', r.history.map((h) => h.topKg).toList(), dayTypeColor('strength'))],
                      ),
                    )
                  : null,
              onTap: () => _showExercise(context, r),
            ),
          ),
      ],
    );
  }

  void _showExercise(BuildContext context, ExerciseRecord r) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(r.name, style: Theme.of(ctx).textTheme.titleLarge),
              const SizedBox(height: 12),
              Row(children: [
                _Tile(formatKg(r.bestKg), 'bestes Gewicht'),
                _Tile(r.bestE1rm > 0 ? formatKg(r.bestE1rm.roundToDouble()) : '–', 'geschätztes 1RM'),
                _Tile('${r.maxReps}', 'max. Wdh.'),
              ]),
              const SizedBox(height: 16),
              if (r.history.length >= 2)
                SimpleLineChart(
                  series: [
                    LineSeries('Top-Gewicht', r.history.map((h) => h.topKg).toList(), dayTypeColor('strength'), fill: true),
                    if (r.history.any((h) => h.e1rm > 0))
                      LineSeries('1RM geschätzt', r.history.map((h) => h.e1rm).toList(), AppColors.dusk),
                  ],
                  startLabel: germanDate(r.history.first.date),
                  endLabel: germanDate(r.history.last.date),
                ),
              const SizedBox(height: 12),
              for (final h in r.history.reversed.take(6))
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 3),
                  child: Row(children: [
                    SizedBox(width: 90, child: Text(germanDate(h.date))),
                    Expanded(child: Text('Top ${formatKg(h.topKg)}')),
                    Text('Volumen ${h.volume.round()} kg', style: Theme.of(ctx).textTheme.bodySmall),
                  ]),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------- Hyrox-Rennen ----------

class _RaceSection extends StatelessWidget {
  const _RaceSection({required this.results});
  final List<Map<String, dynamic>> results;

  @override
  Widget build(BuildContext context) {
    final sorted = [...results]..sort((a, b) => b['date'].toString().compareTo(a['date'].toString()));
    final r = sorted.first;
    final prev = sorted.length > 1 ? sorted[1] : null;
    final runs = (r['runsSec'] as List).map((e) => (e as num).toInt()).toList();
    final stations = (r['stationsSec'] as List).map((e) => (e as num).toInt()).toList();
    final prevStations = prev == null ? null : (prev['stationsSec'] as List).map((e) => (e as num).toInt()).toList();
    final total = (r['totalTimeSec'] as num).toInt();
    final runSum = runs.fold(0, (a, b) => a + b);
    final stationSum = stations.fold(0, (a, b) => a + b);
    final rox = (r['roxzoneSec'] as num?)?.toInt();
    final maxStation = stations.reduce((a, b) => a > b ? a : b);
    final text = Theme.of(context).textTheme;

    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('${r['eventName'] ?? 'Rennen'} · ${germanDate(r['date'].toString())} ${r['date'].toString().substring(0, 4)}',
                style: text.bodySmall),
            const SizedBox(height: 4),
            Text(formatSec(total), style: text.headlineMedium?.copyWith(fontWeight: FontWeight.w800)),
            if (prev != null)
              Text(_delta(total - (prev['totalTimeSec'] as num).toInt(), 'zum Rennen davor'), style: text.bodySmall),
            const SizedBox(height: 12),
            // Anteile Laufen / Stationen / Roxzone
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: SizedBox(
                height: 14,
                child: Row(children: [
                  Expanded(flex: runSum, child: Container(color: dayTypeColor('run'))),
                  Expanded(flex: stationSum, child: Container(color: dayTypeColor('hyrox_sim'))),
                  if (rox != null && rox > 0) Expanded(flex: rox, child: Container(color: AppColors.greige)),
                ]),
              ),
            ),
            const SizedBox(height: 6),
            Wrap(spacing: 12, children: [
              Text('Laufen ${formatSec(runSum)} (${(runSum * 100 / total).round()} %)', style: text.labelSmall),
              Text('Stationen ${formatSec(stationSum)} (${(stationSum * 100 / total).round()} %)', style: text.labelSmall),
              if (rox != null) Text('Roxzone ${formatSec(rox)} (${(rox * 100 / total).round()} %)', style: text.labelSmall),
            ]),
            const SizedBox(height: 16),
            Text('Stationen', style: text.labelLarge),
            for (var i = 0; i < stations.length && i < hyroxStations.length; i++)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Row(children: [
                  SizedBox(width: 120, child: Text(hyroxStations[i], style: text.bodySmall)),
                  Expanded(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(3),
                      child: LinearProgressIndicator(
                        value: stations[i] / maxStation,
                        minHeight: 10,
                        color: stations[i] == maxStation ? AppColors.danger : dayTypeColor('hyrox_sim'),
                        backgroundColor: Theme.of(context).colorScheme.surfaceContainerHighest,
                      ),
                    ),
                  ),
                  SizedBox(width: 52, child: Text(formatSec(stations[i]), textAlign: TextAlign.right, style: text.bodySmall)),
                  if (prevStations != null)
                    SizedBox(
                      width: 48,
                      child: Text(
                        _short(stations[i] - prevStations[i]),
                        textAlign: TextAlign.right,
                        style: text.labelSmall?.copyWith(color: stations[i] <= prevStations[i] ? AppColors.success : AppColors.danger),
                      ),
                    ),
                ]),
              ),
            const SizedBox(height: 12),
            Text('Läufe: ${runs.map(formatSec).join(' · ')}', style: text.bodySmall),
          ],
        ),
      ),
    );
  }

  static String _short(int d) => d == 0 ? '±0' : (d < 0 ? '−${formatSec(-d)}' : '+${formatSec(d)}');
  static String _delta(int d, String suffix) =>
      d <= 0 ? '${formatSec(-d)} schneller $suffix' : '${formatSec(d)} langsamer $suffix';
}

// ---------- Verlauf ----------

class _History extends StatelessWidget {
  const _History({required this.stats});
  final ProgressStats stats;

  @override
  Widget build(BuildContext context) {
    if (stats.sessions.isEmpty) {
      return const _Empty('Hier erscheinen deine Trainings wie im Strava-Feed.');
    }
    final text = Theme.of(context).textTheme;
    return Column(
      children: [
        for (final s in stats.sessions.reversed.take(15))
          Card(
            margin: const EdgeInsets.only(bottom: 8),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  CircleAvatar(
                    backgroundColor: dayTypeColor(s.type).withValues(alpha: 0.15),
                    child: Icon(dayTypeIcon(s.type), color: dayTypeColor(s.type)),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(s.title, style: text.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
                        Text('${germanDate(s.date)} · ${dayTypeLabels[s.type] ?? s.type}', style: text.bodySmall),
                        const SizedBox(height: 6),
                        Wrap(spacing: 16, runSpacing: 4, children: [
                          _Mini('Zeit', '${s.minutes} Min'),
                          if (s.runMeters > 0) _Mini('Distanz', formatKm(s.runMeters)),
                          if (s.pace != null) _Mini('Pace', s.pace!),
                          if (s.volumeKg > 0) _Mini('Volumen', '${s.volumeKg.round()} kg'),
                          if (s.rpe != null) _Mini('RPE', '${s.rpe}/10'),
                          _Mini('Sätze', '${s.doneSets}'),
                        ]),
                        if (s.feedback != null)
                          Padding(
                            padding: const EdgeInsets.only(top: 6),
                            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              const Icon(Icons.sports, size: 14, color: AppColors.blue),
                              const SizedBox(width: 6),
                              Expanded(child: Text(s.feedback!, style: text.bodySmall)),
                            ]),
                          ),
                        if (s.notes != null && s.notes!.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(top: 6),
                            child: Text('„${s.notes}“', style: text.bodySmall?.copyWith(fontStyle: FontStyle.italic)),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

class _Mini extends StatelessWidget {
  const _Mini(this.label, this.value);
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: Theme.of(context).textTheme.labelSmall),
          Text(value, style: const TextStyle(fontWeight: FontWeight.w700)),
        ],
      );
}


// ---------- Benchmarks ----------

class _BenchmarkSection extends StatelessWidget {
  const _BenchmarkSection({required this.stats});
  final ProgressStats stats;

  @override
  Widget build(BuildContext context) {
    if (stats.benchmarks.isEmpty) {
      return const _Empty('Der Plan enthält regelmäßig Leistungstests (z. B. 1000 m SkiErg oder 100 Wall Balls). '
          'Deine Zeiten erscheinen hier und fließen in die Rennprognose ein.');
    }
    final text = Theme.of(context).textTheme;
    return Column(children: [
      for (final e in stats.benchmarks.entries)
        Card(
          margin: const EdgeInsets.only(bottom: 8),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(children: [
              const Icon(Icons.timer_outlined, color: AppColors.race),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(e.key, style: text.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
                  Text('${e.value.length} Tests · Bestzeit ${formatSec(e.value.map((b) => b.sec).reduce((a, b) => a < b ? a : b))}',
                      style: text.bodySmall),
                ]),
              ),
              Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                Text(formatSec(e.value.last.sec), style: text.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
                if (e.value.length > 1)
                  Builder(builder: (_) {
                    final d = e.value.last.sec - e.value[e.value.length - 2].sec;
                    return Text(
                      d <= 0 ? '−${formatSec(-d)}' : '+${formatSec(d)}',
                      style: text.labelSmall?.copyWith(color: d <= 0 ? AppColors.success : AppColors.danger),
                    );
                  }),
              ]),
            ]),
          ),
        ),
    ]);
  }
}

// ---------- Prognose ----------

class _PredictionCard extends StatelessWidget {
  const _PredictionCard({required this.state});
  final AppState state;

  @override
  Widget build(BuildContext context) {
    final p = RacePrediction.build(anamnese: state.anamnese, results: state.results, workouts: state.workouts);
    final race = nextRace(state.anamnese, preferA: true);
    final text = Theme.of(context).textTheme;
    return Card(
      margin: EdgeInsets.zero,
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: race == null
            ? null
            : () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => RaceScreen(race: race))),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(race == null ? 'Wenn du heute starten würdest' : '${race['name']} · ${germanDate(race['date'].toString())}',
                    style: text.bodySmall),
                Text(formatSec(p.totalSec), style: text.headlineMedium?.copyWith(fontWeight: FontWeight.w800)),
                Text('Spanne ${formatSec(p.lowSec)} – ${formatSec(p.highSec)} · Sicherheit ${p.confidence}', style: text.bodySmall),
              ]),
            ),
            if (race != null) const Icon(Icons.chevron_right),
          ]),
        ),
      ),
    );
  }
}
