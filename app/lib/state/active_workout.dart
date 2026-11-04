import '../util.dart';

/// Ein Satz bzw. ein Intervall eines laufenden Trainings. Werte als Text, so wie sie in den Feldern stehen.
class ActiveSet {
  ActiveSet({this.reps = '', this.load = '', this.distance = '', this.time = '', this.done = false});

  String reps;
  String load;
  String distance; // Laufen in km, Cardio in m
  String time; // mm:ss
  bool done;

  ActiveSet copy() => ActiveSet(reps: reps, load: load, distance: distance, time: time);

  Map<String, dynamic> toJson() => {'reps': reps, 'load': load, 'distance': distance, 'time': time, 'done': done};

  factory ActiveSet.fromJson(Map<String, dynamic> j) => ActiveSet(
        reps: j['reps']?.toString() ?? '',
        load: j['load']?.toString() ?? '',
        distance: j['distance']?.toString() ?? '',
        time: j['time']?.toString() ?? '',
        done: j['done'] == true,
      );
}

class ActiveExercise {
  ActiveExercise({
    required this.data,
    required this.blockName,
    required this.previous,
    required this.sets,
    this.skipped = false,
  }) : kind = exerciseKind(data, hadLoad: previous.any((s) => ((s['loadKg'] as num?) ?? 0) > 0));

  final Map<String, dynamic> data; // Vorgabe aus dem Plan
  final String blockName;
  final List<Map<String, dynamic>> previous; // zuletzt protokollierte Sätze
  final List<ActiveSet> sets;
  final ExerciseKind kind;
  bool skipped;

  String get name => data['name'].toString();
  bool get allDone => sets.isNotEmpty && sets.every((s) => s.done);

  Map<String, dynamic> toJson() => {
        'data': data,
        'blockName': blockName,
        'previous': previous,
        'sets': sets.map((s) => s.toJson()).toList(),
        'skipped': skipped,
      };

  factory ActiveExercise.fromJson(Map<String, dynamic> j) => ActiveExercise(
        data: Map<String, dynamic>.from(j['data'] as Map),
        blockName: j['blockName'].toString(),
        previous: asMapList(j['previous']),
        sets: asMapList(j['sets']).map(ActiveSet.fromJson).toList(),
        skipped: j['skipped'] == true,
      );
}

/// Zustand eines geführten Laufs. Zeiten als Zeitstempel, damit er weiterläuft, wenn die App zu ist.
class RunState {
  RunState({required this.exercise});

  final int exercise; // Index in ActiveWorkout.exercises
  String phase = 'ready'; // ready | running | paused | resting | done
  final List<int> laps = []; // Sekunden je abgeschlossenem Intervall
  DateTime? segmentStart; // Beginn des aktuell laufenden Abschnitts
  int accumulatedMs = 0; // bereits gelaufene Zeit des aktuellen Intervalls vor einer Pause
  DateTime? restUntil;

  int get lapMs =>
      accumulatedMs + (phase == 'running' && segmentStart != null ? DateTime.now().difference(segmentStart!).inMilliseconds : 0);

  Map<String, dynamic> toJson() => {
        'exercise': exercise,
        'phase': phase,
        'laps': laps,
        'segmentStart': segmentStart?.toIso8601String(),
        'accumulatedMs': accumulatedMs,
        'restUntil': restUntil?.toIso8601String(),
      };

  factory RunState.fromJson(Map<String, dynamic> j) {
    final r = RunState(exercise: (j['exercise'] as num).toInt())
      ..phase = j['phase'].toString()
      ..accumulatedMs = (j['accumulatedMs'] as num?)?.toInt() ?? 0
      ..segmentStart = j['segmentStart'] == null ? null : DateTime.parse(j['segmentStart'].toString())
      ..restUntil = j['restUntil'] == null ? null : DateTime.parse(j['restUntil'].toString());
    r.laps.addAll(((j['laps'] as List?) ?? []).map((e) => (e as num).toInt()));
    return r;
  }
}

/// Laufendes Training. Wird bei jeder Änderung gespeichert und beim App-Start wiederhergestellt.
class ActiveWorkout {
  ActiveWorkout({
    required this.day,
    required this.variant,
    required this.planId,
    required this.startedAt,
    required this.exercises,
    this.run,
  });

  final Map<String, dynamic> day;
  final Map<String, dynamic> variant;
  final String planId;
  final DateTime startedAt;
  final List<ActiveExercise> exercises;
  RunState? run;

