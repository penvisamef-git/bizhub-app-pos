import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../../core/app_state.dart';
import '../../core/format.dart';
import '../../core/printing/printer_settings.dart' show printErrorMessage;
import '../../core/theme.dart';
import '../../widgets/ui.dart';
import 'ts_api.dart';
import 'ts_card.dart';
import 'ts_print.dart';
import '../updates/updates_page.dart';

// Telegram Store staff screen (web: /pos/tg-store): paired with the owner's 6-digit code (link page) → each staff
// member's PIN → orders come in with a sound: New · Making · Ready, accept / reject / ready / done / paid, print a ticket;
// Done today · Products (sold out) · Today (managers: sales of the day, pause / take orders)
class TsStaffRoot extends StatefulWidget {
  const TsStaffRoot({super.key});
  @override
  State<TsStaffRoot> createState() => _TsStaffRootState();
}

class _TsStaffRootState extends State<TsStaffRoot> {
  bool _ready = false;
  bool _pin = true;

  @override
  void initState() {
    super.initState();
    Future.wait([TsStore.init(), TsPrint.load()]).then((_) {
      if (!mounted) return;
      setState(() {
        _ready = true;
        _pin = TsPos.session.isEmpty;
      });
    });
  }

  void _lock() {
    TsStore.set('session', null);
    setState(() => _pin = true);
  }

  void _unpaired() {
    TsStore.clear();
    AppState.i.unlink();
  }

