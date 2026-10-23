import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/app_state.dart';
import '../../core/format.dart' as f;
import '../../core/pos_api.dart' show ApiError;
import '../../core/theme.dart';
import '../../widgets/ui.dart';
import 'engine/calc.dart';
import 'engine/rest_pos.dart';
import 'pos_ui.dart';
import 'rest_order.dart' show lineName;
import 'rest_print.dart';

// The POS's own reports: sales of every device on any days (or just this shift, worked out here — works offline)
// + every bill with its lines and payments.
Future<void> openReports(BuildContext context) => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const RestReports()));

String _two(int x) => x.toString().padLeft(2, '0');
String _day(DateTime d) => '${d.year}-${_two(d.month)}-${_two(d.day)}';
DateTime get _localNow => DateTime.now().toUtc().add(const Duration(hours: 7)); // Cambodia, like the cloud
String get _today => _day(_localNow);
String _addDays(String day, int n) => _day(DateTime.parse('${day}T00:00:00Z').add(Duration(days: n)));

class RestReports extends StatefulWidget {
  const RestReports({super.key});
  @override
  State<RestReports> createState() => _RestReportsState();
}

class _RestReportsState extends State<RestReports> {
  String _scope = 'today'; // today | yesterday | d7 | d30 | custom | shift
  ({String from, String to}) _custom = (from: _today, to: _today);
  J? _remote; // { report, orders, range, history, bills_total, at }
  bool _loading = false;
  String _error = '';
  String _filter = 'all';
  final _q = TextEditingController();
  final pos = RestPos.i;

