import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/app_state.dart';
import '../../core/theme.dart';
import '../../widgets/ui.dart';
import '../restaurant/engine/calc.dart' show js;
import '../restaurant/pos_ui.dart';
import 'engine/gh_pos.dart';
import 'gh_bookings.dart';
import 'gh_calendar.dart';
import 'gh_display.dart';
import 'gh_lease.dart';
import 'gh_ops.dart';
import 'gh_requests.dart';
import 'gh_print.dart';
import 'gh_today.dart';
import '../updates/updates_page.dart';
import '../updates/changelog.dart' show bizhubVersion;
import '../../core/powered_by.dart';

// The Guest House desk app: link → staff PIN → Today / Calendar / Bookings (+ more with the add-ons)
class GhRoot extends StatefulWidget {
  const GhRoot({super.key});
  @override
  State<GhRoot> createState() => _GhRootState();
}

class _GhRootState extends State<GhRoot> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    GhPos.i.start(AppState.i.token);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && GhPos.i.stage == 'main') GhPos.i.syncNow();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: GhPos.i,
    builder: (context, _) {
      final pos = GhPos.i;
      final t = tr(context);
      return switch (pos.stage) {
        'unlinked' => GhMessage(icon: LucideIcons.unplug, text: t('ghp.ended'), button: t('rp.relink'), onTap: () => AppState.i.unlink()),
        'pin' => const GhPin(),
        'nocache' => GhMessage(icon: LucideIcons.cloudOff, text: t('ghp.noCache'), button: t('ghp.syncNow'), onTap: pos.loadBoot),
        'main' => GhMain(), // not const: it rebuilds when the engine changes (online, waiting, booking requests)
        _ => Scaffold(
          backgroundColor: context.c.appBg,
          body: Center(child: CircularProgressIndicator(color: context.c.brand)),
        ),
      };
    },
  );
}

class GhMessage extends StatelessWidget {
  final IconData icon;
  final String text, button;
  final VoidCallback onTap;
  const GhMessage({super.key, required this.icon, required this.text, required this.button, required this.onTap});
  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Scaffold(
      backgroundColor: c.appBg,
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Center(
                    child: Container(
                      width: 72,
                      height: 72,
                      decoration: BoxDecoration(color: c.warnBg, borderRadius: BorderRadius.circular(24)),
                      child: Icon(icon, size: 32, color: c.warn),
                    ),
                  ),
                  const SizedBox(height: 18),
                  Text(
                    text,
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700, height: 1.45),
                  ),
                  const SizedBox(height: 20),
                  Btn(button, expand: true, onTap: onTap),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// the staff 4-digit PIN (checked on the device when there is no internet)
class GhPin extends StatefulWidget {
  const GhPin({super.key});
  @override
  State<GhPin> createState() => _GhPinState();
}

class _GhPinState extends State<GhPin> {
  String _pin = '';
  bool _error = false, _busy = false, _sure = false;

