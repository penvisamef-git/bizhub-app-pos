import 'package:shared_preferences/shared_preferences.dart';

import 'local_prefs.dart';

// the web: no SQLite, SharedPreferences is used
Future<LocalPrefs?> openDesktop(SharedPreferences sp) async => null;
