import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'core/app_state.dart';
import 'core/config.dart';
import 'core/i18n.dart';
import 'core/theme.dart';
import 'features/attendance/att_kiosk.dart';
import 'features/attendance/att_staff.dart';
import 'features/event/ev_root.dart';
import 'features/guesthouse/gh_root.dart';
import 'features/mart/mart_display.dart';
import 'features/mart/mart_root.dart';
import 'features/restaurant/rest_main.dart';
import 'features/stamp/sc_root.dart';
import 'features/start/choose_page.dart';
import 'features/start/welcome_page.dart';

// BizHub POS — the counter app for staff. Works on the device first, syncs with Biz Hub when online.
//   first time: 4 welcome pages → choose the POS → type the link code → that POS
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Future.wait([AppState.init(), T.load()]);
  runApp(AppScope(child: const PosApp()));
}

// the customer screen of a dual-screen Android terminal: Android starts this in a second engine (MainActivity.kt)
@pragma('vm:entry-point')
void displayMain() => runMartDisplay();

class PosApp extends StatelessWidget {
  const PosApp({super.key});
  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final km = app.lang == 'km';
    // started without env.json → no server address: say so instead of failing every request
    if (Config.apiHost.isEmpty) {
      return const MaterialApp(
        debugShowCheckedModeBanner: false,
        home: Scaffold(
          body: Center(
            child: Padding(
              padding: EdgeInsets.all(28),
              child: Text(
                'No server address (API_HOST).\n\nRun with:\nflutter run --dart-define-from-file=env.json\n\n(copy env.example.json to env.json first)',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 16, height: 1.5),
              ),
            ),
          ),
        ),
      );
    }
    return MaterialApp(
      title: 'BizHub POS',
      debugShowCheckedModeBanner: false,
      theme: buildTheme(dark: false, khmer: km),
      darkTheme: buildTheme(dark: true, khmer: km),
      themeMode: app.themeMode,
      locale: Locale(app.lang),
      supportedLocales: const [Locale('en'), Locale('km')],
      localizationsDelegates: const [GlobalMaterialLocalizations.delegate, GlobalWidgetsLocalizations.delegate, GlobalCupertinoLocalizations.delegate],
      home: !app.onboarded
          ? const WelcomePage()
          : app.link == null
          ? const ChoosePage()
          : switch (app.kind) {
              'restaurant' => const RestRoot(),
              'mart' => const MartRoot(),
              'guest_house' => const GhRoot(),
              'stamp_card' => const StampDeskRoot(),
              'event' => const EvDoorRoot(),
              'attendance' => app.link?['mode'] == 'kiosk' ? const AttKioskRoot() : const AttStaffRoot(),
              _ => const ChoosePage(),
            },
    );
  }
}
