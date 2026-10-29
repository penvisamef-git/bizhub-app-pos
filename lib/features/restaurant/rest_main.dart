import 'dart:async';

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/app_state.dart';
import '../../core/format.dart' as f;
import '../../core/theme.dart';
import '../../widgets/ui.dart';
import 'engine/calc.dart';
import 'engine/rest_pos.dart';
import 'pos_ui.dart';
import 'rest_book.dart';
import 'rest_order.dart';
import 'rest_print.dart';
import 'rest_report.dart';
import 'rest_shift.dart';
import 'rest_start.dart';
import '../updates/updates_page.dart';
import '../updates/changelog.dart' show bizhubVersion;
import '../../core/powered_by.dart';

// time at the table: 05:12 → 1:05:12
String elapsed(Object? at, DateTime now) {
  final d = DateTime.tryParse(js(at));
  if (d == null) return '';
  final sec = now.difference(d).inSeconds.clamp(0, 1 << 31);
  final h = sec ~/ 3600;
  final mm = ((sec % 3600) ~/ 60).toString().padLeft(2, '0');
  final ss = (sec % 60).toString().padLeft(2, '0');
  return h > 0 ? '$h:$mm:$ss' : '$mm:$ss';
}

// rebuilds every second (the clocks on the tables)
class Ticker extends StatefulWidget {
  final Widget Function(BuildContext, DateTime) builder;
  const Ticker({super.key, required this.builder});
  @override
  State<Ticker> createState() => _TickerState();
}

class _TickerState extends State<Ticker> {
  late final Timer _t = Timer.periodic(const Duration(seconds: 1), (_) => setState(() {}));
  @override
  void dispose() {
    _t.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.builder(context, DateTime.now());
}

// The selling home: tables (or open orders when the shop has no tables) + takeaway.
class RestMain extends StatelessWidget {
  const RestMain({super.key});

  static Future<void> openOrder(BuildContext context, {String? orderId, J? table}) => Navigator.of(context).push(
    MaterialPageRoute(
      builder: (_) => OrderPage(orderId: orderId, table: table),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final t = tr(context);
    final c = context.c;
    final pos = RestPos.i;
    final blocked = pos.blockedReason;
    return Scaffold(
      backgroundColor: c.appBg,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            const _TopBar(),
            if (pos.graceDays > 0) _Note(t('rpos.graceWarn', {'n': pos.graceDays}), warn: true),
            if (blocked.isNotEmpty)
              _Note(
                blocked == 'locked' ? t('rpos.locked') : (blocked == 'offline_off' ? t('rpos.offlineOff') : t('rpos.offlineLong')),
                warn: true,
                icon: LucideIcons.lockKeyhole,
                action: TextButton.icon(onPressed: pos.syncNow, icon: const Icon(LucideIcons.refreshCw, size: 15), label: Text(t('rpos.retry'))),
              )
            else if (pos.shiftMode && pos.pending > 0)
              _Note(t('rpos.shiftModeWarn')),
            GuestAlerts(onOpen: (id) => RestMain.openOrder(context, orderId: id)),
            Expanded(
              child: pos.noTables ? _OrdersOnly(disabled: blocked.isNotEmpty) : _Floor(disabled: blocked.isNotEmpty),
            ),
          ],
        ),
      ),
    );
  }
}

class _Note extends StatelessWidget {
  final String text;
  final bool warn;
  final IconData? icon;
  final Widget? action;
  const _Note(this.text, {this.warn = false, this.icon, this.action});
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
          if (icon != null) ...[Icon(icon, size: 18, color: warn ? c.warn : c.brandInk), const SizedBox(width: 8)],
          Expanded(
            child: Text(
              text,
              style: TextStyle(color: warn ? c.warn : c.brandInk, fontWeight: FontWeight.w600, fontSize: 13.5),
            ),
          ),
          ?action,
        ],
      ),
    );
  }
}

