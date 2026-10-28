// System activity in BizHub POS: the same versions as the website (lib/features/updates/changelog.dart is made from
// the web's changelog.js by tool/gen_changelog.js), reachable from the first screen and every POS menu.
//   pictures: flutter test test/updates_test.dart --update-goldens --dart-define=TS_SHOTS=true → test/shots/up-*.png
import 'dart:io';

import 'package:bizhub_pos/core/app_state.dart';
import 'package:bizhub_pos/core/i18n.dart';
import 'package:bizhub_pos/core/theme.dart';
import 'package:bizhub_pos/features/start/choose_page.dart';
import 'package:bizhub_pos/features/updates/changelog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'store/store_shots_test.dart' show loadFonts;

const _shots = bool.fromEnvironment('TS_SHOTS');

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

Future<void> settle(WidgetTester t) async {
  for (var i = 0; i < 6; i++) {
    await t.pump(const Duration(milliseconds: 100));
  }
}

Future<void> shot(WidgetTester t, String name) async {
  if (_shots) await expectLater(find.byType(MaterialApp), matchesGoldenFile('shots/$name.png'));
}

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});
    await Future.wait([AppState.init(), T.load()]);
    await loadFonts();
  });

  test('the same list as the website, newest first', () {
    final web = File('../bizhub/src/dashboard/client/updates/changelog.js');
    if (!web.existsSync()) return; // the web code is not next to this app here
    final versions = RegExp(r'version: "([\d.]+)"').allMatches(web.readAsStringSync()).map((m) => m[1]).toList();
    expect(changelog.map((r) => r.version).toList(), versions, reason: 'run: node tool/gen_changelog.js');
    expect(bizhubVersion, versions.first);
  });

  for (final lang in ['en', 'km']) {
    testWidgets('first screen → System activity ($lang)', (t) async {
      await t.binding.setSurfaceSize(const Size(400, 1300));
      t.view.devicePixelRatio = 2;
      t.view.physicalSize = const Size(800, 2600);
      addTearDown(t.view.reset);
      AppState.i.setLang(lang);
      await t.pumpWidget(app(const ChoosePage()));
      await settle(t);
      final link = find.byKey(const ValueKey('choose-updates'));
      await t.ensureVisible(link);
      await settle(t);
      expect(find.textContaining('v$bizhubVersion'), findsOneWidget);
      // search: one word finds the POS, in either language
      await t.enterText(find.byKey(const ValueKey('choose-search')), lang == 'km' ? 'telegram' : 'ហាង Telegram');
      await settle(t);
      expect(find.text(lang == 'km' ? 'ហាង Telegram' : 'Telegram Store'), findsOneWidget);
      expect(find.text(lang == 'km' ? 'ភោជនីយដ្ឋាន' : 'Restaurant'), findsNothing);
      if (lang == 'en') await shot(t, 'up-choose-search');
      await t.enterText(find.byKey(const ValueKey('choose-search')), 'hotel');
      await settle(t);
      expect(find.text(lang == 'km' ? 'ផ្ទះសំណាក់' : 'Guest House'), findsOneWidget);
      await t.enterText(find.byKey(const ValueKey('choose-search')), 'zzzz');
      await settle(t);
      expect(find.textContaining('zzzz'), findsWidgets);
      await t.enterText(find.byKey(const ValueKey('choose-search')), '');
      await settle(t);
      if (lang == 'en') await shot(t, 'up-choose');
      await t.tap(link);
      await settle(t);
      expect(find.byKey(ValueKey('up-v-$bizhubVersion')), findsOneWidget);
      // the newest version's title is at the top (the older ones further down)
      expect(find.text(lang == 'km' ? changelog.first.titleKm : changelog.first.titleEn), findsOneWidget);
      await shot(t, 'up-page-$lang');
    });
  }
}
