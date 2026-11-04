import 'dart:convert';

import 'package:http/http.dart' as http;

class ApiException implements Exception {
  ApiException(this.status, this.message);
  final int status;
  final String message;

  @override
  String toString() => message;
}

/// Dünner HTTP-Client für das Backend (siehe docs/api.md).
class ApiClient {
  ApiClient({required this.baseUrl, this.code});

  String baseUrl;
  String? code;

  Uri _uri(String path, [Map<String, String>? query]) {
    final base = baseUrl.trim().replaceAll(RegExp(r'/+$'), '');
    final uri = Uri.parse('$base$path');
    return query == null ? uri : uri.replace(queryParameters: query);
  }

  Map<String, String> get _headers => {
        'Content-Type': 'application/json; charset=utf-8',
        if (code != null) 'Authorization': 'Bearer $code',
      };

  Future<dynamic> _send(Future<http.Response> Function() request) async {
    http.Response r;
    try {
      // Plan-Erstellung per KI kann etwas dauern
      r = await request().timeout(const Duration(minutes: 9));
    } on Exception catch (e) {
      throw ApiException(0, 'Backend nicht erreichbar: $e');
    }

    dynamic body;
    if (r.body.isNotEmpty) {
      try {
        body = jsonDecode(utf8.decode(r.bodyBytes));
      } catch (_) {
        body = null;
      }
    }

    if (r.statusCode >= 200 && r.statusCode < 300) return body;
    final msg = body is Map && body['error'] != null ? body['error'].toString() : 'Fehler ${r.statusCode}';
    throw ApiException(r.statusCode, msg);
  }

  Future<dynamic> get(String path, [Map<String, String>? query]) =>
      _send(() => http.get(_uri(path, query), headers: _headers));

  Future<dynamic> post(String path, Object? body) =>
      _send(() => http.post(_uri(path), headers: _headers, body: jsonEncode(body)));

  Future<dynamic> delete(String path) => _send(() => http.delete(_uri(path), headers: _headers));

  Future<dynamic> put(String path, Object? body) =>
      _send(() => http.put(_uri(path), headers: _headers, body: jsonEncode(body)));
}
