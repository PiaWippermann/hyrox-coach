import 'package:flutter_test/flutter_test.dart';
import 'package:hyrox_coach/race_prediction.dart';

void main() {
  final result = {
    'date': '2026-03-14',
    'runsSec': [292, 310, 318, 325, 320, 331, 336, 344],
    'stationsSec': [298, 261, 347, 339, 302, 125, 289, 412],
    'roxzoneSec': 372,
  };

  test('Mit Rennergebnis: Summe passt, Spanne mittel', () {
    final p = RacePrediction.build(anamnese: {}, results: [result], workouts: []);
    // Läufe gleich verteilt umgeformt, Summe bleibt (bis auf Rundung) gleich
    expect(p.runsSec.fold<int>(0, (a, b) => a + b), closeTo(2576, 4));
    expect(p.stationsSec, result['stationsSec']);
    expect(p.roxzoneSec, 372);
    expect(p.confidence, 'mittel');
    expect(p.runsSec.first < p.runsSec.last, isTrue);
  });

  test('Neuerer SkiErg-Benchmark ersetzt die Station mit 5 % Zuschlag', () {
    final p = RacePrediction.build(anamnese: {}, results: [result], workouts: [
      {
        'date': '2026-10-20',
        'exercises': [
          {
            'name': '1000 m SkiErg Test',
            'station': 'skierg',
            'benchmark': true,
            'sets': [
              {'durationSec': 260, 'distanceM': 1000}
            ],
          }
        ],
      }
    ]);
    expect(p.stationsSec[0], 273);
    expect(p.spread, lessThan(0.05));
  });

  test('Ohne Ergebnis: Läufe aus 10-km-Zeit, Richtwerte, breite Spanne', () {
    final p = RacePrediction.build(anamnese: {
      'selfAssessment': {'run10kTime': '51:00'},
    }, results: [], workouts: []);
    expect(p.runsSec.fold<int>(0, (a, b) => a + b) / 8, closeTo(3060 / 10 * 1.12, 2));
    expect(p.confidence, 'niedrig');
  });

  test('Skalieren auf Zielzeit', () {
    final p = RacePrediction.build(anamnese: {}, results: [result], workouts: []);
    final t = p.scaledTo(5100);
    expect(t.totalSec, closeTo(5100, 10));
  });
}
