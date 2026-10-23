import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqlite3/sqlite3.dart';

import 'local_prefs.dart';

// Mac and Windows only: the SQLite store. Android, iOS (and Linux) keep SharedPreferences → null.
// SQLite comes with the system (macOS /usr/lib/libsqlite3.dylib, Windows 10+ winsqlite3.dll): nothing extra to ship.
bool get desktopStorage => Platform.isMacOS || Platform.isWindows;

Future<LocalPrefs?> openDesktop(SharedPreferences sp) async {
  if (!desktopStorage) return null;
  try {
    final dir = await getApplicationSupportDirectory();
    await dir.create(recursive: true);
    return SqlitePrefs.open('${dir.path}${Platform.pathSeparator}bizhub_pos.db', importFrom: sp);
  } catch (e) {
    debugPrint('[local_prefs] SQLite could not open, using SharedPreferences: $e');
    return null;
  }
}

// One table of keys and values, all read into memory when the app starts (reads stay instant, like
// SharedPreferences); every change is written to the file at once (WAL: a crash or power cut keeps what was saved).
//   kv(k TEXT PRIMARY KEY, t INTEGER, v TEXT)   t: 0 text · 1 int · 2 bool · 3 double
class SqlitePrefs implements LocalPrefs {
  final Database _db;
  final Map<String, Object> _cache;
  final PreparedStatement _put, _del;
  SqlitePrefs._(this._db, this._cache, this._put, this._del);

  static const _migratedKey = '__imported_shared_preferences';

  // also used by the tests (a temporary file)
  static SqlitePrefs open(String path, {SharedPreferences? importFrom}) {
    final db = sqlite3.open(path);
    db.execute('PRAGMA journal_mode = WAL;');
    db.execute('PRAGMA synchronous = NORMAL;');
    db.execute('CREATE TABLE IF NOT EXISTS kv (k TEXT PRIMARY KEY NOT NULL, t INTEGER NOT NULL, v TEXT NOT NULL) WITHOUT ROWID;');
    final cache = <String, Object>{};
    for (final r in db.select('SELECT k, t, v FROM kv')) {
      final v = _decode(r['t'] as int, r['v'] as String);
      if (v != null) cache[r['k'] as String] = v;
    }
    final put = db.prepare('INSERT INTO kv (k, t, v) VALUES (?, ?, ?) ON CONFLICT(k) DO UPDATE SET t = excluded.t, v = excluded.v');
    final del = db.prepare('DELETE FROM kv WHERE k = ?');
    final s = SqlitePrefs._(db, cache, put, del);
    if (importFrom != null && !cache.containsKey(_migratedKey)) s._import(importFrom);
    return s;
  }

  // the first time on this computer: copy what SharedPreferences has (an older desktop build), in one transaction
  void _import(SharedPreferences sp) {
    _db.execute('BEGIN');
    try {
      for (final k in sp.getKeys()) {
        if (_cache.containsKey(k)) continue;
        final v = sp.get(k);
        if (v is String || v is int || v is bool || v is double) _write(k, v!);
      }
      _write(_migratedKey, true);
      _db.execute('COMMIT');
    } catch (e) {
      _db.execute('ROLLBACK');
      rethrow;
    }
  }

  static Object? _decode(int t, String v) => switch (t) {
    0 => v,
    1 => int.tryParse(v),
    2 => v == '1',
    3 => double.tryParse(v),
    _ => null,
  };

  bool _write(String key, Object value) {
    final (t, s) = switch (value) {
      String v => (0, v),
      int v => (1, '$v'),
      bool v => (2, v ? '1' : '0'),
      double v => (3, jsonEncode(v)),
      _ => throw ArgumentError('unsupported type ${value.runtimeType}'),
    };
    try {
      _put.execute([key, t, s]);
      _cache[key] = value;
      return true;
    } catch (e) {
      debugPrint('[local_prefs] write $key failed: $e');
      return false;
    }
  }

  T? _get<T>(String key) {
    final v = _cache[key];
    return v is T ? v : null;
  }

  @override
  String get engine => 'sqlite';
  @override
  String? getString(String key) => _get<String>(key);
  @override
  int? getInt(String key) => _get<int>(key);
  @override
  bool? getBool(String key) => _get<bool>(key);
  @override
  double? getDouble(String key) => _get<double>(key);
  @override
  Set<String> getKeys() => _cache.keys.where((k) => k != _migratedKey).toSet();
  @override
  bool containsKey(String key) => key != _migratedKey && _cache.containsKey(key);
  @override
  Future<bool> setString(String key, String value) async => _write(key, value);
  @override
  Future<bool> setInt(String key, int value) async => _write(key, value);
  @override
  Future<bool> setBool(String key, bool value) async => _write(key, value);
  @override
  Future<bool> setDouble(String key, double value) async => _write(key, value);
  @override
  Future<bool> remove(String key) async {
    try {
      _del.execute([key]);
      _cache.remove(key);
      return true;
    } catch (e) {
      debugPrint('[local_prefs] remove $key failed: $e');
      return false;
    }
  }

  // tests: close the file
  void close() {
    _put.dispose();
    _del.dispose();
    _db.dispose();
  }
}
