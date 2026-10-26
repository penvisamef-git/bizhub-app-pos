import 'dart:convert';

import 'package:dio/dio.dart';

import '../../core/api.dart' show ApiError, Json, makeDio, str;
import '../../core/app_state.dart';
import '../../core/config.dart';
import '../../core/local_prefs.dart';

export '../../core/api.dart' show ApiError, Json, obj, objs, str, n;

// Telegram Store staff screen (the web's pos/tgstore/tsPosApi.js), base /api/tspos:
//   the paired screen = x-ts-device (kept as the link token) · the staff member's PIN login = x-ts-session (kept in TsStore)
class TsPos {
  static final Dio _dio = makeDio(
    BaseOptions(baseUrl: Config.apiHost, connectTimeout: const Duration(seconds: 12), receiveTimeout: const Duration(seconds: 30), responseType: ResponseType.json, validateStatus: (_) => true),
  );

  static String get device => str((AppState.i.link ?? const {})['token']);
  static String get session => TsStore.str('session');

  // tests: answers without a server
  static Future<Json> Function(String method, String path, Object? body)? fake;

  static Future<Json> call(String method, String path, {Object? body}) async {
    if (fake != null) return fake!(method, path, body);
    try {
      final r = await _dio.request<dynamic>(
        '/api/tspos$path',
        data: method == 'GET' ? null : (body ?? const {}),
        options: Options(method: method, headers: {'x-api-key': Config.apiKey, if (device.isNotEmpty) 'x-ts-device': device, if (session.isNotEmpty) 'x-ts-session': session}),
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
  static Future<Json> shop() => call('GET', '/shop');
  static Future<Json> login(String pin) => call('POST', '/login', body: {'pin': pin});
  static Future<Json> boot() => call('GET', '/boot');
  static Future<Json> orders(String view) => call('GET', '/orders?view=$view');
  static Future<Json> move(String oid, String status, [Json extra = const {}]) => call('POST', '/orders/$oid/status', body: {'status': status, ...extra});
  static Future<Json> paid(String oid) => call('POST', '/orders/$oid/paid');
  static Future<Json> toRiders(String oid) => call('POST', '/orders/$oid/riders');
  static Future<Json> products() => call('GET', '/products');
  static Future<Json> soldOut(String pid, bool v) => call('PUT', '/products/$pid', body: {'sold_out': v});
  static Future<Json> setOpen(bool v) => call('PUT', '/open', body: {'open': v});
  static Future<Json> today() => call('GET', '/today');
}

// what the screen keeps on itself: the PIN login and the sound switch (the printer is under ts.printer)
class TsStore {
  static LocalPrefs? _p;
  static Future<void> init() async => _p ??= await LocalPrefs.getInstance();

  static Object? get(String k) {
    final raw = _p?.getString('ts.$k');
    if (raw == null || raw.isEmpty) return null;
    try {
      return jsonDecode(raw);
    } catch (_) {
      return null;
    }
  }

  static void set(String k, Object? v) {
    if (v == null) {
      _p?.remove('ts.$k');
    } else {
      _p?.setString('ts.$k', jsonEncode(v));
    }
  }

  static String str(String k) {
    final v = get(k);
    return v is String ? v : '';
  }

  // unpaired: forget the login (the printer stays with the device)
  static void clear() {
    final p = _p;
    if (p == null) return;
    for (final k in p.getKeys().where((k) => k.startsWith('ts.') && k != 'ts.printer').toList()) {
      p.remove(k);
    }
  }
}

// the staff screen's words (tsx.*), the owner's order words (ts.*) and the app-only ones (tsa.*)
String tsx(String k, [Map<String, Object?> v = const {}]) => AppState.i.t('tsx.$k', v);
String tsm(String k, [Map<String, Object?> v = const {}]) => AppState.i.t('ts.$k', v);
String tsa(String k, [Map<String, Object?> v = const {}]) => AppState.i.t('tsa.$k', v);
