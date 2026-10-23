// Google Play screenshots: the real POS screens with the demo shops' data (answers recorded from the real API on a
// throwaway database: bizhub-api scripts/demo-pos.js --test --capture=…/fixtures.json).
//
//   flutter test test/store/store_shots_test.dart --update-goldens \
//     --dart-define=API_HOST=http://demo --dart-define=STORE_SHOTS=true --dart-define=SHOT_KIND=restaurant --dart-define=SHOT_LANG=en
//   → test/store/out/<lang>-<kind>-<n>-<name>.png   (SHOT_KIND: restaurant | mart | guest_house · SHOT_LANG: en | km)
//
// A picture maker, not a check: it only runs when asked (STORE_SHOTS=true). store/android/compose/ then puts each
// picture in a phone frame with a headline.
import 'dart:convert';
import 'dart:io';

import 'package:bizhub_pos/core/api.dart';
import 'package:bizhub_pos/core/app_state.dart';
import 'package:bizhub_pos/core/i18n.dart';
import 'package:bizhub_pos/features/guesthouse/engine/gh_pos.dart';
import 'package:bizhub_pos/features/mart/engine/mart_pos.dart';
import 'package:bizhub_pos/features/restaurant/engine/rest_pos.dart';
import 'package:bizhub_pos/main.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _run = bool.fromEnvironment('STORE_SHOTS');
const _kind = String.fromEnvironment('SHOT_KIND', defaultValue: 'restaurant');
const _lang = String.fromEnvironment('SHOT_LANG', defaultValue: 'en');
const _tablet = bool.fromEnvironment('SHOT_TABLET');
// phone: 392.7 × 850.9 dp × 2.75 = 1080 × 2340 · tablet (10", landscape): 1280 × 800 dp × 2 = 2560 × 1600
const _size = _tablet ? Size(1280, 800) : Size(392.727, 850.909);
const _ratio = _tablet ? 2.0 : 2.75;

Future<void> loadFonts() async {
  Future<void> fam(String name, List<String> files) async {
    final l = FontLoader(name);
    for (final f in files) {
      l.addFont(rootBundle.load(f));
    }
    await l.load();
  }

  await fam('PlusJakartaSans', [for (final w in [400, 500, 600, 700, 800]) 'assets/fonts/PlusJakartaSans-$w.ttf']);
  await fam('KantumruyPro', [for (final w in [400, 500, 600, 700]) 'assets/fonts/KantumruyPro-$w.ttf']);
  await fam('Roboto', [for (final w in [400, 700]) 'assets/fonts/PlusJakartaSans-$w.ttf']);
  await fam('packages/lucide_icons_flutter/Lucide', ['packages/lucide_icons_flutter/assets/lucide.ttf']);
  // Material icons (back arrows, checkboxes) come with the Flutter SDK
  final exe = Platform.resolvedExecutable; // …/flutter/bin/cache/artifacts/engine/<platform>/flutter_tester
  final cache = exe.contains('/bin/cache/') ? exe.substring(0, exe.indexOf('/bin/cache/') + 11) : '${Platform.environment['FLUTTER_ROOT']}/bin/cache/';
  final mi = File('${cache}artifacts/material_fonts/MaterialIcons-Regular.otf');
  if (mi.existsSync()) {
    final l = FontLoader('MaterialIcons')..addFont(Future.value(ByteData.view(Uint8List.fromList(mi.readAsBytesSync()).buffer)));
    await l.load();
  }
}

// answers the app's API calls from the recorded fixtures (unknown ones: an empty success, and printed)
class FixtureAdapter implements HttpClientAdapter {
  final Map<String, dynamic> fx;
  final misses = <String>{};
  int _sale = 0;
  FixtureAdapter(this.fx);

  @override
  Future<ResponseBody> fetch(RequestOptions o, Stream<Uint8List>? requestStream, Future<void>? cancelFuture) async {
    final path = o.uri.path;
    final full = o.uri.query.isEmpty ? path : '$path?${o.uri.query}';
    Object? r = fx['${o.method} $full'] ?? fx['${o.method} $path'];
    if (o.method == 'POST' && path == '/api/martpos/sales') r = _martSale(o.data);
    if (r == null) {
      misses.add('${o.method} $full');
      r = {'success': true, 'data': <String, dynamic>{}};
    }
    final ok = (r as Map)['success'] != false;
    return ResponseBody.fromString(jsonEncode(r), ok ? 200 : 402, headers: {
      Headers.contentTypeHeader: [Headers.jsonContentType],
    });
  }

