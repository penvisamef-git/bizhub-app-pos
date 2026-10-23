import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../core/app_state.dart';
import '../../core/format.dart';
import '../../core/theme.dart';
import '../../widgets/ui.dart';
import 'ev_api.dart';
import 'ev_ctl.dart';

// Scan: the camera stays open; every ticket shows a big green / red answer for a moment (tap = next one).
// No internet → the phone checks the codes it saved and sends the scans later.
class EvScanTab extends StatefulWidget {
  final EvCtl ctl;
  const EvScanTab({super.key, required this.ctl});
  // tests have no camera
  static bool camera = true;
  @override
  State<EvScanTab> createState() => _EvScanTabState();
}

class _EvScanTabState extends State<EvScanTab> {
  MobileScannerController? _cam;
  final _typed = TextEditingController();
  ScanResult? _res;
  bool _busy = false;
  bool _torch = false;
  Timer? _hide;
  String _last = '';
  DateTime _lastAt = DateTime(0);

  @override
  void initState() {
    super.initState();
    if (EvScanTab.camera) _cam = MobileScannerController(detectionSpeed: DetectionSpeed.normal, formats: const [BarcodeFormat.qrCode]);
  }

  @override
  void dispose() {
    _hide?.cancel();
    _cam?.dispose();
    _typed.dispose();
    super.dispose();
  }

  Future<void> _check(String raw) async {
    final code = evCodeOf(raw);
    if (code.isEmpty || _busy || _res != null) return;
    // the same QR still in front of the camera
    if (code == _last && DateTime.now().difference(_lastAt).inMilliseconds < 3500) return;
    _last = code;
    _lastAt = DateTime.now();
    setState(() => _busy = true);
    final r = await widget.ctl.scan(code);
    if (!mounted) return;
    if (r.ok) {
      HapticFeedback.mediumImpact();
      SystemSound.play(SystemSoundType.click);
    } else {
      HapticFeedback.heavyImpact();
      SystemSound.play(SystemSoundType.alert);
    }
    _hide?.cancel();
    _hide = Timer(Duration(milliseconds: r.ok ? 2200 : 4000), _next);
    setState(() {
      _busy = false;
      _res = r;
    });
  }