// sync status: online / sending / n waiting / offline (tap = sync now)
class SyncPill extends StatelessWidget {
  final bool compact;
  const SyncPill({super.key, this.compact = false});
  @override
  Widget build(BuildContext context) {
    final t = tr(context);
    final c = context.c;
    final pos = RestPos.i;
    final waiting = pos.pending;
    final (fg, bg) = !pos.online ? (c.danger, c.dangerBg) : (waiting > 0 ? (c.warn, c.warnBg) : (c.good, c.goodBg));
    final icon = !pos.online ? LucideIcons.cloudOff : (pos.syncing ? LucideIcons.refreshCw : (waiting > 0 ? LucideIcons.cloudUpload : LucideIcons.wifi));
    final label = pos.online
        ? (pos.syncing ? t('rpos.syncing') : (waiting > 0 ? t('rpos.waiting', {'n': waiting}) : t('rpos.online')))
        : '${t('rpos.offline')}${waiting > 0 ? ' · ${t('rpos.waiting', {'n': waiting})}' : ''}';
    return Tooltip(
      message: t('rpos.syncNow'),
      child: Material(
        color: bg,
        borderRadius: BorderRadius.circular(999),
        child: InkWell(
          borderRadius: BorderRadius.circular(999),
          onTap: pos.syncNow,
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: compact ? 10 : 12, vertical: 8),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 15, color: fg),
                if (!compact) ...[
                  const SizedBox(width: 6),
                  Text(
                    label,
                    style: TextStyle(color: fg, fontWeight: FontWeight.w700, fontSize: 12.5),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _TopBar extends StatelessWidget {
  const _TopBar();
  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final c = context.c;
    final pos = RestPos.i;
    final logo = js(pos.restaurant['logo']);
    final big = wide(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 6, 8),
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
                    errorBuilder: (_, _, _) => Icon(LucideIcons.chefHat, color: c.brand, size: 20),
                  )
                : Icon(LucideIcons.chefHat, color: c.brand, size: 20),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  nameOf(pos.restaurant, app.lang),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
                ),
                Text(
                  '${js(pos.staff?['name'])} · ${js(pos.device['name'])} · ${js(pos.device['prefix'])}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: c.muted, fontSize: 12.5),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          SyncPill(compact: !big),
          if (big) ...[
            const SizedBox(width: 8),
            TextButton.icon(onPressed: () => openReports(context), icon: const Icon(LucideIcons.chartColumn, size: 16), label: Text(tr(context)('rpos.reportsTitle'))),
          ],
          if (big) ...[
            const SizedBox(width: 10),
            Ticker(
              builder: (_, now) => Text(
                f.fmtTime(now),
                style: TextStyle(color: c.muted, fontWeight: FontWeight.w700),
              ),
            ),
          ],
          IconButton(onPressed: () => _menu(context), icon: const Icon(LucideIcons.menu), tooltip: tr(context)('rpos.more')),
        ],
      ),
    );
  }

  void _menu(BuildContext context) {
    final app = AppScope.of(context);
    posSheet(
      context,
      title: nameOf(RestPos.i.restaurant, app.lang),
      body: (ctx) => ListenableBuilder(
        listenable: RestPos.i,
        builder: (ctx, _) {
          final t = tr(ctx);
          final c = ctx.c;
          final pos = RestPos.i;
          Widget item(IconData icon, String label, VoidCallback onTap, {bool danger = false}) => ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 6),
            leading: Icon(icon, color: danger ? c.danger : c.ink),
            title: Text(
              label,
              style: TextStyle(fontWeight: FontWeight.w700, color: danger ? c.danger : c.ink),
            ),
            onTap: onTap,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          );
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  Chip2(pos.online ? t('rpos.online') : t('rpos.offline'), tone: pos.online ? Tone.good : Tone.danger),
                  Chip2(pos.pending > 0 ? t('rpos.waiting', {'n': pos.pending}) : t('rpos.allSent'), tone: pos.pending > 0 ? Tone.warn : Tone.good),
                  if (pos.lastSync > 0) Chip2(t('rpos.lastSync', {'t': f.fmtTime(DateTime.fromMillisecondsSinceEpoch(pos.lastSync))})),
                ],
              ),
              const SizedBox(height: 10),
              item(LucideIcons.chartColumn, t('rpos.reportsTitle'), () {
                Navigator.pop(ctx);
                openReports(context);
              }),
              item(LucideIcons.refreshCw, t('rpos.syncNow'), pos.syncNow),
              item(LucideIcons.printer, t('rp.printers'), () {
                Navigator.pop(ctx);
                openPrinters(context);
              }),
              item(LucideIcons.wallet, t('rpos.closeShift'), () {
                Navigator.pop(ctx);
                showCloseShift(context);
              }),
              item(LucideIcons.logOut, t('rpos.switchStaff'), () {
                Navigator.pop(ctx);
                pos.lock();
              }),
              item(LucideIcons.languages, t('home.lang'), () => app.setLang(app.lang == 'km' ? 'en' : 'km')),
              item(LucideIcons.sunMoon, t('app.theme'), () => pickTheme(context)),
              item(LucideIcons.history, '${updatesText(app.lang, 'title')} · v$bizhubVersion', () {
                Navigator.pop(ctx);
                openUpdates(context);
              }),
              const Divider(height: 18),
              item(LucideIcons.unplug, t('rpos.unlink'), () {
                Navigator.pop(ctx);
                showUnlink(context);
              }, danger: true),
              const PoweredBy(),
            ],
          );
        },
      ),
    );
  }
}

