// Bizi in the POS (v3.0.0): the cashier's questions find themselves (EN + KM, Khmer written together, typos), the
// bubble opens the panel, a question opens its steps, the quick dark mode / language, and the red dot when Telegram
// orders wait.   pictures: flutter test test/pos_bizi_test.dart --update-goldens --dart-define=TS_SHOTS=true
import 'package:bizhub_pos/core/app_state.dart';
import 'package:bizhub_pos/core/i18n.dart';
import 'package:bizhub_pos/core/theme.dart';
import 'package:bizhub_pos/features/bizi/bizi_face.dart';
import 'package:bizhub_pos/features/bizi/pos_bizi.dart';
import 'package:bizhub_pos/features/bizi/pos_bizi_find.dart';
import 'package:bizhub_pos/features/bizi/pos_bizi_help.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'store/store_shots_test.dart' show loadFonts;

const _shots = bool.fromEnvironment('TS_SHOTS');

Widget _app(String kind) => AppScope(
  child: Builder(
    builder: (context) {
      final a = AppScope.of(context);
      return MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: buildTheme(dark: false, khmer: a.lang == 'km'),
        darkTheme: buildTheme(dark: true, khmer: a.lang == 'km'),
        themeMode: a.themeMode,
        home: PosBizi(
          kind: kind,
          child: const Scaffold(body: Center(child: Text('THE POS'))),
        ),
      );
    },
  ),
);

Future<void> _settle(WidgetTester t) async {
  for (var i = 0; i < 6; i++) {
    await t.pump(const Duration(milliseconds: 100));
  }
}

Future<void> _shot(WidgetTester t, String name) async {
  if (_shots) await expectLater(find.byType(MaterialApp), matchesGoldenFile('shots/bizi-$name.png'));
}

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});
    await Future.wait([AppState.init(), T.load()]);
    await loadFonts();
    BiziFace.animate = false;
  });

  const kinds = ['restaurant', 'mart', 'guest_house', 'tg_store', 'stamp_card', 'event'];

  test('every question finds itself in its POS (EN + KM), same number of steps', () {
    for (final kind in kinds) {
      final list = posHelpFor(kind);
      expect(list.where((a) => a['popular'] == true), isNotEmpty, reason: '$kind has popular questions');
      for (final a in list) {
        final h = HelpHit(a, 0);
        expect(findHelp(h.q('en'), list).first.id, h.id, reason: '$kind: ${h.q('en')}');
        expect(findHelp(h.q('km'), list).first.id, h.id, reason: '$kind: ${h.q('km')}');
        expect(h.steps('km').length, h.steps('en').length, reason: h.id);
      }
    }
  });

  test('what cashiers type', () {
    String? top(String q, String kind) => findHelp(q, posHelpFor(kind)).firstOrNull?.id;
    expect(top("printer doesn't print", 'restaurant'), 'printer');
    expect(top('prnter', 'mart'), 'printer');
    expect(top('ម៉ាស៊ីនព្រីន', 'guest_house'), 'printer');
    expect(top('close shift', 'restaurant'), 'r_shift');
    expect(top('បិទវេន', 'mart'), 'm_shift');
    expect(top('how do I cancel an item', 'restaurant'), 'r_void');
    expect(top('void a sale', 'mart'), 'm_void');
    expect(top('no internet', 'mart'), 'r_offline');
    expect(top('accept order', 'tg_store'), 'ts_orders');
    expect(top('sound', 'tg_store'), 'ts_sound');
    expect(top('check out guest', 'guest_house'), 'gh_checkin');
    expect(top('give stamp', 'stamp_card'), 'sc_stamp');
    expect(top('red', 'event'), 'ev_scan');
    expect(top('unlink', 'event'), 'unlink');
    expect(findHelp('coffee', posHelpFor('restaurant')), isEmpty);
    expect(posHelpFor('tg_store').any((a) => a['id'] == 'r_void'), isFalse, reason: 'only the questions of this POS');
  });

  testWidgets('restaurant: the bubble, popular questions, a question opens its steps, quick dark mode', (t) async {
    await t.binding.setSurfaceSize(const Size(900, 700));
    t.view.devicePixelRatio = 2;
    t.view.physicalSize = const Size(1800, 1400);
    addTearDown(t.view.reset);
    AppState.i.setLang('en');
    AppState.i.setTheme('light');
    await t.pumpWidget(_app('restaurant'));
    await _settle(t);
    expect(find.byKey(const ValueKey('pos-bizi')), findsOneWidget);
    expect(find.byKey(const ValueKey('pos-bizi-dot')), findsNothing);
    await t.tap(find.byKey(const ValueKey('pos-bizi')));
    await _settle(t);
    expect(find.text('How do I open or close a shift?'), findsOneWidget);
    expect(find.text("The printer doesn’t print — what do I do?"), findsOneWidget);
    await _shot(t, 'pos-open');
    await t.enterText(find.byKey(const ValueKey('pos-bizi-input')), 'how do I cancel an item?');
    await _settle(t);
    expect(find.byKey(const ValueKey('pos-bizi-steps')), findsOneWidget); // a question opens by itself
    expect(find.textContaining('Cancel order'), findsOneWidget);
    await _shot(t, 'pos-steps');
    await t.enterText(find.byKey(const ValueKey('pos-bizi-input')), 'dark');
    await _settle(t);
    await t.tap(find.text('Dark mode'));
    await _settle(t);
    expect(AppState.i.theme, 'dark');
    await t.enterText(find.byKey(const ValueKey('pos-bizi-input')), 'how do I fly?');
    await _settle(t);
    expect(find.byKey(const ValueKey('pos-bizi-none')), findsOneWidget);
    await t.tap(find.byKey(const ValueKey('pos-bizi-close')));
    await _settle(t);
    expect(find.byKey(const ValueKey('pos-bizi-panel')), findsNothing);
    AppState.i.setTheme('light');
  });

  testWidgets('Telegram Store (Khmer): orders waiting → red dot + Bizi says; drag stays', (t) async {
    await t.binding.setSurfaceSize(const Size(400, 860));
    t.view.devicePixelRatio = 2;
    t.view.physicalSize = const Size(800, 1720);
    addTearDown(t.view.reset);
    AppState.i.setLang('km');
    await t.pumpWidget(_app('tg_store'));
    await _settle(t);
    posBiziWaiting.value = PosWaiting('tg_new', 2, oldest: DateTime.now().subtract(const Duration(minutes: 12)));
    await _settle(t);
    expect(find.descendant(of: find.byKey(const ValueKey('pos-bizi-dot')), matching: find.text('2')), findsOneWidget);
    final from = t.getTopLeft(find.byKey(const ValueKey('pos-bizi')));
    await t.drag(find.byKey(const ValueKey('pos-bizi')), const Offset(200, -300));
    await _settle(t);
    final to = t.getTopLeft(find.byKey(const ValueKey('pos-bizi')));
    expect(to.dx, greaterThan(from.dx + 150));
    expect(AppState.i.pref('pos.bizi_pos'), isNotNull);
    await t.tap(find.byKey(const ValueKey('pos-bizi')));
    await _settle(t);
    expect(find.text('ការកម្ម៉ង់ Telegram ថ្មី 2 កំពុងរង់ចាំ'), findsOneWidget);
    expect(find.textContaining('12 នាទី'), findsOneWidget);
    expect(find.text('តើធ្វើយ៉ាងណាជាមួយការកម្ម៉ង់ថ្មី?'), findsOneWidget);
    await _shot(t, 'pos-tg-km');
    posBiziWaiting.value = null;
    AppState.i.setLang('en');
  });
}