  String get date => day['date'].toString();
  String get title => day['title'].toString();
  String get location => variant['location'].toString();
  int get elapsedSec => DateTime.now().difference(startedAt).inSeconds;
  int get doneSets => exercises.fold(0, (n, e) => n + e.sets.where((s) => s.done).length);
  int get totalSets => exercises.where((e) => !e.skipped).fold(0, (n, e) => n + e.sets.length);

  /// Neues Training aus der gewählten Variante. Gewicht: Planvorgabe, sonst zuletzt benutztes Gewicht.
  factory ActiveWorkout.start(
    Map<String, dynamic> day,
    Map<String, dynamic> variant,
    String planId,
    List<Map<String, dynamic>> Function(String name) lastSetsFor,
  ) {
    final exercises = <ActiveExercise>[];
    for (final block in asMapList(variant['blocks'])) {
      final rounds = (block['rounds'] as num?)?.round() ?? 1;
      for (final ex in asMapList(block['exercises'])) {
        final previous = lastSetsFor(ex['name'].toString());
        final kind = exerciseKind(ex, hadLoad: previous.any((s) => ((s['loadKg'] as num?) ?? 0) > 0));
        final lastKg = previous.map((s) => s['loadKg']).whereType<num>().lastOrNull?.toDouble();
        final loadKg = (ex['loadKg'] as num?)?.toDouble();
        final load = kind == ExerciseKind.weighted ? ((loadKg != null && loadKg > 0) ? loadKg : lastKg) : null;
        final distanceM = (ex['distanceM'] as num?)?.toDouble();
        final durationSec = (ex['durationSec'] as num?)?.round();
        final count = ((ex['sets'] as num?)?.round() ?? 1) * rounds;
        exercises.add(ActiveExercise(
          data: ex,
          blockName: block['name'].toString(),
          previous: previous,
          sets: [
            for (var i = 0; i < count; i++)
              ActiveSet(
                reps: (ex['reps'] as num?)?.round().toString() ?? '',
                load: load == null ? '' : fmtNum(load),
                distance: distanceM == null ? '' : fmtNum(kind == ExerciseKind.run ? distanceM / 1000 : distanceM),
                time: durationSec == null ? '' : formatSec(durationSec),
              ),
          ],
        ));
      }
    }
    return ActiveWorkout(day: day, variant: variant, planId: planId, startedAt: DateTime.now(), exercises: exercises);
  }

  /// Body für POST /api/workouts.
  Map<String, dynamic> toLog({required int rpe, required String notes}) {
    final finished = DateTime.now();
    double? num(String s) => double.tryParse(s.trim().replaceAll(',', '.'));
    return {
      'date': isoDate(startedAt),
      'planId': planId,
      'dayTitle': title,
      'dayType': day['dayType'],
      'location': location,
      'startedAt': startedAt.toUtc().toIso8601String(),
      'finishedAt': finished.toUtc().toIso8601String(),
      'durationMin': finished.difference(startedAt).inMinutes,
      'rpe': rpe,
      if (notes.isNotEmpty) 'notes': notes,
      'exercises': exercises.map((e) {
        final done = e.sets.where((s) => s.done).map((s) {
          final dist = num(s.distance);
          return {
            'reps': int.tryParse(s.reps.trim()),
            'loadKg': num(s.load),
            'distanceM': dist == null ? null : (e.kind == ExerciseKind.run ? dist * 1000 : dist),
            'durationSec': parseTimeSec(s.time) ?? int.tryParse(s.time.trim()),
          };
        }).toList();
        return {
          'name': e.name,
          if (e.data['station'] != null) 'station': e.data['station'],
          if (e.data['benchmark'] == true) 'benchmark': true,
          'skipped': e.skipped || done.isEmpty,
          'sets': done,
        };
      }).toList(),
    };
  }

  Map<String, dynamic> toJson() => {
        'day': day,
        'variant': variant,
        'planId': planId,
        'startedAt': startedAt.toIso8601String(),
        'exercises': exercises.map((e) => e.toJson()).toList(),
        'run': run?.toJson(),
      };

  factory ActiveWorkout.fromJson(Map<String, dynamic> j) => ActiveWorkout(
        day: Map<String, dynamic>.from(j['day'] as Map),
        variant: Map<String, dynamic>.from(j['variant'] as Map),
        planId: j['planId'].toString(),
        startedAt: DateTime.parse(j['startedAt'].toString()),
        exercises: asMapList(j['exercises']).map(ActiveExercise.fromJson).toList(),
        run: j['run'] == null ? null : RunState.fromJson(Map<String, dynamic>.from(j['run'] as Map)),
      );
}