// ---------- floor: tables + takeaway ----------
class _Floor extends StatefulWidget {
  final bool disabled;
  const _Floor({required this.disabled});
  @override
  State<_Floor> createState() => _FloorState();
}

class _FloorState extends State<_Floor> {
  String _zone = '';
  String _show = 'all'; // all | sitting | booked | free

  @override
  Widget build(BuildContext context) {
    final t = tr(context);
    final c = context.c;
    final pos = RestPos.i;
    final cur = pos.currency;
    final open = pos.openOrders;
    final byTable = <String, List<J>>{};
    for (final o in open) {
      if (js(o['table_id']).isNotEmpty) (byTable[js(o['table_id'])] ??= []).add(o);
    }
    final booked = <String, J>{};
    for (final b in pos.activeBookings..sort((a, b) => js(a['time']).compareTo(js(b['time'])))) {
      if (js(b['table_id']).isNotEmpty) booked.putIfAbsent(js(b['table_id']), () => b);
    }
    String stateOf(J tb) => byTable.containsKey(js(tb['_id'])) ? 'sitting' : (booked.containsKey(js(tb['_id'])) ? 'booked' : 'free');
    final inZone = pos.tables.where((x) => _zone.isEmpty || js(x['zone_id']) == _zone).toList();
    final count = {'all': inZone.length, 'sitting': 0, 'booked': 0, 'free': 0};
    for (final tb in inZone) {
      count[stateOf(tb)] = count[stateOf(tb)]! + 1;
    }
    final tables = inZone.where((tb) => _show == 'all' || stateOf(tb) == _show).toList();
    final takeaways = open.where((o) => js(o['table_id']).isEmpty).toList();
    final big = wide(context);

    final filters = Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (pos.zones.isNotEmpty) ...[
            PosChips<String>(scroll: true, value: _zone, onTap: (v) => setState(() => _zone = v), options: [('', t('rpos.allZones')), for (final z in pos.zones) (js(z['_id']), js(z['name']))]),
            const SizedBox(height: 8),
          ],
          PosChips<String>(
            scroll: true,
            value: _show,
            onTap: (v) => setState(() => _show = v),
            options: [
              ('all', '${t('rpos.filterAll')} ${count['all']}'),
              ('sitting', '${t('rpos.filterSitting')} ${count['sitting']}'),
              ('booked', '${t('rpos.filterBooked')} ${count['booked']}'),
              ('free', '${t('rpos.filterFree')} ${count['free']}'),
            ],
          ),
        ],
      ),
    );

    final grid = Ticker(
      builder: (context, now) => tables.isEmpty
          ? Center(child: Muted(t('rpos.noTablesHere')))
          : GridView.builder(
              padding: EdgeInsets.fromLTRB(12, 0, 12, big ? 16 : 96),
              gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(maxCrossAxisExtent: 190, mainAxisExtent: 128, crossAxisSpacing: 10, mainAxisSpacing: 10),
              itemCount: tables.length,
              itemBuilder: (context, i) {
                final tb = tables[i];
                final orders = byTable[js(tb['_id'])] ?? const <J>[];
                final o = orders.isEmpty ? null : orders.first;
                return _TableTile(
                  table: tb,
                  orders: orders,
                  booking: booked[js(tb['_id'])],
                  now: now,
                  currency: cur,
                  disabled: widget.disabled && o == null && booked[js(tb['_id'])] == null,
                  onTap: () {
                    final bk = booked[js(tb['_id'])];
                    if (o == null && bk != null) {
                      showBooking(context, js(bk['_id']), onSeated: (order) => RestMain.openOrder(context, orderId: js(order['_id'])));
                    } else {
                      RestMain.openOrder(context, orderId: o == null ? null : js(o['_id']), table: tb);
                    }
                  },
                );
              },
            ),
    );

    final bookings = pos.activeBookings..sort((a, b) => js(a['time']).compareTo(js(b['time'])));
    void openBooking(J b) => showBooking(context, js(b['_id']), onSeated: (order) => RestMain.openOrder(context, orderId: js(order['_id'])));
    final newTakeaway = Btn(t('rpos.newTakeaway'), icon: LucideIcons.shoppingBag, expand: true, onTap: widget.disabled ? null : () => RestMain.openOrder(context));

    if (big) {
      return Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                filters,
                Expanded(child: grid),
              ],
            ),
          ),
          Container(
            width: 300,
            margin: const EdgeInsets.fromLTRB(0, 0, 12, 12),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(color: c.card, borderRadius: BorderRadius.circular(22), boxShadow: c.cardShadow),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                newTakeaway,
                const SizedBox(height: 8),
                Btn(t('rpos.bookTable'), icon: LucideIcons.calendarPlus, kind: BtnKind.ghost, expand: true, onTap: widget.disabled ? null : () => showBookingForm(context)),
                const SizedBox(height: 16),
                Expanded(
                  child: Ticker(
                    builder: (context, now) => ListView(
                      children: [
                        Text('${t('rpos.takeaway')} · ${takeaways.length}', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
                        const SizedBox(height: 8),
                        if (takeaways.isEmpty) Muted(t('rpos.noOrders')),
                        for (final o in takeaways) Padding(padding: const EdgeInsets.only(bottom: 8), child: _TakeawayChip(o, now, full: true)),
                        if (bookings.isNotEmpty) ...[
                          const SizedBox(height: 10),
                          Text('${t('rpos.bookings')} · ${bookings.length}', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
                          const SizedBox(height: 8),
                          for (final b in bookings)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 8),
                              child: BookingChip(b, full: true, onTap: () => openBooking(b)),
                            ),
                        ],
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      );
    }
    return Stack(
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            filters,
            if (takeaways.isNotEmpty || bookings.isNotEmpty)
              SizedBox(
                height: 66,
                child: Ticker(
                  builder: (context, now) => ListView(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
                    children: [
                      for (final o in takeaways) Padding(padding: const EdgeInsets.only(right: 8), child: _TakeawayChip(o, now)),
                      for (final b in bookings)
                        Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: BookingChip(b, onTap: () => openBooking(b)),
                        ),
                    ],
                  ),
                ),
              ),
            Expanded(child: grid),
          ],
        ),
        Positioned(
          left: 16,
          right: 16,
          bottom: 16 + MediaQuery.paddingOf(context).bottom,
          child: Row(
            children: [
              Expanded(child: newTakeaway),
              const SizedBox(width: 10),
              RoundBtn(LucideIcons.calendarPlus, size: 50, tip: t('rpos.bookTable'), onTap: widget.disabled ? null : () => showBookingForm(context)),
            ],
          ),
        ),
      ],
    );
  }
}