  // the server's answer to a sale, made from what the POS sent (the recorded sale is the template)
  Map<String, dynamic> _martSale(Object? sent) {
    final b = sent is Map ? Map<String, dynamic>.from(sent) : <String, dynamic>{};
    final tpl = Map<String, dynamic>.from(fx['POST /api/martpos/sales']['data'] as Map);
    final items = [
      for (final it in (b['items'] as List? ?? const []))
        {...Map<String, dynamic>.from(it as Map), 'unit_en': 'Piece', 'unit_km': 'ដុំ', 'total': ((it['price'] as num) * (it['qty'] as num) * 100).round() / 100},
    ];
    final total = (items.fold<num>(0, (a, x) => a + (x['total'] as num)) * 100).round() / 100;
    final usd = (b['paid_usd'] as num?) ?? 0, khr = (b['paid_khr'] as num?) ?? 0;
    final change = b['method'] == 'cash' ? ((usd + khr / 4100 - total) * 100).round() / 100 : 0;
    _sale++;
    return {
      'success': true,
      'data': {
        ...tpl,
        'no': 'S-${(5 + _sale).toString().padLeft(6, '0')}',
        'items': items,
        'subtotal': total,
        'total': total,
        'method': b['method'] ?? 'cash',
        'paid_usd': usd,
        'paid_khr': khr,
        'change': change,
        'change_khr': ((change * 4100) / 100).round() * 100,
        'at': DateTime.now().toUtc().toIso8601String(),
        '_id': 'sale$_sale',
      },
    };
  }

  @override
  void close({bool force = false}) {}
}

Map<String, dynamic> link(Map<String, dynamic> fx) => switch (_kind) {
  'restaurant' => {
    'kind': 'restaurant',
    'token': 'a' * 64,
    'device': fx['GET /api/pos/bootstrap']['data']['device'],
    'shop': 'Mekong Kitchen',
    'logo': '',
    'demo': true,
    'pin': '1234',
  },
  'mart' => {'kind': 'mart', 'token': 'b' * 64, 'device': {'name': 'Counter 1'}, 'shop': 'Lucky Mini Mart', 'logo': '', 'demo': true, 'pin': '1234'},
  _ => {'kind': 'guest_house', 'token': 'c' * 64, 'device': {'name': 'Front desk'}, 'shop': 'Lotus Guest House', 'logo': '', 'demo': true, 'pin': '1234'},
};

int _n = 0;
// a dish / category in the screenshot language (the menu shows name_km in Khmer)
final _names = <String, String>{};
String nm(String en) => _lang == 'km' ? (_names[en] ?? en) : en;
String tx(String key) => T.of(_lang)(key);
Future<void> shot(WidgetTester t, String name) async {
  // no "Sent" / "Saved" notes on the pictures
  for (final e in find.byType(ScaffoldMessenger).evaluate()) {
    (e as StatefulElement).state is ScaffoldMessengerState ? (e.state as ScaffoldMessengerState).removeCurrentSnackBar() : null;
  }
  await t.pump(const Duration(milliseconds: 400));
  _n++;
  await expectLater(find.byType(MaterialApp).first, matchesGoldenFile('out/$_lang-$_kind${_tablet ? '-tab' : ''}-$_n-$name.png'));
}

Future<void> settle(WidgetTester t, [int ms = 600]) async {
  for (var i = 0; i < 4; i++) {
    await t.pump(Duration(milliseconds: ms ~/ 4));
  }
}

Future<void> tapText(WidgetTester t, String text, {int at = 0}) async {
  final f = find.text(text);
  expect(f, findsWidgets, reason: 'text "$text" not on screen');
  await t.tap(f.at(at), warnIfMissed: false);
  await settle(t);
}

