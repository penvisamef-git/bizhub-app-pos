// The Mac / Windows-only parts (keyboard keys, key hints, printers installed on the computer, the typed scan box,
// the customer screen switch) — and that a phone (Android / iPhone) gets none of them.
import 'package:bizhub_pos/core/app_state.dart';
import 'package:bizhub_pos/core/customer_display.dart';
import 'package:bizhub_pos/core/desktop.dart';
import 'package:bizhub_pos/core/i18n.dart';
import 'package:bizhub_pos/core/local_prefs.dart';
import 'package:bizhub_pos/core/printing/printer_settings.dart';
import 'package:bizhub_pos/core/printing/printing.dart';
import 'package:bizhub_pos/core/theme.dart';
import 'package:bizhub_pos/widgets/qr_scan.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

final desktops = TargetPlatformVariant({TargetPlatform.macOS, TargetPlatform.windows});
final phones = TargetPlatformVariant({TargetPlatform.android, TargetPlatform.iOS});

Widget app(Widget home) => AppScope(
  child: MaterialApp(theme: buildTheme(dark: false, khmer: false), home: home),
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  // once, outside the widget tests: the store is opened one time per app, and a widget test's fake clock
  // would never deliver a store opened inside an earlier test
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({'pos.lang': 'en'});
    await LocalPrefs.getInstance();
    await AppState.init();
    await T.load();
  });

  group('keyboard keys', () {
    Widget screen(void Function() pay) => app(
      Scaffold(
        body: DesktopKeys(
          keys: {LogicalKeyboardKey.f12: pay, LogicalKeyboardKey.f2: null},
          child: const Column(
            children: [
              Text('cart'),
              KeyHints([('F12', 'Pay')]),
            ],
          ),
        ),
      ),
    );

    testWidgets('Mac / Windows: F12 pays, the hint line shows', (t) async {
      var paid = 0;
      await t.pumpWidget(screen(() => paid++));
      await t.pump();
      await t.sendKeyEvent(LogicalKeyboardKey.f12);
      await t.sendKeyEvent(LogicalKeyboardKey.f2); // no action → nothing happens
      expect(paid, 1);
      expect(find.text('F12'), findsOneWidget);
    }, variant: desktops);

    testWidgets('phones: no keys, no hint line', (t) async {
      var paid = 0;
      await t.pumpWidget(screen(() => paid++));
      await t.pump();
      await t.sendKeyEvent(LogicalKeyboardKey.f12);
      expect(paid, 0);
      expect(find.byType(CallbackShortcuts), findsNothing);
      expect(find.text('F12'), findsNothing);
      expect(find.text('cart'), findsOneWidget);
    }, variant: phones);
  });

  group('receipt printer', () {
    // a tall window so the whole list is built; the page's older ListTile-in-a-coloured-box warning (newer
    // Flutter, debug only, also on phones) is not what these tests check
    Future<void> tall(WidgetTester t) async {
      t.view.physicalSize = const Size(1280, 2600);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);
      final old = FlutterError.onError;
      FlutterError.onError = (d) {
        if (!d.exceptionAsString().contains('ListTile background color')) old?.call(d);
      };
      addTearDown(() => FlutterError.onError = old);
    }

    Widget page() => app(PrinterSettingsPage(conf: const PrinterConf(), licensed: true, lockedText: '', onChanged: (_) {}, testDoc: (_) => const SizedBox()));

    testWidgets('Mac / Windows: "printer on this computer" + the customer screen switch', (t) async {
      await tall(t);
      await t.pumpWidget(page());
      await t.pumpAndSettle();
      expect(find.text(AppState.i.t('rp.installed')), findsOneWidget);
      debugPrint('DBG sw=${find.byType(DesktopCustomerScreenSwitch).evaluate().length} on=${await t.runAsync(CustomerDisplay.desktopOn)}');
      await t.pump(const Duration(milliseconds: 50));
      debugPrint('DBG2 tiles=${find.byType(SwitchListTile).evaluate().length} texts=${find.textContaining('Customer').evaluate().length}');
      expect(find.text(AppState.i.t('cd.desktop')), findsOneWidget);
    }, variant: desktops);

    testWidgets('phones: same page as before', (t) async {
      await tall(t);
      await t.pumpWidget(page());
      await t.pumpAndSettle();
      expect(find.text(AppState.i.t('rp.installed')), findsNothing);
      expect(find.text(AppState.i.t('cd.desktop')), findsNothing);
      expect(find.text(AppState.i.t('rp.bluetooth')), findsOneWidget);
    }, variant: phones);
  });

  testWidgets('the customer screen switch: off → the second monitor is not used', (t) async {
    final calls = <String>[];
    t.binding.defaultBinaryMessenger.setMockMethodCallHandler(const MethodChannel('bizhub/display'), (c) async {
      calls.add(c.method);
      return c.method == 'available' ? true : null;
    });
    addTearDown(() => t.binding.defaultBinaryMessenger.setMockMethodCallHandler(const MethodChannel('bizhub/display'), null));

    await t.runAsync(() async {
      // (real time: the test store's writes don't finish inside the widget test's fake clock)
      expect(await CustomerDisplay.desktopOn(), isTrue, reason: 'on until switched off');
      expect(await CustomerDisplay.available(fresh: true), isTrue);
      await CustomerDisplay.setDesktopOn(false);
      expect(calls, contains('hide'), reason: 'switching off closes the customer window');
      calls.clear();
      expect(await CustomerDisplay.available(fresh: true), isFalse);
      expect(calls, isNot(contains('available')), reason: 'not even asked');
      await CustomerDisplay.setDesktopOn(true);
      expect(await CustomerDisplay.available(fresh: true), isTrue);
    });
  }, variant: TargetPlatformVariant.only(TargetPlatform.windows));

  testWidgets('Windows: scanning = a box the USB scanner types into (+ Enter)', (t) async {
    String? got;
    await t.pumpWidget(
      app(
        Scaffold(
          body: Builder(
            builder: (ctx) => TextButton(onPressed: () async => got = await scanQr(ctx), child: const Text('scan')),
          ),
        ),
      ),
    );
    await t.tap(find.text('scan'));
    await t.pumpAndSettle();
    expect(find.byType(AlertDialog), findsOneWidget);
    await t.enterText(find.byType(TextField), ' TK-0042 ');
    await t.testTextInput.receiveAction(TextInputAction.done);
    await t.pumpAndSettle();
    expect(got, 'TK-0042');
    expect(find.byType(AlertDialog), findsNothing);
  }, variant: TargetPlatformVariant.only(TargetPlatform.windows));
}
