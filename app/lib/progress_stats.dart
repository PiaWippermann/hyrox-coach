import 'dart:math' as math;

import 'util.dart';

/// Auswertung der protokollierten Trainings, komplett lokal und ohne KI.
/// Belastung = Session-RPE (RPE × Minuten), das funktioniert ohne Pulsgurt.
/// Fitness/Ermüdung/Form wie bei Strava/TrainingPeaks: gleitende Mittel über 42 bzw. 7 Tage.

class WorkoutStat {
  WorkoutStat({
    required this.date,
    required this.title,
    required this.type,
    required this.minutes,
    required this.rpe,
    required this.runMeters,
    required this.runSec,
    required this.volumeKg,
    required this.doneSets,
    required this.notes,
    this.feedback,
  });

  final String date;
  final String title;
  final String type; // dayType
  final int minutes;
  final int? rpe;
  final double runMeters;
  final int runSec; // Zeit der Laufabschnitte mit Distanz (für Pace)
  final double volumeKg; // Σ kg × Wdh.
  final int doneSets;
  final String? notes;
  final String? feedback; // Coach-Feedback nach dem Training

  int get load => (rpe ?? 5) * minutes;
  String? get pace => formatPace(runSec, runMeters);
}

class WeekStat {
  WeekStat(this.monday);
  final DateTime monday;
  final Map<String, int> minutesByType = {};
  int sessions = 0;
  int load = 0;
  double runMeters = 0;
  int get minutes => minutesByType.values.fold(0, (a, b) => a + b);
}

class ExerciseRecord {
  ExerciseRecord(this.name);
  final String name;
  double bestKg = 0;
  int bestKgReps = 0;
  double bestE1rm = 0;
  int maxReps = 0;
  String lastDate = '';
  /// Pro Einheit: Datum, geschätztes 1RM, Top-Gewicht, Volumen
  final List<({String date, double e1rm, double topKg, double volume})> history = [];
  bool get weighted => bestKg > 0;
}

class PersonalBest {
  PersonalBest(this.date, this.label, this.value);
  final String date;
  final String label;
  final String value;
}

class ProgressStats {
  ProgressStats._();

  final List<WorkoutStat> sessions = [];
  final List<WeekStat> weeks = []; // chronologisch, lückenlos, max. 12 Wochen bis heute
  final Map<String, ExerciseRecord> exercises = {};
  final List<PersonalBest> recentBests = [];
  /// Benchmark-Tests je Übung, chronologisch: Datum und Zeit in Sekunden.
  final Map<String, List<({String date, int sec})>> benchmarks = {};

  int plannedSoFar = 0; // geplante Einheiten bis heute
  int doneOfPlanned = 0;
  int plannedThisWeek = 0;
  int streakWeeks = 0;

  double fitness = 0; // CTL
  double fatigue = 0; // ATL
  final List<({DateTime day, double fitness, double fatigue})> loadCurve = [];

  double totalRunMeters = 0;
  double longestRunMeters = 0;
  int? bestPaceSec; // schnellste Pace eines Laufabschnitts ab 400 m, Sek./km

  double get form => fitness - fatigue;
  double get adherence => plannedSoFar == 0 ? 0 : doneOfPlanned / plannedSoFar;
  WeekStat get thisWeek => weeks.last;

