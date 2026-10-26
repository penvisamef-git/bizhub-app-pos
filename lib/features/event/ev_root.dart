import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../../core/app_state.dart';
import '../../core/theme.dart';
import '../../widgets/ui.dart';
import 'ev_api.dart';
import 'ev_ctl.dart';
import 'ev_live.dart';
import 'ev_print.dart';
import 'ev_scan.dart';
import 'ev_tabs.dart';
import '../updates/updates_page.dart';

// Event Tickets door phone (web: /pos/event): paired with the organiser's 6-digit code (link page) →
// each team member's PIN → choose the event → Scan (works offline) · Live · Guests · Sell at the gate · Orders
class EvDoorRoot extends StatefulWidget {
  const EvDoorRoot({super.key});
  @override
  State<EvDoorRoot> createState() => _EvDoorRootState();
}

class _EvDoorRootState extends State<EvDoorRoot> {
  bool _ready = false;
  String _stage = 'pin'; // pin | boot | main
  Json? _boot;
  Json? _event;
  String _err = '';

  @override
  void initState() {
    super.initState();
    EvStore.init().then((_) {
      if (!mounted) return;
      setState(() {
        _ready = true;
        _stage = EvDoor.session.isEmpty ? 'pin' : 'boot';
      });
      if (_stage == 'boot') _loadBoot();
    });
  }

  Future<void> _loadBoot() async {
    setState(() => _err = '');
    try {
      final d = obj((await EvDoor.boot())['data']);
      EvStore.set('boot', d);
      if (!mounted) return;
      setState(() {
        _boot = d;
        _stage = 'main';
        // the open event gets the newest numbers
        if (_event != null) _event = objs(d['events']).firstWhere((e) => e['_id'] == _event!['_id'], orElse: () => _event!);
      });
    } on ApiError catch (e) {
      if (!mounted) return;
      if (e.code == 'no_device') return _unpaired();
      if (e.status == 401) return _logout();
      final cached = EvStore.map('boot');
      if (e.network && cached.isNotEmpty) {
        setState(() {
          _boot = cached;
          _stage = 'main';
        });
      } else {
        setState(() => _err = e.network ? AppState.i.t('app.offline') : e.message);
      }
    }
  }

  void _logout() {
    EvStore.set('session', null);
    setState(() {
      _event = null;
      _boot = null;
      _stage = 'pin';
    });
  }

  void _unpaired() {
    EvStore.clear();
    AppState.i.unlink();
  }

  Future<void> _unpair() async {
    final t = AppState.i.t;
    final ok = await showDialog<bool>(
      context: context,
      builder: (d) => AlertDialog(
        content: Text(ev('unpairSure')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(d, false), child: Text(t('app.cancel'))),
          TextButton(
            onPressed: () => Navigator.pop(d, true),
            child: Text(ev('unpair'), style: TextStyle(color: d.c.danger)),
          ),
        ],
      ),
    );
    if (ok == true) _unpaired();
  }

  Future<void> _more() async {
    final app = AppState.i;
    final t = app.t;
    final pick = await showModalBottomSheet<String>(
      context: context,
      builder: (s) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (_stage == 'main') ListTile(leading: const Icon(LucideIcons.refreshCw), title: Text(t('evx.refresh')), onTap: () => Navigator.pop(s, 'refresh')),
            ListTile(leading: const Icon(LucideIcons.printer), title: Text(t('evx.printers')), onTap: () => Navigator.pop(s, 'print')),
            ListTile(leading: const Icon(LucideIcons.sunMoon), title: Text(t('app.theme')), onTap: () => Navigator.pop(s, 'theme')),
            ListTile(leading: const Icon(LucideIcons.languages), title: Text(app.lang == 'km' ? 'English' : 'ភាសាខ្មែរ'), onTap: () => Navigator.pop(s, 'lang')),
            UpdatesTile(onTap: () => Navigator.pop(s, 'updates')),
            if (_stage == 'main') ListTile(leading: const Icon(LucideIcons.logOut), title: Text(ev('logout')), onTap: () => Navigator.pop(s, 'logout')),
            ListTile(
              leading: Icon(LucideIcons.unlink, color: s.c.danger),
              title: Text(ev('unpair'), style: TextStyle(color: s.c.danger)),
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
        _loadBoot();
      case 'print':
        openEvPrinters(context);
      case 'theme':
        pickTheme(context);
      case 'updates':
        openUpdates(context);
      case 'lang':
        app.setLang(app.lang == 'km' ? 'en' : 'km');
      case 'logout':
        _logout();
      case 'unpair':
        _unpair();
    }
  }

  @override
  Widget build(BuildContext context) {
    AppScope.of(context); // rebuild on language / theme
    final c = context.c;
    if (!_ready) {
      return Scaffold(
        backgroundColor: c.appBg,
        body: const Center(child: CircularProgressIndicator()),
      );
    }
    if (_stage == 'pin') {
      return EvPinPage(
        onMore: _more,
        onDone: () {
          setState(() => _stage = 'boot');
          _loadBoot();
        },
        onUnpaired: _unpaired,
      );
    }
    if (_boot == null) {
      return Scaffold(
        backgroundColor: c.appBg,
        body: SafeArea(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: _err.isEmpty ? const CircularProgressIndicator() : LoadError(text: _err, retry: AppState.i.t('app.retry'), onRetry: _loadBoot),
            ),
          ),
        ),
      );
    }
    if (_event == null) {
      return EvEventsPage(boot: _boot!, onPick: (e) => setState(() => _event = e), onRefresh: _loadBoot, onMore: _more, onUnpair: _unpair);
    }
    return EvEventScreen(
      key: ValueKey(_event!['_id']),
      boot: _boot!,
      event: _event!,
      onBack: () {
        setState(() => _event = null);
        _loadBoot();
      },
      onLogout: _logout,
      onMore: _more,
    );
  }
}

