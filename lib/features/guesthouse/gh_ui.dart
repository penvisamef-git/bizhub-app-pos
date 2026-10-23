import 'package:flutter/material.dart';

import '../../core/api.dart' show ApiError;
import '../../core/app_state.dart';
import '../../core/theme.dart';
import '../restaurant/engine/calc.dart' show nz;
import '../restaurant/pos_ui.dart' show tr;

// small helpers shared by the Guest House screens (the web's guesthouse/text.js helpers)

String _group(String s) => s.replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (_) => ',');

// "$25" / "$25.5" / "100,000៛" — like the web (no forced decimals)
String ghMoney(Object? v, String cur) {
  final n = nz(v);
  if (cur == 'KHR') return '${n < 0 ? '-' : ''}${_group(n.abs().round().toString())}៛';
  var s = n.abs().toStringAsFixed(2);
  if (s.endsWith('.00')) {
    s = s.substring(0, s.length - 3);
  } else if (s.endsWith('0')) {
    s = s.substring(0, s.length - 1);
  }
  final parts = s.split('.');
  return '${n < 0 ? '-' : ''}\$${_group(parts[0])}${parts.length > 1 ? '.${parts[1]}' : ''}';
}

const _monEn = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
const _monKm = ['មករា', 'កុម្ភៈ', 'មីនា', 'មេសា', 'ឧសភា', 'មិថុនា', 'កក្កដា', 'សីហា', 'កញ្ញា', 'តុលា', 'វិច្ឆិកា', 'ធ្នូ'];
const _wdEn = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
const _wdKm = ['ច័ន្ទ', 'អង្គារ', 'ពុធ', 'ព្រហ', 'សុក្រ', 'សៅរ៍', 'អាទិត្យ'];
const _wdLongEn = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'];
const _monLongEn = ['January', 'February', 'March', 'April', 'May', 'June', 'July', 'August', 'September', 'October', 'November', 'December'];

String get _lang => AppState.i.lang;

// a day "YYYY-MM-DD" → "19 Oct" (+ weekday / year)
String ghDay(String day, {bool weekday = false, bool year = false, bool long = false}) {
  final d = DateTime.tryParse('${day}T00:00:00Z');
  if (d == null) return '';
  final km = _lang == 'km';
  if (long) return km ? 'ថ្ងៃ${_wdKm[d.weekday - 1]} ទី${d.day} ${_monKm[d.month - 1]}' : '${_wdLongEn[d.weekday - 1]} ${d.day} ${_monLongEn[d.month - 1]}';
  final s = '${d.day} ${km ? _monKm[d.month - 1] : _monEn[d.month - 1]}${year ? ' ${d.year}' : ''}';
  return weekday ? '${km ? _wdKm[d.weekday - 1] : _wdEn[d.weekday - 1]} $s' : s;
}

String ghWeekday(String day) {
  final d = DateTime.tryParse('${day}T00:00:00Z');
  return d == null ? '' : (_lang == 'km' ? _wdKm[d.weekday - 1] : _wdEn[d.weekday - 1]);
}

String ghMonth(String month) {
  final p = month.split('-');
  if (p.length < 2) return month;
  final m = int.tryParse(p[1]) ?? 1;
  return _lang == 'km' ? '${_monKm[m - 1]} ${p[0]}' : '${_monLongEn[m - 1]} ${p[0]}';
}

// a moment → "19 Oct, 14:05" (Phnom Penh time)
String ghTime(Object? iso) {
  final d = DateTime.tryParse('${iso ?? ''}')?.toUtc().add(const Duration(hours: 7));
  if (d == null) return '';
  String two(int x) => x.toString().padLeft(2, '0');
  return '${d.day} ${_lang == 'km' ? _monKm[d.month - 1] : _monEn[d.month - 1]}, ${two(d.hour)}:${two(d.minute)}';
}

// colours: booking status / room state
(Color, Color) ghStatusColors(BuildContext context, String s) {
  final c = context.c;
  return switch (s) {
    'booked' || 'arriving' => (c.brandInk, c.active),
    'in' || 'occupied' => (const Color(0xFF1D4ED8), const Color(0x1F2563EB)),
    'due_out' => (c.warn, c.warnBg),
    'out' => (c.good, c.goodBg),
    'free' => (c.good, c.goodBg),
    'cancelled' || 'no_show' => (c.danger, c.dangerBg),
    _ => (c.muted, c.chip),
  };
}

Color ghColor(String hex, [Color fallback = const Color(0xFF2563EB)]) {
  final h = hex.replaceFirst('#', '');
  final v = int.tryParse(h.length == 6 ? 'FF$h' : '', radix: 16);
  return v == null ? fallback : Color(v);
}

class GhPill extends StatelessWidget {
  final String text;
  final Color fg, bg;
  const GhPill(this.text, {super.key, required this.fg, required this.bg});
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
    decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(999)),
    child: Text(
      text,
      style: TextStyle(color: fg, fontSize: 11.5, fontWeight: FontWeight.w700),
    ),
  );
}

String ghErr(BuildContext context, Object e) => e is ApiError ? (e.network ? tr(context)('rpos.needInternetShort') : e.message) : '$e';

void ghToast(BuildContext context, String msg) => ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(content: Text(msg)));