  static ProgressStats build(List<Map<String, dynamic>> workouts, Map<String, dynamic>? plan, DateTime now,
      {Map<String, dynamic>? anamnese}) {
    final s = ProgressStats._();
    final today = isoDate(now);

    // Plan-Tage nach Datum, um jedem Training seine Art zuzuordnen
    final planDays = <String, Map<String, dynamic>>{};
    for (final w in asMapList(plan?['weeks'])) {
      for (final d in asMapList(w['days'])) {
        planDays[d['date'].toString()] = d;
      }
    }

    final sorted = [...workouts]..sort((a, b) => a['date'].toString().compareTo(b['date'].toString()));
    for (final w in sorted) {
      s._addWorkout(w, planDays);
    }

    // Wochen: die letzten 12 bis einschließlich der aktuellen
    final currentMonday = mondayOf(now);
    for (var i = 11; i >= 0; i--) {
      s.weeks.add(WeekStat(currentMonday.subtract(Duration(days: 7 * i))));
    }
    for (final w in s.sessions) {
      final m = mondayOf(parseIso(w.date));
      final week = s.weeks.where((x) => x.monday == m).firstOrNull;
      if (week == null) continue;
      week.sessions++;
      week.load += w.load;
      week.runMeters += w.runMeters;
      week.minutesByType[w.type] = (week.minutesByType[w.type] ?? 0) + w.minutes;
    }

    // Serie: Wochen in Folge mit mindestens einem Training (aktuelle Woche zählt, wenn schon trainiert)
    for (var i = s.weeks.length - 1; i >= 0; i--) {
      if (s.weeks[i].sessions > 0) {
        s.streakWeeks++;
      } else if (i != s.weeks.length - 1) {
        break;
      }
    }

    // Plan-Umsetzung
    final done = sorted.where((w) => w['fixed'] != true).map((w) => doneKey(w['date'].toString(), w['dayTitle'])).toSet();
    final weekStart = isoDate(currentMonday);
    final weekEnd = isoDate(currentMonday.add(const Duration(days: 6)));
    for (final d in planDays.values) {
      if (d['dayType'] == 'rest' || d['dayType'] == 'race' || isFixedDuplicate(anamnese, d)) continue;
      final date = d['date'].toString();
      if (date.compareTo(weekStart) >= 0 && date.compareTo(weekEnd) <= 0) s.plannedThisWeek++;
      // Vergangene Tage zählen immer, heute nur wenn schon erledigt
      final isDone = done.contains(doneKey(date, d['title']));
      final cmp = date.compareTo(today);
      if (cmp < 0 || (cmp == 0 && isDone)) {
        s.plannedSoFar++;
        if (isDone) s.doneOfPlanned++;
      }
    }

    s._buildLoadCurve(now);
    return s;
  }

