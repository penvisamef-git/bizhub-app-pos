import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/api.dart' show ApiError, Json, makeDio, str;
import '../../core/app_state.dart';
import '../../core/config.dart';

export '../../core/api.dart' show ApiError, Json, obj, objs, str, n;

// Event Tickets door phone (the web's pos/event/evDoorApi.js):
//   the paired phone = x-ev-device (kept as the link token) · the team member's PIN login = x-ev-session (kept in EvStore)
class EvDoor {
  static final Dio _dio = makeDio(
    BaseOptions(baseUrl: Config.apiHost, connectTimeout: const Duration(seconds: 12), receiveTimeout: const Duration(seconds: 30), responseType: ResponseType.json, validateStatus: (_) => true),
  );

  static String get device => str((AppState.i.link ?? const {})['token']);
  static String get session => EvStore.str('session');

  // tests: answers without a server
  static Future<Json> Function(String method, String path, Object? body, Map<String, dynamic>? query)? fake;

  static Future<Json> call(String method, String path, {Object? body, Map<String, dynamic>? query}) async {
    if (fake != null) return fake!(method, path, body, query);
    try {
      final r = await _dio.request<dynamic>(
        '/api/evdoor$path',
        data: method == 'GET' ? null : (body ?? const {}),
        queryParameters: query?..removeWhere((_, v) => v == null || v == ''),
        options: Options(method: method, headers: {'x-api-key': Config.apiKey, if (device.isNotEmpty) 'x-ev-device': device, if (session.isNotEmpty) 'x-ev-session': session}),
      );
      final data = r.data;
      final json = data is Map ? Map<String, dynamic>.from(data) : <String, dynamic>{'data': data};
      final status = r.statusCode ?? 0;
      if (status >= 400 || json['success'] == false) throw ApiError(status, '${json['message'] ?? 'Error $status'}', code: json['code'] as String?, body: json);
      return json;
    } on DioException catch (e) {
      throw ApiError(0, e.message ?? 'network');
    }
  }

  static Future<Json> pair(String code, String name) => call('POST', '/pair', body: {'code': code, 'name': name});
  static Future<Json> login(String pin) => call('POST', '/login', body: {'pin': pin});
  static Future<Json> boot() => call('GET', '/boot');
  static Future<Json> event(String eid, {bool codes = false}) => call('GET', '/events/$eid', query: {if (codes) 'codes': '1'});
  static Future<Json> scan(String eid, String code, String show) => call('POST', '/scan', body: {'event_id': eid, 'code': code, if (show.isNotEmpty) 'show': show});
  static Future<Json> sync(String eid, List<Json> scans, String show) => call('POST', '/sync', body: {'event_id': eid, 'scans': scans, if (show.isNotEmpty) 'show': show});
  static Future<Json> guests(String eid, Map<String, dynamic> q) => call('GET', '/events/$eid/guests', query: q);
  static Future<Json> sell(String eid, Json body) => call('POST', '/events/$eid/sell', body: body);
  static Future<Json> orders(Map<String, dynamic> q) => call('GET', '/orders', query: q);
  static Future<Json> approve(String oid) => call('POST', '/orders/$oid/approve');
  static Future<Json> reject(String oid, String reason) => call('POST', '/orders/$oid/reject', body: {'reason': reason});
}

// what the door phone keeps on itself: the login, the last event list, every ticket code (offline scanning),
// the scans still to send and this phone's scan history
class EvStore {
  static SharedPreferences? _p;
  static Future<void> init() async => _p ??= await SharedPreferences.getInstance();

  static Object? get(String k) {
    final raw = _p?.getString('ev.$k');
    if (raw == null || raw.isEmpty) return null;
    try {
      return jsonDecode(raw);
    } catch (_) {
      return null;
    }
  }

  static void set(String k, Object? v) {
    if (v == null) {
      _p?.remove('ev.$k');
    } else {
      _p?.setString('ev.$k', jsonEncode(v));
    }
  }

  static String str(String k) {
    final v = get(k);
    return v is String ? v : '';
  }

  static Json map(String k) {
    final v = get(k);
    return v is Map ? Map<String, dynamic>.from(v) : <String, dynamic>{};
  }

  static List<Json> list(String k) {
    final v = get(k);
    return v is List ? v.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList() : <Json>[];
  }

  // unpaired: forget everything about the organiser
  static void clear() {
    final p = _p;
    if (p == null) return;
    for (final k in p.getKeys().where((k) => k.startsWith('ev.') && k != 'ev.printer').toList()) {
      p.remove(k);
    }
  }
}

// the code inside a ticket QR: …/ev/t/CODE or the bare code
String evCodeOf(String raw) {
  final s = raw.trim();
  final m = RegExp(r'/ev/t/([A-Za-z0-9]{8,14})').firstMatch(s);
  final v = (m != null ? m[1]! : s).toUpperCase().replaceAll(RegExp(r'[^A-Z0-9]'), '');
  return v.length > 14 ? v.substring(0, 14) : v;
}
