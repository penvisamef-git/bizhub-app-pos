import 'package:shared_preferences/shared_preferences.dart';

import 'local_prefs_stub.dart' if (dart.library.io) 'local_prefs_io.dart' as impl;

// Where this device keeps its data (link, menus / products, today's sales, the offline queue, printers…).
//   phones and tablets (Android, iOS) and the web: SharedPreferences, exactly as before
//   Mac and Windows: one SQLite file, bizhub_pos.db in the app's support folder (safe if the power goes,
//     quick with big product lists). The first time, whatever an older desktop build kept in SharedPreferences
//     is copied in, so nothing is lost. If SQLite can't open, it falls back to SharedPreferences.
// The same small API as SharedPreferences, so the POS engines did not change.
abstract class LocalPrefs {
  static Future<LocalPrefs>? _instance;
  static Future<LocalPrefs> getInstance() => _instance ??= _open();

  static Future<LocalPrefs> _open() async {
    final sp = await SharedPreferences.getInstance();
    return await impl.openDesktop(sp) ?? SpPrefs(sp);
  }

  // which storage is in use ('shared_preferences' | 'sqlite'), for Settings → This device
  String get engine;

  String? getString(String key);
  int? getInt(String key);
  bool? getBool(String key);
  double? getDouble(String key);
  Set<String> getKeys();
  bool containsKey(String key);
  Future<bool> setString(String key, String value);
  Future<bool> setInt(String key, int value);
  Future<bool> setBool(String key, bool value);
  Future<bool> setDouble(String key, double value);
  Future<bool> remove(String key);
}

// phones, tablets, the web (and the desktop fallback): SharedPreferences as it is
class SpPrefs implements LocalPrefs {
  final SharedPreferences _p;
  SpPrefs(this._p);
  @override
  String get engine => 'shared_preferences';
  @override
  String? getString(String key) => _p.getString(key);
  @override
  int? getInt(String key) => _p.getInt(key);
  @override
  bool? getBool(String key) => _p.getBool(key);
  @override
  double? getDouble(String key) => _p.getDouble(key);
  @override
  Set<String> getKeys() => _p.getKeys();
  @override
  bool containsKey(String key) => _p.containsKey(key);
  @override
  Future<bool> setString(String key, String value) => _p.setString(key, value);
  @override
  Future<bool> setInt(String key, int value) => _p.setInt(key, value);
  @override
  Future<bool> setBool(String key, bool value) => _p.setBool(key, value);
  @override
  Future<bool> setDouble(String key, double value) => _p.setDouble(key, value);
  @override
  Future<bool> remove(String key) => _p.remove(key);
}
