import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

// The screen facing the customer on dual-screen Android terminals (Sunmi D2, iMin…).
// The counter app sends a "picture" (JSON); Android shows it on the second display with a small
// second Flutter engine (entry point displayMain in main.dart). Works offline — nothing goes over the internet.
// On phones, tablets, iOS and the web there is no second display: everything here does nothing.
class CustomerDisplay {
  static const _ch = MethodChannel('bizhub/display');
  static bool get _platform => !kIsWeb && defaultTargetPlatform == TargetPlatform.android;
  static bool? _has;
  static String _last = '';

  // is a second screen plugged in / built in?
  static Future<bool> available({bool fresh = false}) async {
    if (!_platform) return false;
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
