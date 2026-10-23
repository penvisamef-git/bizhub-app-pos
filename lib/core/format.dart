import 'package:intl/intl.dart';

final _n = NumberFormat.decimalPattern('en_US');
final _m2 = NumberFormat('#,##0.00', 'en_US');

String fmt(Object? v) => _n.format(v is num ? v : num.tryParse('${v ?? ''}') ?? 0);
String usd(Object? v) => '\$${_m2.format(v is num ? v : num.tryParse('${v ?? ''}') ?? 0)}';
String money(Object? v, String? currency) {
  final x = v is num ? v : num.tryParse('${v ?? ''}') ?? 0;
  return currency == 'KHR' ? '${_n.format(x.round())}៛' : usd(x);
}

// Phnom Penh time, like the web
DateTime? _parse(Object? v) {
  final d = v is DateTime ? v : DateTime.tryParse('${v ?? ''}');
  return d?.toUtc().add(const Duration(hours: 7));
}

const _monEn = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
const _monKm = ['មករា', 'កុម្ភៈ', 'មីនា', 'មេសា', 'ឧសភា', 'មិថុនា', 'កក្កដា', 'សីហា', 'កញ្ញា', 'តុលា', 'វិច្ឆិកា', 'ធ្នូ'];
const _dayEn = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'];
const _dayKm = ['ច័ន្ទ', 'អង្គារ', 'ពុធ', 'ព្រហស្បតិ៍', 'សុក្រ', 'សៅរ៍', 'អាទិត្យ'];
String _pad2(int x) => x.toString().padLeft(2, '0');

// "13 Oct 2026" / "13 Oct 2026, 20:20"
String fmtDate(Object? v, {bool time = false, String lang = 'en'}) {
  final d = _parse(v);
  if (d == null) return '-';
  final mon = lang == 'km' ? _monKm[d.month - 1] : _monEn[d.month - 1];
  final s = '${_pad2(d.day)} $mon ${d.year}';
  return time ? '$s, ${_pad2(d.hour)}:${_pad2(d.minute)}' : s;
}

// "Tuesday 13 October" under the page title
String fmtToday(String lang) {
  final d = DateTime.now();
  const fullEn = ['January', 'February', 'March', 'April', 'May', 'June', 'July', 'August', 'September', 'October', 'November', 'December'];
  return lang == 'km' ? 'ថ្ងៃ${_dayKm[d.weekday - 1]} ទី${d.day} ${_monKm[d.month - 1]}' : '${_dayEn[d.weekday - 1]} ${d.day} ${fullEn[d.month - 1]}';
}

String fmtTime(Object? v) {
  final d = _parse(v);
  return d == null ? '' : '${_pad2(d.hour)}:${_pad2(d.minute)}';
}

// "+855 12 345 678" → "+85512345678"; "012 345 678" → "+85512345678" (Cambodia when no code)
String? normalizePhone(String input) {
  var s = input.trim().replaceAll(RegExp(r'[\s\-()]'), '');
  if (s.isEmpty) return null;
  if (s.startsWith('00')) s = '+${s.substring(2)}';
  if (!s.startsWith('+')) s = '+855${s.replaceFirst(RegExp(r'^0+'), '')}';
  final digits = s.substring(1);
  if (!RegExp(r'^\d{8,15}$').hasMatch(digits)) return null;
  if (digits.startsWith('855') && !RegExp(r'^855\d{8,9}$').hasMatch(digits)) return null;
  return s;
}

String prettyPhone(String e164) {
  final m = RegExp(r'^\+855(\d{2})(\d{3})(\d{3,4})$').firstMatch(e164);
  return m == null ? e164 : '+855 ${m[1]} ${m[2]} ${m[3]}';
}

String initialOf(String name) => name.trim().isEmpty ? '?' : name.trim().characters1.toUpperCase();

extension on String {
  String get characters1 => runes.isEmpty ? '' : String.fromCharCode(runes.first);
}
