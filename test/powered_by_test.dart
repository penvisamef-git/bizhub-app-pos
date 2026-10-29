// "Powered by Cyber Tech System" (v3.3.0): EN / KM, and a tap on the name opens ctscambodia.com.
import 'package:bizhub_pos/core/app_state.dart';
import 'package:bizhub_pos/core/i18n.dart';
import 'package:bizhub_pos/core/powered_by.dart';
import 'package:bizhub_pos/core/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

Widget _app() => AppScope(
  child: Builder(
    builder: (context) => MaterialApp(
      theme: buildTheme(dark: false, khmer: AppScope.of(context).lang == 'km'),
      home: const Scaffold(body: Center(child: PoweredBy())),
    ),
  ),
);

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});
    await Future.wait([AppState.init(), T.load()]);
  });

  testWidgets('English, Khmer, and the tap opens the website', (t) async {
    final opened = <Uri>[];
    openPowered = (u) async => opened.add(u);
    AppState.i.setLang('en');
    await t.pumpWidget(_app());
    await t.pump();
    expect(find.text('Powered by Cyber Tech System ↗', findRichText: true), findsOneWidget);
    await t.tapOnText(find.textRange.ofSubstring('Cyber Tech System'));
    expect(opened, [Uri.parse('https://ctscambodia.com/')]);
    AppState.i.setLang('km');
    await t.pump();
    expect(find.text('ដំណើរការដោយ Cyber Tech System ↗', findRichText: true), findsOneWidget);
    AppState.i.setLang('en');
  });
}