  Future<void> _unpair() async {
    final t = AppState.i.t;
    final ok = await showDialog<bool>(
      context: context,
      builder: (d) => AlertDialog(
        content: Text(tsx('unpairAsk')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(d, false), child: Text(t('app.cancel'))),
          TextButton(
            onPressed: () => Navigator.pop(d, true),
            child: Text(tsx('unpair'), style: TextStyle(color: d.c.danger)),
          ),
        ],
      ),
    );
    if (ok == true) _unpaired();
  }

  // printers · appearance · language · lock · disconnect
  Future<void> _more({VoidCallback? refresh}) async {
    final app = AppState.i;
    final t = app.t;
    final pick = await showModalBottomSheet<String>(
      context: context,
      builder: (s) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (refresh != null) ListTile(leading: const Icon(LucideIcons.refreshCw), title: Text(tsa('refresh')), onTap: () => Navigator.pop(s, 'refresh')),
            ListTile(leading: const Icon(LucideIcons.printer), title: Text(tsa('printers')), onTap: () => Navigator.pop(s, 'print')),
            ListTile(leading: const Icon(LucideIcons.sunMoon), title: Text(t('app.theme')), onTap: () => Navigator.pop(s, 'theme')),
            ListTile(leading: const Icon(LucideIcons.languages), title: Text(app.lang == 'km' ? 'English' : 'ភាសាខ្មែរ'), onTap: () => Navigator.pop(s, 'lang')),
            UpdatesTile(onTap: () => Navigator.pop(s, 'updates')),
            if (!_pin) ListTile(leading: const Icon(LucideIcons.lock), title: Text(tsx('logout')), onTap: () => Navigator.pop(s, 'lock')),
            ListTile(
              leading: Icon(LucideIcons.unlink, color: s.c.danger),
              title: Text(tsx('unpair'), style: TextStyle(color: s.c.danger)),
              onTap: () => Navigator.pop(s, 'unpair'),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (!mounted) return;
    switch (pick) {
      case 'refresh':
        refresh?.call();
      case 'print':
        openTsPrinters(context);
      case 'theme':
        pickTheme(context);
      case 'updates':
        openUpdates(context);
      case 'lang':
        app.setLang(app.lang == 'km' ? 'en' : 'km');
      case 'lock':
        _lock();
      case 'unpair':
        _unpair();
    }
  }

  @override
  Widget build(BuildContext context) {
    AppScope.of(context); // rebuild on language / theme
    if (!_ready) {
      return Scaffold(
        backgroundColor: context.c.appBg,
        body: const Center(child: CircularProgressIndicator()),
      );
    }
    if (_pin) {
      return TsPinPage(onDone: () => setState(() => _pin = false), onUnpaired: _unpaired, onUnpair: _unpair, onMore: () => _more());
    }
    return TsMain(
      onLock: _lock,
      onUnpaired: _unpaired,
      onMore: (refresh) => _more(refresh: refresh),
    );
  }
}

// ---------------------------------------------------------------- the shop's logo
class TsShopMark extends StatelessWidget {
  final double size;
  final String logo;
  const TsShopMark({super.key, this.size = 40, this.logo = ''});
  @override
  Widget build(BuildContext context) {
    final url = logo.isNotEmpty ? logo : str((AppState.i.link ?? const {})['logo']);
    if (url.isEmpty) return TypeIcon('tg_store', size: size);
    return ClipRRect(
      borderRadius: BorderRadius.circular(size * .3),
      child: Image(
        image: netImage(url),
        width: size,
        height: size,
        fit: BoxFit.cover,
        errorBuilder: (_, _, _) => TypeIcon('tg_store', size: size),
      ),
    );
  }
}

// ---------------------------------------------------------------- PIN
class TsPinPage extends StatefulWidget {
  final VoidCallback onDone, onUnpaired, onUnpair, onMore;
  const TsPinPage({super.key, required this.onDone, required this.onUnpaired, required this.onUnpair, required this.onMore});
  @override
  State<TsPinPage> createState() => _TsPinPageState();
}

class _TsPinPageState extends State<TsPinPage> {
  String _pin = '';
  bool _busy = false;
  String _err = '';
  final _focus = FocusNode();

  @override
  void initState() {
    super.initState();
    // still paired? (the owner may have removed this screen) + the newest name and logo
    TsPos.shop()
        .then((r) {
          final shop = obj(obj(r['data'])['shop']);
          final link = AppState.i.link;
          if (link != null && shop.isNotEmpty && (str(shop['name']) != str(link['shop']) || str(shop['logo']) != str(link['logo']))) {
            AppState.i.linked({...link, 'shop': str(shop['name']), 'logo': str(shop['logo'])});
          }
        })
        .catchError((Object e) {
          if (e is ApiError && e.code == 'no_device') widget.onUnpaired();
          return null;
        });
  }

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  Future<void> _press(String k) async {
    if (_busy) return;
    HapticFeedback.selectionClick();
    if (k == 'del') {
      setState(() => _pin = _pin.isEmpty ? '' : _pin.substring(0, _pin.length - 1));
      return;
    }
    final next = (_pin + k).length > 4 ? _pin : _pin + k;
    setState(() {
      _pin = next;
      _err = '';
    });
    if (next.length < 4) return;
    setState(() => _busy = true);
    try {
      final d = obj((await TsPos.login(next))['data']);
      TsStore.set('session', str(d['session']));
      widget.onDone();
    } on ApiError catch (e) {
      if (e.code == 'no_device') return widget.onUnpaired();
      HapticFeedback.heavyImpact();
      if (!mounted) return;
      setState(() {
        _err = e.network ? AppState.i.t('app.offline') : (e.code == 'bad_pin' ? tsx('wrongPin') : e.message);
        _pin = '';
        _busy = false;
      });
    }
  }

  // Mac / Windows: type the PIN on the keyboard
  KeyEventResult _key(FocusNode _, KeyEvent e) {
    if (e is! KeyDownEvent) return KeyEventResult.ignored;
    final ch = e.character ?? '';
    if (RegExp(r'^\d$').hasMatch(ch)) {
      _press(ch);
      return KeyEventResult.handled;
    }
    if (e.logicalKey == LogicalKeyboardKey.backspace) {
      _press('del');
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final link = AppState.i.link ?? const {};
    return Scaffold(
      backgroundColor: c.appBg,
      body: Focus(
        focusNode: _focus,
        autofocus: true,
        onKeyEvent: _key,
        child: SafeArea(
          child: Stack(
            children: [
              Positioned(
                top: 6,
                right: 8,
                child: IconButton(onPressed: widget.onMore, icon: const Icon(LucideIcons.ellipsisVertical), tooltip: tsa('more')),
              ),
              Center(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(24, 40, 24, 24),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 360),
                    child: Column(
                      children: [
                        const TsShopMark(size: 64),
                        const SizedBox(height: 10),
                        Text(
                          str(link['shop']),
                          textAlign: TextAlign.center,
                          style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
                        ),
                        Text(str(obj(link['device'])['name']), style: TextStyle(color: c.muted, fontSize: 13)),
                        const SizedBox(height: 22),
                        Text(tsx('pinTitle'), style: Theme.of(context).textTheme.headlineSmall),
                        const SizedBox(height: 4),
                        Muted(tsx('pinSub'), align: TextAlign.center),
                        const DemoPinHint(),
                        const SizedBox(height: 20),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            for (var i = 0; i < 4; i++)
                              AnimatedContainer(
                                duration: const Duration(milliseconds: 150),
                                width: 18,
                                height: 18,
                                margin: const EdgeInsets.symmetric(horizontal: 9),
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: i < _pin.length ? (_err.isNotEmpty ? c.danger : c.brand) : Colors.transparent,
                                  border: Border.all(color: _err.isNotEmpty ? c.danger : (i < _pin.length ? c.brand : c.lineStrong), width: 2),
                                ),
                              ),
                          ],
                        ),
                        if (_err.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 14), child: Alert(_err)),
                        const SizedBox(height: 20),
                        GridView.count(
                          crossAxisCount: 3,
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          mainAxisSpacing: 12,
                          crossAxisSpacing: 12,
                          childAspectRatio: 1.45,
                          children: [
                            for (final k in ['1', '2', '3', '4', '5', '6', '7', '8', '9', '', '0', 'del'])
                              k.isEmpty
                                  ? const SizedBox.shrink()
                                  : Material(
                                      color: c.card,
                                      borderRadius: BorderRadius.circular(18),
                                      child: InkWell(
                                        borderRadius: BorderRadius.circular(18),
                                        onTap: _busy ? null : () => _press(k),
                                        child: Center(
                                          child: k == 'del' ? Icon(LucideIcons.delete, color: c.ink) : Text(k, style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w700)),
                                        ),
                                      ),
                                    ),
                          ],
                        ),
                        if (_busy) const Padding(padding: EdgeInsets.only(top: 16), child: CircularProgressIndicator()),
                        const SizedBox(height: 14),
                        TextButton.icon(
                          onPressed: widget.onUnpair,
                          icon: Icon(LucideIcons.unlink, size: 15, color: c.muted),
                          label: Text(tsx('unpair'), style: TextStyle(color: c.muted)),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------- the staff screen
const _cols = [
  ('new', ['new']),
  ('making', ['accepted']),
  ('ready', ['ready', 'on_way']),
];

class TsMain extends StatefulWidget {
  final VoidCallback onLock, onUnpaired;
  final void Function(VoidCallback refresh) onMore;
  const TsMain({super.key, required this.onLock, required this.onUnpaired, required this.onMore});
  @override
  State<TsMain> createState() => _TsMainState();
}

class _TsMainState extends State<TsMain> with WidgetsBindingObserver {
  Json? _boot;
  List<Json>? _orders;
  Json _counts = const {};
  bool? _open;
  Json _openNow = const {};
  bool _offline = false;
  DateTime? _at;
  bool _sound = true;
  Json? _flash;
  String _busy = '';
  String _tab = 'orders';
  String _col = 'new';
  Set<String>? _seen;
  Timer? _poll, _ring, _flashOff;
  bool _front = true;
  int _ticks = 0;
  int _doneKey = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WakelockPlus.enable().catchError((_) {});
    final s = TsStore.get('sound');
    _sound = s is bool ? s : true;
    _loadBoot();
    _load();
    // every 5 s while the screen is in front, every 15 s behind other apps
    _poll = Timer.periodic(const Duration(seconds: 5), (_) {
      _ticks++;
      if (_front || _ticks % 3 == 0) _load();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    WakelockPlus.disable().catchError((_) {});
    _poll?.cancel();
    _ring?.cancel();
    _flashOff?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _front = state == AppLifecycleState.resumed;
    if (_front) _load();
  }

  void _fail(Object e) {
    if (e is! ApiError) return;
    if (e.code == 'no_device') return widget.onUnpaired();
    if (e.code == 'login' || e.status == 401) return widget.onLock();
    if (e.network && mounted) setState(() => _offline = true);
  }

  Future<void> _loadBoot() async {
    try {
      final d = obj((await TsPos.boot())['data']);
      if (!mounted) return;
      setState(() {
        _boot = d;
        _counts = obj(d['counts']);
        _open = d['open'] != false;
        _openNow = obj(d['open_now']);
      });
    } catch (e) {
      _fail(e);
    }
  }

  Future<void> _load() async {
    try {
      final r = await TsPos.orders('open');
      if (!mounted) return;
      final list = objs(r['data']);
      final fresh = list.where((o) => o['status'] == 'new').toList();
      Json? arrived;
      if (_seen != null) {
        final news = fresh.where((o) => !_seen!.contains(str(o['_id']))).toList();
        if (news.isNotEmpty) arrived = news.last;
      }
      _seen = {...?_seen, ...list.map((o) => str(o['_id']))};
      setState(() {
        _offline = false;
        _at = DateTime.now();
        _orders = list;
        _counts = obj(r['counts']);
        _open = r['open'] != false;
        _openNow = obj(r['open_now']);
        if (arrived != null) {
          _flash = arrived;
          if (_tab == 'orders') _col = 'new';
        }
      });
      if (arrived != null) {
        _flashOff?.cancel();
        _flashOff = Timer(const Duration(seconds: 6), () => mounted ? setState(() => _flash = null) : null);
        if (_sound) TsSound.chime();
      }
      _syncRing();
    } catch (e) {
      _fail(e);
    }
  }

  int get _waiting => (_orders ?? const []).where((o) => o['status'] == 'new').length;

  // ring every 6 s while an order waits for someone to accept it
  void _syncRing() {
    if (_waiting > 0 && _sound) {
      if (_ring != null) return;
      TsSound.chime();
      _ring = Timer.periodic(const Duration(seconds: 6), (_) => TsSound.chime());
    } else {
      _ring?.cancel();
      _ring = null;
    }
  }

  void _toggleSound() {
    setState(() => _sound = !_sound);
    TsStore.set('sound', _sound);
    if (_sound) TsSound.chime();
    _ring?.cancel();
    _ring = null;
    _syncRing();
  }

  bool get _readOnly => _boot?['read_only'] == true;
  bool get _manager => obj(_boot?['staff'])['role'] == 'manager';
  Json get _shop => obj(_boot?['shop']);
  String get _cur => str(_shop['currency']);
  String get _shopName => str(_shop['name']).isNotEmpty ? str(_shop['name']) : str((AppState.i.link ?? const {})['shop']);

  Future<void> _act(Json o, String status, [Json extra = const {}]) async {
    final oid = str(o['_id']);
    setState(() => _busy = oid);
    try {
      final r = status == 'paid'
          ? await TsPos.paid(oid)
          : status == 'riders'
          ? await TsPos.toRiders(oid)
          : await TsPos.move(oid, status, extra);
      final d = obj(r['data']);
      if (!mounted) return;
      setState(() {
        final list = _orders ?? [];
        _orders = ['done', 'cancelled'].contains(d['status']) ? list.where((y) => y['_id'] != oid).toList() : [for (final y in list) y['_id'] == oid ? d : y];
      });
      _syncRing();
      if (status == 'accepted' && TsPrint.auto && TsPrint.conf.on) _print(d, quiet: true);
      _load();
    } catch (e) {
      _fail(e);
      if (e is ApiError && !e.network && mounted) toast(context, e.message);
      _load();
    } finally {
      if (mounted) setState(() => _busy = '');
    }
  }

  Future<void> _print(Json o, {bool quiet = false}) async {
    await TsPrint.load();
    if (!mounted) return;
    if (!TsPrint.conf.on) {
      toast(context, tsa('noPrinter'));
      openTsPrinters(context);
      return;
    }
    try {
      await TsPrint.ticket(o, _shopName);
      if (mounted && !quiet) toast(context, tsa('printed'));
    } catch (e) {
      if (mounted) toast(context, '${AppState.i.t('rp.failed')} ${printErrorMessage(e)}');
    }
  }

  Future<void> _toggleOpen() async {
    try {
      final d = obj((await TsPos.setOpen(!(_open ?? true)))['data']);
      if (!mounted) return;
      setState(() {
        _open = d['open'] != false;
        if (d['open_now'] is Map) _openNow = obj(d['open_now']);
      });
    } catch (e) {
      _fail(e);
      if (e is ApiError && !e.network && mounted) toast(context, e.message);
    }
  }

  Widget _printBtn(Json o) => Btn(tsx('print'), icon: LucideIcons.printer, small: true, kind: BtnKind.ghost, onTap: () => _print(o), key: ValueKey('ts-print-${o['no']}'));

  @override
  Widget build(BuildContext context) {
    AppScope.of(context);
    final c = context.c;
    final staff = obj(_boot?['staff']);
    final tabs = ['orders', 'done', 'products', if (_manager) 'today'];
    if (!tabs.contains(_tab)) _tab = 'orders';
    const icons = {'orders': LucideIcons.receiptText, 'done': LucideIcons.circleCheck, 'products': LucideIcons.package, 'today': LucideIcons.chartColumn};
    final waiting = _waiting;
    final body = switch (_tab) {
      'done' => TsDoneView(key: ValueKey('done$_doneKey'), act: _act, busy: _busy, readOnly: _readOnly, ridersOn: _shop['riders'] == true, printBtn: _printBtn, fail: _fail),
      'products' => TsProductsView(cur: _cur, readOnly: _readOnly, fail: _fail),
      'today' => TsTodayView(counts: _counts, fail: _fail),
      _ => _board(context),
    };
    return Scaffold(
      backgroundColor: c.appBg,
      appBar: AppBar(
        backgroundColor: c.appBg,
        surfaceTintColor: Colors.transparent,
        titleSpacing: 16,
        title: Row(
          children: [
            TsShopMark(size: 38, logo: str(_shop['logo'])),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _shopName,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
                  ),
                  Text(
                    [str(staff['name']), if (_manager) tsx('manager'), str(obj(_boot?['device'])['name'])].where((x) => x.isNotEmpty).join(' · '),
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: c.muted, fontSize: 12.5),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            key: const ValueKey('ts-sound'),
            onPressed: _toggleSound,
            icon: Icon(_sound ? LucideIcons.bell : LucideIcons.bellOff, color: _sound ? c.ink : c.muted),
            tooltip: _sound ? tsx('soundOn') : tsx('soundOff'),
          ),
          IconButton(key: const ValueKey('ts-lock'), onPressed: widget.onLock, icon: const Icon(LucideIcons.lock), tooltip: tsx('logout')),
          IconButton(
            onPressed: () => widget.onMore(() {
              _loadBoot();
              _load();
              setState(() => _doneKey++);
            }),
            icon: const Icon(LucideIcons.ellipsisVertical),
            tooltip: tsa('more'),
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            if (_offline) _Bar(icon: LucideIcons.wifiOff, text: tsx('offline'), tone: Tone.danger),
            if (_readOnly) _Bar(icon: LucideIcons.lock, text: tsx('readOnly'), tone: Tone.warn),
            AnimatedSize(
              duration: const Duration(milliseconds: 200),
              child: _flash == null
                  ? const SizedBox(width: double.infinity)
                  : GestureDetector(
                      onTap: () => setState(() {
                        _flash = null;
                        _tab = 'orders';
                        _col = 'new';
                      }),
                      child: Container(
                        key: const ValueKey('ts-flash'),
                        width: double.infinity,
                        margin: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                        decoration: BoxDecoration(gradient: c.gradient, borderRadius: BorderRadius.circular(16), boxShadow: c.orangeShadow),
                        child: Row(
                          children: [
                            const Icon(LucideIcons.bellRing, color: Colors.white, size: 20),
                            const SizedBox(width: 10),
                            Text(
                              tsx('newOrder', {'n': _flash!['no']}),
                              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 16),
                            ),
                          ],
                        ),
                      ),
                    ),
            ),
            Expanded(child: body),
          ],
        ),
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: tabs.indexOf(_tab),
        onDestinationSelected: (i) => setState(() => _tab = tabs[i]),
        destinations: [
          for (final k in tabs)
            NavigationDestination(
              icon: k == 'orders' && waiting > 0 ? Badge(label: Text('$waiting'), child: Icon(icons[k])) : Icon(icons[k]),
              label: tsx('tabs.$k'),
            ),
        ],
      ),
    );
  }

  // the status line: taking orders / paused (managers tap to change) · updated hh:mm
  Widget _state(BuildContext context) {
    final c = context.c;
    if (_open == null) return const SizedBox.shrink();
    final state = _open == false ? 'paused' : (_openNow['open'] == false ? 'hours' : 'on');
    final (bg, fg) = switch (state) {
      'on' => (c.goodBg, c.good),
      'paused' => (c.dangerBg, c.danger),
      _ => (c.warnBg, c.warn),
    };
    final can = _manager && !_readOnly;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
      child: Row(
        children: [
          Material(
            color: bg,
            borderRadius: BorderRadius.circular(999),
            child: InkWell(
              key: const ValueKey('ts-open'),
              borderRadius: BorderRadius.circular(999),
              onTap: can ? _toggleOpen : null,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(state == 'on' ? LucideIcons.play : LucideIcons.pause, size: 14, color: fg),
                    const SizedBox(width: 6),
                    Text(
                      state == 'on' ? tsx('taking') : (state == 'paused' ? tsx('paused') : tsx('closedHours')),
                      style: TextStyle(color: fg, fontWeight: FontWeight.w800, fontSize: 13),
                    ),
                    if (can) ...[
                      const SizedBox(width: 8),
                      Text(
                        '· ${_open == true ? tsx('pause') : tsx('resume')}',
                        style: TextStyle(color: fg, fontSize: 12.5, fontWeight: FontWeight.w600),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
          const Spacer(),
          if (_at != null && !_offline) Text(tsx('updated', {'time': fmtTime(_at!.toUtc().toIso8601String())}), style: TextStyle(color: c.muted, fontSize: 12)),
        ],
      ),
    );
  }

  Widget _board(BuildContext context) {
    final c = context.c;
    final orders = _orders;
    List<Json> rows(List<String> sts) => (orders ?? const <Json>[]).where((o) => sts.contains(o['status'])).toList();
    Widget list(String k, List<String> sts, {bool header = false}) {
      final r = rows(sts);
      return RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          key: PageStorageKey('ts-col-$k'),
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
          children: [
            if (header)
              Padding(
                padding: const EdgeInsets.only(bottom: 10, top: 2),
                child: Row(
                  children: [
                    Text(tsx('cols.$k'), style: Theme.of(context).textTheme.titleMedium),
                    const SizedBox(width: 8),
                    Chip2('${r.length}', tone: k == 'new' && r.isNotEmpty ? Tone.brand : Tone.muted),
                  ],
                ),
              ),
            if (orders == null)
              const SkelList(rows: 2)
            else if (r.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 40),
                child: Column(
                  children: [
                    Icon(k == 'new' ? LucideIcons.inbox : (k == 'making' ? LucideIcons.chefHat : LucideIcons.packageCheck), color: c.muted, size: 30),
                    const SizedBox(height: 8),
                    Muted(tsx('empty.$k'), align: TextAlign.center),
                  ],
                ),
              )
            else
              for (final o in r) TsOrderCard(key: ValueKey(o['_id']), o: o, act: _act, busy: _busy == o['_id'], readOnly: _readOnly, ridersOn: _shop['riders'] == true, extra: _printBtn(o)),
          ],
        ),
      );
    }

    return LayoutBuilder(
      builder: (context, box) {
        final wide = box.maxWidth >= 900;
        return Column(
          children: [
            _state(context),
            if (!wide)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                child: Row(
                  children: [
                    for (final (k, sts) in _cols)
                      Expanded(
                        child: Padding(
                          padding: EdgeInsets.only(right: k == 'ready' ? 0 : 8),
                          child: _ColPick(
                            key: ValueKey('ts-colpick-$k'),
                            label: tsx('cols.$k').split(' · ').first, // "Ready" (the column also has "on the way")
                            count: rows(sts).length,
                            on: _col == k,
                            hot: k == 'new' && rows(sts).isNotEmpty,
                            onTap: () => setState(() => _col = k),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            Expanded(
              child: wide
                  ? Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [for (final (k, sts) in _cols) Expanded(child: list(k, sts, header: true))],
                      ),
                    )
                  : list(_col, _cols.firstWhere((x) => x.$1 == _col).$2),
            ),
          ],
        );
      },
    );
  }
}

class _ColPick extends StatelessWidget {
  final String label;
  final int count;
  final bool on, hot;
  final VoidCallback onTap;
  const _ColPick({super.key, required this.label, required this.count, required this.on, required this.hot, required this.onTap});
  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Material(
      color: on ? c.solid : c.card,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
          child: Column(
            children: [
              Text(
                '$count',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, height: 1.1, color: hot && !on ? c.brand : (on ? c.onSolid : c.ink)),
              ),
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: on ? c.onSolid : c.muted),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Bar extends StatelessWidget {
  final IconData icon;
  final String text;
  final Tone tone;
  const _Bar({required this.icon, required this.text, required this.tone});
  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final (bg, fg) = tone == Tone.danger ? (c.dangerBg, c.danger) : (c.warnBg, c.warn);
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(14)),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 16, color: fg),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: TextStyle(color: fg, fontWeight: FontWeight.w600, fontSize: 13.5),
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------- done today
class TsDoneView extends StatefulWidget {
  final TsAct act;
  final String busy;
  final bool readOnly, ridersOn;
  final Widget Function(Json o) printBtn;
  final void Function(Object e) fail;
  const TsDoneView({super.key, required this.act, required this.busy, required this.readOnly, required this.ridersOn, required this.printBtn, required this.fail});
  @override
  State<TsDoneView> createState() => _TsDoneViewState();
}

class _TsDoneViewState extends State<TsDoneView> {
  List<Json>? _rows;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final r = await TsPos.orders('done');
      if (mounted) setState(() => _rows = objs(r['data']));
    } catch (e) {
      widget.fail(e);
      if (mounted) setState(() => _rows ??= []);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final rows = _rows;
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
        children: [
          Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 760),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (rows == null)
                    const SkelList(rows: 3)
                  else if (rows.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 48),
                      child: Column(
                        children: [
                          Icon(LucideIcons.circleCheck, color: c.muted, size: 30),
                          const SizedBox(height: 8),
                          Muted(tsx('noDone'), align: TextAlign.center),
                        ],
                      ),
                    )
                  else
                    for (final o in rows)
                      TsOrderCard(
                        key: ValueKey(o['_id']),
                        o: o,
                        busy: widget.busy == o['_id'],
                        readOnly: widget.readOnly,
                        ridersOn: widget.ridersOn,
                        extra: widget.printBtn(o),
                        act: (o, s, [e = const {}]) async {
                          await widget.act(o, s, e);
                          await _load();
                        },
                      ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------- products: on sale / sold out
class TsProductsView extends StatefulWidget {
  final String cur;
  final bool readOnly;
  final void Function(Object e) fail;
  const TsProductsView({super.key, required this.cur, required this.readOnly, required this.fail});
  @override
  State<TsProductsView> createState() => _TsProductsViewState();
}

class _TsProductsViewState extends State<TsProductsView> {
  List<Json>? _list;
  List<Json> _cats = const [];
  String _q = '', _cat = '', _busy = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final r = await TsPos.products();
      if (!mounted) return;
      setState(() {
        _list = objs(r['data']);
        _cats = objs(r['categories']);
      });
    } catch (e) {
      widget.fail(e);
      if (mounted) setState(() => _list ??= []);
    }
  }

  Future<void> _flip(Json p) async {
    final pid = str(p['_id']);
    setState(() => _busy = pid);
    try {
      final d = obj((await TsPos.soldOut(pid, p['sold_out'] != true))['data']);
      if (mounted) {
        setState(
          () => _list = [
            for (final y in _list ?? <Json>[]) y['_id'] == pid ? (d.isEmpty ? {...y, 'sold_out': p['sold_out'] != true} : d) : y,
          ],
        );
      }
    } catch (e) {
      widget.fail(e);
      if (e is ApiError && !e.network && mounted) toast(context, e.message);
    } finally {
      if (mounted) setState(() => _busy = '');
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final km = AppState.i.lang == 'km';
    String name(Json x) => km && str(x['name_km']).isNotEmpty ? str(x['name_km']) : str(x['name']);
    final all = _list;
    final q = _q.toLowerCase();
    final list = (all ?? const <Json>[])
        .where((p) => (_cat.isEmpty || str(p['category_id']) == _cat) && (q.isEmpty || name(p).toLowerCase().contains(q) || str(p['name']).toLowerCase().contains(q)))
        .toList();
    Widget chip(String id, String label) => Padding(
      padding: const EdgeInsets.only(right: 8),
      child: ChoiceChip(selected: _cat == id, onSelected: (_) => setState(() => _cat = id), label: Text(label)),
    );
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
        children: [
          TextField(
            onChanged: (v) => setState(() => _q = v.trim()),
            decoration: InputDecoration(
              prefixIcon: const Icon(LucideIcons.search, size: 18),
              hintText: tsx('search'),
              filled: true,
              fillColor: c.card,
              isDense: true,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: BorderSide(color: c.line),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: BorderSide(color: c.line),
              ),
            ),
          ),
          const SizedBox(height: 10),
          SizedBox(
            height: 40,
            child: ListView(scrollDirection: Axis.horizontal, children: [chip('', tsx('all')), for (final x in _cats) chip(str(x['_id']), name(x))]),
          ),
          const SizedBox(height: 10),
          if (all == null)
            const SkelList(rows: 4)
          else
            LayoutBuilder(
              builder: (context, box) {
                final cols = box.maxWidth >= 1000 ? 3 : (box.maxWidth >= 640 ? 2 : 1);
                final w = (box.maxWidth - 10 * (cols - 1)) / cols;
                return Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    for (final p in list)
                      SizedBox(
                        width: w,
                        child: _ProdRow(p: p, name: name(p), cur: widget.cur, busy: _busy == p['_id'], off: widget.readOnly, onFlip: () => _flip(p)),
                      ),
                  ],
                );
              },
            ),
        ],
      ),
    );
  }
}

class _ProdRow extends StatelessWidget {
  final Json p;
  final String name, cur;
  final bool busy, off;
  final VoidCallback onFlip;
  const _ProdRow({required this.p, required this.name, required this.cur, required this.busy, required this.off, required this.onFlip});
  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final out = p['sold_out'] == true;
    final photo = photoUrl(p['photo']);
    return Opacity(
      opacity: out ? .7 : 1,
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: c.card,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: out ? c.danger.withValues(alpha: .35) : c.line),
        ),
        child: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Container(
                width: 50,
                height: 50,
                color: c.chip,
                child: photo.isEmpty
                    ? Icon(LucideIcons.package, color: c.muted, size: 22)
                    : Image(
                        image: netImage(photo),
                        fit: BoxFit.cover,
                        errorBuilder: (_, _, _) => Icon(LucideIcons.package, color: c.muted, size: 22),
                      ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15, decoration: out ? TextDecoration.lineThrough : null),
                  ),
                  Text('${tsMoney(p['price'], cur)}${p['stock'] != null ? ' · ${tsx('left', {'n': p['stock']})}' : ''}', style: TextStyle(color: c.muted, fontSize: 13)),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Material(
              color: out ? c.dangerBg : c.goodBg,
              borderRadius: BorderRadius.circular(999),
              child: InkWell(
                key: ValueKey('ts-sold-${p['name']}'),
                borderRadius: BorderRadius.circular(999),
                onTap: off || busy ? null : onFlip,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (busy)
                        Padding(
                          padding: const EdgeInsets.only(right: 6),
                          child: SizedBox(width: 12, height: 12, child: CircularProgressIndicator(strokeWidth: 2, color: out ? c.danger : c.good)),
                        )
                      else
                        Padding(
                          padding: const EdgeInsets.only(right: 6),
                          child: Icon(out ? LucideIcons.circleSlash : LucideIcons.circleCheck, size: 14, color: out ? c.danger : c.good),
                        ),
                      Text(
                        out ? tsx('soldOut') : tsx('available'),
                        style: TextStyle(color: out ? c.danger : c.good, fontWeight: FontWeight.w800, fontSize: 13),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------- today (managers)
class TsTodayView extends StatefulWidget {
  final Json counts;
  final void Function(Object e) fail;
  const TsTodayView({super.key, required this.counts, required this.fail});
  @override
  State<TsTodayView> createState() => _TsTodayViewState();
}

class _TsTodayViewState extends State<TsTodayView> {
  Json? _d;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final r = await TsPos.today();
      if (mounted) setState(() => _d = obj(r['data']));
    } catch (e) {
      widget.fail(e);
      if (mounted) setState(() => _d ??= {});
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final d = _d;
    if (d == null) {
      return const Padding(padding: EdgeInsets.all(16), child: SkelList(rows: 3));
    }
    final cur = str(d['currency']);
    final total = n(d['total']), paid = n(d['paid']);
    Widget kpi(String k, String v, {bool hot = false}) => Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: hot ? c.active : c.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: hot ? c.brand : c.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            k,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 12.5, color: c.muted),
          ),
          const SizedBox(height: 2),
          Text(
            v,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: hot ? c.brandInk : c.ink),
          ),
        ],
      ),
    );
    Widget sums(String title, Json m, String Function(String k) label) => Panel(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(title, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          if (m.isEmpty) Muted('—'),
          for (final e in m.entries)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Row(
                children: [
                  Expanded(child: Text(label(e.key))),
                  Text(tsMoney(e.value, cur), style: const TextStyle(fontWeight: FontWeight.w800)),
                ],
              ),
            ),
        ],
      ),
    );
    final t = AppState.i.t;
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
        children: [
          LayoutBuilder(
            builder: (context, box) {
              final cols = box.maxWidth >= 640 ? 4 : 2;
              final w = (box.maxWidth - 10 * (cols - 1)) / cols;
              return Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  for (final x in [
                    kpi(tsx('orders'), fmt(n(d['orders']))),
                    kpi(tsx('sales'), tsMoney(total, cur), hot: true),
                    kpi(tsx('paid'), tsMoney(paid, cur)),
                    kpi(tsx('unpaid'), tsMoney(total - paid < 0 ? 0 : total - paid, cur)),
                  ])
                    SizedBox(width: w, child: x),
                ],
              );
            },
          ),
          const SizedBox(height: 12),
          LayoutBuilder(
            builder: (context, box) {
              final a = sums(tsx('byPay'), obj(d['by_pay']), (k) => t.maybe('tsx.payMethods.$k') ?? t.maybe('ts.payMethods.$k') ?? k);
              final b = sums(tsx('byMode'), obj(d['by_mode']), (k) => t.maybe('tsx.modes.$k') ?? t.maybe('ts.modes.$k') ?? k);
              if (box.maxWidth < 640) return Column(children: [a, const SizedBox(height: 12), b]);
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: a),
                  const SizedBox(width: 12),
                  Expanded(child: b),
                ],
              );
            },
          ),
          const SizedBox(height: 12),
          if (widget.counts['new'] != null) Center(child: Muted(tsx('newOrders', {'n': widget.counts['new']}))),
        ],
      ),
    );
  }
}
