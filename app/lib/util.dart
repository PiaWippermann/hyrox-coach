const weekdayShort = ['Mo', 'Di', 'Mi', 'Do', 'Fr', 'Sa', 'So'];
const weekdayLong = ['Montag', 'Dienstag', 'Mittwoch', 'Donnerstag', 'Freitag', 'Samstag', 'Sonntag'];

const dayTypeLabels = {
  'run': 'Laufen',
  'strength': 'Kraft',
  'hyrox_sim': 'Hyrox-Simulation',
  'mixed': 'Mixed',
  'recovery': 'Regeneration',
  'rest': 'Ruhetag',
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
