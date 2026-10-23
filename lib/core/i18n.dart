import 'dart:convert';

import 'package:flutter/services.dart';

import 'app_text.dart';

// Texts: assets/i18n/en.json + km.json are made from the web's own text files (tool/extract_texts.js),
// so the app says exactly what the website says. Words only the app needs are in app_text.dart.
//
//   t('dash.today')                       → "Sales today"
//   t('dash.updated', {'t': '20:15'})     → "Updated 20:15"
class T {
  final String lang;
  final Map<String, dynamic> _m;
  const T(this.lang, this._m);

  bool get km => lang == 'km';

  String call(String key, [Map<String, Object?> vars = const {}]) {
    var s = _m[key];
    if (s is! String) return key;
    vars.forEach((k, v) => s = (s as String).replaceAll('{$k}', '${v ?? ''}'));
    return s as String;
  }

  // a text that may not exist (product names, statuses…)
  String? maybe(String key) => _m[key] is String ? _m[key] as String : null;
  String or(String key, String fallback) => maybe(key) ?? fallback;

  // the same texts with some replaced (the super admin can change homepage texts)
  T over(Map<String, dynamic> extra) => extra.isEmpty ? this : T(lang, {..._m, ...extra});

  // the same key in the other language (search both)
  String other(String lang, String key) => _all[lang]?[key] is String ? _all[lang]![key] as String : '';

  // a value as it is in the json (lists of lists, numbers…)
  Object? raw(String key) => _m[key];

  List<String> list(String key) => (_m[key] is List) ? (_m[key] as List).map((e) => '$e').toList() : const [];

  static final Map<String, Map<String, dynamic>> _all = {};

  static Future<void> load() async {
    for (final lang in ['en', 'km']) {
      final raw = jsonDecode(await rootBundle.loadString('assets/i18n/$lang.json')) as Map<String, dynamic>;
      _all[lang] = {...raw, ...appText[lang]!};
    }
  }

  static T of(String lang) => T(lang, _all[lang] ?? _all['en'] ?? const {});
}
