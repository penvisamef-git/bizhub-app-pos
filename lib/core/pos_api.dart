import 'package:dio/dio.dart';

import 'api.dart' show ApiError, Json, makeDio;
import 'config.dart';

export 'api.dart' show ApiError, Json, obj, objs, str, n;

// Talks to Biz Hub as a linked POS device (the web's pos/api.js): x-api-key + x-device-token.
class PosApi {
  final String token;
  PosApi([this.token = '']);

  static final Dio _dio = makeDio(
    BaseOptions(baseUrl: Config.apiHost, connectTimeout: const Duration(seconds: 12), receiveTimeout: const Duration(seconds: 40), responseType: ResponseType.json, validateStatus: (_) => true),
  );

  Future<Json> call(String method, String path, {Object? body}) async {
    try {
      final r = await _dio.request<dynamic>(
        path,
        data: method == 'GET' ? null : (body ?? const {}),
        options: Options(method: method, headers: {'x-api-key': Config.apiKey, if (token.isNotEmpty) 'x-device-token': token}),
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

  // ---- restaurant (/api/pos/…) ----
  Future<Json> restPair(String code, String name) => call('POST', '/api/pos/pair', body: {'code': code, 'name': name, 'kind': 'app'});
  Future<Json> restBootstrap() => call('GET', '/api/pos/bootstrap');
}