  ({String from, String to})? get _range => switch (_scope) {
    'shift' => null,
    'yesterday' => (from: _addDays(_today, -1), to: _addDays(_today, -1)),
    'd7' => (from: _addDays(_today, -6), to: _today),
    'd30' => (from: _addDays(_today, -29), to: _today),
    'custom' => _custom,
    _ => (from: _today, to: _today),
  };

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _q.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final r = _range;
    if (r == null) return setState(() {});
    setState(() {
      _loading = true;
      _error = '';
    });
    try {
      final data = await pos.report(r.from, r.to);
      final byId = {for (final o in jlist(data['orders'])) js(o['_id']): o};
      final range = jmap(data['range']);
      if (range['to'] == range['today']) {
        // bills still waiting on this device are newer than the cloud's copy; open bills are already here
        for (final o in pos.orders.values) {
          if (o['_dirty'] == true && (byId.containsKey(js(o['_id'])) || o['status'] != 'open')) byId[js(o['_id'])] = o;
          if (o['status'] == 'open' && !byId.containsKey(js(o['_id']))) byId[js(o['_id'])] = o;
        }
      }
      if (!mounted) return;
      setState(() => _remote = {...data, 'orders': byId.values.toList(), 'at': DateTime.now().toIso8601String()});
    } on ApiError catch (e) {
      if (mounted) setState(() => _error = e.network ? tr(context)('rpos.needInternet') : e.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _pickDates() async {
    final now = _localNow;
    final v = await showDateRangePicker(
      context: context,
      firstDate: DateTime(now.year - 3),
      lastDate: DateTime(now.year, now.month, now.day),
      initialDateRange: DateTimeRange(start: DateTime.parse(_custom.from), end: DateTime.parse(_custom.to)),
    );
    if (v == null) return;
    setState(() {
      _custom = (from: _day(v.start), to: _day(v.end));
      _scope = 'custom';
    });
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final t = app.t;
    final c = context.c;
    final cur = pos.currency;
    final shift = pos.openShift;
    final localOrders = pos.orders.values.where((o) => shift != null && o['shift_id'] == shift['_id']).toList();
    final showDay = _scope != 'shift' && _remote != null && _error.isEmpty && !_loading;
    final report = showDay ? jmap(_remote!['report']) : salesReport(localOrders, pos.moneyS);
    final orders = showDay ? jlist(_remote!['orders']) : localOrders;
    final moreBills = showDay ? nz(_remote!['bills_total']).toInt() - orders.length : 0;
    final open = orders.where((o) => o['status'] == 'open').length;
    final q = _q.text.trim().toLowerCase();
    final list = orders.where((o) => (_filter == 'all' || o['status'] == _filter) && (q.isEmpty || '${o['number']} ${o['table_name'] ?? ''}'.toLowerCase().contains(q))).toList()
      ..sort((a, b) => js(b['paid_at'] ?? b['opened_at']).compareTo(js(a['paid_at'] ?? a['opened_at'])));
    final range = jmap(_remote?['range']);
    final multi = nz(range['days']) > 1;
    final sub = _scope == 'shift'
        ? (shift == null ? '' : '${t('rpos.shiftStarted', {'t': f.fmtTime(shift['opened_at'])})} · ${js(jmap(shift['opened_by'])['name'])}')
        : showDay
        ? '${f.fmtDate(range['from'], lang: app.lang)}${range['from'] != range['to'] ? ' → ${f.fmtDate(range['to'], lang: app.lang)}' : ''} · ${t('rpos.allDevicesShort')} · ${t('rpos.updated', {'t': f.fmtTime(_remote!['at'])})}'
        : (_error.isNotEmpty ? t('rpos.shiftInstead') : t('rpos.loadingReport'));

    final byMethod = jlist(report['by_method']);
    final methodsTotal = byMethod.fold<double>(0, (a, x) => a + (nz(x['value']) > 0 ? nz(x['value']) : 0));
    final items = jlist(report['by_item']).take(8).toList();
    final maxQty = items.fold<double>(1, (a, x) => nz(x['qty']) > a ? nz(x['qty']) : a);
    final byType = jmap(report['by_type']);

    Widget kpi(IconData icon, String label, String value, {String sub = '', bool main = false, bool warn = false}) => Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(gradient: main ? c.gradient : null, color: main ? null : (warn ? c.warnBg : c.card), borderRadius: BorderRadius.circular(18), boxShadow: main ? null : c.cardShadow),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 15, color: main ? Colors.white : c.muted),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  label,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: main ? Colors.white : c.muted, fontSize: 12.5, fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              value,
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: main ? Colors.white : (warn ? c.warn : c.ink)),
            ),
          ),
          if (sub.isNotEmpty) Text(sub, style: TextStyle(color: main ? Colors.white.withValues(alpha: .85) : c.muted, fontSize: 12)),
        ],
      ),
    );

    Widget bar(String label, String value, double frac) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis)),
              Text(value, style: const TextStyle(fontWeight: FontWeight.w800)),
            ],
          ),
          const SizedBox(height: 4),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(value: frac.clamp(0, 1), minHeight: 6, backgroundColor: c.chip, color: c.brand),
          ),
        ],
      ),
    );

    Widget panel(String title, IconData? icon, List<Widget> children) => Panel(
      padding: const EdgeInsets.all(16),
      margin: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              if (icon != null) ...[Icon(icon, size: 16, color: c.brand), const SizedBox(width: 6)],
              Text(title, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
            ],
          ),
          const SizedBox(height: 8),
          ...children,
        ],
      ),
    );

    final stats = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        GridView.count(
          crossAxisCount: 2,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: 10,
          crossAxisSpacing: 10,
          childAspectRatio: 1.75,
          children: [
            kpi(LucideIcons.trendingUp, t('rpos.sales'), m$(report['sales'], cur), sub: m$(otherCurrency(report['sales'], pos.moneyS), other(cur)), main: true),
            kpi(LucideIcons.receiptText, t('rpos.bills'), '${nz(report['bills']).toInt()}', sub: open > 0 ? '$open ${t('rpos.fOpen').toLowerCase()}' : ''),
            kpi(LucideIcons.users, t('rpos.avgBill'), m$(report['avg'], cur)),
            kpi(
              LucideIcons.ban,
              t('rpos.cancelledBills'),
              '${nz(report['void_orders']).toInt()}',
              sub: nz(report['void_value']) > 0 ? m$(report['void_value'], cur) : '',
              warn: nz(report['void_orders']) > 0,
            ),
          ],
        ),
        const SizedBox(height: 12),
        panel(t('rpos.byMethod'), LucideIcons.wallet, [
          if (byMethod.isEmpty) Muted('—'),
          for (final x in byMethod) bar('${js(x['name'])}  ×${nz(x['count']).toInt()}', m$(x['value'], cur), methodsTotal == 0 ? 0 : (nz(x['value']) > 0 ? nz(x['value']) : 0) / methodsTotal),
        ]),
        panel(t('rpos.topItems'), LucideIcons.flame, [
          if (items.isEmpty) Muted('—'),
          for (final x in items) bar('${nameOf(x, app.lang)}${js(x['size']).isNotEmpty ? ' · ${js(x['size'])}' : ''}', '×${_n(x['qty'])}', nz(x['qty']) / maxQty),
        ]),
        if (showDay && jlist(report['by_staff']).isNotEmpty)
          panel(t('rpos.byStaff'), LucideIcons.userRound, [for (final x in jlist(report['by_staff'])) SumRow('${js(x['name'])} · ${nz(x['bills']).toInt()}', m$(x['sales'], cur))]),
        panel(t('rpos.byType'), null, [
          SumRow('${t('rpos.dineIn')} · ${nz(jmap(byType['dine_in'])['bills']).toInt()}', m$(jmap(byType['dine_in'])['sales'], cur)),
          SumRow('${t('rpos.takeaway')} · ${nz(jmap(byType['takeaway'])['bills']).toInt()}', m$(jmap(byType['takeaway'])['sales'], cur)),
          if (nz(report['discounts']) > 0) SumRow(t('rpos.discounts'), '−${m$(report['discounts'], cur)}'),
        ]),
      ],
    );

    final bills = Panel(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(LucideIcons.receiptText, size: 16, color: c.brand),
              const SizedBox(width: 6),
              Text('${t('rpos.invoices')} · ${list.length}', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
            ],
          ),
          const SizedBox(height: 10),
          Field(controller: _q, hint: t('rpos.searchBills'), icon: LucideIcons.search, onChanged: (_) => setState(() {})),
          const SizedBox(height: 10),
          PosChips<String>(
            scroll: true,
            value: _filter,
            onTap: (v) => setState(() => _filter = v),
            options: [('all', t('rpos.all')), ('paid', t('rpos.fPaid')), ('open', t('rpos.fOpen')), ('void', t('rpos.fCancelled'))],
          ),
          const SizedBox(height: 6),
          if (list.isEmpty)
            Padding(
              padding: const EdgeInsets.all(20),
              child: Muted(t('rpos.noBills'), align: TextAlign.center),
            ),
          if (moreBills > 0)
            Padding(
              padding: const EdgeInsets.all(8),
              child: Muted(t('rpos.moreBills', {'n': moreBills}), align: TextAlign.center),
            ),
          for (final o in list) _BillRow(o, multiDay: showDay && multi),
        ],
      ),
    );

    return Scaffold(
      backgroundColor: c.appBg,
      appBar: AppBar(
        backgroundColor: c.appBg,
        surfaceTintColor: Colors.transparent,
        title: Text(t('rpos.reportsTitle'), style: const TextStyle(fontWeight: FontWeight.w800)),
        actions: [
          if (_scope != 'shift')
            IconButton(
              onPressed: _loading ? null : _load,
              tooltip: t('rpos.refresh'),
              icon: _loading ? SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: c.brand)) : const Icon(LucideIcons.refreshCw),
            ),
        ],
      ),
      body: ListenableBuilder(
        listenable: pos,
        builder: (context, _) => ListView(
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 24),
          children: [
            PosChips<String>(
              scroll: true,
              value: _scope,
              onTap: (v) {
                if (v == 'custom') {
                  _pickDates();
                  return;
                }
                setState(() => _scope = v);
                _load();
              },
              options: [
                ('today', t('rpos.today')),
                ('yesterday', t('rpos.yesterday')),
                ('d7', t('rpos.last7')),
                ('d30', t('rpos.last30')),
                ('custom', _scope == 'custom' ? '${_custom.from.substring(5)} → ${_custom.to.substring(5)}' : t('rpos.pickDates')),
                ('shift', t('rpos.myShift')),
              ],
            ),
            const SizedBox(height: 10),
            if (_scope != 'shift' && _error.isNotEmpty) ...[Alert(_error, tone: Tone.warn), const SizedBox(height: 8)],
            if (showDay && jmap(_remote!['history'])['limited'] == true) ...[
              Alert(t('rpos.historyCut', {'n': jmap(_remote!['history'])['free_days']}), tone: Tone.brand),
              const SizedBox(height: 8),
            ],
            Muted(sub),
            const SizedBox(height: 12),
            if (wide(context))
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: stats),
                  const SizedBox(width: 12),
                  Expanded(child: bills),
                ],
              )
            else ...[
              stats,
              bills,
            ],
          ],
        ),
      ),
    );
  }
}

