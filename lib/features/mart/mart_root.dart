import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/app_state.dart';
import '../../core/theme.dart';
import '../../widgets/ui.dart';
import '../restaurant/engine/calc.dart' show J, jmap, js;
import '../restaurant/pos_ui.dart';
import 'engine/mart_pos.dart';
import 'mart_debt.dart';
import 'mart_display.dart';
import 'mart_expiry.dart';
import 'mart_kit.dart';
import 'mart_purchase.dart';
import 'mart_orders.dart';
import 'mart_receipt.dart';
import 'mart_sales.dart';
import 'mart_sell.dart';
import 'mart_shift.dart';
import 'mart_stock.dart';
import '../updates/updates_page.dart';
import '../updates/changelog.dart' show bizhubVersion;

// The Mini Mart POS in the app: PIN → (count the drawer) → sell. Works offline like the web's /pos/mini-mart.
class MartRoot extends StatefulWidget {
  const MartRoot({super.key});
  @override
  State<MartRoot> createState() => _MartRootState();
}

class _MartRootState extends State<MartRoot> with WidgetsBindingObserver {
  bool _skipShift = false;
  J? _shiftDone;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    MartPos.i.start(AppState.i.token);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    MartDisplayFeed.i.stop();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && MartPos.i.stage == 'main') MartPos.i.syncNow();
  }

  void _lock() {
    setState(() {
      _skipShift = false;
      _shiftDone = null;
    });
    MartPos.i.lock();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: MartPos.i,
      builder: (context, _) {
        final pos = MartPos.i;
        switch (pos.stage) {
          case 'unlinked':
            return MartMessage(icon: LucideIcons.unplug, text: tr(context)('mpos.ended'), button: tr(context)('rp.relink'), onTap: () => AppState.i.unlink());
          case 'pin':
            return const MartPin();
          case 'nocache':
            return MartMessage(icon: LucideIcons.cloudOff, text: tr(context)('mpos.noCache'), button: tr(context)('mpos.syncNow'), onTap: pos.loadBoot);
          case 'main':
            break;
          default:
            return Scaffold(
              backgroundColor: context.c.appBg,
              body: Center(child: CircularProgressIndicator(color: context.c.brand)),
            );
        }
        if (_shiftDone != null) return MartShiftDone(shift: _shiftDone!, onDone: _lock);
        if (pos.boot['shifts'] == true && pos.boot['shift'] == null && !_skipShift) {
          return MartOpenShift(onLock: _lock, onSkip: () => setState(() => _skipShift = true));
        }
        return MartMain(onLock: _lock, onShiftClosed: (s) => setState(() => _shiftDone = s));
      },
    );
  }
}

// a full-screen message with one button (unlinked, no copy saved yet)
class MartMessage extends StatelessWidget {
  final IconData icon;
  final String text, button;
  final VoidCallback onTap;
  const MartMessage({super.key, required this.icon, required this.text, required this.button, required this.onTap});
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

// the cashier's 4-digit PIN (checked on the device when there is no internet)
class MartPin extends StatefulWidget {
  const MartPin({super.key});
  @override
  State<MartPin> createState() => _MartPinState();
}

class _MartPinState extends State<MartPin> {
  String _pin = '';
  bool _error = false, _busy = false, _sure = false;