  void _next() {
    _hide?.cancel();
    _lastAt = DateTime.now();
    if (mounted) setState(() => _res = null);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final t = AppState.i.t;
    return Stack(
      children: [
        ListView(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
          children: [
            Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 480),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    AspectRatio(
                      aspectRatio: 1,
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(26),
                        child: Stack(
                          fit: StackFit.expand,
                          children: [
                            Container(color: Colors.black),
                            if (_cam != null)
                              MobileScanner(
                                controller: _cam,
                                onDetect: (cap) {
                                  final v = cap.barcodes.map((b) => b.rawValue ?? '').firstWhere((x) => x.isNotEmpty, orElse: () => '');
                                  if (v.isNotEmpty) _check(v);
                                },
                                errorBuilder: (_, _) => _CamMsg(ev('camDenied')),
                              )
                            else
                              Center(child: Icon(LucideIcons.scanLine, size: 70, color: Colors.white.withValues(alpha: .35))),
                            // the frame
                            Center(
                              child: FractionallySizedBox(
                                widthFactor: .66,
                                heightFactor: .66,
                                child: Container(
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(22),
                                    border: Border.all(color: Colors.white.withValues(alpha: .9), width: 3),
                                  ),
                                ),
                              ),
                            ),
                            if (_busy) const Center(child: CircularProgressIndicator(color: Colors.white)),
                            if (_cam != null)
                              Positioned(
                                right: 10,
                                bottom: 10,
                                child: Row(
                                  children: [
                                    RoundBtn(
                                      _torch ? LucideIcons.flashlightOff : LucideIcons.flashlight,
                                      tip: t('evx.torch'),
                                      size: 42,
                                      bg: Colors.black54,
                                      fg: Colors.white,
                                      onTap: () {
                                        _cam?.toggleTorch();
                                        setState(() => _torch = !_torch);
                                      },
                                    ),
                                    const SizedBox(width: 8),
                                    RoundBtn(LucideIcons.switchCamera, tip: t('evx.flip'), size: 42, bg: Colors.black54, fg: Colors.white, onTap: () => _cam?.switchCamera()),
                                  ],
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),
                    Row(
                      children: [
                        Expanded(
                          child: Field(
                            controller: _typed,
                            hint: ev('typeCode'),
                            icon: LucideIcons.ticket,
                            onChanged: (v) {
                              final up = v.toUpperCase();
                              if (up != v) _typed.value = _typed.value.copyWith(text: up);
                              setState(() {});
                            },
                            onSubmit: (_) {
                              _last = '';
                              _check(_typed.text);
                              _typed.clear();
                            },
                          ),
                        ),
                        const SizedBox(width: 10),
                        Btn(
                          ev('check'),
                          kind: BtnKind.solid,
                          onTap: _typed.text.trim().isEmpty || _busy
                              ? null
                              : () {
                                  _last = '';
                                  _check(_typed.text);
                                  _typed.clear();
                                  FocusScope.of(context).unfocus();
                                },
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(LucideIcons.sun, size: 14, color: c.muted),
                        const SizedBox(width: 6),
                        Flexible(
                          child: Text(t('evx.keepAwake'), style: TextStyle(color: c.muted, fontSize: 12.5)),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
        if (_res != null)
          Positioned.fill(
            child: _ResultCard(res: _res!, onTap: _next),
          ),
      ],
    );
  }
}

class _CamMsg extends StatelessWidget {
  final String text;
  const _CamMsg(this.text);
  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Text(
        text,
        textAlign: TextAlign.center,
        style: const TextStyle(color: Colors.white, height: 1.45),
      ),
    ),
  );
}

// the big answer over the scanner
class _ResultCard extends StatelessWidget {
  final ScanResult res;
  final VoidCallback onTap;
  const _ResultCard({required this.res, required this.onTap});
  @override
  Widget build(BuildContext context) {
    final good = res.ok;
    final warn = res.kind == 'used';
    final bg = good ? const Color(0xFF15803D) : (warn ? const Color(0xFFB45309) : const Color(0xFFB91C1C));
    final tk = res.ticket;
    final title = switch (res.kind) {
      'ok' => ev('ok'),
      'used' => ev('used'),
      'cancelled' => ev('cancelled'),
      'other_event' => ev('otherEvent'),
      'other_show' => ev('otherShow'),
      'not_found' => ev('notFound'),
      _ => res.msg,
    };
    const white = TextStyle(color: Colors.white);
    return Semantics(
      button: true,
      label: title,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(28)),
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(good ? LucideIcons.circleCheck : LucideIcons.circleX, size: 96, color: Colors.white),
              const SizedBox(height: 14),
              Text(
                title,
                textAlign: TextAlign.center,
                style: white.copyWith(fontSize: 28, fontWeight: FontWeight.w800, height: 1.25),
              ),
              if (tk != null) ...[
                const SizedBox(height: 14),
                if (str(tk['holder']).isNotEmpty)
                  Text(
                    str(tk['holder']),
                    textAlign: TextAlign.center,
                    style: white.copyWith(fontSize: 21, fontWeight: FontWeight.w700),
                  ),
                if (str(tk['type'] ?? tk['type_name']).isNotEmpty)
                  Container(
                    margin: const EdgeInsets.only(top: 8),
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
                    decoration: BoxDecoration(color: Colors.white.withValues(alpha: .2), borderRadius: BorderRadius.circular(999)),
                    child: Text(str(tk['type'] ?? tk['type_name']), style: white.copyWith(fontWeight: FontWeight.w700)),
                  ),
              ],
              if (res.kind == 'used' && tk?['used_at'] != null)
                Padding(
                  padding: const EdgeInsets.only(top: 10),
                  child: Text(
                    ev('usedAt', {'t': fmtTime(tk!['used_at']), 'name': str(tk['used_by']).isEmpty ? '—' : str(tk['used_by'])}),
                    textAlign: TextAlign.center,
                    style: white.copyWith(fontSize: 15),
                  ),
                ),
              if (res.kind == 'other_event' && res.other != null)
                Padding(
                  padding: const EdgeInsets.only(top: 10),
                  child: Text(str(res.other!['title']), textAlign: TextAlign.center, style: white.copyWith(fontSize: 15)),
                ),
              if (str(tk?['seat_label']).isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 10),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(LucideIcons.armchair, size: 20, color: Colors.white),
                      const SizedBox(width: 6),
                      Text(str(tk!['seat_label']), style: white.copyWith(fontSize: 19, fontWeight: FontWeight.w800)),
                    ],
                  ),
                ),
              if (res.kind == 'other_show' && tk?['show_at'] != null)
                Padding(
                  padding: const EdgeInsets.only(top: 10),
                  child: Text(ev('forShow', {'t': evWhen(tk!['show_at'])}), textAlign: TextAlign.center, style: white.copyWith(fontSize: 15)),
                ),
              if (res.offline)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(LucideIcons.cloudOff, size: 15, color: Colors.white),
                      const SizedBox(width: 6),
                      Flexible(child: Text(ev('offline'), style: white.copyWith(fontSize: 13))),
                    ],
                  ),
                ),
              const SizedBox(height: 18),
              Text(ev('tapNext'), style: white.copyWith(fontSize: 13, color: Colors.white70)),
            ],
          ),
        ),
      ),
    );
  }
}