  void _addWorkout(Map<String, dynamic> w, Map<String, Map<String, dynamic>> planDays) {
    final date = w['date'].toString();
    var runMeters = 0.0;
    var runSec = 0;
    var volume = 0.0;
    var doneSets = 0;
    var hasWeighted = false;
    var longest = 0.0;

    for (final e in asMapList(w['exercises'])) {
      if (e['skipped'] == true) continue;
      final sets = asMapList(e['sets']);
      if (sets.isEmpty) continue;
      doneSets += sets.length;
      final kind = exerciseKind({'name': e['name'], 'station': e['station']});
      final name = e['name'].toString();
      if (e['benchmark'] == true) {
        final sec = sets.map((x) => (x['durationSec'] as num?)?.toInt()).whereType<int>().where((x) => x > 0).firstOrNull;
        if (sec != null) {
          final list = benchmarks.putIfAbsent(name, () => []);
          if (list.isNotEmpty && sec < list.map((b) => b.sec).reduce(math.min)) {
            recentBests.add(PersonalBest(date, '$name (Test)', formatSec(sec)));
          }
          list.add((date: date, sec: sec));
        }
      }

      if (kind == ExerciseKind.run) {
        for (final set in sets) {
          final m = (set['distanceM'] as num?)?.toDouble() ?? 0;
          final sec = (set['durationSec'] as num?)?.toInt() ?? 0;
          runMeters += m;
          longest += m;
          if (m > 0 && sec > 0) {
            runSec += sec;
            if (m >= 400) {
              final pace = (sec / (m / 1000)).round();
              if (bestPaceSec == null || pace < bestPaceSec!) {
                if (bestPaceSec != null) recentBests.add(PersonalBest(date, 'Schnellste Pace', formatPace(sec, m)!));
                bestPaceSec = pace;
              }
            }
          }
        }
        continue;
      }

      // Kraft: Rekorde und geschätztes 1RM (Epley, nur bis 12 Wdh. sinnvoll)
      final rec = exercises.putIfAbsent(name.toLowerCase(), () => ExerciseRecord(name));
      var topKg = 0.0;
      var e1rm = 0.0;
      var vol = 0.0;
      for (final set in sets) {
        final kg = (set['loadKg'] as num?)?.toDouble() ?? 0;
        final reps = (set['reps'] as num?)?.toInt() ?? 0;
        if (reps > rec.maxReps) rec.maxReps = reps;
        if (kg <= 0) continue;
        hasWeighted = true;
        vol += kg * math.max(reps, 1);
        if (kg > topKg) topKg = kg;
        if (reps > 0 && reps <= 12) e1rm = math.max(e1rm, kg * (1 + reps / 30));
        if (kg > rec.bestKg || (kg == rec.bestKg && reps > rec.bestKgReps)) {
          if (rec.bestKg > 0 && kg > rec.bestKg) {
            recentBests.add(PersonalBest(date, name, '${_kg(kg)} kg × $reps'));
          }
          rec.bestKg = kg;
          rec.bestKgReps = reps;
        }
      }
      volume += vol;
      rec.lastDate = date;
      if (e1rm > rec.bestE1rm) rec.bestE1rm = e1rm;
      if (topKg > 0) rec.history.add((date: date, e1rm: e1rm, topKg: topKg, volume: vol));
    }

    totalRunMeters += runMeters;
    if (longest > longestRunMeters) {
      if (longestRunMeters > 0) recentBests.add(PersonalBest(date, 'Längster Lauf', formatKm(longest)));
      longestRunMeters = longest;
    }

    final planDay = planDays[date];
    final type = w['dayType']?.toString() ??
        planDay?['dayType']?.toString() ??
        (runMeters > 0 && !hasWeighted ? 'run' : (hasWeighted && runMeters == 0 ? 'strength' : 'mixed'));

    sessions.add(WorkoutStat(
      date: date,
      title: w['dayTitle']?.toString() ?? 'Training',
      type: type,
      minutes: (w['durationMin'] as num?)?.toInt() ?? 0,
      rpe: (w['rpe'] as num?)?.toInt(),
      runMeters: runMeters,
      runSec: runSec,
      volumeKg: volume,
      doneSets: doneSets,
      notes: w['notes']?.toString(),
      feedback: w['feedback']?.toString(),
    ));
  }

  void _buildLoadCurve(DateTime now) {
    if (sessions.isEmpty) return;
    final daily = <String, int>{};
    for (final w in sessions) {
      daily[w.date] = (daily[w.date] ?? 0) + w.load;
    }
    var day = parseIso(sessions.first.date);
    final end = DateTime(now.year, now.month, now.day);
    final curveStart = end.subtract(const Duration(days: 56));
    while (!day.isAfter(end)) {
      final load = (daily[isoDate(day)] ?? 0).toDouble();
      fitness += (load - fitness) / 42;
      fatigue += (load - fatigue) / 7;
      if (!day.isBefore(curveStart)) loadCurve.add((day: day, fitness: fitness, fatigue: fatigue));
      day = day.add(const Duration(days: 1));
    }
  }

  /// Einschätzung der Form wie bei Strava "Fitness & Freshness".
  String get formLabel {
    if (sessions.length < 3) return 'Noch zu wenig Daten';
    final f = form;
    if (f > 10) return 'Frisch – gut für einen harten Tag oder ein Rennen';
    if (f > -10) return 'Ausgeglichen';
    if (f > -30) return 'Im Aufbau – produktive Belastung';
    return 'Hohe Ermüdung – Erholung einplanen';
  }

  List<ExerciseRecord> get strengthRecords =>
      exercises.values.where((e) => e.weighted).toList()..sort((a, b) => b.lastDate.compareTo(a.lastDate));
}

String _kg(double kg) => kg == kg.roundToDouble() ? kg.round().toString() : kg.toStringAsFixed(1).replaceAll('.', ',');
String formatKg(double kg) => '${_kg(kg)} kg';

const hyroxStations = [
  'SkiErg', 'Sled Push', 'Sled Pull', 'Burpee Broad Jumps', 'Rudern', 'Farmers Carry', 'Sandbag Lunges', 'Wall Balls',
];
