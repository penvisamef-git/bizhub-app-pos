import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../core/app_state.dart';

// a QR from the camera → its text (null = closed)
Future<String?> scanQr(BuildContext context, {String? title}) => Navigator.of(context).push<String>(MaterialPageRoute(builder: (_) => _ScanPage(title: title)));

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
