import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'desktop.dart';
import 'local_prefs.dart';

// The screen facing the customer on dual-screen Android terminals (Sunmi D2, iMin…), and on Mac / Windows a
// full-screen window on a second monitor (macos/Runner/MainFlutterWindow.swift, windows/runner/customer_display.cpp).
// The counter app sends a "picture" (JSON); the native side shows it with a small second Flutter engine
// (entry point displayMain in main.dart). Works offline — nothing goes over the internet.
// On phones, tablets, iOS and the web there is no second display: everything here does nothing.
// Mac / Windows: a switch on this computer (printer settings) can keep it off, e.g. for an office's second monitor.
class CustomerDisplay {
  static const _ch = MethodChannel('bizhub/display');
  static const _desktopKey = 'pos.customer_screen';
  static bool get _platform => !kIsWeb && (defaultTargetPlatform == TargetPlatform.android || isDesktop);
  static bool? _has;
  static String _last = '';

  // Mac / Windows: may this computer use its second monitor for the customer? (yes until switched off)
  static Future<bool> desktopOn() async => (await LocalPrefs.getInstance()).getBool(_desktopKey) ?? true;
  static Future<void> setDesktopOn(bool on) async {
    await (await LocalPrefs.getInstance()).setBool(_desktopKey, on);
    _has = null;
    if (!on) await hide();
  }

  // is a second screen plugged in / built in?
  static Future<bool> available({bool fresh = false}) async {
    if (!_platform) return false;
    if (isDesktop && !await desktopOn()) return false;
    if (_has != null && !fresh) return _has!;
    try {
      _has = await _ch.invokeMethod<bool>('available') ?? false;
    } catch (_) {
      _has = false;
    }
    return _has!;
  }

  // show this picture (the same one twice is not sent again)
  static Future<void> show(Map<String, Object?> pic) async {
    if (!_platform || _has == false) return;
    final s = jsonEncode(pic);
    if (s == _last) return;
    _last = s;
    try {
      await _ch.invokeMethod('show', s);
    } catch (_) {
      /* no second screen */
    }
  }

  static Future<void> hide() async {
    if (!_platform) return;
    _last = '';
    try {
      await _ch.invokeMethod('hide');
    } catch (_) {}
  }
}
