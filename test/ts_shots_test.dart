// Telegram Store staff screen (v2.0) on a fake API answering with real answers recorded from the API on a throwaway
// database (bizhub-api scripts/demo-pos.js --test --capture=…, the tspos part → test/fixtures/tgstore.json).
// Pictures, not checks: test/shots/ts-*.png (not in git)
//   flutter test test/ts_shots_test.dart --update-goldens --dart-define=TS_SHOTS=true
import 'dart:convert';
import 'dart:io';

import 'package:bizhub_pos/core/app_state.dart';
import 'package:bizhub_pos/core/i18n.dart';
import 'package:bizhub_pos/core/theme.dart';
import 'package:bizhub_pos/features/start/choose_page.dart';
import 'package:bizhub_pos/features/start/link_page.dart';
import 'package:bizhub_pos/features/tgstore/ts_api.dart';
import 'package:bizhub_pos/features/tgstore/ts_card.dart';
import 'package:bizhub_pos/features/tgstore/ts_print.dart';
import 'package:bizhub_pos/features/tgstore/ts_root.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'store/store_shots_test.dart' show loadFonts;

final _fx = jsonDecode(File('test/fixtures/tgstore.json').readAsStringSync()) as Map<String, dynamic>;
final calls = <String>[];

Future<Json> _fake(String method, String path, Object? body) async {
  calls.add('$method $path ${body == null ? '' : jsonEncode(body)}');
  final r = _fx['$method /api/tspos$path'];
  if (r != null) return Map<String, dynamic>.from(r as Map);
  // a change: the order / product back with the change made
  final m = RegExp(r'^/orders/(\w+)/(status|paid)$').firstMatch(path);
  if (m != null) {
    final open = objs(_fx['GET /api/tspos/orders?view=open']['data']);
    final o = open.firstWhere((x) => x['_id'] == m[1], orElse: () => open.first);
    final b = obj(body);
    return {
      'success': true,
      'data': m[2] == 'paid'
          ? {
              ...o,
              'pay': {...obj(o['pay']), 'status': 'paid'},
            }
          : {...o, 'status': b['status'], 'eta_min': b['eta'] ?? 0},
    };
  }
  return {'success': true, 'data': <String, dynamic>{}};
}

Widget app(Widget home) => AppScope(
  child: Builder(
    builder: (context) {
      final a = AppScope.of(context);
      return MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: buildTheme(dark: false, khmer: a.lang == 'km'),
        home: home,
      );
    },
  ),
);

Future<void> settle(WidgetTester t, [int ms = 600]) async {
  for (var i = 0; i < 6; i++) {
    await t.pump(Duration(milliseconds: ms ~/ 6));
  }
}

