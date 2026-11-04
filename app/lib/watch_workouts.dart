import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'util.dart';

/// Überträgt geplante Läufe der nächsten 14 Tage als Workouts in die Training-App der Apple Watch (WorkoutKit).
/// Die Watch führt dann mit Pace-Alarm durch die Intervalle; das Ergebnis kommt über Apple Health zurück.
class WatchWorkouts {
  WatchWorkouts._();
  static final instance = WatchWorkouts._();

  static const _channel = MethodChannel('hyrox/workoutkit');
  static const _enabledKey = 'watch_runs_enabled';

  Future<bool> get enabled async => (await SharedPreferences.getInstance()).getBool(_enabledKey) ?? false;

  Future<void> setEnabled(bool on) async {
    await (await SharedPreferences.getInstance()).setBool(_enabledKey, on);
    if (!on) await _channel.invokeMethod('clear');
  }

  Future<bool> get supported async {
    try {
      return await _channel.invokeMethod<bool>('isSupported') ?? false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false; // z. B. Android
    }
  }

  /// Plant die Läufe neu. Gibt die Anzahl übertragener Workouts zurück (null, wenn ausgeschaltet).
  Future<int?> sync(Map<String, dynamic>? plan, Set<String> doneKeys) async {
    if (!await enabled || plan == null) return null;
    final items = buildItems(plan, doneKeys, DateTime.now());
    return _channel.invokeMethod<int>('sync', items);
  }

  /// Übersetzt Lauftage des Plans in das Format der nativen Brücke (siehe AppDelegate.swift).
  static List<Map<String, dynamic>> buildItems(Map<String, dynamic> plan, Set<String> doneKeys, DateTime now) {
    final today = isoDate(now);
    final until = isoDate(now.add(const Duration(days: 14)));
    final items = <Map<String, dynamic>>[];

    for (final w in asMapList(plan['weeks'])) {
      for (final day in asMapList(w['days'])) {
        final date = day['date'].toString();
        if (day['dayType'] != 'run' || date.compareTo(today) < 0 || date.compareTo(until) > 0) continue;
        if (doneKeys.contains(doneKey(date, day['title']))) continue;
        final variants = asMapList(day['variants']);
        if (variants.isEmpty) continue;

        Map<String, dynamic>? warmup;
        Map<String, dynamic>? cooldown;
        final blocks = <Map<String, dynamic>>[];
        for (final b in asMapList(variants.first['blocks'])) {
          final rounds = (b['rounds'] as num?)?.toInt() ?? 1;
          for (final e in asMapList(b['exercises'])) {
            if (exerciseKind(e) != ExerciseKind.run) continue;
            final goal = {
              if (e['distanceM'] is num) 'distanceM': (e['distanceM'] as num).toDouble(),
              if (e['distanceM'] is! num && e['durationSec'] is num) 'durationSec': (e['durationSec'] as num).toInt(),
            };
            if (b['type'] == 'warmup' && warmup == null) {
              warmup = goal;
            } else if (b['type'] == 'cooldown') {
              cooldown = goal;
            } else {
              final pace = parseTimeSec(e['targetPace']?.toString().split('/').first.split('-').first ?? '');
              blocks.add({
                'iterations': ((e['sets'] as num?)?.toInt() ?? 1) * rounds,
                'work': {...goal, if (pace != null) 'paceSecPerKm': pace},
                if (e['restSec'] is num) 'recoverySec': (e['restSec'] as num).toInt(),
              });
            }
          }
        }
        if (blocks.isEmpty) continue;
        items.add({
          'date': date,
          'hour': 7,
          'name': day['title'].toString(),
          if (warmup != null) 'warmup': warmup,
          if (cooldown != null) 'cooldown': cooldown,
          'blocks': blocks,
        });
      }
    }
    return items;
  }
}
