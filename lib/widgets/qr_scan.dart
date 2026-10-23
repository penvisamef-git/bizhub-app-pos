import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../core/app_state.dart';
import '../core/desktop.dart';

// a QR from the camera → its text (null = closed). Windows (no camera scanner): a box to type the code into,
// which a USB scanner fills in and presses Enter.
Future<String?> scanQr(BuildContext context, {String? title}) {
  if (!hasCameraScanner) return _typeCode(context, title: title);
  return Navigator.of(context).push<String>(MaterialPageRoute(builder: (_) => _ScanPage(title: title)));
}

Future<String?> _typeCode(BuildContext context, {String? title}) {
  final t = AppScope.of(context).t;
  final ctl = TextEditingController();
  return showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title ?? t('ks.typeCode')),
      content: SizedBox(
        width: 420,
        child: TextField(
          controller: ctl,
          autofocus: true,
          decoration: InputDecoration(hintText: t('ks.typeCode')),
          onSubmitted: (v) => Navigator.pop(ctx, v.trim().isEmpty ? null : v.trim()),
        ),
      ),
      actions: [TextButton(onPressed: () => Navigator.pop(ctx, ctl.text.trim().isEmpty ? null : ctl.text.trim()), child: Text(t('ks.ok')))],
    ),
  );
}

class _ScanPage extends StatefulWidget {
  final String? title;
  const _ScanPage({this.title});
  @override
  State<_ScanPage> createState() => _ScanPageState();
}

class _ScanPageState extends State<_ScanPage> {
  final _cam = MobileScannerController(detectionSpeed: DetectionSpeed.noDuplicates, formats: const [BarcodeFormat.qrCode]);
  bool _done = false;
  @override
  void dispose() {
    _cam.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = AppScope.of(context).t;
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(backgroundColor: Colors.black, foregroundColor: Colors.white, title: Text(widget.title ?? '')),
      body: Stack(
        children: [
          Positioned.fill(
            child: MobileScanner(
              controller: _cam,
              onDetect: (cap) {
                final v = cap.barcodes.map((b) => b.rawValue ?? '').firstWhere((x) => x.isNotEmpty, orElse: () => '');
                if (v.isEmpty || _done) return;
                _done = true;
                HapticFeedback.mediumImpact();
                Navigator.pop(context, v.trim());
              },
              errorBuilder: (_, e) => Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(
                    t('att.cameraNo'),
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.white),
                  ),
                ),
              ),
            ),
          ),
          Center(
            child: Container(
              width: 250,
              height: 250,
              decoration: BoxDecoration(
                border: Border.all(color: Colors.white, width: 3),
                borderRadius: BorderRadius.circular(24),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