String _n(Object? v) {
  final x = nz(v);
  return x == x.roundToDouble() ? x.toInt().toString() : x.toString();
}

class _BillRow extends StatelessWidget {
  final J o;
  final bool multiDay;
  const _BillRow(this.o, {required this.multiDay});
  @override
  Widget build(BuildContext context) {
    final t = tr(context);
    final c = context.c;
    final pos = RestPos.i;
    final st = js(o['status']);
    final at = o['paid_at'] ?? o['opened_at'];
    final who = js(jmap(o['closed_by'])['name']).isNotEmpty ? js(jmap(o['closed_by'])['name']) : js(jmap(o['opened_by'])['name']);
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: () => showBill(context, o),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
        child: Row(
          children: [
            SizedBox(
              width: 76,
              child: Text('#${js(o['number'])}', style: const TextStyle(fontWeight: FontWeight.w800)),
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(js(o['table_name']).isNotEmpty ? '${t('rpos.table')} ${js(o['table_name'])}' : t('rpos.takeaway'), style: const TextStyle(fontWeight: FontWeight.w600)),
                  Text(
                    '${multiDay ? f.fmtDate(at, time: true) : f.fmtTime(at)} · $who${js(o['device_name']).isNotEmpty ? ' · ${js(o['device_name'])}' : ''}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: c.muted, fontSize: 12),
                  ),
                ],
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(m$(pos.totals(o).total, pos.currency), style: const TextStyle(fontWeight: FontWeight.w800)),
                Chip2(st == 'paid' ? t('rpos.fPaid') : (st == 'void' ? t('rpos.fCancelled') : t('rpos.fOpen')), tone: st == 'paid' ? Tone.good : (st == 'void' ? Tone.danger : Tone.warn)),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// one bill: what was ordered, the totals and how it was paid
Future<void> showBill(BuildContext context, J o) {
  final app = AppScope.of(context);
  final t = app.t;
  final pos = RestPos.i;
  final cur = pos.currency;
  final tot = pos.totals(o);
  final st = js(o['status']);
  return posSheet(
    context,
    title: '${st == 'paid' ? t('rpos.receipt') : (st == 'void' ? t('rpos.fCancelled') : t('rpos.billTitle'))} · #${js(o['number'])}',
    maxWidth: 480,
    footer: st == 'void'
        ? null
        : (ctx) => Btn(
            t('rpos.reprint'),
            icon: LucideIcons.printer,
            expand: true,
            onTap: () {
              Navigator.pop(ctx);
              previewReceipt(context, o, paid: st == 'paid');
            },
          ),
    body: (ctx) {
      final c = ctx.c;
      final lines = jlist(o['lines']).where((l) => l['void_reason'] != 'removed').toList();
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Muted(
            '${js(o['table_name']).isNotEmpty ? '${t('rpos.table')} ${js(o['table_name'])}' : t('rpos.takeaway')} · ${f.fmtDate(o['paid_at'] ?? o['opened_at'], time: true, lang: app.lang)} · ${t('rpos.cashier')}: ${js(jmap(o['closed_by'])['name']).isNotEmpty ? js(jmap(o['closed_by'])['name']) : js(jmap(o['opened_by'])['name'])}',
          ),
          if (js(o['void_reason']).isNotEmpty && st == 'void') ...[const SizedBox(height: 8), Alert('${t('rpos.reason')}: ${js(o['void_reason'])}')],
          const SizedBox(height: 10),
          for (final l in lines)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 34,
                    child: Text(
                      '${_n(l['qty'])}×',
                      style: TextStyle(color: c.muted, fontWeight: FontWeight.w700),
                    ),
                  ),
                  Expanded(
                    child: Text(
                      '${lineName(l, app.lang)}${js(l['size']).isNotEmpty ? ' · ${js(l['size'])}' : ''}${jlist(l['addons']).isNotEmpty ? '\n${jlist(l['addons']).map((a) => '+ ${js(a['name'])}').join(', ')}' : ''}',
                      style: TextStyle(decoration: l['status'] == 'void' ? TextDecoration.lineThrough : null, color: l['status'] == 'void' ? c.muted : c.ink),
                    ),
                  ),
                  Text(m$(lineTotal(l) - lineOff(l), cur), style: const TextStyle(fontWeight: FontWeight.w700)),
                ],
              ),
            ),
          Divider(color: c.line),
          SumRow(t('rpos.subtotal'), m$(tot.subtotal, cur)),
          if (tot.discount > 0) SumRow(t('rpos.discount'), '−${m$(tot.discount, cur)}', color: c.good),
          if (tot.service > 0) SumRow(t('rpos.service'), m$(tot.service, cur)),
          if (tot.vat > 0) SumRow(tot.vatIncluded ? t('rpos.vatIncl') : t('rpos.vat'), m$(tot.vat, cur)),
          SumRow(t('rpos.total'), m$(tot.total, cur), big: true),
          for (final p in jlist(o['payments'])) SumRow(js(p['method']), m$(p['amount'], js(p['currency']))),
          if (nz(jmap(o['change'])['usd']) > 0 || nz(jmap(o['change'])['khr']) > 0)
            SumRow(
              t('rpos.change'),
              [if (nz(jmap(o['change'])['usd']) > 0) m$(jmap(o['change'])['usd'], 'USD'), if (nz(jmap(o['change'])['khr']) > 0) m$(jmap(o['change'])['khr'], 'KHR')].join(' + '),
            ),
        ],
      );
    },
  );
}
