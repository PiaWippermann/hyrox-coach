import 'package:flutter/material.dart';
import 'theme/app_colors.dart';

const weekdayShort = ['Mo', 'Di', 'Mi', 'Do', 'Fr', 'Sa', 'So'];
const weekdayLong = ['Montag', 'Dienstag', 'Mittwoch', 'Donnerstag', 'Freitag', 'Samstag', 'Sonntag'];

const dayTypeLabels = {
  'run': 'Laufen',
  'strength': 'Kraft',
  'hyrox_sim': 'Hyrox-Simulation',
  'mixed': 'Mixed',
  'recovery': 'Regeneration',
  'rest': 'Ruhetag',
  'race': 'Rennen',
};

String isoDate(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

DateTime parseIso(String s) {
  final p = s.split('-');
  return DateTime(int.parse(p[0]), int.parse(p[1]), int.parse(p[2]));
}

String germanDate(String iso) {
  final d = parseIso(iso);
  return '${weekdayShort[d.weekday - 1]}, ${d.day.toString().padLeft(2, '0')}.${d.month.toString().padLeft(2, '0')}.';
}

/// "mm:ss" oder "h:mm:ss" -> Sekunden, sonst null.
int? parseTimeSec(String input) {
  final s = input.trim();
  if (s.isEmpty) return null;
  final parts = s.split(':');
  if (parts.length < 2 || parts.length > 3) return null;
  final nums = parts.map(int.tryParse).toList();
  if (nums.any((n) => n == null)) return null;
  if (parts.length == 2) return nums[0]! * 60 + nums[1]!;
  return nums[0]! * 3600 + nums[1]! * 60 + nums[2]!;
}

String formatSec(int s) {
  final h = s ~/ 3600;
  final m = (s % 3600) ~/ 60;
  final sec = s % 60;
  final mm = m.toString().padLeft(2, '0');
  final ss = sec.toString().padLeft(2, '0');
  return h > 0 ? '$h:$mm:$ss' : '$mm:$ss';
}

List<Map<String, dynamic>> asMapList(dynamic v) {
  if (v is! List) return [];
  return v.map((e) => Map<String, dynamic>.from(e as Map)).toList();
}

String _num(num n) => n == n.roundToDouble() ? n.round().toString() : n.toString();

/// Kurzbeschreibung der Vorgabe einer Übung, z. B. "4 × 6 · 70 kg · Pause 120 s".
String describeExercise(Map<String, dynamic> e) {
  final parts = <String>[];
  final sets = e['sets'];
  final reps = e['reps'];
  if (sets != null && reps != null) {
    parts.add('$sets × $reps');
  } else if (sets != null) {
    parts.add('$sets Sätze');
  } else if (reps != null) {
    parts.add('$reps Wdh.');
  }
  if (e['distanceM'] is num) parts.add('${_num(e['distanceM'] as num)} m');
  if (e['durationSec'] is num) parts.add(formatSec((e['durationSec'] as num).round()));
  if (e['loadKg'] is num) parts.add('${_num(e['loadKg'] as num)} kg');
  if (e['loadNote'] != null) parts.add(e['loadNote'].toString());
  if (e['targetPace'] != null) parts.add(e['targetPace'].toString());
  if (e['restSec'] is num) parts.add('Pause ${_num(e['restSec'] as num)} s');
  if (e['rpeTarget'] is num) parts.add('RPE ${_num(e['rpeTarget'] as num)}');
  return parts.join(' · ');
}

// ---------- Darstellung je Trainingsart ----------
const dayTypeIcons = {
  'run': Icons.directions_run,
  'strength': Icons.fitness_center,
  'hyrox_sim': Icons.bolt,
  'mixed': Icons.shuffle,
  'recovery': Icons.self_improvement,
  'rest': Icons.bedtime_outlined,
  'race': Icons.emoji_events,
};

const dayTypeColors = {
  'run': AppColors.run,
  'strength': AppColors.strength,
  'hyrox_sim': AppColors.hyroxSim,
  'mixed': AppColors.mixed,
  'recovery': AppColors.recovery,
  'rest': AppColors.rest,
  'race': AppColors.race,
};

Color dayTypeColor(String? type) => dayTypeColors[type] ?? AppColors.rest;
IconData dayTypeIcon(String? type) => dayTypeIcons[type] ?? Icons.event;

// ---------- Übungsarten ----------
/// Wie eine Übung beim Training erfasst wird.
enum ExerciseKind { run, cardio, weighted, bodyweight, timed }

const _cardioStations = {'skierg', 'rowing'};
const _weightedStations = {'sled_push', 'sled_pull', 'farmers_carry', 'sandbag_lunges', 'wall_balls'};
final _runName = RegExp(r'\b(lauf|laufen|jog|run|tempolauf|intervall|einlaufen|auslaufen|laufband)', caseSensitive: false);
final _cardioName = RegExp(r'(skierg|ski-erg|rudern|rower|row erg|bike|rad|assault|echo)', caseSensitive: false);
// Übungen, die praktisch immer mit Zusatzgewicht gemacht werden, auch wenn der Plan kein loadKg nennt
final _weightedName = RegExp(
    r'(hantel|\bKH\b|\bLH\b|kettlebell|\bKB\b|sandbag|goblet|kreuzheben|kniebeuge|bankdrück|schulterdrück|'
    r'squat|deadlift|thruster|swing|farmer|wall ?ball|sled|schlitten|kabelzug|clean|snatch|press)',
    caseSensitive: false);
final _bodyweightName = RegExp(r'(band|körpergewicht|bodyweight|air squat|jump squat)', caseSensitive: false);

/// [hadLoad]: die Übung wurde früher schon mit Gewicht protokolliert.
ExerciseKind exerciseKind(Map<String, dynamic> e, {bool hadLoad = false}) {
  // loadKg 0 heißt Körpergewicht (z. B. Klimmzüge)
  if (e['loadKg'] is num && (e['loadKg'] as num) <= 0) e = {...e}..remove('loadKg');
  final station = e['station']?.toString();
  final name = e['name']?.toString() ?? '';
  if (station == 'run' || e['targetPace'] != null || (station == null && _runName.hasMatch(name) && e['loadKg'] == null)) {
    return ExerciseKind.run;
  }
  if (_cardioStations.contains(station) || (e['loadKg'] == null && _cardioName.hasMatch(name) && e['reps'] == null)) {
    return ExerciseKind.cardio;
  }
  if (e['loadKg'] != null || _weightedStations.contains(station) || hadLoad) return ExerciseKind.weighted;
  if (_weightedName.hasMatch(name) && !_bodyweightName.hasMatch(name)) return ExerciseKind.weighted;
  if (e['reps'] != null) return ExerciseKind.bodyweight;
  return ExerciseKind.timed;
}

/// Geplante Laufdistanz eines Tages in Metern (Gym-Variante bevorzugt). Null, wenn nur nach Zeit geplant.
double? plannedRunMeters(Map<String, dynamic> day, [String? location]) {
  final variants = asMapList(day['variants']);
  if (variants.isEmpty) return null;
  final v = variants.firstWhere((x) => x['location'] == location, orElse: () => variants.first);
  var meters = 0.0;
  for (final b in asMapList(v['blocks'])) {
    final rounds = (b['rounds'] as num?)?.toInt() ?? 1;
    for (final e in asMapList(b['exercises'])) {
      if (exerciseKind(e) != ExerciseKind.run) continue;
      final d = (e['distanceM'] as num?)?.toDouble();
      if (d != null) meters += d * ((e['sets'] as num?)?.toInt() ?? 1) * rounds;
    }
  }
  return meters > 0 ? meters : null;
}

String formatKm(double meters) {
  final km = meters / 1000;
  return '${km.toStringAsFixed(km >= 10 ? 0 : 1).replaceAll('.', ',')} km';
}

/// Pace als "m:ss/km" aus Sekunden und Metern.
String? formatPace(int? sec, double? meters) {
  if (sec == null || meters == null || sec <= 0 || meters <= 0) return null;
  final perKm = (sec / (meters / 1000)).round();
  return '${perKm ~/ 60}:${(perKm % 60).toString().padLeft(2, '0')}/km';
}

/// Montag der Woche zu [d].
DateTime mondayOf(DateTime d) => DateTime(d.year, d.month, d.day).subtract(Duration(days: d.weekday - 1));

/// Kalenderwoche Mo–So für die Anzeige. Tage außerhalb des Plans sind null.
class CalendarWeek {
  CalendarWeek(this.monday, this.days, this.theme);
  final DateTime monday;
  final List<Map<String, dynamic>?> days; // genau 7, Mo..So
  final String? theme;
  Iterable<Map<String, dynamic>> get planDays => days.whereType<Map<String, dynamic>>();
}

/// Ordnet die Plantage Kalenderwochen (Montag bis Sonntag) zu, egal an welchem Wochentag der Plan beginnt.
/// [next] ist ein optionaler Folgeblock, dessen Tage direkt angehängt werden.
List<CalendarWeek> calendarWeeks(Map<String, dynamic> plan, [Map<String, dynamic>? next]) {
  final byDate = <String, Map<String, dynamic>>{};
  final themeByDate = <String, String>{};
  for (final w in [...asMapList(plan['weeks']), ...asMapList(next?['weeks'])]) {
    for (final d in asMapList(w['days'])) {
      byDate[d['date'].toString()] = d;
      themeByDate[d['date'].toString()] = w['theme']?.toString() ?? '';
    }
  }
  if (byDate.isEmpty) return [];
  final dates = byDate.keys.toList()..sort();
  var monday = mondayOf(parseIso(dates.first));
  final last = parseIso(dates.last);
  final weeks = <CalendarWeek>[];
  while (!monday.isAfter(last)) {
    final days = [for (var i = 0; i < 7; i++) byDate[isoDate(monday.add(Duration(days: i)))]];
    // Thema der Plan-Woche, zu der die meisten Tage dieser Kalenderwoche gehören
    final counts = <String, int>{};
    for (var i = 0; i < 7; i++) {
      final t = themeByDate[isoDate(monday.add(Duration(days: i)))];
      if (t != null && t.isNotEmpty) counts[t] = (counts[t] ?? 0) + 1;
    }
    final theme = counts.isEmpty ? null : (counts.entries.toList()..sort((a, b) => b.value - a.value)).first.key;
    weeks.add(CalendarWeek(monday, days, theme));
    monday = monday.add(const Duration(days: 7));
  }
  return weeks;
}

/// Nächster Montag (heute, wenn heute Montag ist).
DateTime nextMonday(DateTime now) {
  final d = DateTime(now.year, now.month, now.day);
  return d.weekday == DateTime.monday ? d : d.add(Duration(days: 8 - d.weekday));
}

/// Zahl ohne überflüssige Nachkommastellen, mit deutschem Komma.
String fmtNum(double d) => d == d.roundToDouble() ? d.round().toString() : d.toString().replaceAll('.', ',');

// ---------- Feste Termine (Kurse) ----------
/// Feste Termine aus der Anamnese, die auf [date] fallen, nach Uhrzeit sortiert.
List<Map<String, dynamic>> fixedSessionsOn(Map<String, dynamic>? anamnese, String date) {
  final schedule = anamnese?['schedule'];
  if (schedule is! Map) return [];
  final weekday = parseIso(date).weekday;
  return asMapList(schedule['fixedSessions']).where((f) => f['weekday'] == weekday).toList()
    ..sort((a, b) => a['time'].toString().compareTo(b['time'].toString()));
}

/// Schlüssel für „erledigt“: Datum + Titel, damit Kurs und Training am selben Tag getrennt zählen.
String doneKey(String date, Object? title) => '$date|$title';

// ---------- Rennen ----------
const racePriorityLabels = {'A': 'Hauptrennen', 'B': 'Wichtiges Rennen', 'C': 'Trainingsrennen'};

/// Rennen aus der Anamnese; übernimmt ein altes Einzel-Renndatum als A-Rennen.
List<Map<String, dynamic>> racesOf(Map<String, dynamic>? anamnese) {
  final goal = anamnese?['goal'];
  if (goal is! Map) return [];
  final races = asMapList(goal['races']);
  if (races.isEmpty && goal['raceDate'] != null) {
    races.add({'name': 'Rennen', 'date': goal['raceDate'], 'priority': 'A', 'category': goal['category'] ?? 'single'});
  }
  return races..sort((a, b) => a['date'].toString().compareTo(b['date'].toString()));
}

List<Map<String, dynamic>> racesOn(Map<String, dynamic>? anamnese, String date) =>
    racesOf(anamnese).where((r) => r['date'] == date).toList();

/// Nächstes Rennen ab heute (A-Rennen bevorzugt nur, wenn [preferA]).
Map<String, dynamic>? nextRace(Map<String, dynamic>? anamnese, {bool preferA = false}) {
  final today = isoDate(DateTime.now());
  final upcoming = racesOf(anamnese).where((r) => r['date'].toString().compareTo(today) >= 0).toList();
  if (upcoming.isEmpty) return null;
  return preferA ? (upcoming.where((r) => r['priority'] == 'A').firstOrNull ?? upcoming.first) : upcoming.first;
}

/// Ist [day] eigentlich der feste Termin selbst (z. B. Plantag „Hyrox-Kurs (abends)“ und Termin „Hyrox-Kurs“)?
/// Ältere Pläne enthalten Kurse noch als eigene Einheit; die App zeigt dann nur den abhakbaren Termin.
bool isFixedDuplicate(Map<String, dynamic>? anamnese, Map<String, dynamic> day) {
  if (day['dayType'] == 'rest' || day['dayType'] == 'race') return false;
  final title = day['title'].toString().toLowerCase().trim();
  for (final f in fixedSessionsOn(anamnese, day['date'].toString())) {
    // Kern des Termin-Namens: „Yoga / Mobility“ → „yoga“, „Hyrox-Kurs“ → „hyrox-kurs“
    final core = f['title'].toString().toLowerCase().split(RegExp(r'\s*[/(,]\s*')).first.trim();
    if (core.length >= 3 && title.startsWith(core)) return true;
  }
  return false;
}