  Future<void> _typed(String v) async {
    setState(() => _pin = v);
    if (v.length != 4) return;
    setState(() => _busy = true);
    final ok = await MartPos.i.login(v);
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
    final pos = MartPos.i;
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
                          t('mpos.title'),
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
                              errorBuilder: (_, _, _) => Icon(LucideIcons.shoppingBasket, color: c.brand, size: 36),
                            )
                          : Icon(LucideIcons.shoppingBasket, color: c.brand, size: 36),
                    ),
                  ),
                  const SizedBox(height: 14),
                  Text(
                    name.isEmpty ? t('mpos.title') : name,
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
                        _error ? t('mpos.wrongPin') : t('mpos.enterPin'),
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
                      t('mpos.unlinkSure'),
                      tone: Tone.warn,
                      action: Row(
                        children: [
                          Btn(t('mpos.unlink'), small: true, kind: BtnKind.danger, onTap: () => pos.unlinkHere()),
                          const SizedBox(width: 8),
                          TextButton(onPressed: () => setState(() => _sure = false), child: Text(t('mpos.close'))),
                        ],
                      ),
                    )
                  else
                    Center(
                      child: TextButton.icon(
                        style: TextButton.styleFrom(foregroundColor: c.muted),
                        onPressed: () => setState(() => _sure = true),
                        icon: const Icon(LucideIcons.unplug, size: 16),
                        label: Text(t('mpos.unlink')),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// the shell: top bar (shop, online / waiting, cashier, lock) + Sell / Sales
class MartMain extends StatefulWidget {
  final VoidCallback onLock;
  final ValueChanged<J> onShiftClosed;
  const MartMain({super.key, required this.onLock, required this.onShiftClosed});
  @override
  State<MartMain> createState() => _MartMainState();
}

class _MartMainState extends State<MartMain> {
  String _tab = 'sell';

  @override
  void initState() {
    super.initState();
    // online orders: ring while new ones wait
    MartPos.i.watchOrders(MartPos.i.boot['shop'] == true);
    MartDisplayFeed.i.start(); // the customer screen of a dual-screen terminal (stays on while locked)
  }

  @override
  void dispose() {
    MartPos.i.watchOrders(false);
    super.dispose();
  }

  // the tabs this shop has (stock / debt book / online orders come with their add-ons)
  List<(String, IconData, String)> _tabs(BuildContext context) {
    final t = tr(context);
    final b = MartPos.i.boot;
    return [
      ('sell', LucideIcons.shoppingCart, t('mart.tabs.sell')),
      ('sales', LucideIcons.clipboardList, t('mart.tabs.sales')),
      if (b['stock'] == true) ('stock', LucideIcons.boxes, t('mart.tabs.stock')),
      if (b['debt'] == true) ('debt', LucideIcons.handCoins, t('mart.tabs.debt')),
      if (b['shop'] == true) ('orders', LucideIcons.shoppingBag, t('mart.tabs.orders')),
    ];
  }

  Widget _body() => switch (_tab) {
    'sales' => const MartSales(),
    'stock' => const MartStock(),
    'debt' => const MartDebt(),
    'orders' => const MartOrders(),
    _ => const MartSell(),
  };

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final t = app.t;
    final c = context.c;
    final pos = MartPos.i;
    final logo = js(pos.business['logo_url']);
    final big = wide(context);
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
                    if (big) pos.syncing ? t('mpos.syncing') : (pos.online ? t('mpos.online') : t('mpos.offline')),
                    if (pos.pending > 0) t('mpos.waiting', {'n': pos.pending}),
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
                            errorBuilder: (_, _, _) => Icon(LucideIcons.shoppingBasket, color: c.brand, size: 20),
                          )
                        : Icon(LucideIcons.shoppingBasket, color: c.brand, size: 20),
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
                          '${js(pos.staff['name'])} · ${t('mpos.roles.${js(pos.staff['role'])}')}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(color: c.muted, fontSize: 12.5),
                        ),
                      ],
                    ),
                  ),
                  net,
                  IconButton(onPressed: () => _menu(context), icon: const Icon(LucideIcons.menu), tooltip: t('mpos.more')),
                ],
              ),
            ),
            if (!pos.online) _Band(t('mpos.offlineHint'), warn: true) else if (pos.readOnly) _Band(t('rpos.locked'), warn: true),
            if (pos.failed.isNotEmpty)
              _Band(
                '${pos.held ? t('mp.heldOffline') : t('mpos.failedTitle')}\n${pos.failed.map((f) => '${js(f['label']).isNotEmpty ? '${js(f['label'])} · ' : ''}${js(f['message'])}').join('\n')}',
                warn: true,
                action: TextButton(onPressed: pos.dismissFailed, child: Text(t('mpos.dismiss'))),
              ),
            if (_tab != 'orders') MartOrderAlert(onOpen: () => setState(() => _tab = 'orders')),
            if (big)
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
                child: Row(
                  children: [
                    for (final (k, icon, label) in _tabs(context))
                      Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: _TabBtn(icon: icon, label: label, on: _tab == k, badge: k == 'orders' ? pos.newOrders : 0, onTap: () => setState(() => _tab = k)),
                      ),
                  ],
                ),
              ),
            Expanded(child: _body()),
          ],
        ),
      ),
      bottomNavigationBar: big
          ? null
          : NavigationBar(
              height: 64,
              labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
              selectedIndex: _tabs(context).indexWhere((x) => x.$1 == _tab).clamp(0, 9),
              onDestinationSelected: (i) => setState(() => _tab = _tabs(context)[i].$1),
              destinations: [
                for (final (k, icon, label) in _tabs(context))
                  NavigationDestination(
                    icon: k == 'orders' && pos.newOrders > 0 ? Badge(label: Text('${pos.newOrders}'), child: Icon(icon)) : Icon(icon),
                    label: k == 'orders' ? tr(context)('mw.orders') : label, // short under the icon
                  ),
              ],
            ),
    );
  }

  void _menu(BuildContext context) {
    final app = AppScope.of(context);
    posSheet(
      context,
      title: js(MartPos.i.business['name']),
      body: (ctx) {
        final t = tr(ctx);
        final c = ctx.c;
        final pos = MartPos.i;
        Widget item(IconData icon, String label, VoidCallback onTap, {bool danger = false}) => ListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: 6),
          leading: Icon(icon, color: danger ? c.danger : c.ink),
          title: Text(
            label,
            style: TextStyle(fontWeight: FontWeight.w700, color: danger ? c.danger : c.ink),
          ),
          onTap: onTap,
        );
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            item(LucideIcons.refreshCw, t('mpos.syncNow'), () {
              Navigator.pop(ctx);
              pos.syncNow();
            }),
            if (pos.boot['shifts'] == true && pos.boot['shift'] != null)
              item(LucideIcons.vault, t('mpos.closeShift'), () async {
                Navigator.pop(ctx);
                final done = await showMartCloseShift(context);
                if (done != null) widget.onShiftClosed(done);
              }),
            // manager pages (their add-on on)
            if (pos.manager && jmap(pos.boot['addons_on'])['mart_expiry'] == true)
              item(LucideIcons.calendarX, t('mart.tabs.expiry'), () {
                Navigator.pop(ctx);
                openMartPage(context, t('mart.tabs.expiry'), const MartExpiry());
              }),
            if (pos.manager && jmap(pos.boot['addons_on'])['mart_purchase'] == true)
              item(LucideIcons.clipboardCheck, t('mart.tabs.purchase'), () {
                Navigator.pop(ctx);
                openMartPage(context, t('mart.tabs.purchase'), const MartPurchase());
              }),
            item(LucideIcons.printer, t('rp.printers'), () {
              Navigator.pop(ctx);
              openMartPrinters(context);
            }),
            item(LucideIcons.languages, t('home.lang'), () => app.setLang(app.lang == 'km' ? 'en' : 'km')),
            item(LucideIcons.sunMoon, t('app.theme'), () => pickTheme(context)),
            item(LucideIcons.history, '${updatesText(app.lang, 'title')} · v$bizhubVersion', () {
              Navigator.pop(ctx);
              openUpdates(context);
            }),
            item(LucideIcons.lock, t('mpos.lock'), () {
              Navigator.pop(ctx);
              widget.onLock();
            }),
          ],
        );
      },
    );
  }
}

class _TabBtn extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool on;
  final int badge;
  final VoidCallback onTap;
  const _TabBtn({required this.icon, required this.label, required this.on, required this.badge, required this.onTap});
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
              if (badge > 0) ...[const SizedBox(width: 6), Badge(label: Text('$badge'))],
            ],
          ),
        ),
      ),
    );
  }
}

class _Band extends StatelessWidget {
  final String text;
  final bool warn;
  final Widget? action;
  const _Band(this.text, {this.warn = false, this.action});
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