Future<void> tapContaining(WidgetTester t, String text, {int at = 0}) async {
  final f = find.textContaining(text);
  expect(f, findsWidgets, reason: 'text with "$text" not on screen');
  await t.tap(f.at(at), warnIfMissed: false);
  await settle(t);
}

// a chip / row that may be off screen: scroll it into view first
Future<void> tapVisible(WidgetTester t, String text, {int at = 0}) async {
  final f = find.text(text);
  expect(f, findsWidgets, reason: 'text "$text" not found');
  await t.ensureVisible(f.at(at));
  await settle(t, 300);
  await t.tap(f.at(at), warnIfMissed: false);
  await settle(t);
}

// an "Add · $x" button of an item sheet, when one opened
Future<void> tapIfSheet(WidgetTester t) async {
  final f = find.textContaining(RegExp(r'^\+? ?(Add|បន្ថែម)'));
  if (f.evaluate().isNotEmpty) {
    await t.tap(f.last, warnIfMissed: false);
    await settle(t);
  }
}

// the bill (a tab on a phone; beside the menu on a tablet)
Future<void> orderTab(WidgetTester t) async {
  final f = find.textContaining('${tx('rpos.order')} ·');
  if (f.evaluate().isEmpty) return;
  await t.tap(f.first, warnIfMissed: false);
  await settle(t);
}

Future<void> back(WidgetTester t) async {
  final f = find.byIcon(LucideIcons.arrowLeft);
  if (f.evaluate().isEmpty) return; // (already back on the tables)
  await t.tap(f.first, warnIfMissed: false);
  await settle(t, 900);
}

// one table's bill: open it, add dishes (name → how many), send to the kitchen, back to the tables
Future<void> table(WidgetTester t, String name, Map<String, int> dishes, {bool send = true}) async {
  await tapText(t, name);
  await settle(t, 600);
  for (final e in {for (final d in dishes.entries) nm(d.key): d.value}.entries) {
    // find it with the menu search (the grid only builds what is on screen)
    await t.enterText(find.byType(TextField).first, e.key);
    await settle(t, 400);
    for (var i = 0; i < e.value; i++) {
      await t.tap(find.text(e.key).last, warnIfMissed: false);
      await settle(t);
      await tapIfSheet(t);
    }
    await t.enterText(find.byType(TextField).first, '');
    await settle(t, 300);
  }
  await orderTab(t);
  if (send) await tapText(t, tx('rpos.send'));
  await settle(t, 900);
  await t.pump(const Duration(seconds: 10)); // the "Sent" note goes away
  await back(t);
}

Future<void> typePin(WidgetTester t, String pin) async {
  for (final d in pin.split('')) {
    await t.tap(find.text(d).last, warnIfMissed: false);
    await t.pump(const Duration(milliseconds: 60));
  }
  await settle(t, 900);
}

