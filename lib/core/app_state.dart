import 'dart:convert';

import 'package:flutter/material.dart';
import 'local_prefs.dart';

import 'i18n.dart';

// The POS kinds this app can be (Biz Hub business types). Only "ready" ones can be linked in the app today.
const posKinds = ['restaurant', 'mart', 'guest_house', 'tg_store', 'event', 'attendance', 'stamp_card'];
const readyKinds = {'restaurant', 'mart', 'guest_house', 'tg_store', 'event', 'attendance', 'stamp_card'};

// What this device is: its language, whether the welcome pages were seen, and the business it is linked to.
// Everything is kept on the device (LocalPrefs: SharedPreferences on phones, SQLite on Mac / Windows), so the POS
// opens straight to work, even offline.
class AppState extends ChangeNotifier {
  AppState._();
  static final AppState i = AppState._();
  late LocalPrefs _p;

  String lang = 'km';
  String theme = 'system'; // light | dark | system (same as the phone)
  bool onboarded = false;
  Map<String, dynamic>? link; // { kind, token, device: {_id, name, prefix}, shop, logo, linked_at }

  T get t => T.of(lang);
  String? get kind => link?['kind'] as String?;
  String get token => (link?['token'] as String?) ?? '';
  // linked to a sample shop with "Try demo" (no owner code); the staff PIN to show on the PIN screens
  bool get demo => link?['demo'] == true;
  String get demoPin => (link?['pin'] as String?) ?? '';

  static Future<void> init() async {
    final s = i;
    s._p = await LocalPrefs.getInstance();
    s.lang = s._p.getString('pos.lang') ?? 'km';
    s.onboarded = s._p.getBool('pos.onboarded') ?? false;
    s.theme = s._p.getString('pos.theme') ?? 'system';
    final raw = s._p.getString('pos.link');
    if (raw != null && raw.isNotEmpty) {
      try {
        s.link = Map<String, dynamic>.from(jsonDecode(raw) as Map);
      } catch (_) {}
    }
  }

  void setLang(String v) {
    lang = v;
    _p.setString('pos.lang', v);
    notifyListeners();
  }

  ThemeMode get themeMode => switch (theme) {
    'light' => ThemeMode.light,
    'dark' => ThemeMode.dark,
    _ => ThemeMode.system,
  };

  void setTheme(String v) {
    theme = v;
    _p.setString('pos.theme', v);
    notifyListeners();
  }

  // small per-device choices (where Bizi sits…)
  String? pref(String key) => _p.getString(key);
  void setPref(String key, String value) => _p.setString(key, value);

  void doneWelcome() {
    onboarded = true;
    _p.setBool('pos.onboarded', true);
    notifyListeners();
  }

  void linked(Map<String, dynamic> v) {
    link = v;
    _p.setString('pos.link', jsonEncode(v));
    notifyListeners();
  }

  void unlink() {
    link = null;
    _p.remove('pos.link');
    notifyListeners();
  }
}

// rebuilds its child when the app state changes (language, link)
class AppScope extends InheritedNotifier<AppState> {
  AppScope({super.key, required super.child}) : super(notifier: AppState.i);
  static AppState of(BuildContext context) => context.dependOnInheritedWidgetOfExactType<AppScope>()!.notifier!;
}
