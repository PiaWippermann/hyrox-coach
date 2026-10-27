import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../api/api_client.dart';

class AppState extends ChangeNotifier {
  final FlutterSecureStorage _secure = const FlutterSecureStorage();

  bool ready = false;
  ApiClient? client;
  String? userName;

  Map<String, dynamic>? anamnese;
  Map<String, dynamic>? planEnvelope; // {id, startDate, weeks, kind, plan}
  List<Map<String, dynamic>> workouts = [];
  Map<String, dynamic>? progress;

  bool get loggedIn => client != null;
  Map<String, dynamic>? get plan => planEnvelope?['plan'] as Map<String, dynamic>?;
  Set<String> get workoutDates => workouts.map((w) => w['date'].toString()).toSet();

  Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    final url = prefs.getString('baseUrl');
    final name = prefs.getString('name');
    final code = await _secure.read(key: 'code');
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
    client = null;
    userName = null;
    anamnese = null;
    planEnvelope = null;
    workouts = [];
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
    final pr = await c.get('/api/progress');
    progress = Map<String, dynamic>.from(pr as Map);
    notifyListeners();
  }

  Future<void> saveAnamnese(Map<String, dynamic> a) async {
    final res = await client!.put('/api/anamnese', a);
    anamnese = Map<String, dynamic>.from(res as Map);
    notifyListeners();
  }

  Future<List<Map<String, dynamic>>> loadSuggestions() async {
    final res = await client!.get('/api/anamnese/suggestions');
    return (res as List).map((e) => Map<String, dynamic>.from(e as Map)).toList();
  }

  Future<void> generatePlan(String startDate, int weeks) async {
    final res = await client!.post('/api/plans/generate', {'startDate': startDate, 'weeks': weeks});
    planEnvelope = Map<String, dynamic>.from(res as Map);
    notifyListeners();
  }

  Future<void> adaptPlan(String startDate, int weeks, String notes) async {
    final res = await client!.post('/api/plans/adapt', {
      'startDate': startDate,
      'weeks': weeks,
      if (notes.trim().isNotEmpty) 'notes': notes.trim(),
    });
    planEnvelope = Map<String, dynamic>.from(res as Map);
    notifyListeners();
  }

  Future<void> postWorkout(Map<String, dynamic> body) async {
    await client!.post('/api/workouts', body);
    await refresh();
  }

  Future<Map<String, dynamic>> loadUsage() async {
    final res = await client!.get('/api/usage');
    return Map<String, dynamic>.from(res as Map);
  }
}
