// The cart divider (v3.1.0): drag it wider / narrower, never too small or too big, the menu (Small / Medium / Large,
// left / right, back to normal), double-tap = normal, kept for each cashier on this device.
//   pictures: flutter test test/pos_split_test.dart --update-goldens --dart-define=TS_SHOTS=true
import 'package:bizhub_pos/core/app_state.dart';
import 'package:bizhub_pos/core/i18n.dart';
import 'package:bizhub_pos/core/pos_split.dart';
import 'package:bizhub_pos/core/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'store/store_shots_test.dart' show loadFonts;

const _shots = bool.fromEnvironment('TS_SHOTS');

Widget _app({String who = 's1', String name = 'Dara'}) => AppScope(
  child: Builder(
    builder: (context) {
      final a = AppScope.of(context);
      return MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: buildTheme(dark: false, khmer: a.lang == 'km'),
        home: Scaffold(
          body: PosSplit(
            scope: 'mart',
            who: who,
            whoName: name,
            thing: 'cart',
            main: Container(key: const ValueKey('main'), color: const Color(0xFFEFF3F8), child: const Center(child: Text('PRODUCTS'))),
            panel: (left) => Container(
              margin: left ? const EdgeInsets.fromLTRB(12, 0, 0, 12) : const EdgeInsets.fromLTRB(0, 0, 12, 12),
              color: Colors.white,
              child: Center(child: Text(left ? 'CART · LEFT' : 'CART · RIGHT')),
            ),
          ),
        ),
      );
    },
  ),
);

double _cartW(WidgetTester t) => t.getSize(find.byKey(const ValueKey('pos-split-cart'))).width;
bool _cartLeft(WidgetTester t) => t.getTopLeft(find.byKey(const ValueKey('pos-split-cart'))).dx < t.getTopLeft(find.byKey(const ValueKey('main'))).dx;

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});
    await Future.wait([AppState.init(), T.load()]);
    await loadFonts();
    AppState.i.setLang('en');
  });

  Future<void> screen(WidgetTester t, double w, double h) async {
    await t.binding.setSurfaceSize(Size(w, h));
    t.view.devicePixelRatio = 1;
    t.view.physicalSize = Size(w, h);
    addTearDown(t.view.reset);
  }

  test('limits: the cart never under 300, never over 60% — the products keep their room', () {
    expect(PosSplit.maxFor(1400), 840);
    expect(PosSplit.maxFor(900), closeTo(522, .1)); // 900 − 360 − 18
    expect(PosSplit.maxFor(600), 300);
  });

  testWidgets('drag wider / narrower, limits, kept for this cashier; double-tap = normal', (t) async {
    await screen(t, 1400, 860);
    await t.pumpWidget(_app());
    await t.pumpAndSettle();
    expect(_cartW(t), 400); // normal
    expect(_cartLeft(t), isFalse);
    await t.drag(find.byKey(const ValueKey('pos-split-handle')), const Offset(-150, 0)); // the cart is on the right: drag left = wider
    await t.pumpAndSettle();
    expect(_cartW(t), closeTo(550, 1));
    expect(AppState.i.pref(PosSplit.keyOf('mart', 's1')), '550|right');
    await t.drag(find.byKey(const ValueKey('pos-split-handle')), const Offset(-2000, 0));
    await t.pumpAndSettle();
    expect(_cartW(t), 840, reason: '60% of 1400');
    await t.drag(find.byKey(const ValueKey('pos-split-handle')), const Offset(2000, 0));
    await t.pumpAndSettle();
    expect(_cartW(t), 300, reason: 'never smaller than the Pay button needs');
    // another cashier: their own (normal) size
    await t.pumpWidget(_app(who: 's2', name: 'Sophea'));
    await t.pumpAndSettle();
    expect(_cartW(t), 400);
    await t.pumpWidget(_app());
    await t.pumpAndSettle();
    expect(_cartW(t), 300, reason: "Dara's size is back for Dara");
    // double-tap the handle: back to normal
    await t.tap(find.byKey(const ValueKey('pos-split-handle')));
    await t.pump(const Duration(milliseconds: 60));
    await t.tap(find.byKey(const ValueKey('pos-split-handle')));
    await t.pumpAndSettle();
    expect(_cartW(t), 400);
  });

  testWidgets('tap the handle: Large, put it on the left (then drag right = wider), back to normal', (t) async {
    await screen(t, 1280, 800);
    await t.pumpWidget(_app(who: 's3', name: 'Vanna'));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const ValueKey('pos-split-handle')));
    await t.pumpAndSettle(const Duration(milliseconds: 400));
    expect(find.text('SIZE OF THE CART'), findsOneWidget);
    expect(find.text('Only for Vanna, on this device.'), findsOneWidget);
    if (_shots) await expectLater(find.byType(MaterialApp), matchesGoldenFile('shots/split-menu.png'));
    await t.tap(find.text('Large'));
    await t.pumpAndSettle();
    expect(_cartW(t), 520);
    await t.tap(find.byKey(const ValueKey('pos-split-handle')));
    await t.pumpAndSettle(const Duration(milliseconds: 400));
    await t.tap(find.text('Put the cart on the left'));
    await t.pumpAndSettle();
    expect(_cartLeft(t), isTrue);
    expect(find.text('CART · LEFT'), findsOneWidget);
    expect(AppState.i.pref(PosSplit.keyOf('mart', 's3')), '520|left');
    expect(posCartLeft.value, isTrue, reason: "Bizi's bubble starts on the other side");
    await t.drag(find.byKey(const ValueKey('pos-split-handle')), const Offset(60, 0)); // on the left: drag right = wider
    await t.pumpAndSettle();
    expect(_cartW(t), closeTo(580, 1));
    if (_shots) await expectLater(find.byType(MaterialApp), matchesGoldenFile('shots/split-left.png'));
    await t.tap(find.byKey(const ValueKey('pos-split-handle')));
    await t.pumpAndSettle(const Duration(milliseconds: 400));
    expect(find.text('Put the cart on the right'), findsOneWidget);
    await t.tap(find.text('Back to normal'));
    await t.pumpAndSettle();
    expect((_cartW(t), _cartLeft(t)), (400, false));
    expect(posCartLeft.value, isFalse);
  });

  testWidgets('a smaller screen: a big saved size fits in (never more than the screen allows)', (t) async {
    AppState.i.setPref(PosSplit.keyOf('mart', 's4'), '800|right');
    await screen(t, 960, 700);
    await t.pumpWidget(_app(who: 's4'));
    await t.pumpAndSettle();
    expect(_cartW(t), closeTo(576, .5)); // 60% of 960
    expect(t.getSize(find.byKey(const ValueKey('main'))).width, greaterThanOrEqualTo(360));
  });

  testWidgets('Khmer', (t) async {
    AppState.i.setLang('km');
    await screen(t, 1280, 800);
    await t.pumpWidget(_app(who: 's5', name: 'ដារ៉ា'));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const ValueKey('pos-split-handle')));
    await t.pumpAndSettle(const Duration(milliseconds: 400));
    expect(find.text('ទំហំកន្ត្រក'), findsOneWidget);
    expect(find.text('ដាក់កន្ត្រកនៅខាងឆ្វេង'), findsOneWidget);
    expect(find.text('សម្រាប់តែ ដារ៉ា លើឧបករណ៍នេះ។'), findsOneWidget);
    AppState.i.setLang('en');
  });
}
