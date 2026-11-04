import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../api/api_client.dart';
import '../util.dart';
import 'active_workout.dart';
import '../health_sync.dart';
import '../notifications.dart';
import '../watch_workouts.dart';

class AppState extends ChangeNotifier {
  final FlutterSecureStorage _secure = const FlutterSecureStorage();

  bool ready = false;
  ApiClient? client;
  String? userName;

  Map<String, dynamic>? anamnese;
  Map<String, dynamic>? planEnvelope; // {id, startDate, weeks, kind, plan}
  List<Map<String, dynamic>> workouts = [];
  List<Map<String, dynamic>> results = []; // Hyrox-Rennergebnisse

  /// Laufendes Training. Bleibt bestehen, bis es aktiv beendet oder abgebrochen wird – auch über App-Neustarts.
  ActiveWorkout? active;
  static const _activeKey = 'activeWorkout';
  Map<String, dynamic>? progress;

  bool get loggedIn => client != null;
  Map<String, dynamic>? get plan => planEnvelope?['plan'] as Map<String, dynamic>?;

  /// Folgeblock, der automatisch im Anschluss an den aktiven Plan erstellt wurde (noch nicht gestartet).
  Map<String, dynamic>? get upcomingEnvelope =>
      planEnvelope?['upcoming'] is Map ? Map<String, dynamic>.from(planEnvelope!['upcoming'] as Map) : null;
  Map<String, dynamic>? get upcomingPlan => upcomingEnvelope?['plan'] as Map<String, dynamic>?;

