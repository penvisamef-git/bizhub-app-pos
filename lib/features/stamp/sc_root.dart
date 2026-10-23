import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/api.dart';
import '../../core/app_state.dart';
import '../../core/format.dart' show fmt;
import '../../core/theme.dart';
import '../../widgets/qr_scan.dart';
import '../../widgets/ui.dart';
import '../start/demo_link.dart';
import 'sc_common.dart';
import 'sc_desk.dart';

// …/stamp/desk/<slug> or the bare slug
String? parseDeskLink(String v) {
  final s = v.trim();
  final m = RegExp(r'/stamp/desk/([a-z0-9-]{2,60})/?(?:\?.*)?$', caseSensitive: false).firstMatch(s);
  if (m != null) return m[1]!.toLowerCase();
  if (RegExp(r'^[a-z0-9-]{2,60}$').hasMatch(s)) return s;
  return null;
}

// Link this device to a stamp card: scan the desk QR (owner: Staff desk) or paste the link. The PIN comes next.
class StampLinkPage extends StatefulWidget {
  const StampLinkPage({super.key});
  @override
  State<StampLinkPage> createState() => _StampLinkPageState();
}

class _StampLinkPageState extends State<StampLinkPage> {
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
    final slug = parseDeskLink(raw ?? _link.text);
    if (slug == null) return setState(() => _error = t('st.bad'));
    setState(() {
      _busy = true;
      _error = '';
    });
    try {
      final d = obj((await DeskApi(slug).get('/api/public/stamp/shop/$slug'))['data']);
      final shop = obj(d['shop']);
      AppState.i.linked({'kind': 'stamp_card', 'slug': slug, 'token': '', 'name': '', 'shop': str(shop['name']), 'logo': str(shop['logo']), 'linked_at': DateTime.now().toIso8601String()});
      if (mounted) Navigator.of(context).popUntil((r) => r.isFirst);
    } on ApiError catch (e) {
      setState(() {
        _busy = false;
        _error = e.network ? t('app.offline') : (e.status == 404 ? t('st.bad') : e.message);
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
        title: Text(t('st.title'), style: const TextStyle(fontWeight: FontWeight.w800)),
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
              children: [
                Row(
                  children: [
                    const TypeIcon('stamp_card', size: 46),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(t('type.stamp_card'), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 18)),
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
                        child: Text(t('st.how'), style: TextStyle(color: c.brandInk, height: 1.45)),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
                Btn(
                  t('st.scan'),
                  icon: LucideIcons.scanLine,
                  expand: true,
                  onTap: _busy
                      ? null
                      : () async {
                          final v = await scanQr(context, title: t('st.scan'));
                          if (v != null) {
                            _link.text = v;
                            _go(v);
                          }
                        },
                ),
                const SizedBox(height: 20),
                Field(label: t('st.link'), controller: _link, hint: 'https://…/stamp/desk/…', icon: LucideIcons.link, keyboard: TextInputType.url, onSubmit: (_) => _go()),
                if (_error.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 12), child: Alert(_error)),
                const SizedBox(height: 14),
                Btn(t('st.next'), kind: BtnKind.solid, busy: _busy, expand: true, onTap: _busy ? null : () => _go()),
                const DemoTry('stamp_card'),
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

// The counter phone / tablet (the web's DeskPage): PIN once, then scan cards, add stamps, give rewards.
class StampDeskRoot extends StatefulWidget {
  const StampDeskRoot({super.key});
  @override
  State<StampDeskRoot> createState() => _StampDeskRootState();
}

class _StampDeskRootState extends State<StampDeskRoot> {
  Json? _d;
  String _off = ''; // the desk was turned off / the card is gone
  String _error = '';
  String _tab = 'stamp';
  (int, String)? _pick;
  Json? _open; // the customer open on the Stamp tab
  List<Json>? _ready, _recent;

  Json get _link => AppState.i.link ?? const {};
  String get _slug => str(_link['slug']);
  String get _token => str(_link['token']);
  String get _name => str(_link['name']);
  DeskApi get _api => DeskApi(_slug, token: _token, name: _name);

  @override
  void initState() {
    super.initState();
    if (_token.isNotEmpty) _load();
  }

  void _lock() {
    AppState.i.linked({..._link, 'token': ''});
    setState(() {
      _d = null;
      _open = null;
      _tab = 'stamp';
    });
  }

  Future<void> _load() async {
    try {
      final d = obj((await _api.get(''))['data']);
      if (!mounted) return;
      setState(() {
        _d = d;
        _error = '';
      });
      _loadLists();
    } on ApiError catch (e) {
      if (!mounted) return;
      if (e.status == 401) return _lock();
      if (e.status == 403 || e.status == 404) return setState(() => _off = e.message);
      setState(() => _error = e.network ? AppState.i.t('app.offline') : e.message);
    }
  }

  Future<void> _loadLists() async {
    try {
      final r = await _api.get('/members', {'filter': 'ready', 'sort': 'stamps'});
      final c = await _api.get('/members', {'sort': 'recent'});
      if (!mounted) return;
      setState(() {
        _ready = objs(r['data']);
        _recent = objs(c['data']).where((m) => m['last_visit_at'] != null).take(8).toList();
      });
    } catch (_) {}
  }

  void _choose(Json m) => setState(() {
    _pick = ((_pick?.$1 ?? 0) + 1, '#${m['no']}');
    _tab = 'stamp';
  });

  Future<void> _unlink() async {
    final t = AppState.i.t;
    final ok = await showDialog<bool>(
      context: context,
      builder: (d) => AlertDialog(
        content: Text(t('st.unlinkSure')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(d, false), child: Text(t('sc.cancel'))),
          TextButton(onPressed: () => Navigator.pop(d, true), child: Text(t('st.unlink'))),
        ],
      ),
    );
    if (ok == true) AppState.i.unlink();
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final t = app.t;
    final c = context.c;
    if (_off.isNotEmpty) {
      return Scaffold(
        backgroundColor: c.appBg,
        body: SafeArea(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(28),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(LucideIcons.stamp, size: 40, color: c.muted),
                  const SizedBox(height: 12),
                  Text(t('scp.deskTitle'), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 19)),
                  const SizedBox(height: 6),
                  Muted(_off, align: TextAlign.center),
                  const SizedBox(height: 18),
                  Btn(
                    t('att.refresh'),
                    icon: LucideIcons.refreshCw,
                    small: true,
                    onTap: () {
                      setState(() => _off = '');
                      _token.isEmpty ? setState(() {}) : _load();
                    },
                  ),
                  TextButton(onPressed: _unlink, child: Text(t('st.unlink'))),
                ],
              ),
            ),
          ),
        ),
      );
    }
    if (_token.isEmpty) return _Pin(onIn: _load, onOff: (m) => setState(() => _off = m), onUnlink: _unlink);
    final d = _d;
    if (d == null) {
      return Scaffold(
        backgroundColor: c.appBg,
        body: Center(
          child: _error.isEmpty
              ? const CircularProgressIndicator()
              : Padding(
                  padding: const EdgeInsets.all(24),
                  child: LoadError(text: _error, retry: t('att.refresh'), onRetry: _load),
                ),
        ),
      );
    }
    final ctx = ScCtx(api: _api, t: t, data: d, reload: _load, notify: (s) => toast(context, s), authLost: _lock);
    final accent = scHex(str(ctx.shopData['color'])) ?? scThemeOf(str(ctx.shopData['theme'])).accent;
    final logo = str(ctx.shopData['logo']);
    final tabs = [('stamp', LucideIcons.stamp), ('customers', LucideIcons.users), ('stats', LucideIcons.chartColumn), ('history', LucideIcons.history)];

