import 'util.dart';

/// Rennprognose ohne KI: nachvollziehbar aus letztem Rennergebnis, Benchmark-Tests und Laufbestzeiten.
class RacePrediction {
  RacePrediction({
    required this.runsSec,
    required this.stationsSec,
    required this.roxzoneSec,
    required this.spread,
    required this.basis,
  });

  final List<int> runsSec; // 8 Läufe
  final List<int> stationsSec; // 8 Stationen in Rennreihenfolge
  final int roxzoneSec;
  final double spread; // Unsicherheit als Anteil, z. B. 0.05 = ±5 %
  final List<String> basis; // Begründung in Klartext

  int get totalSec => runsSec.fold<int>(0, (a, b) => a + b) + stationsSec.fold<int>(0, (a, b) => a + b) + roxzoneSec;
  int get lowSec => (totalSec * (1 - spread)).round();
  int get highSec => (totalSec * (1 + spread)).round();
  String get confidence => spread <= 0.035 ? 'hoch' : (spread <= 0.055 ? 'mittel' : 'niedrig');

  /// Split-Plan auf eine Zielzeit skaliert (alle Abschnitte im gleichen Verhältnis).
  RacePrediction scaledTo(int targetSec) {
    final f = targetSec / totalSec;
    return RacePrediction(
      runsSec: [for (final r in runsSec) (r * f).round()],
      stationsSec: [for (final s in stationsSec) (s * f).round()],
      roxzoneSec: (roxzoneSec * f).round(),
      spread: 0,
      basis: const [],
    );
  }

  /// Richtwerte ohne eigenes Ergebnis (grobe Mittelwerte Open-Division, Sekunden).
  static const _femaleStations = [300, 240, 330, 330, 315, 120, 300, 420];
  static const _maleStations = [270, 195, 270, 270, 285, 105, 255, 330];

  /// Benchmark → Station: Index in der Stationsliste und Zuschlag für Ermüdung im Rennen.
  static const _benchmarkStations = {
    'skierg': (0, 1.05),
    'rowing': (4, 1.05),
    'wall_balls': (7, 1.08),
  };

  static RacePrediction build({
    required Map<String, dynamic>? anamnese,
    required List<Map<String, dynamic>> results,
    required List<Map<String, dynamic>> workouts,
  }) {
    final basis = <String>[];
    var spread = 0.08;

    final sorted = [...results]..sort((a, b) => b['date'].toString().compareTo(a['date'].toString()));
    final last = sorted.firstOrNull;
    final profile = anamnese?['profile'] is Map ? anamnese!['profile'] as Map : const {};
    final goal = anamnese?['goal'] is Map ? anamnese!['goal'] as Map : const {};
    final self = anamnese?['selfAssessment'] is Map ? anamnese!['selfAssessment'] as Map : const {};
    final male = profile['sex'] == 'male' || RegExp('men|herren|männer', caseSensitive: false).hasMatch('${goal['division']}') &&
        !RegExp('women|damen|frauen', caseSensitive: false).hasMatch('${goal['division']}');

    // ---------- Stationen ----------
    late List<int> stations;
    if (last != null) {
      stations = (last['stationsSec'] as List).map((e) => (e as num).toInt()).toList();
      basis.add('Stationen aus deinem Rennen am ${germanDate(last['date'].toString())} ${last['date'].toString().substring(0, 4)}.');
      spread = 0.05;
    } else {
      stations = List.of(male ? _maleStations : _femaleStations);
      basis.add('Kein Rennergebnis vorhanden: Stationen sind grobe Richtwerte der Open-Division.');
    }

    // Neuere Benchmark-Tests ersetzen die jeweilige Station
    final lastDate = last?['date']?.toString() ?? '';
    final benchmarks = <String, ({String date, int sec})>{};
    for (final w in workouts) {
      final date = w['date'].toString();
      if (date.compareTo(lastDate) <= 0) continue;
      for (final e in asMapList(w['exercises'])) {
        final station = e['station']?.toString();
        if (e['benchmark'] != true || !_benchmarkStations.containsKey(station)) continue;
        final sec = asMapList(e['sets']).map((s) => (s['durationSec'] as num?)?.toInt()).whereType<int>().firstOrNull;
        if (sec == null || sec <= 0) continue;
        final prev = benchmarks[station!];
        if (prev == null || date.compareTo(prev.date) > 0) benchmarks[station] = (date: date, sec: sec);
      }
    }
    for (final b in benchmarks.entries) {
      final (index, factor) = _benchmarkStations[b.key]!;
      stations[index] = (b.value.sec * factor).round();
      basis.add('${_stationLabel(index)}: Benchmark vom ${germanDate(b.value.date)} (${formatSec(b.value.sec)}) '
          '+${((factor - 1) * 100).round()} % Rennermüdung.');
    }
    if (benchmarks.isNotEmpty) spread = (spread - 0.015).clamp(0.03, 0.1);

    // ---------- Laufen ----------
    late int runAvg;
    if (last != null) {
      final runs = (last['runsSec'] as List).map((e) => (e as num).toInt()).toList();
      runAvg = (runs.fold(0, (a, b) => a + b) / runs.length).round();
      basis.add('Läufe aus deinem letzten Rennen (Ø ${formatSec(runAvg)}/km).');
    } else {
      final t10 = parseTimeSec(self['run10kTime']?.toString() ?? '');
      final t5 = parseTimeSec(self['run5kTime']?.toString() ?? '');
      if (t10 != null) {
        runAvg = (t10 / 10 * 1.12).round();
        basis.add('Läufe aus deiner 10-km-Zeit + 12 % Hyrox-Ermüdung (Ø ${formatSec(runAvg)}/km).');
        spread = (spread - 0.01).clamp(0.03, 0.1);
      } else if (t5 != null) {
        runAvg = (t5 / 5 * 1.18).round();
        basis.add('Läufe aus deiner 5-km-Zeit + 18 % Hyrox-Ermüdung (Ø ${formatSec(runAvg)}/km).');
      } else {
        runAvg = male ? 300 : 345;
        basis.add('Keine Laufzeiten bekannt: Läufe als Richtwert ${formatSec(runAvg)}/km.');
      }
    }
    // Erster Lauf etwas schneller, letzter etwas langsamer – Summe bleibt 8 × Ø
    const shape = [0.95, 1.0, 1.0, 1.0, 1.0, 1.0, 1.01, 1.04];
    final shapeSum = shape.fold(0.0, (a, b) => a + b);
    final runs = [for (final f in shape) (runAvg * 8 * f / shapeSum).round()];

    // ---------- Roxzone ----------
    final work = runs.fold(0, (a, b) => a + b) + stations.fold(0, (a, b) => a + b);
    final rox = (last?['roxzoneSec'] as num?)?.toInt() ?? (work * 0.07).round();
    if (last?['roxzoneSec'] == null) basis.add('Roxzone geschätzt (≈ 7 % der Rennzeit).');

    return RacePrediction(runsSec: runs, stationsSec: stations, roxzoneSec: rox, spread: spread, basis: basis);
  }

  static String _stationLabel(int i) => const [
        'SkiErg', 'Sled Push', 'Sled Pull', 'Burpee Broad Jumps', 'Rudern', 'Farmers Carry', 'Sandbag Lunges', 'Wall Balls',
      ][i];
}
