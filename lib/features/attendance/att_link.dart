import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/app_state.dart';
import '../../core/format.dart' show normalizePhone;
import '../../core/i18n.dart';
import '../../core/theme.dart';
import '../start/demo_link.dart';
import '../../widgets/qr_scan.dart';
import '../../widgets/ui.dart';
import 'att_api.dart';

// Attendance on this device: a door tablet (shows the changing QR) or one staff member's own phone.
class AttModePage extends StatelessWidget {
  const AttModePage({super.key});
  @override
  Widget build(BuildContext context) {
    final t = AppScope.of(context).t;
    final c = context.c;
    Widget card(String mode, IconData icon, Widget page) => Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Panel(
        padding: const EdgeInsets.all(18),
        onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => page)),
        child: Row(
          children: [
            Container(
              width: 54,
              height: 54,
              decoration: BoxDecoration(color: c.active, borderRadius: BorderRadius.circular(18)),
              child: Icon(icon, color: c.brandInk, size: 26),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(t('att.mode.$mode'), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 17)),
                  const SizedBox(height: 3),
                  Text(t('att.mode.${mode}Sub'), style: TextStyle(color: c.muted, fontSize: 13.5, height: 1.4)),
                ],
              ),
            ),
            Icon(LucideIcons.chevronRight, color: c.muted),
          ],
        ),
      ),
    );
    return Scaffold(
      backgroundColor: c.appBg,
      appBar: AppBar(
        backgroundColor: c.appBg,
        surfaceTintColor: Colors.transparent,
        title: Text(t('type.attendance'), style: const TextStyle(fontWeight: FontWeight.w800)),
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
              children: [
                Text(t('att.mode.title'), style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
                const SizedBox(height: 16),
                card('staff', LucideIcons.smartphone, const StaffLoginPage()),
                card('kiosk', LucideIcons.tabletSmartphone, const KioskLinkPage()),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------- door tablet: the kiosk link (…/k/<token>)
class KioskLinkPage extends StatefulWidget {
  const KioskLinkPage({super.key});
  @override
  State<KioskLinkPage> createState() => _KioskLinkPageState();
}

class _KioskLinkPageState extends State<KioskLinkPage> {
  final _link = TextEditingController();
  bool _busy = false;
  String _error = '';

  @override
  void dispose() {
    _link.dispose();
    super.dispose();
  }

  Future<void> _go([String? raw]) async {
    final t = AppState.i.t;
    final token = parseKioskLink(raw ?? _link.text);
    if (token == null) return setState(() => _error = t('att.kl.bad'));
    setState(() {
      _busy = true;
      _error = '';
    });
    try {
      final d = obj(await AttApi().get('/kiosk/$token'));
      final b = obj(d['business']);
      AppState.i.linked({'kind': 'attendance', 'mode': 'kiosk', 'token': token, 'shop': str(b['name']), 'logo': str(b['logo_url']), 'linked_at': DateTime.now().toIso8601String()});
      if (!mounted) return;
      toast(context, t('link.done', {'shop': str(b['name'])}));
      Navigator.of(context).popUntil((r) => r.isFirst);
    } on ApiError catch (e) {
      setState(() {
        _busy = false;
        _error = e.network ? t('att.network') : t('att.kl.needAddon');
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = AppScope.of(context).t;
    final c = context.c;
    return Scaffold(
      backgroundColor: c.appBg,
      appBar: AppBar(
        backgroundColor: c.appBg,
        surfaceTintColor: Colors.transparent,
        title: Text(t('att.kl.title'), style: const TextStyle(fontWeight: FontWeight.w800)),
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
              children: [
                _HowBox(t('att.kl.how')),
                const SizedBox(height: 20),
                Btn(
                  t('att.kl.scan'),
                  icon: LucideIcons.scanLine,
                  expand: true,
                  onTap: _busy
                      ? null
                      : () async {
                          final v = await scanQr(context, title: t('att.kl.scan'));
                          if (v != null) {
                            _link.text = v;
                            _go(v);
                          }
                        },
                ),
                const SizedBox(height: 20),
                Field(label: t('att.kl.link'), controller: _link, hint: 'https://…/k/…', icon: LucideIcons.link, keyboard: TextInputType.url, onSubmit: (_) => _go()),
                if (_error.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 12), child: Alert(_error)),
                const SizedBox(height: 14),
                Btn(t('att.kl.go'), icon: LucideIcons.link, kind: BtnKind.solid, busy: _busy, expand: true, onTap: _busy ? null : () => _go()),
                const DemoTry('attendance', mode: 'kiosk'),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _HowBox extends StatelessWidget {
  final String text;
  const _HowBox(this.text);
  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: c.active, borderRadius: BorderRadius.circular(16)),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(LucideIcons.info, size: 18, color: c.brandInk),
          const SizedBox(width: 10),
          Expanded(
            child: Text(text, style: TextStyle(color: c.brandInk, height: 1.45)),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------- staff phone: shop code → phone → PIN
class StaffLoginPage extends StatefulWidget {
  final String code; // already known (logged out on this phone before)
  const StaffLoginPage({super.key, this.code = ''});
  @override
  State<StaffLoginPage> createState() => _StaffLoginPageState();
}

class _StaffLoginPageState extends State<StaffLoginPage> {
  final _codeIn = TextEditingController();
  final _phone = TextEditingController();
  String _step = 'code'; // code | phone | pin
  String _code = '';
  Json? _info; // { name, logo_url, color }
  String _pin = '';
  bool _busy = false;
  String _error = '';

  @override
  void initState() {
    super.initState();
    if (widget.code.isNotEmpty) WidgetsBinding.instance.addPostFrameCallback((_) => _useCode(widget.code));
  }

  @override
  void dispose() {
    _codeIn.dispose();
    _phone.dispose();
    super.dispose();
  }

  T get t => AppState.i.t;

  Future<void> _useCode(String raw) async {
    final p = parseStaffLink(raw);
    if (p == null) return setState(() => _error = t('att.sl.bad'));
    setState(() {
      _busy = true;
      _error = '';
    });
    try {
      final d = obj(await AttApi().get('/info/${p.code}'));
      setState(() {
        _code = p.code;
        _info = d;
        _step = 'phone';
        _busy = false;
      });
    } on ApiError catch (e) {
      setState(() {
        _busy = false;
        _error = attErr(t, e);
      });
    }
  }

  void _toPin() {
    if (normalizePhone(_phone.text) == null) return setState(() => _error = t('att.badPhone'));
    setState(() {
      _error = '';
      _pin = '';
      _step = 'pin';
    });
  }

  void _press(String k) {
    if (_busy) return;
    HapticFeedback.selectionClick();
    setState(() {
      _error = '';
      if (k == 'del') {
        if (_pin.isNotEmpty) _pin = _pin.substring(0, _pin.length - 1);
      } else if (_pin.length < 4) {
        _pin += k;
      }
    });
    if (_pin.length == 4) _login();
  }

  Future<void> _login() async {
    setState(() => _busy = true);
    try {
      final d = obj(await AttApi().post('/login', {'code': _code, 'phone': _phone.text.trim(), 'pin': _pin, 'device_id': await attDeviceId(), 'device_label': 'BizHub POS app'}));
      final me = obj(d['me']);
      final b = obj(me['business']);
      AppState.i.linked({
        'kind': 'attendance',
        'mode': 'staff',
        'code': _code,
        'token': str(d['token']),
        'shop': str(b['name']),
        'logo': str(b['logo_url']),
        'linked_at': DateTime.now().toIso8601String(),
      });
      if (!mounted) return;
      Navigator.of(context).popUntil((r) => r.isFirst);
    } on ApiError catch (e) {
      setState(() {
        _busy = false;
        _pin = '';
        _error = attErr(t, e);
        if (e.code == 'bad_link') _step = 'code';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = AppScope.of(context).t;
    final c = context.c;
    final accent = hexColor(_info?['color'], c.brand);
    final logo = str(_info?['logo_url']);
    return Scaffold(
      backgroundColor: c.appBg,
      appBar: AppBar(
        backgroundColor: c.appBg,
        surfaceTintColor: Colors.transparent,
        title: Text(t('att.sl.title'), style: const TextStyle(fontWeight: FontWeight.w800)),
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
              children: [
                if (_step == 'code') ...[
                  _HowBox(t('att.sl.how')),
                  const SizedBox(height: 20),
                  Btn(
                    t('att.sl.scan'),
                    icon: LucideIcons.scanLine,
                    expand: true,
                    busy: _busy,
                    onTap: _busy
                        ? null
                        : () async {
                            final v = await scanQr(context, title: t('att.sl.scan'));
                            if (v != null) _useCode(v);
                          },
                  ),
                  const SizedBox(height: 20),
                  Field(label: t('att.sl.code'), controller: _codeIn, hint: 'AB12CD', icon: LucideIcons.keyRound, maxLength: 60, onSubmit: (v) => _useCode(v)),
                  if (_error.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 12), child: Alert(_error)),
                  const SizedBox(height: 14),
                  Btn(t('att.next'), kind: BtnKind.solid, expand: true, onTap: _busy ? null : () => _useCode(_codeIn.text)),
                  const DemoTry('attendance', mode: 'staff'),
                ] else ...[
                  const SizedBox(height: 8),
                  Center(
                    child: Container(
                      width: 76,
                      height: 76,
                      clipBehavior: Clip.antiAlias,
                      decoration: BoxDecoration(color: accent.withValues(alpha: .12), borderRadius: BorderRadius.circular(24)),
                      child: logo.isNotEmpty ? Image(image: netImage(logo), fit: BoxFit.cover) : Icon(LucideIcons.fingerprintPattern, color: accent, size: 36),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    str(_info?['name']),
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 21),
                  ),
                  const SizedBox(height: 4),
                  Muted(_step == 'phone' ? t('att.loginSub') : t('att.pinSub'), align: TextAlign.center),
                  const SizedBox(height: 20),
                  if (_step == 'phone') ...[
                    Field(label: t('att.phone'), controller: _phone, hint: '012 345 678', icon: LucideIcons.phone, keyboard: TextInputType.phone, autofocus: true, onSubmit: (_) => _toPin()),
                    if (_error.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 12), child: Alert(_error)),
                    const SizedBox(height: 14),
                    Btn(t('att.next'), expand: true, onTap: _toPin),
                  ] else ...[
                    Center(
                      child: TextButton.icon(
                        onPressed: _busy ? null : () => setState(() => (_step = 'phone', _pin = '', _error = '')),
                        icon: const Icon(LucideIcons.chevronLeft, size: 16),
                        label: Text(_phone.text.trim()),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        for (var i = 0; i < 4; i++)
                          Container(
                            width: 18,
                            height: 18,
                            margin: const EdgeInsets.symmetric(horizontal: 9),
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: i < _pin.length ? accent : Colors.transparent,
                              border: Border.all(color: i < _pin.length ? accent : c.lineStrong, width: 2),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    if (_busy) const Center(child: SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.4))),
                    if (_error.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 6), child: Alert(_error)),
                    const SizedBox(height: 14),
                    GridView.count(
                      crossAxisCount: 3,
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      mainAxisSpacing: 10,
                      crossAxisSpacing: 10,
                      childAspectRatio: 1.7,
                      children: [
                        for (final k in ['1', '2', '3', '4', '5', '6', '7', '8', '9', '', '0', 'del'])
                          k.isEmpty
                              ? const SizedBox.shrink()
                              : Material(
                                  color: c.card,
                                  borderRadius: BorderRadius.circular(16),
                                  child: InkWell(
                                    borderRadius: BorderRadius.circular(16),
                                    onTap: () => _press(k),
                                    child: Center(
                                      child: k == 'del' ? Icon(LucideIcons.delete, color: c.ink, semanticLabel: 'Delete') : Text(k, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w700)),
                                    ),
                                  ),
                                ),
                      ],
                    ),
                  ],
                  const SizedBox(height: 16),
                  Muted(t('att.oneDevice'), align: TextAlign.center),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