// ---------------------------------------------------------------- the organiser's logo / name
class _OrgMark extends StatelessWidget {
  final double size;
  const _OrgMark({this.size = 40});
  @override
  Widget build(BuildContext context) {
    final logo = str((AppState.i.link ?? const {})['logo']);
    final c = context.c;
    if (logo.isNotEmpty) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(size * .3),
        child: Image(
          image: netImage(logo),
          width: size,
          height: size,
          fit: BoxFit.cover,
          errorBuilder: (_, _, _) => TypeIcon('event', size: size),
        ),
      );
    }
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(color: c.active, borderRadius: BorderRadius.circular(size * .3)),
      child: Icon(LucideIcons.ticket, color: c.brandInk, size: size * .5),
    );
  }
}

// ---------------------------------------------------------------- PIN
class EvPinPage extends StatefulWidget {
  final VoidCallback onDone, onUnpaired, onMore;
  const EvPinPage({super.key, required this.onDone, required this.onUnpaired, required this.onMore});
  @override
  State<EvPinPage> createState() => _EvPinPageState();
}

class _EvPinPageState extends State<EvPinPage> {
  String _pin = '';
  bool _busy = false;
  String _err = '';

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
      final d = obj((await EvDoor.login(next))['data']);
      EvStore.set('session', str(d['session']));
      widget.onDone();
    } on ApiError catch (e) {
      if (e.code == 'no_device') return widget.onUnpaired();
      HapticFeedback.heavyImpact();
      if (!mounted) return;
      setState(() {
        _err = e.network ? AppState.i.t('app.offline') : (e.code == 'bad_pin' ? ev('wrongPin') : e.message);
        _pin = '';
        _busy = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final link = AppState.i.link ?? const {};
    return Scaffold(
      backgroundColor: c.appBg,
      body: SafeArea(
        child: Stack(
          children: [
            Positioned(
              top: 6,
              right: 8,
              child: IconButton(onPressed: widget.onMore, icon: const Icon(LucideIcons.ellipsisVertical), tooltip: AppState.i.t('evx.more')),
            ),
            Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(24, 40, 24, 24),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 360),
                  child: Column(
                    children: [
                      const _OrgMark(size: 64),
                      const SizedBox(height: 10),
                      Text(
                        str(link['shop']),
                        textAlign: TextAlign.center,
                        style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
                      ),
                      Text(str(obj(link['device'])['name']), style: TextStyle(color: c.muted, fontSize: 13)),
                      const SizedBox(height: 22),
                      Text(ev('pinTitle'), style: Theme.of(context).textTheme.headlineSmall),
                      const SizedBox(height: 4),
                      Muted(ev('pinSub'), align: TextAlign.center),
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

// ---------------------------------------------------------------- choose the event
class EvEventsPage extends StatelessWidget {
  final Json boot;
  final ValueChanged<Json> onPick;
  final Future<void> Function() onRefresh;
  final VoidCallback onMore, onUnpair;
  const EvEventsPage({super.key, required this.boot, required this.onPick, required this.onRefresh, required this.onMore, required this.onUnpair});

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final member = obj(boot['member']);
    final role = ev('roles.${member['role']}');
    final events = objs(boot['events']);
    final org = obj(boot['org']);
    return Scaffold(
      backgroundColor: c.appBg,
      appBar: AppBar(
        backgroundColor: c.appBg,
        surfaceTintColor: Colors.transparent,
        titleSpacing: 16,
        title: Row(
          children: [
            const _OrgMark(size: 38),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    str(org['name']),
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
                  ),
                  Text(
                    '${member['name']} · $role',
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: c.muted, fontSize: 12.5),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [IconButton(onPressed: onMore, icon: const Icon(LucideIcons.ellipsisVertical), tooltip: AppState.i.t('evx.more'))],
      ),
      body: RefreshIndicator(
        onRefresh: onRefresh,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 28),
          children: [
            Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 720),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Panel(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(ev('hello', {'name': member['name']}), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 18)),
                          const SizedBox(height: 2),
                          Text(
                            [str(obj(boot['device'])['name']), role, if (boot['read_only'] == true) ev('readOnly')].where((x) => x.isNotEmpty).join(' · '),
                            style: TextStyle(color: c.muted, fontSize: 13),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 18),
                    Text(ev('events'), style: Theme.of(context).textTheme.titleLarge),
                    const SizedBox(height: 10),
                    if (events.isEmpty)
                      Panel(
                        child: Column(
                          children: [
                            Icon(LucideIcons.calendarX, color: c.muted, size: 30),
                            const SizedBox(height: 8),
                            Muted(ev('noEvents'), align: TextAlign.center),
                          ],
                        ),
                      ),
                    for (final e in events)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: _EventCard(e: e, onTap: () => onPick(e)),
                      ),
                    const SizedBox(height: 10),
                    Center(
                      child: TextButton.icon(
                        onPressed: onUnpair,
                        icon: Icon(LucideIcons.unlink, size: 15, color: c.muted),
                        label: Text(ev('unpair'), style: TextStyle(color: c.muted)),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _EventCard extends StatelessWidget {
  final Json e;
  final VoidCallback onTap;
  const _EventCard({required this.e, required this.onTap});
  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final tickets = n(e['tickets']).toInt(), used = n(e['used']).toInt(), review = n(e['review']).toInt();
    final shows = objs(e['shows']);
    final poster = str(e['poster']);
    return Panel(
      padding: const EdgeInsets.all(12),
      onTap: onTap,
      child: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(14),
            child: poster.isNotEmpty
                ? Image(image: netImage(poster), width: 64, height: 64, fit: BoxFit.cover, errorBuilder: (_, _, _) => const TypeIcon('event', size: 64))
                : const TypeIcon('event', size: 64),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  str(e['title']),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15.5),
                ),
                const SizedBox(height: 2),
                Text(
                  [
                    evWhen(e['starts_at']),
                    evSoon(e['starts_at']),
                    if (shows.length > 1) ev('showsN', {'n': shows.length}),
                  ].join(' · '),
                  style: TextStyle(color: c.muted, fontSize: 12.5),
                ),
                const SizedBox(height: 8),
                ClipRRect(
                  borderRadius: BorderRadius.circular(9),
                  child: LinearProgressIndicator(value: tickets == 0 ? 0 : used / tickets, minHeight: 6, backgroundColor: c.chip),
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    Text('$used / $tickets ${ev('inside')}', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
                    if (review > 0) ...[
                      const SizedBox(width: 8),
                      Chip2(ev('toCheck', {'n': review}), tone: Tone.warn),
                    ],
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 6),
          Icon(LucideIcons.chevronRight, color: c.muted),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------- one event
class EvEventScreen extends StatefulWidget {
  final Json boot, event;
  final VoidCallback onBack, onLogout, onMore;
  const EvEventScreen({super.key, required this.boot, required this.event, required this.onBack, required this.onLogout, required this.onMore});
  @override
  State<EvEventScreen> createState() => _EvEventScreenState();
}

class _EvEventScreenState extends State<EvEventScreen> {
  late final EvCtl _ctl = EvCtl(boot: widget.boot, event: widget.event, onLogout: widget.onLogout);
  String _tab = 'scan';

  @override
  void initState() {
    super.initState();
    WakelockPlus.enable().catchError((_) {});
  }

  @override
  void dispose() {
    WakelockPlus.disable().catchError((_) {});
    _ctl.dispose();
    super.dispose();
  }

  static const _icons = {'scan': LucideIcons.scanLine, 'live': LucideIcons.activity, 'guests': LucideIcons.usersRound, 'sell': LucideIcons.store, 'orders': LucideIcons.receiptText};

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return ListenableBuilder(
      listenable: _ctl,
      builder: (context, _) {
        final tabs = _ctl.tabs;
        final shows = objs(widget.event['shows']);
        final body = switch (_tab) {
          'live' => EvLiveTab(ctl: _ctl, onGo: (k) => setState(() => _tab = k)),
          'guests' => EvGuestsTab(ctl: _ctl),
          'sell' => EvSellTab(ctl: _ctl),
          'orders' => EvOrdersTab(ctl: _ctl),
          _ => EvScanTab(ctl: _ctl),
        };
        return PopScope(
          canPop: false,
          onPopInvokedWithResult: (did, _) {
            if (!did) widget.onBack();
          },
          child: Scaffold(
            backgroundColor: c.appBg,
            appBar: AppBar(
              backgroundColor: c.appBg,
              surfaceTintColor: Colors.transparent,
              leading: IconButton(onPressed: widget.onBack, icon: const Icon(LucideIcons.arrowLeft), tooltip: ev('back')),
              titleSpacing: 0,
              title: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    str(widget.event['title']),
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
                  ),
                  Text(
                    '${_ctl.me} · ${ev('roles.${_ctl.role}')}',
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: c.muted, fontSize: 12.5),
                  ),
                ],
              ),
              actions: [IconButton(onPressed: widget.onMore, icon: const Icon(LucideIcons.ellipsisVertical), tooltip: AppState.i.t('evx.more'))],
            ),
            body: SafeArea(
              bottom: false,
              child: Column(
                children: [
                  if (shows.isNotEmpty)
                    SizedBox(
                      height: 44,
                      child: ListView(
                        scrollDirection: Axis.horizontal,
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                        children: [
                          for (final s in shows)
                            Padding(
                              padding: const EdgeInsets.only(right: 8),
                              child: ChoiceChip(
                                selected: _ctl.show == s['key'],
                                onSelected: (_) => _ctl.setShow(str(s['key'])),
                                label: Text([evWhen(s['starts_at']), if (str(s['label']).isNotEmpty) str(s['label'])].join(' · ')),
                              ),
                            ),
                        ],
                      ),
                    ),
                  _Counter(ctl: _ctl),
                  Expanded(child: body),
                ],
              ),
            ),
            bottomNavigationBar: tabs.length < 2
                ? null
                : NavigationBar(
                    selectedIndex: tabs.indexOf(_tab).clamp(0, tabs.length - 1),
                    onDestinationSelected: (i) => setState(() => _tab = tabs[i]),
                    destinations: [for (final k in tabs) NavigationDestination(icon: Icon(_icons[k]), label: ev('tabs.$k'))],
                  ),
          ),
        );
      },
    );
  }
}

// "123 / 400 inside" + the bar + offline / waiting scans
class _Counter extends StatelessWidget {
  final EvCtl ctl;
  const _Counter({required this.ctl});
  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final used = ctl.used, total = ctl.total;
    final off = !ctl.online || ctl.queue.isNotEmpty;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 10),
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
        decoration: BoxDecoration(color: c.card, borderRadius: BorderRadius.circular(20), boxShadow: c.cardShadow),
        child: Column(
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text('$used', style: const TextStyle(fontSize: 30, fontWeight: FontWeight.w800, height: 1)),
                const SizedBox(width: 6),
                Padding(
                  padding: const EdgeInsets.only(bottom: 3),
                  child: Text(
                    '/ $total ${ev('inside')}',
                    style: TextStyle(color: c.muted, fontWeight: FontWeight.w600),
                  ),
                ),
                const Spacer(),
                if (off)
                  Chip2(
                    [
                      if (!ctl.online) AppState.i.t('evd.offline').split('—').first.trim(),
                      if (ctl.queue.isNotEmpty) ev('queued', {'n': ctl.queue.length}),
                    ].join(' · '),
                    tone: Tone.warn,
                    icon: LucideIcons.cloudOff,
                  ),
              ],
            ),
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(9),
              child: LinearProgressIndicator(value: total == 0 ? 0 : used / total, minHeight: 8, backgroundColor: c.chip, color: c.good),
            ),
          ],
        ),
      ),
    );
  }
}
