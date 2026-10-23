import 'dart:math';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import '../../core/local_prefs.dart';

import '../../core/api.dart' show ApiError, Json, makeDio;
import '../../core/config.dart';
import '../../core/i18n.dart';

export '../../core/api.dart' show ApiError, Json, obj, objs, str, n;

// Attendance talks to Biz Hub like the web staff app (/a/<code>) and door page (/k/<token>):
//   staff phone: x-api-key + x-att-token      door tablet: x-api-key, the kiosk token in the path
class AttApi {
  final String token;
  AttApi([this.token = '']);

  static final Dio _dio = makeDio(
    BaseOptions(baseUrl: Config.apiHost, connectTimeout: const Duration(seconds: 12), receiveTimeout: const Duration(seconds: 40), responseType: ResponseType.json, validateStatus: (_) => true),
  );

  // → the answer's `data`
  Future<dynamic> call(String method, String path, {Object? body}) async {
    try {
      final r = await _dio.request<dynamic>(
        '/api/att$path',
        data: method == 'GET' ? null : (body ?? const {}),
        options: Options(method: method, headers: {'x-api-key': Config.apiKey, if (token.isNotEmpty) 'x-att-token': token}),
      );
      final data = r.data;
      final json = data is Map ? Map<String, dynamic>.from(data) : <String, dynamic>{'data': data};
      final status = r.statusCode ?? 0;
      if (status >= 400 || json['success'] == false) throw ApiError(status, '${json['message'] ?? 'Error $status'}', code: json['code'] as String?, body: json);
      return json['data'];
    } on DioException catch (e) {
      throw ApiError(0, e.message ?? 'network');
    }
  }

  Future<dynamic> get(String path) => call('GET', path);
  Future<dynamic> post(String path, [Object? body]) => call('POST', path, body: body);
  Future<dynamic> del(String path) => call('DELETE', path);

  // clock in / out; the selfie goes as form-data "photo"
  Future<Json> punch(Map<String, Object?> fields, {Uint8List? photo}) async {
    final clean = {
      for (final e in fields.entries)
        if (e.value != null) e.key: e.value,
    };
    final body = photo == null
        ? clean
        : FormData.fromMap({for (final e in clean.entries) e.key: '${e.value}', 'photo': MultipartFile.fromBytes(photo, filename: 'selfie.jpg', contentType: DioMediaType('image', 'jpeg'))});
    return Map<String, dynamic>.from(await call('POST', '/punch', body: body) as Map);
  }
}

// one id per phone, kept forever: the first staff log in locks the account to it (like the web's bizhub_att_device)
Future<String> attDeviceId() async {
  final p = await LocalPrefs.getInstance();
  var id = p.getString('att.device') ?? '';
  if (id.isEmpty) {
    final r = Random.secure();
    id = List.generate(32, (_) => r.nextInt(16).toRadixString(16)).join();
    await p.setString('att.device', id);
  }
  return id;
}

// the error words for a code the API sends (att.err.*), else its own message
String attErr(T t, Object e) {
  if (e is ApiError) {
    if (e.network) return t('att.network');
    final known = e.code == null ? null : t.maybe('att.err.${e.code}');
    return known ?? e.message;
  }
  return '$e';
}

// ---------------------------------------------------------------- links (QR codes)
// staff link …/a/<code>[?k=<branch>.<code>]   door link …/k/<token>
({String code, String k})? parseStaffLink(String v) {
  final s = v.trim();
  final m = RegExp(r'/a/([A-Za-z0-9]{6,12})(?:\?(.*))?$').firstMatch(s);
  if (m != null) return (code: m[1]!, k: Uri.splitQueryString(m[2] ?? '')['k'] ?? '');
  if (RegExp(r'^[A-Za-z0-9]{6,12}$').hasMatch(s)) return (code: s, k: '');
  return null;
}

String? parseKioskLink(String v) {
  final s = v.trim();
  final m = RegExp(r'/k/([A-Za-z0-9]{16,40})/?$').firstMatch(s);
  if (m != null) return m[1];
  if (RegExp(r'^[A-Za-z0-9]{16,40}$').hasMatch(s)) return s;
  return null;
}