// the pictures only when asked (the clock on the orders changes every run); the taps and checks always run
const _shots = bool.fromEnvironment('TS_SHOTS');
Future<void> shot(WidgetTester t, String name) async {
  if (_shots) await expectLater(find.byType(MaterialApp), matchesGoldenFile('shots/$name.png'));
}

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});
    await Future.wait([AppState.init(), T.load()]);
    await loadFonts();
    await TsStore.init();
    await TsPrint.load();
    TsPos.fake = _fake;
    TsSound.off = true;
  });

  Future<void> size(WidgetTester t, {double w = 400, double h = 860}) async {
    await t.binding.setSurfaceSize(Size(w, h));
    t.view.devicePixelRatio = 2;
    t.view.physicalSize = Size(w * 2, h * 2);
    addTearDown(t.view.reset);
  }

  void linked({String lang = 'en', bool session = true}) {
    AppState.i.setLang(lang);
    AppState.i.linked({
      'kind': 'tg_store',
      'token': 'd' * 64,
      'device': {'name': 'Counter'},
      'shop': 'Mekong Coffee Shop',
      'logo': '',
      'demo': true,
      'pin': '1234',
    });
    TsStore.set('session', session ? 'test-session' : null);
  }

  Future<void> done(WidgetTester t) async {
    await t.pumpWidget(const SizedBox()); // stop the 5 s refresh
    await t.pump(const Duration(seconds: 1));
  }

  testWidgets('choose: Telegram Store is a POS', (t) async {
    await size(t, h: 1100);
    AppState.i.setLang('en');
    await t.pumpWidget(app(const ChoosePage()));
    await settle(t);
    await shot(t, 'ts-choose');
  });

  testWidgets('link with the 6-digit code', (t) async {
    await size(t, h: 1000);
    AppState.i.setLang('en');
    await t.pumpWidget(app(const LinkPage(kind: 'tg_store')));
    await settle(t);
    await shot(t, 'ts-link');
  });

  testWidgets('staff PIN', (t) async {
    await size(t);
    linked(session: false);
    await t.pumpWidget(app(const TsStaffRoot()));
    await settle(t);
    await shot(t, 'ts-pin');
    for (final k in ['1', '2', '3', '4']) {
      await t.tap(find.text(k).last);
      await t.pump(const Duration(milliseconds: 50));
    }
    await settle(t);
    expect(calls.any((c) => c.startsWith('POST /login {"pin":"1234"}')), true);
    expect(find.text('Taking orders'), findsOneWidget);
    await done(t);
  });

  testWidgets('orders: new (phone)', (t) async {
    await size(t, h: 1400);
    linked();
    await t.pumpWidget(app(const TsStaffRoot()));
    await settle(t);
    await shot(t, 'ts-new');
    // accept with 15 min
    calls.clear();
    await t.tap(find.byKey(const ValueKey('ts-o4-eta15')));
    await settle(t);
    expect(calls.first, contains('/status {"status":"accepted","eta":15}'));
    await done(t);
  });

  for (final (col, name) in [('making', 'ts-making'), ('ready', 'ts-ready')]) {
    testWidgets('orders: $col (phone)', (t) async {
      await size(t, h: 1000);
      linked();
      await t.pumpWidget(app(const TsStaffRoot()));
      await settle(t);
      await t.tap(find.byKey(ValueKey('ts-colpick-$col')));
      await settle(t);
      await shot(t, name);
      await done(t);
    });
  }

  testWidgets('orders: tablet, 3 columns', (t) async {
    await size(t, w: 1280, h: 800);
    linked();
    await t.pumpWidget(app(const TsStaffRoot()));
    await settle(t);
    await shot(t, 'ts-tablet');
    await done(t);
  });

  testWidgets('orders in Khmer', (t) async {
    await size(t, h: 1400);
    linked(lang: 'km');
    await t.pumpWidget(app(const TsStaffRoot()));
    await settle(t);
    await shot(t, 'ts-new-km');
    await done(t);
    AppState.i.setLang('en');
  });

  for (final (tab, label, h) in [('done', 'Done today', 1000.0), ('products', 'Products', 1000.0), ('today', 'Today', 860.0)]) {
    testWidgets('tab $tab', (t) async {
      await size(t, h: h);
      linked();
      await t.pumpWidget(app(const TsStaffRoot()));
      await settle(t);
      await t.tap(find.text(label).last);
      await settle(t);
      await shot(t, 'ts-$tab');
      if (tab == 'products') {
        calls.clear();
        await t.tap(find.byKey(const ValueKey('ts-sold-Iced latte')));
        await settle(t);
        expect(calls.first, contains('PUT /products/'));
        expect(calls.first, contains('"sold_out":true'));
      }
      await done(t);
    });
  }

  testWidgets('the paper ticket', (t) async {
    await size(t, w: 320, h: 560);
    AppState.i.setLang('en');
    final o = objs(_fx['GET /api/tspos/orders?view=open']['data']).first;
    await t.pumpWidget(
      app(
        Scaffold(
          backgroundColor: Colors.grey.shade300,
          body: Center(
            child: SizedBox(
              width: 300,
              child: TsTicket(o: o, shop: 'Mekong Coffee Shop'),
            ),
          ),
        ),
      ),
    );
    await settle(t);
    await shot(t, 'ts-ticket');
  });
}