  /// Letzter Tag des aktiven Blocks.
  DateTime? get planEnd {
    final env = planEnvelope;
    if (env == null) return null;
    return parseIso(env['startDate'].toString()).add(Duration(days: (env['weeks'] as int) * 7 - 1));
  }
  /// Erledigte Einheiten als doneKey(Datum, Titel).
  Set<String> get doneKeys => workouts.map((w) => doneKey(w['date'].toString(), w['dayTitle'])).toSet();

  Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    final url = prefs.getString('baseUrl');
    final name = prefs.getString('name');
    final code = await _secure.read(key: 'code');
    final saved = prefs.getString(_activeKey);
    if (saved != null) {
      try {
        active = ActiveWorkout.fromJson(Map<String, dynamic>.from(jsonDecode(saved) as Map));
      } catch (_) {
        await prefs.remove(_activeKey); // unlesbarer Stand, z. B. nach Formatänderung
      }
    }
    if (url != null && name != null && code != null) {
      client = ApiClient(baseUrl: url, code: code);
      userName = name;
      try {
        await refresh();
      } catch (_) {
        // offline oder Backend gerade nicht erreichbar: App trotzdem öffnen
      }
    }
    ready = true;
    notifyListeners();
  }

  Future<void> login(String baseUrl, String name, String code) async {
    final c = ApiClient(baseUrl: baseUrl);
    final res = await c.post('/auth/login', {'name': name.trim(), 'code': code.trim()});
    c.code = code.trim();
    client = c;
    userName = (res as Map)['name'].toString();

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('baseUrl', baseUrl.trim());
    await prefs.setString('name', userName!);
    await _secure.write(key: 'code', value: code.trim());

    await refresh();
    notifyListeners();
  }

  Future<void> logout() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('name');
    await _secure.delete(key: 'code');
    await prefs.remove(_activeKey);
    active = null;
    client = null;
    userName = null;
    anamnese = null;
    planEnvelope = null;
    workouts = [];
    results = [];
    progress = null;
    notifyListeners();
  }

  Future<dynamic> _orNull(Future<dynamic> Function() f) async {
    try {
      return await f();
    } on ApiException catch (e) {
      if (e.status == 404) return null;
      rethrow;
    }
  }

  Future<void> refresh() async {
    final c = client!;
    final a = await _orNull(() => c.get('/api/anamnese'));
    anamnese = a == null ? null : Map<String, dynamic>.from(a as Map);
    final p = await _orNull(() => c.get('/api/plans/current'));
    planEnvelope = p == null ? null : Map<String, dynamic>.from(p as Map);
    final w = await c.get('/api/workouts');
    workouts = (w as List).map((e) => Map<String, dynamic>.from(e as Map)).toList();
    results = asMapList(await c.get('/api/results'));
    final ci = await c.get('/api/plans/checkin') as Map;
    lastCheckinAt = ci['lastCheckinAt'] == null ? null : DateTime.parse(ci['lastCheckinAt'].toString()).toLocal();
    planCreatedAt = ci['planCreatedAt'] == null ? null : DateTime.parse(ci['planCreatedAt'].toString()).toLocal();
    final pr = await c.get('/api/progress');
    progress = Map<String, dynamic>.from(pr as Map);
    notifyListeners();
    rescheduleReminders();
    _syncHealth();
  }

  bool _syncingHealth = false;

  /// Watch-Trainings aus Apple Health übernehmen; lädt die Protokolle neu, wenn sich etwas geändert hat.
  Future<Map<String, dynamic>?> syncHealthNow() async {
    if (client == null || _syncingHealth) return null;
    _syncingHealth = true;
    try {
      final res = await HealthSync.instance.sync(client!);
      if (res != null && ((res['merged'] as num) > 0 || (res['created'] as num) > 0)) {
        workouts = asMapList(await client!.get('/api/workouts'));
        notifyListeners();
        rescheduleReminders();
      }
      return res;
    } finally {
      _syncingHealth = false;
    }
  }

  void _syncHealth() => syncHealthNow().catchError((_) => null);

  Future<void> saveAnamnese(Map<String, dynamic> a) async {
    final res = await client!.put('/api/anamnese', a);
    anamnese = Map<String, dynamic>.from(res as Map);
    notifyListeners();
    rescheduleReminders();
  }

  /// Lässt Screenshots/Fotos auswerten und gibt die erkannten Anamnese-Werte zurück (nichts wird gespeichert).
  Future<Map<String, dynamic>> extractFromImages(List<({String mediaType, List<int> bytes})> images) async {
    final res = await client!.post('/api/anamnese/extract', {
      'images': [
        for (final img in images) {'mediaType': img.mediaType, 'data': base64Encode(img.bytes)},
      ],
    });
    return Map<String, dynamic>.from(res as Map);
  }

  Future<List<Map<String, dynamic>>> loadSuggestions() async {
    final res = await client!.get('/api/anamnese/suggestions');
    return (res as List).map((e) => Map<String, dynamic>.from(e as Map)).toList();
  }

  /// Erstplan: Start (nächster Montag) und Blocklänge bestimmt das Backend aus dem Ziel.
  Future<void> generatePlan() async {
    await client!.post('/api/plans/generate', {});
    await refresh();
  }

  /// Neuen Block erstellen: im Anschluss an den aktiven ([startNow] = false) oder ab dieser Woche als Ersatz.
  Future<void> adaptPlan(String notes, {bool startNow = false}) async {
    final res = await client!.post('/api/plans/adapt', {
      'startNow': startNow,
      if (notes.trim().isNotEmpty) 'notes': notes.trim(),
    });
    if (res is Map && res['status'] == 'upcoming') {
      // Folgeblock: aktiven Plan behalten, neuen als „upcoming“ anhängen
      await refresh();
      return;
    }
    planEnvelope = Map<String, dynamic>.from(res as Map);
    planCreatedAt = DateTime.now();
    notifyListeners();
    rescheduleReminders();
  }

  /// Festen Termin (Kurs) abhaken oder das Häkchen wieder entfernen.
  Future<void> toggleFixed(String date, Map<String, dynamic> fixed, {int? rpe}) async {
    final title = fixed['title'].toString();
    final existing = workouts.where((w) => w['date'] == date && w['dayTitle'] == title && w['fixed'] == true).firstOrNull;
    if (existing != null) {
      await client!.delete('/api/workouts/${existing['id']}');
    } else {
      final start = parseIso(date);
      final time = fixed['time'].toString().split(':');
      final startedAt = DateTime(start.year, start.month, start.day, int.tryParse(time.first) ?? 12,
          time.length > 1 ? int.tryParse(time[1]) ?? 0 : 0);
      await client!.post('/api/workouts', {
        'date': date,
        'dayTitle': title,
        'dayType': fixed['dayType'],
        'fixed': true,
        'location': 'other',
        'startedAt': startedAt.toUtc().toIso8601String(),
        'durationMin': fixed['durationMin'],
        if (rpe != null) 'rpe': rpe,
        'exercises': [],
      });
    }
    await refresh();
  }

  /// Startet ein Training. Es kann immer nur eins gleichzeitig laufen.
  Future<ActiveWorkout> startWorkout(Map<String, dynamic> day, Map<String, dynamic> variant, String planId) async {
    if (active != null) throw StateError('Es läuft bereits ein Training.');
    active = ActiveWorkout.start(day, variant, planId, lastSetsFor);
    await saveActive();
    return active!;
  }

  /// Speichert den aktuellen Stand des laufenden Trainings auf dem Gerät.
  /// [notify] = false bei Tastatureingaben, damit nicht bei jedem Zeichen die ganze App neu baut.
  Future<void> saveActive({bool notify = true}) async {
    final prefs = await SharedPreferences.getInstance();
    if (active == null) {
      await prefs.remove(_activeKey);
    } else {
      await prefs.setString(_activeKey, jsonEncode(active!.toJson()));
    }
    if (notify) notifyListeners();
  }

  /// Speichert das Training im Backend, beendet es und gibt das gespeicherte Protokoll zurück.
  Future<Map<String, dynamic>> finishActive({required int rpe, required String notes}) async {
    final a = active!;
    final log = Map<String, dynamic>.from(await client!.post('/api/workouts', a.toLog(rpe: rpe, notes: notes)) as Map);
    active = null;
    await saveActive();
    await refresh();
    return log;
  }

  /// Coach-Feedback zu einem Training (wird beim ersten Abruf erzeugt und dann gespeichert).
  Future<String> workoutFeedback(String workoutId) async {
    final res = await client!.post('/api/workouts/$workoutId/feedback', {});
    final text = (res as Map)['feedback'].toString();
    final w = workouts.where((x) => x['id'] == workoutId).firstOrNull;
    if (w != null) w['feedback'] = text;
    return text;
  }

  // ---------- Check-in alle 2 Wochen ----------
  DateTime? lastCheckinAt;
  DateTime? planCreatedAt;

  /// Fällig, wenn seit dem letzten Check-in (oder dem Planstart) 14 Tage vergangen sind.
  DateTime? get nextCheckinDue {
    // Der spätere von beiden: nach einem neuen Plan beginnt der Rhythmus neu
    final base = [lastCheckinAt, planCreatedAt].whereType<DateTime>().fold<DateTime?>(
        null, (a, b) => a == null || b.isAfter(a) ? b : a);
    return base?.add(const Duration(days: 14));
  }

  bool get checkinDue => plan != null && nextCheckinDue != null && !DateTime.now().isBefore(nextCheckinDue!);

  Future<Map<String, dynamic>> runCheckin() async {
    final res = Map<String, dynamic>.from(await client!.post('/api/plans/checkin', {}) as Map);
    lastCheckinAt = DateTime.now();
    notifyListeners();
    return Map<String, dynamic>.from(res['reply'] as Map);
  }

  Future<void> cancelActive() async {
    active = null;
    await saveActive();
  }

  /// Erinnerungen an den aktuellen Plan, Termine und Check-in anpassen (läuft im Hintergrund).
  void rescheduleReminders() {
    NotificationService.instance.reschedule(
      plan: plan,
      anamnese: anamnese,
      doneKeys: doneKeys,
      checkinDue: plan == null ? null : nextCheckinDue,
      planEnd: planEnd,
      hasUpcoming: upcomingEnvelope != null,
    );
    // Läufe auf die Apple Watch, falls eingeschaltet
    WatchWorkouts.instance.sync(plan, doneKeys).catchError((_) => null);
  }

  /// Zuletzt protokollierte Sätze einer Übung (gleicher Name), neueste zuerst gesucht.
  List<Map<String, dynamic>> lastSetsFor(String exerciseName) {
    final key = exerciseName.trim().toLowerCase();
    final sorted = [...workouts]..sort((a, b) => b['date'].toString().compareTo(a['date'].toString()));
    for (final w in sorted) {
      for (final e in asMapList(w['exercises'])) {
        if (e['name'].toString().trim().toLowerCase() == key && e['skipped'] != true) {
          final sets = asMapList(e['sets']);
          if (sets.isNotEmpty) return sets;
        }
      }
    }
    return [];
  }

  Future<List<Map<String, dynamic>>> loadChat() async {
    final res = await client!.get('/api/plans/chat');
    return asMapList((res as Map)['messages']);
  }

  /// Schickt eine Nachricht an den Coach. Ändert er den Plan, wird er hier sofort übernommen.
  Future<Map<String, dynamic>> sendChat(String message) async {
    final res = Map<String, dynamic>.from(await client!.post('/api/plans/chat', {'message': message}) as Map);
    if (res['planChanged'] == true && res['plan'] is Map) {
      planEnvelope = Map<String, dynamic>.from(res['plan'] as Map);
      notifyListeners();
      rescheduleReminders();
    }
    return Map<String, dynamic>.from(res['reply'] as Map);
  }

  Future<Map<String, dynamic>> loadUsage() async {
    final res = await client!.get('/api/usage');
    return Map<String, dynamic>.from(res as Map);
  }
}
