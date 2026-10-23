import 'dart:convert';

import 'package:dio/dio.dart';

import 'config.dart';

// Every answer from the API looks like { success, data, pagination?, message? }.
class ApiError implements Exception {
  final int status; // 0 = no connection
  final String message;
  final String? code;
  final Map<String, dynamic> body;
  const ApiError(this.status, this.message, {this.code, this.body = const {}});
  bool get network => status == 0;
  @override
  String toString() => message;
}

typedef Json = Map<String, dynamic>;

// every API client is made here, so tests (store screenshots) can answer instead of the server
HttpClientAdapter? testAdapter;
Dio makeDio(BaseOptions options) {
  final d = Dio(options);
  if (testAdapter != null) d.httpClientAdapter = testAdapter!;
  return d;
}

class Api {
  final Dio _dio;
  final String? Function() token;
  final void Function() onUnauthorized;

  Api({required this.token, required this.onUnauthorized})
    : _dio = makeDio(BaseOptions(baseUrl: Config.apiHost, connectTimeout: const Duration(seconds: 15), receiveTimeout: const Duration(seconds: 30), responseType: ResponseType.json, validateStatus: (_) => true));

  Future<Json> _send(String method, String path, {Object? body, Map<String, dynamic>? query}) async {
    final t = token();
    try {
      final r = await _dio.request<dynamic>(
        path,
        data: body,
        queryParameters: query?..removeWhere((_, v) => v == null || v == ''),
        options: Options(method: method, headers: {'x-api-key': Config.apiKey, if (t != null && t.isNotEmpty) 'Authorization': 'Bearer $t'}),
      );
      final data = r.data is String && (r.data as String).isNotEmpty ? _tryJson(r.data as String) : r.data;
      final json = data is Map ? Map<String, dynamic>.from(data) : <String, dynamic>{'data': data};
      final status = r.statusCode ?? 0;
      if (status == 401 && t != null) onUnauthorized();
      if (status >= 400 || json['success'] == false) {
        throw ApiError(status, '${json['message'] ?? 'Error $status'}', code: json['code'] as String?, body: json);
      }
      return json;
    } on DioException catch (e) {
      throw ApiError(0, e.message ?? 'network');
    }
  }

  static Object? _tryJson(String s) {
    try {
      return jsonDecode(s);
    } catch (_) {
      return {'message': s};
    }
  }

  Future<Json> get(String path, [Map<String, dynamic>? query]) => _send('GET', path, query: query);
  Future<Json> post(String path, [Object? body]) => _send('POST', path, body: body ?? const {});
  Future<Json> put(String path, [Object? body]) => _send('PUT', path, body: body ?? const {});
  Future<Json> patch(String path, [Object? body]) => _send('PATCH', path, body: body ?? const {});
  Future<Json> delete(String path, [Object? body]) => _send('DELETE', path, body: body);

  // a file the API sends as plain text (CSV downloads)
  Future<String> text(String path, [Map<String, dynamic>? query]) async {
    final t = token();
    try {
      final r = await _dio.get<String>(
        path,
        queryParameters: query?..removeWhere((_, v) => v == null || v == ''),
        options: Options(responseType: ResponseType.plain, headers: {'x-api-key': Config.apiKey, if (t != null && t.isNotEmpty) 'Authorization': 'Bearer $t'}),
      );
      final status = r.statusCode ?? 0;
      if (status >= 400) {
        final j = _tryJson(r.data ?? '');
        final body = j is Map ? Map<String, dynamic>.from(j) : <String, dynamic>{};
        throw ApiError(status, '${body['message'] ?? 'Error $status'}', body: body);
      }
      return r.data ?? '';
    } on DioException catch (e) {
      throw ApiError(0, e.message ?? 'network');
    }
  }

  // owner = /api/user, super admin = /api/admin, public = /api/public
  static const user = '/api/user';
  static const admin = '/api/admin';
  static const public = '/api/public';
}

// small helpers to read loose JSON safely
num n(Object? v) => v is num ? v : num.tryParse('${v ?? ''}') ?? 0;
String str(Object? v) => v == null ? '' : '$v';
Json obj(Object? v) => v is Map ? Map<String, dynamic>.from(v) : <String, dynamic>{};
List<Json> objs(Object? v) => v is List ? v.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList() : <Json>[];
