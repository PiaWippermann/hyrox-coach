import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:hyrox_coach/state/active_workout.dart';
import 'package:hyrox_coach/util.dart';

void main() {
  final day = {'date': '2026-11-03', 'dayType': 'mixed', 'title': 'Kraft & Lauf'};
  final variant = {
    'location': 'gym',
    'blocks': [
      {
        'name': 'Kraft',
        'type': 'main',
        'rounds': 2,
        'exercises': [
          {'name': 'Kniebeuge', 'sets': 3, 'reps': 6, 'loadKg': 40},
          {'name': 'Rudern KH', 'sets': 2, 'reps': 10},
        ],
      },
      {
        'name': 'Intervalle',
        'type': 'main',
        'exercises': [
          {'name': 'Intervall', 'station': 'run', 'sets': 4, 'distanceM': 1000, 'targetPace': '5:00/km', 'restSec': 90},
        ],
      },
    ],
  };

  test('Start füllt Sätze vor: Planlast, sonst letzte Last, Läufe in km', () {
    final w = ActiveWorkout.start(day, variant, 'p1', (name) => name == 'Rudern KH' ? [{'loadKg': 12.5, 'reps': 10}] : []);
    expect(w.exercises[0].sets.length, 6); // 3 Sätze × 2 Runden
    expect(w.exercises[0].sets.first.load, '40');
    expect(w.exercises[1].sets.first.load, '12,5'); // aus letztem Training
    expect(w.exercises[2].sets.length, 4);
    expect(w.exercises[2].sets.first.distance, '1');
    expect(w.exercises[2].sets.first.load, '');
  });

  test('Hantelübung ohne Planlast bekommt trotzdem ein kg-Feld, Liegestütze nicht', () {
    expect(exerciseKind({'name': 'Kurzhantel-Rudern', 'reps': 10}), ExerciseKind.weighted);
    expect(exerciseKind({'name': 'Kniebeuge Langhantel', 'sets': 4, 'reps': 6}), ExerciseKind.weighted);
    expect(exerciseKind({'name': 'Band-Kniebeugen', 'reps': 15}), ExerciseKind.bodyweight);
    expect(exerciseKind({'name': 'Liegestütze', 'reps': 10}), ExerciseKind.bodyweight);
    expect(exerciseKind({'name': 'Klimmzüge', 'reps': 6, 'loadKg': 0}), ExerciseKind.bodyweight);
    expect(exerciseKind({'name': 'Lauf draußen', 'station': 'run', 'durationSec': 2400}), ExerciseKind.run);
    expect(exerciseKind({'name': 'Rudern', 'distanceM': 1000}), ExerciseKind.cardio);
  });

  test('Laufendes Training übersteht Speichern und Wiederherstellen', () {
    final w = ActiveWorkout.start(day, variant, 'p1', (_) => []);
    w.exercises[0].sets[0]
      ..load = '42,5'
      ..done = true;
    w.exercises[1].skipped = true;
    w.run = RunState(exercise: 2)
      ..phase = 'running'
      ..segmentStart = DateTime.now().subtract(const Duration(seconds: 30));
    w.run!.laps.add(301);

    final restored = ActiveWorkout.fromJson(jsonDecode(jsonEncode(w.toJson())) as Map<String, dynamic>);
    expect(restored.startedAt, w.startedAt);
    expect(restored.exercises[0].sets[0].load, '42,5');
    expect(restored.exercises[0].sets[0].done, isTrue);
    expect(restored.exercises[1].skipped, isTrue);
    expect(restored.run!.laps, [301]);
    expect(restored.run!.lapMs, greaterThanOrEqualTo(30000)); // Zeit lief weiter

    final log = restored.toLog(rpe: 7, notes: '');
    final squat = (log['exercises'] as List).first as Map;
    expect((squat['sets'] as List).single, {'reps': 6, 'loadKg': 42.5, 'distanceM': null, 'durationSec': null});
    expect(((log['exercises'] as List)[1] as Map)['skipped'], isTrue);
  });
}