void main() {
  testWidgets('store screenshots: $_kind $_lang', (t) async {
    if (!_run) return;
    final fx = jsonDecode(File('test/store/fixtures.json').readAsStringSync().replaceAll('Google Play review', 'Demo Manager')) as Map<String, dynamic>;
    fx['GET /api/pos/bootstrap']['data']['device']['name'] = 'Counter 1';
    final boot = fx['GET /api/pos/bootstrap']['data'] as Map<String, dynamic>;
    for (final x in [...boot['items'] as List, ...boot['categories'] as List]) {
      _names['${x['name_en']}'] = '${x['name_km']}';
    }
    final adapter = FixtureAdapter(fx);
    testAdapter = adapter;
    SharedPreferences.setMockInitialValues({'pos.lang': _lang, 'pos.onboarded': true, 'pos.theme': 'light', 'pos.link': jsonEncode(link(fx))});
    await loadFonts();
    await t.binding.setSurfaceSize(_size);
    t.view.physicalSize = _size * _ratio;
    t.view.devicePixelRatio = _ratio;
    await t.runAsync(() async => Future.wait([AppState.init(), T.load()]));
    await t.pumpWidget(AppScope(child: const PosApp()));
    await settle(t, 1200);

    switch (_kind) {
      case 'restaurant':
        await shot(t, 'pin');
        await typePin(t, '1234');
        await typePin(t, '50');
        await tapText(t, tx('rpos.start'));
        await settle(t, 1500);
        await shot(t, 'tables');
        await tapText(t, 'T2');
        await settle(t, 1000);
        await shot(t, 'menu');
        await tapText(t, nm('Lok lak beef'));
        await tapContaining(t, 'Fried egg');
        await shot(t, 'item-sheet');
        await tapIfSheet(t);
        await tapVisible(t, nm('Soups & Curries'));
        await tapText(t, nm('Fish amok'));
        await tapIfSheet(t);
        await tapVisible(t, nm('Drinks'));
        await tapText(t, nm('Iced coffee with milk'));
        await tapContaining(t, 'Large');
        await tapIfSheet(t);
        await tapText(t, nm('Fresh coconut'));
        await tapIfSheet(t);
        await tapText(t, nm('Fresh coconut'));
        await tapIfSheet(t);
        await shot(t, 'menu-added');
        await orderTab(t);
        await shot(t, 'bill');
        await tapText(t, tx('rpos.send'));
        await settle(t, 900);
        await t.pump(const Duration(seconds: 6));
        await back(t);
        await table(t, 'T4', {'Chicken fried rice': 2, 'Lemon iced tea': 2});
        await table(t, 'T5', {'Phnom Penh noodle soup': 3, nm('Iced coffee with milk'): 3, 'Mango sticky rice': 1});
        await table(t, 'T7', {'Samlor korko': 1, 'Khmer noodles': 2, 'Water': 2});
        await t.pump(const Duration(seconds: 5)); // the last bill is sent in the background
        await shot(t, 'tables-busy');
        await tapText(t, 'T2');
        await settle(t, 600);
        await orderTab(t);
        await tapContaining(t, '${tx('rpos.pay')} ');
        await tapText(t, '+\$20');
        await shot(t, 'pay');
      case 'mart':
        await settle(t, 1200);
        await typePin(t, '1234');
        await settle(t, 1200);
        await shot(t, 'products');
        for (final p in ['Drinking water 500 ml', 'Drinking water 500 ml', 'Potato chips', 'Chocolate bar', 'Iced coffee can']) {
          await t.enterText(find.byType(TextField).first, p);
          await settle(t, 400);
          await t.tap(find.text(p).last, warnIfMissed: false);
          await settle(t, 400);
        }
        await t.enterText(find.byType(TextField).first, '');
        await settle(t, 600);
        await shot(t, 'with-cart');
        if (!_tablet) {
          await tapText(t, '\$3.60');
          await shot(t, 'cart');
        }
        await t.tap(find.text(tx('mpos.pay')).last, warnIfMissed: false);
        await settle(t, 900);
        await tapText(t, '+\$5');
        await shot(t, 'pay');
        await tapVisible(t, tx('mpos.confirm'));
        await settle(t, 1200);
        await shot(t, 'paid');
        await t.pump(const Duration(seconds: 6));
        if (find.textContaining(tx('mpos.newSale')).evaluate().isNotEmpty) await tapContaining(t, tx('mpos.newSale'));
        await back(t);
        await settle(t, 900);
        await t.tap(find.text(tx('mart.tabs.sales')).last, warnIfMissed: false);
        await settle(t, 1500);
        await shot(t, 'sales');
      default:
        await settle(t, 1200);
        await shot(t, 'pin');
        await typePin(t, '1234');
        await settle(t, 1500);
        await shot(t, 'today');
        await tapVisible(t, 'Emma Wilson');
        await settle(t, 1200);
        await shot(t, 'stay');
        await t.tapAt(const Offset(20, 20)); // close the sheet
        await settle(t, 900);
        await t.tap(find.text(tx('gh.tabs.calendar')).last, warnIfMissed: false);
        await settle(t, 1500);
        await shot(t, 'calendar');
    }

    // ignore: avoid_print
    if (adapter.misses.isNotEmpty) print('not in fixtures: ${adapter.misses.join(', ')}');
    RestPos.i.stop();
    MartPos.i.stop();
    GhPos.i.stop();
    await t.pumpWidget(const SizedBox());
    await t.pump(const Duration(seconds: 30));
  });
}
