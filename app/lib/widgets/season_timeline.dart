import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../util.dart';

class SeasonPhase {
  const SeasonPhase(this.label, this.start, this.end, this.color);
  final String label;
  final DateTime start; // erster Tag
  final DateTime end; // letzter Tag
  final Color color;
  int get days => end.difference(start).inDays + 1;
}

/// Grobe Saisonplanung bis zum Peak (ohne KI): Aufbau → spezifisch → Taper → Rennen → Regeneration.
/// Die Detailplanung passiert blockweise; das hier ist nur der Überblick, wo man gerade steht.
class Season {
  Season({required this.phases, required this.title, this.peak});
  final List<SeasonPhase> phases;
  final String title;
  final DateTime? peak;

  DateTime get start => phases.first.start;
  DateTime get end => phases.last.end;

  static Season build(Map<String, dynamic>? anamnese, DateTime now) {
    final monday = mondayOf(now);
    final goal = anamnese?['goal'] is Map ? anamnese!['goal'] as Map : const {};
    DateTime? peak;
    String? peakName;
    if (goal['mode'] == 'race') {
      final race = nextRace(anamnese, preferA: true);
      if (race != null) {
        peak = parseIso(race['date'].toString());
        peakName = race['name'].toString();
      }
    } else if (goal['mode'] == 'horizon' && goal['horizonDate'] != null) {
      peak = parseIso(goal['horizonDate'].toString());
      peakName = 'Bestform';
    }

    if (peak == null) {
      // Offenes Ziel: Zyklen aus 3 Wochen Aufbau + 1 Woche Entlastung
      final phases = <SeasonPhase>[];
      var s = monday;
      for (var i = 0; i < 3; i++) {
        phases.add(SeasonPhase('Aufbau', s, s.add(const Duration(days: 20)), AppColors.dusk));
        phases.add(SeasonPhase('Entlastung', s.add(const Duration(days: 21)), s.add(const Duration(days: 27)), AppColors.greige));
        s = s.add(const Duration(days: 28));
      }
      return Season(phases: phases, title: 'Offener Aufbau in 4-Wochen-Zyklen');
    }

    final days = peak.difference(monday).inDays;
    final taperStart = peak.subtract(Duration(days: math.min(10, math.max(3, days ~/ 4))));
    final specificDays = math.min(56, (taperStart.difference(monday).inDays * 0.45).round());
    final specificStart = taperStart.subtract(Duration(days: specificDays));
    final phases = <SeasonPhase>[
      if (specificStart.isAfter(monday))
        SeasonPhase('Aufbau', monday, specificStart.subtract(const Duration(days: 1)), AppColors.dusk),
      if (specificDays > 0)
        SeasonPhase('Spezifisch', specificStart.isAfter(monday) ? specificStart : monday,
            taperStart.subtract(const Duration(days: 1)), AppColors.blue),
      SeasonPhase('Taper', taperStart.isAfter(monday) ? taperStart : monday, peak.subtract(const Duration(days: 1)),
          AppColors.hyroxSim),
      SeasonPhase(goal['mode'] == 'race' ? 'Rennen' : 'Peak', peak, peak, AppColors.race),
      SeasonPhase('Regeneration', peak.add(const Duration(days: 1)), peak.add(const Duration(days: 7)), AppColors.recovery),
    ].where((p) => !p.end.isBefore(p.start)).toList();
    final weeks = (days / 7).ceil();
    return Season(phases: phases, title: '$peakName in $weeks ${weeks == 1 ? 'Woche' : 'Wochen'}', peak: peak);
  }
}

/// Saisonübersicht als Zeitleiste mit Phasen, Blöcken, Rennen und Heute-Markierung.
class SeasonTimeline extends StatelessWidget {
  const SeasonTimeline({super.key, required this.anamnese, required this.blocks});

  final Map<String, dynamic>? anamnese;
  final List<(DateTime start, DateTime end, bool upcoming)> blocks; // aktiver Block und ggf. Folgeblock

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final season = Season.build(anamnese, now);
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final total = season.end.difference(season.start).inDays + 1;
    final current = season.phases.where((p) => !now.isBefore(p.start) && !now.isAfter(p.end.add(const Duration(days: 1)))).firstOrNull;
    final races = racesOf(anamnese)
        .map((r) => (parseIso(r['date'].toString()), r))
        .where((r) => !r.$1.isBefore(season.start) && !r.$1.isAfter(season.end) && r.$1 != season.peak)
        .toList();

    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            const Icon(Icons.timeline, size: 18),
            const SizedBox(width: 6),
            Expanded(child: Text(season.title, style: text.titleSmall?.copyWith(fontWeight: FontWeight.w700))),
            if (current != null)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(color: current.color, borderRadius: BorderRadius.circular(8)),
                child: Text(current.label, style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w700)),
              ),
          ]),
          const SizedBox(height: 10),
          LayoutBuilder(builder: (context, c) {
            double x(DateTime d) => (d.difference(season.start).inDays / total * c.maxWidth).clamp(0, c.maxWidth);
            final todayX = x(DateTime(now.year, now.month, now.day));
            return SizedBox(
              height: 34,
              child: Stack(clipBehavior: Clip.none, children: [
                // Phasen
                Positioned(
                  top: 8,
                  left: 0,
                  right: 0,
                  height: 12,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: Row(children: [
                      for (final p in season.phases) Expanded(flex: math.max(1, p.days), child: Container(color: p.color)),
                    ]),
                  ),
                ),
                // Blöcke als Klammer darunter
                for (final (s, e, upcoming) in blocks)
                  if (!e.isBefore(season.start) && !s.isAfter(season.end))
                    Positioned(
                      top: 24,
                      left: x(s),
                      width: math.max(2, x(e.add(const Duration(days: 1))) - x(s)),
                      height: 4,
                      child: Container(
                        margin: const EdgeInsets.symmetric(horizontal: 1),
                        decoration: BoxDecoration(
                          color: upcoming ? scheme.outline : scheme.onSurface,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                // weitere Rennen
                for (final (d, _) in races)
                  Positioned(
                    top: 6,
                    left: x(d) - 8,
                    child: const Icon(Icons.emoji_events, size: 16, color: AppColors.race),
                  ),
                // Heute
                Positioned(
                  top: 0,
                  left: todayX - 1,
                  width: 2,
                  height: 28,
                  child: Container(color: scheme.onSurface),
                ),
              ]),
            );
          }),
          const SizedBox(height: 6),
          Wrap(spacing: 12, runSpacing: 4, children: [
            for (final p in {for (final p in season.phases) p.label: p}.values) // jede Phase nur einmal
              Row(mainAxisSize: MainAxisSize.min, children: [
                Container(width: 8, height: 8, decoration: BoxDecoration(color: p.color, shape: BoxShape.circle)),
                const SizedBox(width: 4),
                Text(p.label == 'Rennen' || p.label == 'Peak' ? '${p.label} ${germanDate(isoDate(p.start))}' : p.label,
                    style: text.labelSmall),
              ]),
            if (blocks.isNotEmpty)
              Row(mainAxisSize: MainAxisSize.min, children: [
                Container(width: 12, height: 3, color: scheme.onSurface),
                const SizedBox(width: 4),
                Text(blocks.any((b) => b.$3) ? 'Blöcke (grau = nächster)' : 'aktueller Block', style: text.labelSmall),
              ]),
          ]),
        ]),
      ),
    );
  }
}