// ---------------------------------------------------------------- time (Phnom Penh, like the web)
DateTime? _kh(Object? v) {
  final d = v is DateTime ? v : DateTime.tryParse('${v ?? ''}');
  return d?.toUtc().add(const Duration(hours: 7));
}

String _p2(int x) => x.toString().padLeft(2, '0');
String hhmm(Object? v) {
  final d = _kh(v);
  return d == null ? '—' : '${_p2(d.hour)}:${_p2(d.minute)}';
}

DateTime khNow([int offsetMs = 0]) => DateTime.now().toUtc().add(Duration(milliseconds: offsetMs, hours: 7));
String khDay([int offsetMs = 0]) {
  final d = khNow(offsetMs);
  return '${d.year}-${_p2(d.month)}-${_p2(d.day)}';
}

String khMonth() => khDay().substring(0, 7);
String shiftMonth(String month, int by) {
  final y = int.parse(month.substring(0, 4)), m = int.parse(month.substring(5, 7));
  final d = DateTime.utc(y, m - 1 + by, 1);
  return '${d.year}-${_p2(d.month)}';
}

String dur(Object? min) {
  final m = (min is num ? min : num.tryParse('${min ?? ''}') ?? 0).round();
  if (m < 60) return '${m}m';
  return '${m ~/ 60}h${m % 60 > 0 ? ' ${_p2(m % 60)}m' : ''}';
}

const _monEn = ['January', 'February', 'March', 'April', 'May', 'June', 'July', 'August', 'September', 'October', 'November', 'December'];
const _monKm = ['មករា', 'កុម្ភៈ', 'មីនា', 'មេសា', 'ឧសភា', 'មិថុនា', 'កក្កដា', 'សីហា', 'កញ្ញា', 'តុលា', 'វិច្ឆិកា', 'ធ្នូ'];
const _dayEn = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'];
const _dayKm = ['ច័ន្ទ', 'អង្គារ', 'ពុធ', 'ព្រហស្បតិ៍', 'សុក្រ', 'សៅរ៍', 'អាទិត្យ'];

// "Monday 19 October" / "ថ្ងៃច័ន្ទ ទី19 តុលា"
String longDate(DateTime kh, String lang) => lang == 'km' ? 'ថ្ងៃ${_dayKm[kh.weekday - 1]} ទី${kh.day} ${_monKm[kh.month - 1]}' : '${_dayEn[kh.weekday - 1]} ${kh.day} ${_monEn[kh.month - 1]}';

// "October 2026"
String monthTitle(String month, String lang) {
  final y = month.substring(0, 4), m = int.parse(month.substring(5, 7));
  return lang == 'km' ? '${_monKm[m - 1]} $y' : '${_monEn[m - 1]} $y';
}

// "Mon 19" (withMonth: "Mon 19 Oct")
String dayLabel(String day, String lang, {bool withMonth = false}) {
  final d = DateTime.tryParse(day);
  if (d == null) return day;
  final wd = lang == 'km' ? _dayKm[d.weekday - 1] : _dayEn[d.weekday - 1].substring(0, 3);
  final mon = lang == 'km' ? _monKm[d.month - 1] : _monEn[d.month - 1].substring(0, 3);
  return withMonth ? '$wd ${d.day} $mon' : '$wd ${d.day}';
}

// "#4F46E5" → Color (the owner's chosen colour)
Color hexColor(Object? v, Color fallback) {
  final s = '${v ?? ''}'.replaceAll('#', '');
  final x = int.tryParse(s, radix: 16);
  return s.length == 6 && x != null ? Color(0xFF000000 | x) : fallback;
}

// metres between two points
int distanceM(double lat1, double lng1, double lat2, double lng2) {
  double rad(double x) => x * pi / 180;
  final a = pow(sin(rad(lat2 - lat1) / 2), 2) + cos(rad(lat1)) * cos(rad(lat2)) * pow(sin(rad(lng2 - lng1) / 2), 2);
  return (2 * 6371000 * asin(sqrt(a))).round();
}
