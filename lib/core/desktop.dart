import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'theme.dart';

// Mac and Windows builds of the POS (big screen, mouse and keyboard). Phones, tablets and the web: false, so
// everything desktop-only stays out of the Android / iOS app. (defaultTargetPlatform, so tests can pretend.)
bool get isDesktop => !kIsWeb && (defaultTargetPlatform == TargetPlatform.macOS || defaultTargetPlatform == TargetPlatform.windows);

// the camera scanner (mobile_scanner) has no Windows version: there a USB barcode scanner types into the scan box
bool get hasCameraScanner => kIsWeb || defaultTargetPlatform != TargetPlatform.windows;

// Keyboard shortcuts of a POS screen (F2 find, F12 pay…) — Mac / Windows only; elsewhere it is just `child`.
// A key whose action is null does nothing (the button it stands for is off). autofocus: give the screen the
// keyboard when nothing in it asks for it (a screen with its own autofocus field, like the mini mart scan box, says false).
class DesktopKeys extends StatelessWidget {
  final Map<LogicalKeyboardKey, VoidCallback?> keys;
  final bool autofocus;
  final Widget child;
  const DesktopKeys({super.key, required this.keys, this.autofocus = true, required this.child});

  @override
  Widget build(BuildContext context) {
    if (!isDesktop) return child;
    return CallbackShortcuts(
      bindings: {
        for (final e in keys.entries)
          if (e.value != null) SingleActivator(e.key): e.value!,
      },
      child: Focus(autofocus: autofocus, skipTraversal: true, child: child),
    );
  }
}

// the little "F2 Find · F12 Pay" line at the bottom of a desktop POS screen
class KeyHints extends StatelessWidget {
  final List<(String key, String label)> hints;
  const KeyHints(this.hints, {super.key});

  @override
  Widget build(BuildContext context) {
    if (!isDesktop) return const SizedBox.shrink();
    final c = context.c;
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 4, 14, 10),
      child: Wrap(
        spacing: 16,
        runSpacing: 6,
        children: [
          for (final (k, label) in hints)
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                  decoration: BoxDecoration(
                    color: c.card,
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: c.lineStrong),
                  ),
                  child: Text(
                    k,
                    style: TextStyle(fontWeight: FontWeight.w800, fontSize: 12, color: c.ink),
                  ),
                ),
                const SizedBox(width: 6),
                Text(label, style: TextStyle(fontSize: 12.5, color: c.muted)),
              ],
            ),
        ],
      ),
    );
  }
}
