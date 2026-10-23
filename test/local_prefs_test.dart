// The local store: SQLite on Mac / Windows (SqlitePrefs), SharedPreferences elsewhere (SpPrefs).
// SqlitePrefs is tested on a temporary file (the test machine's own SQLite).
import 'dart:io';

import 'package:bizhub_pos/core/local_prefs.dart';
import 'package:bizhub_pos/core/local_prefs_io.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  late Directory dir;
  setUp(() => dir = Directory.systemTemp.createTempSync('bizhub_prefs_'));
  tearDown(() => dir.deleteSync(recursive: true));
  String db() => '${dir.path}/bizhub_pos.db';

  test('every type is kept, survives a restart, remove works', () async {
    final a = SqlitePrefs.open(db());
    expect(a.engine, 'sqlite');
    expect(await a.setString('mp.boot', '{"products":[1,2,3]}'), isTrue);
    await a.setInt('rp.seq', 42);
    await a.setBool('pos.onboarded', true);
    await a.setDouble('rate', 4100.5);
    await a.setString('gone', 'x');
    expect(await a.remove('gone'), isTrue);
    expect(a.getString('mp.boot'), '{"products":[1,2,3]}');
    expect(a.getInt('rp.seq'), 42);
    expect(a.getBool('pos.onboarded'), isTrue);
    expect(a.getDouble('rate'), 4100.5);
    expect(a.getString('rp.seq'), isNull, reason: 'wrong type gives null, like SharedPreferences');
    a.close();

    final b = SqlitePrefs.open(db()); // the app opened again
    expect(b.getString('mp.boot'), '{"products":[1,2,3]}');
    expect(b.getInt('rp.seq'), 42);
    expect(b.getBool('pos.onboarded'), isTrue);
    expect(b.getDouble('rate'), 4100.5);
    expect(b.containsKey('gone'), isFalse);
    expect(b.getKeys(), {'mp.boot', 'rp.seq', 'pos.onboarded', 'rate'});
    await b.setString('mp.boot', 'v2'); // overwrite
    b.close();
    expect(SqlitePrefs.open(db()).getString('mp.boot'), 'v2');
  });

  test('first open copies the old SharedPreferences data once', () async {
    SharedPreferences.setMockInitialValues({'pos.link': '{"kind":"mart"}', 'pos.lang': 'km', 'mp.queue': '[{"client_id":"a1"}]', 'n': 7, 'ok': true});
    final sp = await SharedPreferences.getInstance();
    final a = SqlitePrefs.open(db(), importFrom: sp);
    expect(a.getString('pos.link'), '{"kind":"mart"}');
    expect(a.getString('mp.queue'), '[{"client_id":"a1"}]');
    expect(a.getInt('n'), 7);
    expect(a.getBool('ok'), isTrue);
    expect(a.getKeys(), {'pos.link', 'pos.lang', 'mp.queue', 'n', 'ok'}, reason: 'the import marker stays hidden');
    await a.setString('pos.lang', 'en');
    await a.remove('mp.queue');
    a.close();
    // opened again: no second import (the change and the removal stay)
    final b = SqlitePrefs.open(db(), importFrom: sp);
    expect(b.getString('pos.lang'), 'en');
    expect(b.containsKey('mp.queue'), isFalse);
    b.close();
  });

  test('a big product list (5,000 items) and many queued sales', () async {
    final a = SqlitePrefs.open(db());
    final products = List.generate(5000, (i) => '{"_id":"p$i","name":"Product $i","price":${i % 50}.5,"barcode":"885${i.toString().padLeft(10, '0')}"}');
    final big = '[${products.join(',')}]';
    final t = Stopwatch()..start();
    await a.setString('mp.boot', big);
    for (var i = 0; i < 500; i++) {
      await a.setString('mp.queue', '[${List.filled(i % 20, '{"x":1}').join(',')}]');
    }
    t.stop();
    a.close();
    expect(SqlitePrefs.open(db()).getString('mp.boot')!.length, big.length);
    expect(t.elapsedMilliseconds, lessThan(5000));
  });

  test('on this test machine (not Mac / Windows) the app uses SharedPreferences', () async {
    SharedPreferences.setMockInitialValues({'pos.lang': 'en'});
    expect(desktopStorage, isFalse);
    final p = await LocalPrefs.getInstance();
    expect(p.engine, 'shared_preferences');
    expect(p.getString('pos.lang'), 'en');
  });
}
