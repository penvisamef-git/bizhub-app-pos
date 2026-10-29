import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/app_state.dart';
import '../../core/pos_api.dart';
import '../../core/theme.dart';
import '../event/ev_api.dart' show EvDoor, EvStore;
import '../tgstore/ts_api.dart' show TsPos, TsStore;
import '../guesthouse/engine/gh_pos.dart';
import '../mart/engine/mart_pos.dart';
import 'demo_link.dart';
import '../../widgets/ui.dart';
import '../../core/powered_by.dart';

// Type the 6-digit code the owner made in Biz Hub → this device is linked to that business.
class LinkPage extends StatefulWidget {
  final String kind;
  const LinkPage({super.key, required this.kind});
  @override
  State<LinkPage> createState() => _LinkPageState();
}

class _LinkPageState extends State<LinkPage> {
  String _code = '';
  final _name = TextEditingController();
  bool _busy = false;
  String _error = '';

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  void _press(String k) {
    if (_busy) return;
    HapticFeedback.selectionClick();
    setState(() {
      _error = '';
      _code = k == 'del' ? (_code.isEmpty ? '' : _code.substring(0, _code.length - 1)) : (_code.length < 6 ? _code + k : _code);
    });
  }

  Future<void> _link() async {
    final t = AppState.i.t;
    if (_code.length != 6) return;
    setState(() {
      _busy = true;
      _error = '';
    });
    try {
      final name = _name.text.trim().isEmpty ? (widget.kind == 'event' ? t('evd.phoneNamePh') : (widget.kind == 'tg_store' ? t('tsx.screenNamePh') : 'POS')) : _name.text.trim();
      if (widget.kind == 'tg_store') {
        // Telegram Store: a staff screen of the shop; each staff member logs in with a PIN next
        final d = obj((await TsPos.pair(_code, name))['data']);
        final shop = obj(d['shop']);
        await TsStore.init();
        TsStore.clear();
        AppState.i.linked({'kind': 'tg_store', 'token': str(d['token']), 'device': {'name': name}, 'shop': str(shop['name']), 'logo': str(shop['logo']), 'linked_at': DateTime.now().toIso8601String()});
        if (!mounted) return;
        toast(context, t('link.done', {'shop': str(shop['name'])}));
        Navigator.of(context).popUntil((r) => r.isFirst);
        return;
      }
      if (widget.kind == 'event') {
        // Event Tickets: a door phone of the organiser; each team member logs in with a PIN next
        final d = obj((await EvDoor.pair(_code, name))['data']);
        final org = obj(d['org']);
        await EvStore.init();
        EvStore.clear();
        AppState.i.linked({
          'kind': 'event',
          'token': str(d['token']),
          'device': {'name': name},
          'shop': str(org['name']),
          'logo': str(org['logo']),
          'linked_at': DateTime.now().toIso8601String(),
        });
        if (!mounted) return;
        toast(context, t('link.done', {'shop': str(org['name'])}));
        Navigator.of(context).popUntil((r) => r.isFirst);
        return;
      }
      if (widget.kind == 'mart' || widget.kind == 'guest_house') {
        // Mini Mart / Guest House: the device token; the shop's name + logo come with it
        final d = widget.kind == 'mart' ? await MartPos.pair(_code, name) : await GhPos.pair(_code, name);
        final b = obj(d['business']);
        AppState.i.linked({
          'kind': widget.kind,
          'token': str(d['token']),
          'device': {'name': name},
          'shop': str(b['name']),
          'logo': str(b['logo_url']),
          'linked_at': DateTime.now().toIso8601String(),
        });
        if (!mounted) return;
        toast(context, t('link.done', {'shop': str(b['name'])}));
        Navigator.of(context).popUntil((r) => r.isFirst);
        return;
      }
      final r = await PosApi().restPair(_code, name);
      final d = obj(r['data']);
      final token = str(d['token']);
      // the shop's name + logo for the first screen (the full download comes with the selling screens)
      var shop = '', logo = '';
      try {
        final b = obj((await PosApi(token).restBootstrap())['data']);
        final rest = obj(b['restaurant']);
        shop = AppState.i.lang == 'km' && str(rest['name_km']).isNotEmpty ? str(rest['name_km']) : str(rest['name_en']);
        logo = str(rest['logo']);
      } catch (_) {}
      AppState.i.linked({'kind': widget.kind, 'token': token, 'device': obj(d['device']), 'shop': shop, 'logo': logo, 'linked_at': DateTime.now().toIso8601String()});
      if (!mounted) return;
      toast(context, t('link.done', {'shop': shop}));
      Navigator.of(context).popUntil((r) => r.isFirst);
    } on ApiError catch (e) {
      setState(() {
        _busy = false;
        _error = e.network ? t('app.offline') : (e.status == 400 ? t('link.bad') : e.message);
        _code = '';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final t = app.t;
    final c = context.c;
    return Scaffold(
      backgroundColor: c.appBg,
      appBar: AppBar(
        backgroundColor: c.appBg,
        surfaceTintColor: Colors.transparent,
        title: Text(t('link.title'), style: const TextStyle(fontWeight: FontWeight.w800)),
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 440),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
              children: [
                Row(
                  children: [
                    TypeIcon(widget.kind, size: 46),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(t('type.${widget.kind}'), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 18)),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(color: c.active, borderRadius: BorderRadius.circular(16)),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(LucideIcons.info, size: 18, color: c.brandInk),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(t('link.how.${widget.kind}'), style: TextStyle(color: c.brandInk, height: 1.45)),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 22),
                Center(child: Muted(t('link.code'))),
                const SizedBox(height: 10),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    for (var i = 0; i < 6; i++)
                      Container(
                        width: 46,
                        height: 58,
                        margin: EdgeInsets.only(left: i == 3 ? 14 : 4, right: 4),
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: c.card,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: i == _code.length && !_busy ? c.brand : c.line, width: i == _code.length ? 2 : 1),
                        ),
                        child: Text(i < _code.length ? _code[i] : '', style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w800)),
                      ),
                  ],
                ),
                if (_error.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 14), child: Alert(_error)),
                const SizedBox(height: 18),
                GridView.count(
                  crossAxisCount: 3,
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  mainAxisSpacing: 10,
                  crossAxisSpacing: 10,
                  childAspectRatio: 1.9,
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
                                  child: k == 'del' ? Icon(LucideIcons.delete, color: c.ink) : Text(k, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w700)),
                                ),
                              ),
                            ),
                  ],
                ),
                const SizedBox(height: 18),
                Field(label: t('link.name'), controller: _name, hint: widget.kind == 'event' ? t('evd.phoneNamePh') : (widget.kind == 'tg_store' ? t('tsx.screenNamePh') : t('link.namePh')), maxLength: 40),
                const SizedBox(height: 16),
                Btn(_busy ? t('link.going') : t('link.go'), icon: LucideIcons.link, busy: _busy, expand: true, onTap: _code.length == 6 && !_busy ? _link : null),
                const PoweredBy(),
                DemoTry(widget.kind),
                const SizedBox(height: 8),
                Center(
                  child: TextButton(onPressed: () => Navigator.of(context).pop(), child: Text(t('link.changeType'))),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