    Widget body = switch (_tab) {
      'customers' => CustomersTab(ctx: ctx, onPick: _choose),
      'stats' => StatsTab(ctx: ctx, onPick: _choose),
      'history' => HistoryTab(ctx: ctx, onPick: _choose),
      _ => _stampTab(ctx, accent),
    };
    return Scaffold(
      backgroundColor: c.appBg,
      appBar: AppBar(
        backgroundColor: c.appBg,
        surfaceTintColor: Colors.transparent,
        titleSpacing: 16,
        title: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              clipBehavior: Clip.antiAlias,
              decoration: BoxDecoration(color: accent.withValues(alpha: .14), borderRadius: BorderRadius.circular(11)),
              child: logo.isNotEmpty ? Image(image: netImage(logo), fit: BoxFit.cover) : Icon(LucideIcons.stamp, size: 19, color: accent),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    ctx.shopName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16.5),
                  ),
                  Text(_name.isNotEmpty ? t('scp.staffAs', {'name': _name}) : t('scp.deskTitle'), style: TextStyle(color: c.muted, fontSize: 12.5)),
                ],
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => app.setLang(app.lang == 'km' ? 'en' : 'km'),
            child: Text(app.lang == 'km' ? 'EN' : 'ខ្មែរ', style: const TextStyle(fontWeight: FontWeight.w700)),
          ),
          IconButton(onPressed: _lock, icon: const Icon(LucideIcons.lock), tooltip: t('scp.logout')),
          PopupMenuButton<String>(
            icon: const Icon(LucideIcons.ellipsisVertical),
            tooltip: t('st.more'),
            onSelected: (v) => v == 'unlink' ? _unlink() : (v == 'theme' ? pickTheme(context) : null),
            itemBuilder: (_) => [PopupMenuItem(value: 'theme', child: Text(t('app.theme'))), PopupMenuItem(value: 'unlink', child: Text(t('st.unlink')))],
          ),
        ],
      ),
      body: Center(
        child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 720), child: body),
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: tabs.indexWhere((x) => x.$1 == _tab),
        indicatorColor: accent.withValues(alpha: .16),
        onDestinationSelected: (i) => setState(() => _tab = tabs[i].$1),
        destinations: [for (final x in tabs) NavigationDestination(icon: Icon(x.$2), label: t('scp.tabs.${x.$1}'))],
      ),
    );
  }

  Widget _stampTab(ScCtx ctx, Color accent) {
    final t = ctx.t;
    final c = context.c;
    final td = ctx.today;
    final tiles = [
      (LucideIcons.calendarCheck, '${t('scp.visits')} · ${t('scp.today')}', fmt(n(td['visits'])), null),
      (LucideIcons.star, '${t('scp.stampsWord')} · ${t('scp.today')}', fmt(n(td['stamps'])), null),
      (LucideIcons.gift, '${t('scp.rewardsWord')} · ${t('scp.today')}', fmt(n(td['rewards'])), null),
      (LucideIcons.userRound, t('scp.readyTile'), _ready == null ? '…' : fmt(_ready!.length), () => setState(() => _tab = 'customers')),
    ];
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
        children: [
          LayoutBuilder(
            builder: (context, box) {
              final cols = box.maxWidth > 560 ? 4 : 2;
              return GridView.count(
                crossAxisCount: cols,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                mainAxisSpacing: 10,
                crossAxisSpacing: 10,
                childAspectRatio: cols == 4 ? 2.0 : 2.3,
                children: [
                  for (final (icon, label, v, go) in tiles)
                    Panel(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                      onTap: go,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Row(
                            children: [
                              Icon(icon, size: 14, color: accent),
                              const SizedBox(width: 6),
                              Expanded(
                                child: Text(
                                  label,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(color: c.muted, fontSize: 12, fontWeight: FontWeight.w600),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 2),
                          Text(v, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
                        ],
                      ),
                    ),
                ],
              );
            },
          ),
          scGap,
          scPanel([
            ScCounter(
              ctx: ctx,
              owner: false,
              canReset: ctx.canReset,
              pick: _pick,
              onMember: (m) => setState(() => _open = m),
              onChanged: () {
                _load();
              },
            ),
          ]),
          if (_open == null) ...[
            if (_ready?.isNotEmpty == true) ...[
              scGap,
              scPanel([
                scTitle(context, t('scp.readyList'), icon: LucideIcons.gift, count: '${_ready!.length}'),
                for (final m in _ready!.take(6)) ScMemberRow(ctx: ctx, m: m, onTap: () => _choose(m)),
              ]),
            ],
            if (_recent?.isNotEmpty == true) ...[
              scGap,
              scPanel([
                scTitle(context, t('scp.recentList'), icon: LucideIcons.history),
                for (final m in _recent!) ScMemberRow(ctx: ctx, m: m, onTap: () => _choose(m)),
                const SizedBox(height: 4),
                Muted(t('scp.tapToOpen')),
              ]),
            ],
          ],
        ],
      ),
    );
  }
}