  Future<void> _typed(String v) async {
    setState(() => _pin = v);
    if (v.length != 4) return;
    setState(() => _busy = true);
    final ok = await GhPos.i.login(v);
    if (!mounted) return;
    setState(() => _busy = false);
    if (!ok) {
      setState(() => _error = true);
      await Future.delayed(const Duration(milliseconds: 650));
      if (mounted) {
        setState(() {
          _error = false;
          _pin = '';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final t = app.t;
    final c = context.c;
    final link = AppState.i.link ?? const {};
    final pos = GhPos.i;
    final name = js(pos.business['name']).isNotEmpty ? js(pos.business['name']) : js(link['shop']);
    final logo = js(pos.business['logo_url']).isNotEmpty ? js(pos.business['logo_url']) : js(link['logo']);
    return Scaffold(
      backgroundColor: c.appBg,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 380),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          t('ghp.title'),
                          style: TextStyle(color: c.muted, fontWeight: FontWeight.w600),
                        ),
                      ),
                      const ThemeBtn(),
                      TextButton(onPressed: () => app.setLang(app.lang == 'km' ? 'en' : 'km'), child: Text(t('home.lang'))),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Center(
                    child: Container(
                      width: 84,
                      height: 84,
                      clipBehavior: Clip.antiAlias,
                      decoration: BoxDecoration(color: c.active, borderRadius: BorderRadius.circular(26)),
                      child: logo.isNotEmpty
                          ? Image(
                              image: netImage(logo),
                              fit: BoxFit.cover,
                              errorBuilder: (_, _, _) => Icon(LucideIcons.bedDouble, color: c.brand, size: 36),
                            )
                          : Icon(LucideIcons.bedDouble, color: c.brand, size: 36),
                    ),
                  ),
                  const SizedBox(height: 14),
                  Text(
                    name.isEmpty ? t('ghp.title') : name,
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 6),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(LucideIcons.lock, size: 14, color: _error ? c.danger : c.muted),
                      const SizedBox(width: 6),
                      Text(
                        _error ? t('ghp.wrongPin') : t('ghp.enterPin'),
                        style: TextStyle(color: _error ? c.danger : c.muted, fontWeight: FontWeight.w600),
                      ),
                    ],
                  ),
                  const DemoPinHint(),
                  const SizedBox(height: 20),
                  PinDots(_pin.length, error: _error),
                  const SizedBox(height: 24),
                  Keypad(value: _pin, onChanged: _typed, max: 4, disabled: _busy || _error, keyHeight: 64),
                  const SizedBox(height: 8),
                  if (_sure)
                    Alert(
                      t('ghp.unlinkSure'),
                      tone: Tone.warn,
                      action: Row(
                        children: [
                          Btn(t('ghp.unlink'), small: true, kind: BtnKind.danger, onTap: () => pos.unlinkHere()),
                          const SizedBox(width: 8),
                          TextButton(onPressed: () => setState(() => _sure = false), child: Text(t('ghp.close'))),
                        ],
                      ),
                    )
                  else
                    Center(
                      child: TextButton.icon(
                        style: TextButton.styleFrom(foregroundColor: c.muted),
                        onPressed: () => setState(() => _sure = true),
                        icon: const Icon(LucideIcons.unplug, size: 16),
                        label: Text(t('ghp.unlink')),
                      ),
                    ),
                  const PoweredBy(),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// the desk: top bar (online / waiting), tabs
class GhMain extends StatefulWidget {
  const GhMain({super.key});
  @override
  State<GhMain> createState() => _GhMainState();
}

class _GhMainState extends State<GhMain> {
  String _tab = 'today';

  @override
  void initState() {
    super.initState();
    final pos = GhPos.i;
    pos.watchRequests(!pos.isHousekeeper); // website booking requests ring at the desk
    GhDisplayFeed.i.start(); // the guest display of a dual-screen terminal
  }

  @override
  void dispose() {
    GhPos.i.watchRequests(false);
    super.dispose();
  }

  // which screens this person sees: a housekeeper only cleans rooms; add-ons the guest house doesn't have stay hidden
  List<(String, IconData, String)> _tabs(BuildContext context) {
    final t = tr(context);
    final b = GhPos.i.boot;
    final hk = ('housekeeping', LucideIcons.sparkles, t('gh.tabs.housekeeping'));
    if (GhPos.i.isHousekeeper) return [hk];
    return [
      ('today', LucideIcons.sun, t('gh.tabs.today')),
      ('calendar', LucideIcons.calendarRange, t('gh.tabs.calendar')),
      ('bookings', LucideIcons.clipboardList, t('gh.tabs.bookings')),
      if (b['housekeeping'] == true) hk,
      if (b['longstay'] == true) ('longstay', LucideIcons.keyRound, t('gh.tabs.longstay')),
      ('report', LucideIcons.chartColumn, t('gh.tabs.report')),
      if (b['expenses'] == true) ('expenses', LucideIcons.wallet, t('gh.tabs.expenses')),
    ];
  }

  Widget _body() => switch (_tab) {
    'calendar' => const GhCalendar(),
    'bookings' => const GhBookings(),
    'housekeeping' => const GhHousekeeping(),
    'longstay' => const GhLeases(),
    'report' => const GhReport(),
    'expenses' => const GhExpenses(),
    _ => const GhToday(),
  };

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final t = app.t;
    final c = context.c;
    final pos = GhPos.i;
    final logo = js(pos.business['logo_url']);
    final big = wide(context);
    final tabs = _tabs(context);
    if (!tabs.any((x) => x.$1 == _tab)) _tab = tabs.first.$1;
    final (fg, bg) = !pos.online ? (c.danger, c.dangerBg) : (pos.pending > 0 ? (c.warn, c.warnBg) : (c.good, c.goodBg));
    final net = Material(
      color: bg,
      borderRadius: BorderRadius.circular(999),
      child: InkWell(
        borderRadius: BorderRadius.circular(999),
        onTap: pos.syncNow,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(pos.syncing ? LucideIcons.refreshCw : (pos.online ? LucideIcons.wifi : LucideIcons.cloudOff), size: 15, color: fg),
              if (big || pos.pending > 0) ...[
                const SizedBox(width: 6),
                Text(
                  [
                    if (big) pos.syncing ? t('ghp.syncing') : (pos.online ? t('ghp.online') : t('ghp.offline')),
                    if (pos.pending > 0) t('ghp.waiting', {'n': pos.pending}),
                  ].join(' · '),
                  style: TextStyle(color: fg, fontWeight: FontWeight.w700, fontSize: 12.5),
                ),
              ],
            ],
          ),
        ),
      ),
    );
    return Scaffold(
      backgroundColor: c.appBg,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 6, 6),
              child: Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    clipBehavior: Clip.antiAlias,
                    decoration: BoxDecoration(color: c.active, borderRadius: BorderRadius.circular(13)),
                    child: logo.isNotEmpty
                        ? Image(
                            image: netImage(logo),
                            fit: BoxFit.cover,
                            errorBuilder: (_, _, _) => Icon(LucideIcons.bedDouble, color: c.brand, size: 20),
                          )
                        : Icon(LucideIcons.bedDouble, color: c.brand, size: 20),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          js(pos.business['name']),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
                        ),
                        Text(
                          '${js(pos.staff['name'])} · ${t('ghp.roles.${pos.role}')}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(color: c.muted, fontSize: 12.5),
                        ),
                      ],
                    ),
                  ),
                  net,
                  IconButton(onPressed: () => _menu(context), icon: const Icon(LucideIcons.menu), tooltip: MaterialLocalizations.of(context).showMenuTooltip),
                ],
              ),
            ),
            if (!pos.online) GhBand(t('ghp.offlineHint'), warn: true) else if (pos.readOnly) GhBand(t('rpos.locked'), warn: true),
            if (pos.failed.isNotEmpty)
              GhBand(
                '${t('ghp.failedTitle')}\n${pos.failed.map((f) => '${js(f['guest']).isNotEmpty ? '${js(f['guest'])} · ' : ''}${js(f['message'])}').join('\n')}',
                warn: true,
                action: TextButton(onPressed: pos.dismissFailed, child: Text(t('ghp.dismiss'))),
              ),
            GhRequestAlert(onOpen: () => openRequests(context)),
            if (big && tabs.length > 1)
              SizedBox(
                height: 48,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
                  children: [
                    for (final (k, icon, label) in tabs)
                      Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: GhTabBtn(icon: icon, label: label, on: _tab == k, onTap: () => setState(() => _tab = k)),
                      ),
                  ],
                ),
              ),
            Expanded(child: _body()),
          ],
        ),
      ),
      bottomNavigationBar: big || tabs.length < 2
          ? null
          : () {
              // a phone fits 4 labels well: the first 3 + "More" for the rest
              final many = tabs.length > 4;
              final shown = many ? tabs.take(3).toList() : tabs;
              final idx = shown.indexWhere((x) => x.$1 == _tab);
              return NavigationBar(
                height: 64,
                labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
                selectedIndex: idx < 0 ? shown.length : idx,
                onDestinationSelected: (i) {
                  if (i < shown.length) {
                    setState(() => _tab = shown[i].$1);
                  } else {
                    _more(context, tabs.skip(3).toList());
                  }
                },
                destinations: [
                  for (final (_, icon, label) in shown) NavigationDestination(icon: Icon(icon), label: label),
                  if (many) NavigationDestination(icon: const Icon(LucideIcons.ellipsis), label: t('mpos.more')),
                ],
              );
            }(),
    );
  }

  void _more(BuildContext context, List<(String, IconData, String)> rest) {
    posSheet(
      context,
      title: tr(context)('mpos.more'),
      body: (ctx) => Column(
        children: [
          for (final (k, icon, label) in rest)
            ListTile(
              leading: Icon(icon),
              title: Text(label, style: const TextStyle(fontWeight: FontWeight.w700)),
              selected: _tab == k,
              onTap: () {
                Navigator.pop(ctx);
                setState(() => _tab = k);
              },
            ),
        ],
      ),
    );
  }

  void _menu(BuildContext context) {
    final app = AppScope.of(context);
    posSheet(
      context,
      title: js(GhPos.i.business['name']),
      body: (ctx) {
        final t = tr(ctx);
        final c = ctx.c;
        final pos = GhPos.i;
        Widget item(IconData icon, String label, VoidCallback onTap) => ListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: 6),
          leading: Icon(icon, color: c.ink),
          title: Text(label, style: const TextStyle(fontWeight: FontWeight.w700)),
          onTap: onTap,
        );
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            item(LucideIcons.refreshCw, t('ghp.syncNow'), () {
              Navigator.pop(ctx);
              pos.syncNow();
            }),
            if (pos.requestsOn)
              item(LucideIcons.bellRing, t('gc.sheetTitle'), () {
                Navigator.pop(ctx);
                openRequests(context);
              }),
            item(LucideIcons.printer, t('rp.printers'), () {
              Navigator.pop(ctx);
              openGhPrinters(context);
            }),
            item(LucideIcons.languages, t('home.lang'), () => app.setLang(app.lang == 'km' ? 'en' : 'km')),
            item(LucideIcons.sunMoon, t('app.theme'), () => pickTheme(context)),
            item(LucideIcons.history, '${updatesText(app.lang, 'title')} · v$bizhubVersion', () {
              Navigator.pop(ctx);
              openUpdates(context);
            }),
            item(LucideIcons.lock, t('ghp.lock'), () {
              Navigator.pop(ctx);
              pos.lock();
            }),
            const PoweredBy(),
          ],
        );
      },
    );
  }
}

class GhTabBtn extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool on;
  final VoidCallback onTap;
  const GhTabBtn({super.key, required this.icon, required this.label, required this.on, required this.onTap});
  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Material(
      color: on ? c.solid : c.card,
      borderRadius: BorderRadius.circular(999),
      child: InkWell(
        borderRadius: BorderRadius.circular(999),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 16, color: on ? c.onSolid : c.ink),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(fontWeight: FontWeight.w700, color: on ? c.onSolid : c.ink),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class GhBand extends StatelessWidget {
  final String text;
  final bool warn;
  final Widget? action;
  const GhBand(this.text, {super.key, this.warn = false, this.action});
  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(12, 0, 12, 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(color: warn ? c.warnBg : c.active, borderRadius: BorderRadius.circular(14)),
      child: Row(
        children: [
          Expanded(
            child: Text(
              text,
              style: TextStyle(color: warn ? c.warn : c.brandInk, fontWeight: FontWeight.w600, fontSize: 13),
            ),
          ),
          ?action,
        ],
      ),
    );
  }
}