class _TableTile extends StatelessWidget {
  final J table;
  final List<J> orders;
  final J? booking;
  final DateTime now;
  final String currency;
  final bool disabled;
  final VoidCallback onTap;
  const _TableTile({required this.table, required this.orders, required this.booking, required this.now, required this.currency, required this.disabled, required this.onTap});
  @override
  Widget build(BuildContext context) {
    final t = tr(context);
    final c = context.c;
    final pos = RestPos.i;
    final o = orders.isEmpty ? null : orders.first;
    final busy = o != null;
    final bill = o?['bill_printed'] == true;
    final bk = booking;
    final sum = orders.fold<double>(0, (a, x) => a + pos.totals(x).total);
    final seats = nz(table['seats']).toInt();
    final guestNew = orders.fold<double>(0, (a, x) => a + jlist(x['lines']).where((l) => l['from'] == 'guest' && l['status'] == 'new').fold<double>(0, (b, l) => b + nz(l['qty'])));
    final (bg, border, ink) = busy ? (bill ? c.warnBg : c.active, bill ? c.warn : c.brand, bill ? c.warn : c.brandInk) : (bk != null ? (c.limeBg, c.limeInk, c.limeInk) : (c.card, c.line, c.ink));
    return Opacity(
      opacity: disabled ? .5 : 1,
      child: Material(
        color: bg,
        borderRadius: BorderRadius.circular(20),
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: disabled ? null : onTap,
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: border, width: busy ? 2 : 1),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        js(table['name']),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18, color: ink),
                      ),
                    ),
                    if (guestNew > 0) Chip2('${guestNew.toInt()}', icon: LucideIcons.smartphone, tone: Tone.lime),
                    if (busy)
                      Text(
                        elapsed(o['opened_at'], now),
                        style: TextStyle(color: ink, fontSize: 12, fontWeight: FontWeight.w700),
                      ),
                  ],
                ),
                const Spacer(),
                if (busy) ...[
                  Text(
                    m$(sum, currency),
                    style: TextStyle(fontWeight: FontWeight.w800, fontSize: 17, color: ink),
                  ),
                  Text(
                    '${bill ? t('rpos.billPrinted') : js(jmap(o['opened_by'])['name'])}${orders.length > 1 ? ' · ×${orders.length}' : ''}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: ink, fontSize: 12),
                  ),
                  if (js(o['note']).isNotEmpty)
                    Text(
                      '📝 ${js(o['note'])}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: ink, fontSize: 12),
                    ),
                ] else if (bk != null) ...[
                  Text(
                    js(bk['name']),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontWeight: FontWeight.w700, color: ink),
                  ),
                  Text(
                    '${js(bk['time']).isNotEmpty ? '${t('rpos.bookedAt')} ${f.fmtTime(bk['time'])}' : t('rpos.booked')}${nz(bk['guests']) > 0 ? ' · ${nz(bk['guests']).toInt()}👤' : ''}',
                    style: TextStyle(color: ink, fontSize: 12),
                  ),
                ] else
                  Text('${t('rpos.free')}${seats > 0 ? ' · $seats👤' : ''}', style: TextStyle(color: c.muted, fontSize: 13)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _TakeawayChip extends StatelessWidget {
  final J o;
  final DateTime now;
  final bool full;
  const _TakeawayChip(this.o, this.now, {this.full = false});
  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final pos = RestPos.i;
    return Material(
      color: c.active,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => RestMain.openOrder(context, orderId: js(o['_id'])),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          child: Row(
            mainAxisSize: full ? MainAxisSize.max : MainAxisSize.min,
            children: [
              Text(
                '#${js(o['number'])}',
                style: TextStyle(fontWeight: FontWeight.w800, color: c.brandInk),
              ),
              const SizedBox(width: 10),
              Text(elapsed(o['opened_at'], now), style: TextStyle(color: c.brandInk, fontSize: 12.5)),
              if (full) const Spacer() else const SizedBox(width: 10),
              Text(
                m$(pos.totals(o).total, pos.currency),
                style: TextStyle(fontWeight: FontWeight.w800, color: c.brandInk),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// a shop with no tables: open orders + "New order"
class _OrdersOnly extends StatelessWidget {
  final bool disabled;
  const _OrdersOnly({required this.disabled});
  @override
  Widget build(BuildContext context) {
    final t = tr(context);
    final pos = RestPos.i;
    final open = pos.openOrders;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Btn(t('rpos.newOrder'), icon: LucideIcons.shoppingBag, expand: true, onTap: disabled ? null : () => RestMain.openOrder(context)),
          const SizedBox(height: 16),
          Text('${t('rpos.openOrders')} · ${open.length}', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
          const SizedBox(height: 8),
          Expanded(
            child: open.isEmpty
                ? Muted(t('rpos.noOrders'))
                : Ticker(
                    builder: (context, now) => GridView.builder(
                      padding: const EdgeInsets.only(bottom: 16),
                      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(maxCrossAxisExtent: 240, mainAxisExtent: 60, crossAxisSpacing: 8, mainAxisSpacing: 8),
                      itemCount: open.length,
                      itemBuilder: (context, i) => _TakeawayChip(open[i], now, full: true),
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

// which screen the restaurant POS shows now
class RestRoot extends StatefulWidget {
  const RestRoot({super.key});
  @override
  State<RestRoot> createState() => _RestRootState();
}

class _RestRootState extends State<RestRoot> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    final link = AppState.i.link ?? const {};
    RestPos.i.start(AppState.i.token, jmap(link['device']));
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) RestPos.i.resumed();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: RestPos.i,
      builder: (context, _) {
        final pos = RestPos.i;
        // not const: these screens read the engine, so they must rebuild with it
        if (pos.phase == 'unlinked') return RestUnlinked();
        if (pos.setup == null) return pos.phase == 'nosetup' ? RestNoSetup() : RestSplash();
        if (pos.shiftDone != null) return ShiftDone();
        if (pos.staff == null) return RestPinLock();
        if (pos.openShift == null) return RestOpenShift();
        return RestMain();
      },
    );
  }
}
