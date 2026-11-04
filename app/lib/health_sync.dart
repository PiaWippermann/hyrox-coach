import 'package:health/health.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'api/api_client.dart';
import 'util.dart';

/// Holt Trainings aus Apple Health (z. B. von der Apple Watch oder per Garmin-Sync) und schickt sie ans Backend,
/// das sie mit Plan, festen Terminen und App-Protokollen zusammenführt (siehe HealthImportService).
class HealthSync {
  HealthSync._();
  static final instance = HealthSync._();

  static const _enabledKey = 'health_enabled';
  static const _types = [HealthDataType.WORKOUT, HealthDataType.HEART_RATE];

  final _health = Health();
  bool _configured = false;

  Future<bool> get enabled async => (await SharedPreferences.getInstance()).getBool(_enabledKey) ?? false;

  Future<void> _configure() async {
    if (_configured) return;
    await _health.configure();
    _configured = true;
  }

  /// Fragt die Berechtigung an und merkt sich die Verbindung. Gibt false zurück, wenn abgelehnt.
  Future<bool> connect() async {
    await _configure();
    final ok = await _health.requestAuthorization(_types, permissions: [HealthDataAccess.READ, HealthDataAccess.READ]);
    await (await SharedPreferences.getInstance()).setBool(_enabledKey, ok);
    return ok;
  }

  Future<void> disconnect() async => (await SharedPreferences.getInstance()).setBool(_enabledKey, false);

  /// Importiert die Trainings der letzten [days] Tage. Gibt {merged, created, skipped} zurück oder null, wenn aus.
  Future<Map<String, dynamic>?> sync(ApiClient client, {int days = 21}) async {
    if (!await enabled) return null;
    await _configure();
    final end = DateTime.now();
    final start = end.subtract(Duration(days: days));

    final workouts = await _health.getHealthDataFromTypes(types: [HealthDataType.WORKOUT], startTime: start, endTime: end);
    if (workouts.isEmpty) return {'merged': 0, 'created': 0, 'skipped': 0};
    final heart = await _health.getHealthDataFromTypes(types: [HealthDataType.HEART_RATE], startTime: start, endTime: end);

    final payload = <Map<String, dynamic>>[];
    for (final w in workouts) {
      final v = w.value;
      if (v is! WorkoutHealthValue) continue;
      final hr = heart
          .where((h) => !h.dateFrom.isBefore(w.dateFrom) && !h.dateFrom.isAfter(w.dateTo))
          .map((h) => (h.value as NumericHealthValue).numericValue.toDouble())
          .toList();
      final local = w.dateFrom.toLocal();
      payload.add({
        'externalId': w.uuid,
        'activityType': v.workoutActivityType.name,
        'start': w.dateFrom.toUtc().toIso8601String(),
        'end': w.dateTo.toUtc().toIso8601String(),
        if (v.totalDistance != null && v.totalDistance! > 0) 'distanceM': v.totalDistance,
        if (v.totalEnergyBurned != null) 'calories': v.totalEnergyBurned,
        if (hr.isNotEmpty) 'avgHr': (hr.reduce((a, b) => a + b) / hr.length).round(),
        if (hr.isNotEmpty) 'maxHr': hr.reduce((a, b) => a > b ? a : b).round(),
        'sourceName': w.sourceName,
        'localDate': isoDate(local),
        'localTime': '${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}',
      });
    }
    if (payload.isEmpty) return {'merged': 0, 'created': 0, 'skipped': 0};
    return Map<String, dynamic>.from(await client.post('/api/workouts/import', {'workouts': payload}) as Map);
  }
}
