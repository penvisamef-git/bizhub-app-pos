import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/app_state.dart';
import '../../core/pos_api.dart';
import '../../core/theme.dart';
import '../../widgets/ui.dart';
import '../attendance/att_api.dart' show attDeviceId;
import '../event/ev_api.dart' show EvStore;
import '../tgstore/ts_api.dart' show TsStore;

// "Try demo": link this device to a sample business of the BizHub demo account, without a code or QR from an owner
// (POST /api/public/pos-demo). Everybody shares the sample businesses; the staff PIN comes with the answer and is shown
// on the PIN screens (DemoPinHint). Attendance: mode "kiosk" (door tablet) or "staff" (logged in as the demo staff).
Future<void> linkDemo(String kind, {String mode = ''}) async {
  final body = <String, dynamic>{'kind': kind, 'name': 'Demo'};
  if (kind == 'attendance') {
    body['mode'] = mode == 'kiosk' ? 'kiosk' : 'staff';
    if (body['mode'] == 'staff') body['device_id'] = await attDeviceId();
  }
  final d = obj((await PosApi().call('POST', '/api/public/pos-demo', body: body))['data']);
  final pin = str(d['pin']);
  final at = DateTime.now().toIso8601String();
  final demo = {'demo': true, 'pin': pin, 'linked_at': at};
  switch (kind) {
    case 'restaurant':
      final token = str(d['token']);
      var shop = '', logo = '';
      try {
        final b = obj((await PosApi(token).restBootstrap())['data']);
        final rest = obj(b['restaurant']);
        shop = AppState.i.lang == 'km' && str(rest['name_km']).isNotEmpty ? str(rest['name_km']) : str(rest['name_en']);
        logo = str(rest['logo']);
      } catch (_) {}
      AppState.i.linked({'kind': kind, 'token': token, 'device': obj(d['device']), 'shop': shop, 'logo': logo, ...demo});
    case 'mart' || 'guest_house':
      final b = obj(d['business']);
      AppState.i.linked({'kind': kind, 'token': str(d['token']), 'device': {'name': 'Demo'}, 'shop': str(b['name']), 'logo': str(b['logo_url']), ...demo});
    case 'event':
      final org = obj(d['org']);
      await EvStore.init();
      EvStore.clear();
      AppState.i.linked({'kind': kind, 'token': str(d['token']), 'device': {'name': 'Demo'}, 'shop': str(org['name']), 'logo': str(org['logo']), ...demo});
    case 'tg_store':
      final shop = obj(d['shop']);
      await TsStore.init();
      TsStore.clear();
      AppState.i.linked({'kind': kind, 'token': str(d['token']), 'device': {'name': 'Demo'}, 'shop': str(shop['name']), 'logo': str(shop['logo']), ...demo});
    case 'stamp_card':
      final shop = obj(d['shop']);
      AppState.i.linked({'kind': kind, 'slug': str(d['slug']), 'token': '', 'name': '', 'shop': str(shop['name']), 'logo': str(shop['logo']), ...demo});
    case 'attendance':
      final b = obj(d['business']);
      AppState.i.linked({
        'kind': kind,
        'mode': str(d['mode']),
        if (str(d['code']).isNotEmpty) 'code': str(d['code']),
        'token': str(d['token']),
        'shop': str(b['name']),
        'logo': str(b['logo_url']),
        ...demo,
      });
  }
}

// "or" + the "Try a demo shop" button, for the bottom of a link screen
class DemoTry extends StatefulWidget {
  final String kind;
  final String mode;
  const DemoTry(this.kind, {super.key, this.mode = ''});
  @override
  State<DemoTry> createState() => _DemoTryState();
}

class _DemoTryState extends State<DemoTry> {
  bool _busy = false;
  String _error = '';

  Future<void> _go() async {
    final t = AppState.i.t;
    setState(() {
      _busy = true;
      _error = '';
    });
    try {
      await linkDemo(widget.kind, mode: widget.mode);
      if (!mounted) return;
      final pin = AppState.i.demoPin;
      toast(context, widget.kind == 'attendance' ? t('demo.doneShop', {'shop': str(AppState.i.link?['shop'])}) : t('demo.done', {'shop': str(AppState.i.link?['shop']), 'pin': pin}));
      Navigator.of(context).popUntil((r) => r.isFirst);
    } on ApiError catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = e.network ? t('app.offline') : (e.code == 'demo_off' ? t('demo.off') : e.message);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = AppScope.of(context).t;
    final c = context.c;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 18),
        Row(
          children: [
            Expanded(child: Divider(color: c.line)),
            Padding(padding: const EdgeInsets.symmetric(horizontal: 10), child: Muted(t('demo.or'))),
            Expanded(child: Divider(color: c.line)),
          ],
        ),
        const SizedBox(height: 12),
        if (_error.isNotEmpty) Padding(padding: const EdgeInsets.only(bottom: 10), child: Alert(_error)),
        Btn(t('demo.try'), icon: LucideIcons.sparkles, kind: BtnKind.ghost, busy: _busy, expand: true, onTap: _busy ? null : _go),
        const SizedBox(height: 6),
        Muted(t(widget.kind == 'attendance' ? 'demo.trySubAtt' : 'demo.trySub'), align: TextAlign.center),
      ],
    );
  }
}