// the PIN pad (4–8 digits) + the staff's name
class _Pin extends StatefulWidget {
  final VoidCallback onIn;
  final ValueChanged<String> onOff;
  final VoidCallback onUnlink;
  const _Pin({required this.onIn, required this.onOff, required this.onUnlink});
  @override
  State<_Pin> createState() => _PinState();
}

class _PinState extends State<_Pin> {
  String _pin = '';
  bool _busy = false;
  String _error = '';
  late final _name = TextEditingController(text: str(AppState.i.link?['name']));

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
      if (k == 'del') {
        if (_pin.isNotEmpty) _pin = _pin.substring(0, _pin.length - 1);
      } else if (_pin.length < 8) {
        _pin += k;
      }
    });
  }

  Future<void> _login() async {
    final t = AppState.i.t;
    final link = AppState.i.link ?? const {};
    setState(() => _busy = true);
    try {
      final d = obj((await DeskApi(str(link['slug'])).post('/login', {'pin': _pin}))['data']);
      AppState.i.linked({...link, 'token': str(d['token']), 'name': _name.text.trim()});
      widget.onIn();
    } on ApiError catch (e) {
      if (!mounted) return;
      if (e.status == 403 || e.status == 404) return widget.onOff(e.message);
      setState(() {
        _busy = false;
        _pin = '';
        _error = e.status == 401 ? t('scp.pinWrong') : (e.network ? t('app.offline') : e.message);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final t = app.t;
    final c = context.c;
    final link = app.link ?? const {};
    final logo = str(link['logo']);
    return Scaffold(
      backgroundColor: c.appBg,
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 400),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
              children: [
                Row(
                  children: [
                    const Spacer(),
                    const ThemeBtn(),
                    TextButton(
                      onPressed: () => app.setLang(app.lang == 'km' ? 'en' : 'km'),
                      child: Text(app.lang == 'km' ? 'EN' : 'ខ្មែរ', style: const TextStyle(fontWeight: FontWeight.w700)),
                    ),
                  ],
                ),
                Center(
                  child: Container(
                    width: 72,
                    height: 72,
                    clipBehavior: Clip.antiAlias,
                    decoration: BoxDecoration(color: c.active, borderRadius: BorderRadius.circular(22)),
                    child: logo.isNotEmpty ? Image(image: netImage(logo), fit: BoxFit.cover) : Icon(LucideIcons.lock, color: c.brandInk, size: 30),
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  str(link['shop']).isNotEmpty ? str(link['shop']) : t('scp.deskTitle'),
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 21),
                ),
                Muted('${t('scp.deskTitle')} · ${t('scp.pin')}', align: TextAlign.center),
                const DemoPinHint(),
                const SizedBox(height: 18),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    for (var i = 0; i < (_pin.length < 4 ? 4 : _pin.length); i++)
                      Container(
                        width: 16,
                        height: 16,
                        margin: const EdgeInsets.symmetric(horizontal: 7),
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: i < _pin.length ? c.brand : Colors.transparent,
                          border: Border.all(color: i < _pin.length ? c.brand : c.lineStrong, width: 2),
                        ),
                      ),
                  ],
                ),
                if (_error.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 14), child: Alert(_error)),
                const SizedBox(height: 16),
                GridView.count(
                  crossAxisCount: 3,
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  mainAxisSpacing: 10,
                  crossAxisSpacing: 10,
                  childAspectRatio: 1.7,
                  children: [
                    for (final k in ['1', '2', '3', '4', '5', '6', '7', '8', '9', 'del', '0', 'ok'])
                      k == 'ok'
                          ? Btn(t('scp.enter'), busy: _busy, onTap: _pin.length < 4 || _busy ? null : _login)
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
                const SizedBox(height: 16),
                Field(label: t('scp.yourName'), controller: _name, icon: LucideIcons.user, maxLength: 40),
                const SizedBox(height: 8),
                Center(
                  child: TextButton(onPressed: widget.onUnlink, child: Text(t('st.unlink'))),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
