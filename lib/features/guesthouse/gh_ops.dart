import 'dart:async';

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/theme.dart';
import '../../widgets/ui.dart';
import '../mart/mart_kit.dart' show DayField, MartBox;
import '../restaurant/engine/calc.dart' show J, jmap, jlist, js, nz;
import '../restaurant/pos_ui.dart';
import 'engine/gh_pos.dart';
import 'gh_book.dart' show ghChips;
import 'gh_stay.dart' show ghNum;
import 'gh_ui.dart';

// Housekeeping (gh_housekeeping), Report, Expenses & profit (gh_expenses) — the web's GhOps.jsx + ReportTab

String _monthNow() => GhPos.localDay().substring(0, 7);
String _shiftMonth(String m, int n) {
  final p = m.split('-').map(int.parse).toList();
  final d = DateTime.utc(p[0], p[1] + n, 1);
  return '${d.year}-${d.month.toString().padLeft(2, '0')}';
}

// month ‹ This month ›
class _MonthNav extends StatelessWidget {
  final String month;
  final ValueChanged<String> onChanged;
  const _MonthNav(this.month, this.onChanged);
  @override
  Widget build(BuildContext context) {
    final t = tr(context);
    final now = _monthNow();
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(onPressed: () => onChanged(_shiftMonth(month, -1)), icon: const Icon(LucideIcons.chevronLeft)),
        Text(month == now ? t('gx.thisMonth') : ghMonth(month), style: const TextStyle(fontWeight: FontWeight.w800)),
        IconButton(onPressed: month.compareTo(now) >= 0 ? null : () => onChanged(_shiftMonth(month, 1)), icon: const Icon(LucideIcons.chevronRight)),
      ],
    );
  }
}

Widget _grid(BuildContext context, List<Widget> boxes, {int wideCols = 4}) => LayoutBuilder(
  builder: (_, box) {
    final per = box.maxWidth > 760 ? wideCols : 2;
    final w = (box.maxWidth - 8 * (per - 1)) / per;
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [for (final b in boxes) SizedBox(width: w, child: b)],
    );
  },
);

// ============================ HOUSEKEEPING ============================
class GhHousekeeping extends StatefulWidget {
  const GhHousekeeping({super.key});
  @override
  State<GhHousekeeping> createState() => _GhHousekeepingState();
}

class _GhHousekeepingState extends State<GhHousekeeping> {
  static const next = {'dirty': ('cleaning', 'gx.hkStart'), 'cleaning': ('ready', 'gx.hkDone'), 'ready': ('dirty', 'gx.hkDirty')};
  final pos = GhPos.i;
  J? _d;
  String _filter = 'all', _busy = '', _error = '';
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _load();
    _timer = Timer.periodic(const Duration(seconds: 30), (_) => _load());
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final r = await pos.api('GET', '/housekeeping');
      if (mounted) {
        setState(() {
          _d = jmap(r['data']);
          _error = '';
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = ghErr(context, e));
    }
  }

  Future<void> _set(J r, String state) async {
    setState(() => _busy = js(r['_id']));
    try {
      await pos.api('PUT', '/rooms/${r['_id']}/hk', {'state': state});
      await _load();
    } catch (e) {
      if (mounted) ghToast(context, ghErr(context, e));
    } finally {
      if (mounted) setState(() => _busy = '');
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = tr(context);
    final c = context.c;
    final d = _d;
    final counts = jmap(d?['counts']);
    final rooms = jlist(d?['rooms']).where((r) => _filter == 'all' || r['hk'] == _filter).toList();
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(12, 4, 12, 24),
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(t('gx.hkTitle'), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 18)),
                    if (!pos.isHousekeeper) Text(t('gx.hkSub'), maxLines: 2, style: TextStyle(color: c.muted, fontSize: 12.5)),
                  ],
                ),
              ),
              IconButton(onPressed: _load, icon: const Icon(LucideIcons.refreshCw, size: 18), tooltip: t('gx.hkRefresh')),
            ],
          ),
          const SizedBox(height: 6),
          if (_error.isNotEmpty) Alert(_error, tone: Tone.warn),
          if (d == null && _error.isEmpty)
            const Padding(
              padding: EdgeInsets.all(40),
              child: Center(child: CircularProgressIndicator()),
            ),
          if (d != null) ...[
            PosChips<String>(
              scroll: true,
              value: _filter,
              onTap: (v) => setState(() => _filter = v),
              options: [
                for (final k in ['all', 'dirty', 'cleaning', 'ready']) (k, '${k == 'all' ? t('gx.hkAll') : t('gx.hk.$k')} ${k == 'all' ? jlist(d['rooms']).length : nz(counts[k]).toInt()}'),
              ],
            ),
            const SizedBox(height: 10),
            if (rooms.isEmpty)
              Padding(
                padding: const EdgeInsets.all(30),
                child: Muted(t('gx.hkNone'), align: TextAlign.center),
              ),
            LayoutBuilder(
              builder: (_, box) {
                final per = (box.maxWidth / 220).floor().clamp(1, 5);
                final w = (box.maxWidth - 10 * (per - 1)) / per;
                return Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    for (final r in rooms)
                      SizedBox(
                        width: w,
                        child: () {
                          final hk = js(r['hk']).isEmpty ? 'ready' : js(r['hk']);
                          final (to, label) = next[hk]!;
                          final (fg, bg) = switch (hk) {
                            'dirty' => (c.danger, c.dangerBg),
                            'cleaning' => (c.warn, c.warnBg),
                            _ => (c.good, c.goodBg),
                          };
                          final guest = r['leaving'] == true ? t('gx.hkLeaving') : (r['guest'] == 'in' ? t('gx.hkIn') : (r['guest'] == 'arriving' ? t('gx.hkArriving') : t('gx.hkEmpty')));
                          final who = r['stay'] != null && r['guest'] != 'empty' ? ' · ${js(jmap(r['stay'])['name'])}' : '';
                          return Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: c.card,
                              borderRadius: BorderRadius.circular(16),
                              border: Border(top: BorderSide(color: fg, width: 4)),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                Row(
                                  children: [
                                    Expanded(
                                      child: Text(js(r['name']), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 18)),
                                    ),
                                    GhPill(t('gx.hk.$hk'), fg: fg, bg: bg),
                                  ],
                                ),
                                Text('${js(r['type'])}${js(r['floor']).isNotEmpty ? ' · ${js(r['floor'])}' : ''}', style: TextStyle(color: c.muted, fontSize: 12)),
                                const SizedBox(height: 4),
                                Text('$guest$who', style: const TextStyle(fontWeight: FontWeight.w600)),
                                if (js(r['hk_at']).isNotEmpty)
                                  Text(t('gx.hkBy', {'who': js(r['hk_by']).isEmpty ? '—' : js(r['hk_by']), 'time': ghTime(r['hk_at'])}), style: TextStyle(color: c.muted, fontSize: 11.5)),
                                const SizedBox(height: 10),
                                Btn(
                                  t(label),
                                  small: true,
                                  expand: true,
                                  kind: to == 'dirty' ? BtnKind.ghost : BtnKind.primary,
                                  busy: _busy == js(r['_id']),
                                  onTap: pos.readOnly || _busy.isNotEmpty ? null : () => _set(r, to),
                                ),
                              ],
                            ),
                          );
                        }(),
                      ),
                  ],
                );
              },
            ),
          ],
        ],
      ),
    );
  }
}

// ============================ REPORT ============================
class GhReport extends StatefulWidget {
  const GhReport({super.key});
  @override
  State<GhReport> createState() => _GhReportState();
}

class _GhReportState extends State<GhReport> {
  final pos = GhPos.i;
  String _month = _monthNow();
  J? _r;
  String _error = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _r = null;
      _error = '';
    });
    try {
      final r = await pos.api('GET', '/report?month=$_month');
      if (mounted) setState(() => _r = jmap(r['data']));
    } catch (e) {
      if (mounted) setState(() => _error = ghErr(context, e));
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = tr(context);
    final c = context.c;
    final r = _r;
    final cur = js(r?['currency']).isEmpty ? pos.currency : js(r?['currency']);
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(12, 4, 12, 24),
        children: [
          Row(
            children: [
              Expanded(
                child: Text(t('gh.repTitle'), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 18)),
              ),
              _MonthNav(_month, (m) {
                _month = m;
                _load();
              }),
            ],
          ),
          if (_error.isNotEmpty) Alert(_error, tone: Tone.warn),
          if (r == null && _error.isEmpty)
            const Padding(
              padding: EdgeInsets.all(40),
              child: Center(child: CircularProgressIndicator()),
            ),
          if (r != null) ...[
            _grid(context, [
              MartBox(icon: LucideIcons.bedDouble, value: '${nz(r['occupancy']).round()}%', label: t('gh.occupancy'), fg: const Color(0xFF1D4ED8)),
              MartBox(icon: LucideIcons.moon, value: '${nz(r['nights']).toInt()}', label: t('gh.nightsSold'), fg: c.ink),
              MartBox(icon: LucideIcons.tag, value: ghMoney(r['adr'], cur), label: t('gh.adr'), fg: c.ink),
              MartBox(icon: LucideIcons.wallet, value: ghMoney(nz(r['room_revenue']) + nz(r['extras']), cur), label: t('gh.roomRevenue'), fg: c.good),
              MartBox(icon: LucideIcons.banknote, value: ghMoney(r['received'], cur), label: t('gh.received'), fg: c.brandInk),
            ], wideCols: 5),
            const SizedBox(height: 12),
            Panel(
              padding: const EdgeInsets.all(14),
              margin: const EdgeInsets.only(bottom: 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(t('gh.occupancy'), style: const TextStyle(fontWeight: FontWeight.w800)),
                  const SizedBox(height: 10),
                  SizedBox(
                    height: 130,
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        for (final d in jlist(r['days']))
                          () {
                            final rooms = nz(r['rooms']);
                            final pct = rooms > 0 ? nz(d['occupied']) / rooms : 0.0;
                            return Expanded(
                              child: Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 1),
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.end,
                                  children: [
                                    Flexible(
                                      child: FractionallySizedBox(
                                        heightFactor: pct < .02 ? .02 : pct,
                                        child: Container(
                                          decoration: BoxDecoration(color: pct >= .8 ? c.good : const Color(0xFF3B82F6), borderRadius: BorderRadius.circular(3)),
                                        ),
                                      ),
                                    ),
                                    const SizedBox(height: 3),
                                    Text(() {
                                      final n = int.parse(js(d['day']).substring(8));
                                      return MediaQuery.sizeOf(context).width < 600 && n != 1 && n % 5 != 0 ? '' : '$n'; // a phone: every 5th day
                                    }(), style: TextStyle(fontSize: 8.5, color: c.muted)),
                                  ],
                                ),
                              ),
                            );
                          }(),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            LayoutBuilder(
              builder: (_, box) {
                final a = Panel(
                  padding: const EdgeInsets.all(14),
                  margin: const EdgeInsets.only(bottom: 10),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(t('gh.byType'), style: const TextStyle(fontWeight: FontWeight.w800)),
                      const SizedBox(height: 6),
                      for (final x in jlist(r['by_type'])) SumRow('${js(x['name'])} · ${t('gh.nights', {'n': nz(x['nights']).toInt()})}', ghMoney(x['revenue'], cur)),
                    ],
                  ),
                );
                final b = Panel(
                  padding: const EdgeInsets.all(14),
                  margin: const EdgeInsets.only(bottom: 10),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(t('gh.byMethod'), style: const TextStyle(fontWeight: FontWeight.w800)),
                      const SizedBox(height: 6),
                      if (jmap(r['by_method']).isEmpty) const Muted('—'),
                      for (final e in jmap(r['by_method']).entries) SumRow(t('gh.methods.${e.key}'), ghMoney(e.value, cur)),
                    ],
                  ),
                );
                return box.maxWidth > 700
                    ? Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(child: a),
                          const SizedBox(width: 10),
                          Expanded(child: b),
                        ],
                      )
                    : Column(children: [a, b]);
              },
            ),
            if (jlist(r['by_room']).isNotEmpty)
              Panel(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(t('gh.byRoom'), style: const TextStyle(fontWeight: FontWeight.w800)),
                    const SizedBox(height: 8),
                    for (final x in jlist(r['by_room']))
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 5),
                        child: Row(
                          children: [
                            SizedBox(
                              width: 80,
                              child: Text(js(x['name']), style: const TextStyle(fontWeight: FontWeight.w800)),
                            ),
                            Expanded(
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(4),
                                child: LinearProgressIndicator(
                                  value: (nz(x['occupancy']) / 100).clamp(0, 1).toDouble(),
                                  minHeight: 8,
                                  color: nz(x['occupancy']) >= 80 ? c.good : const Color(0xFF3B82F6),
                                  backgroundColor: c.chip,
                                ),
                              ),
                            ),
                            SizedBox(
                              width: 44,
                              child: Text(
                                '${nz(x['occupancy']).round()}%',
                                textAlign: TextAlign.right,
                                style: TextStyle(color: c.muted, fontSize: 12),
                              ),
                            ),
                            SizedBox(
                              width: 86,
                              child: Text(
                                ghMoney(x['revenue'], cur),
                                textAlign: TextAlign.right,
                                style: const TextStyle(fontWeight: FontWeight.w700),
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
          ],
        ],
      ),
    );
  }
}

// ============================ EXPENSES & PROFIT ============================
const catIcon = {
  'salary': '👥',
  'electricity': '⚡',
  'water': '💧',
  'internet': '📶',
  'supplies': '🧴',
  'laundry': '🧺',
  'repair': '🔧',
  'food': '🍽️',
  'rent': '🏠',
  'tax': '🧾',
  'marketing': '📣',
  'commission': '🌐',
  'other': '📦',
};
const _cats = ['salary', 'electricity', 'water', 'internet', 'supplies', 'laundry', 'repair', 'food', 'rent', 'tax', 'marketing', 'commission', 'other'];

class GhExpenses extends StatefulWidget {
  const GhExpenses({super.key});
  @override
  State<GhExpenses> createState() => _GhExpensesState();
}

class _GhExpensesState extends State<GhExpenses> {
  final pos = GhPos.i;
  String _month = _monthNow();
  J? _ex, _pf;
  String _error = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _ex = null;
      _pf = null;
      _error = '';
    });
    try {
      final r = await Future.wait([pos.api('GET', '/expenses?month=$_month'), pos.api('GET', '/profit?month=$_month')]);
      if (mounted) {
        setState(() {
          _ex = jmap(r[0]['data']);
          _pf = jmap(r[1]['data']);
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = ghErr(context, e));
    }
  }

  String _signed(Object? v, String cur) => nz(v) < 0 ? '−${ghMoney(-nz(v), cur)}' : ghMoney(v, cur);

  @override
  Widget build(BuildContext context) {
    final t = tr(context);
    final c = context.c;
    final cur = pos.currency;
    final ex = _ex, pf = _pf;
    final series = jlist(pf?['series']);
    final max = series.fold<double>(1, (a, s) => [a, nz(s['income']), nz(s['expenses'])].reduce((x, y) => x > y ? x : y));
    final byCat = jmap(ex?['by_category']).entries.toList()..sort((a, b) => nz(b.value).compareTo(nz(a.value)));
    final catMax = byCat.fold<double>(1, (a, e) => nz(e.value) > a ? nz(e.value) : a);
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(12, 4, 12, 24),
        children: [
          Row(
            children: [
              Expanded(
                child: Text(t('gx.exTitle'), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 18)),
              ),
              Btn(t('gx.exAdd'), icon: LucideIcons.plus, small: true, onTap: pos.readOnly ? null : () => _edit(context, null)),
            ],
          ),
          Align(
            alignment: Alignment.centerLeft,
            child: _MonthNav(_month, (m) {
              _month = m;
              _load();
            }),
          ),
          if (_error.isNotEmpty) Alert(_error, tone: Tone.warn),
          if ((ex == null || pf == null) && _error.isEmpty)
            const Padding(
              padding: EdgeInsets.all(40),
              child: Center(child: CircularProgressIndicator()),
            ),
          if (ex != null && pf != null) ...[
            _grid(context, [
              MartBox(icon: LucideIcons.arrowDownLeft, value: ghMoney(pf['income'], cur), label: t('gx.exIncome'), fg: const Color(0xFF1D4ED8)),
              MartBox(icon: LucideIcons.arrowUpRight, value: ghMoney(pf['expenses'], cur), label: t('gx.exOut'), fg: c.danger),
              MartBox(
                icon: LucideIcons.trendingUp,
                value: _signed(pf['profit'], cur),
                label: '${t('gx.exProfit')}${nz(pf['income']) > 0 ? ' · ${t('gx.exMargin', {'n': nz(pf['margin']).round()})}' : ''}',
                fg: nz(pf['profit']) >= 0 ? c.good : c.danger,
              ),
            ], wideCols: 3),
            const SizedBox(height: 12),
            Panel(
              padding: const EdgeInsets.all(14),
              margin: const EdgeInsets.only(bottom: 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(t('gx.exMonths'), style: const TextStyle(fontWeight: FontWeight.w800)),
                  const SizedBox(height: 10),
                  SizedBox(
                    height: 150,
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        for (final s in series)
                          Expanded(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.end,
                              children: [
                                Flexible(
                                  child: Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    crossAxisAlignment: CrossAxisAlignment.end,
                                    children: [
                                      for (final (v, col) in [(nz(s['income']), const Color(0xFF3B82F6)), (nz(s['expenses']), c.danger)])
                                        FractionallySizedBox(
                                          heightFactor: (v / max) < .02 ? .02 : v / max,
                                          child: Container(
                                            width: 12,
                                            margin: const EdgeInsets.symmetric(horizontal: 1.5),
                                            decoration: BoxDecoration(color: col, borderRadius: BorderRadius.circular(3)),
                                          ),
                                        ),
                                    ],
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  _signed(s['profit'], cur),
                                  style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: nz(s['profit']) < 0 ? c.danger : c.ink),
                                ),
                                Text(ghMonth(js(s['month'])).split(' ').first.substring(0, 3), style: TextStyle(fontSize: 10.5, color: c.muted)),
                              ],
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            if (byCat.isNotEmpty)
              Panel(
                padding: const EdgeInsets.all(14),
                margin: const EdgeInsets.only(bottom: 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(t('gx.exByCat'), style: const TextStyle(fontWeight: FontWeight.w800)),
                    const SizedBox(height: 6),
                    for (final e in byCat)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            SumRow('${catIcon[e.key] ?? ''} ${t('gx.cats.${e.key}')}', ghMoney(e.value, cur)),
                            ClipRRect(
                              borderRadius: BorderRadius.circular(3),
                              child: LinearProgressIndicator(value: nz(e.value) / catMax, minHeight: 5, color: c.danger, backgroundColor: c.chip),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
            Text('${t('gx.exOut')} · ${ghMoney(ex['total'], cur)}', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
            const SizedBox(height: 6),
            if (jlist(ex['rows']).isEmpty)
              Padding(
                padding: const EdgeInsets.all(20),
                child: Muted(t('gx.exNone'), align: TextAlign.center),
              ),
            for (final x in jlist(ex['rows']))
              Card(
                margin: const EdgeInsets.only(bottom: 6),
                elevation: 0,
                color: c.card,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                child: ListTile(
                  onTap: pos.readOnly ? null : () => _edit(context, x),
                  leading: Text(catIcon[js(x['category'])] ?? '📦', style: const TextStyle(fontSize: 22)),
                  title: Text(t('gx.cats.${js(x['category'])}'), style: const TextStyle(fontWeight: FontWeight.w700)),
                  subtitle: Text([ghDay(js(x['day']), weekday: true), t('gx.exMethods.${js(x['method'])}'), js(x['note']), js(x['by'])].where((s) => s.isNotEmpty).join(' · '), maxLines: 2),
                  trailing: Text(
                    '−${ghMoney(x['amount'], cur)}',
                    style: TextStyle(fontWeight: FontWeight.w800, color: c.danger),
                  ),
                ),
              ),
          ],
        ],
      ),
    );
  }

  Future<void> _edit(BuildContext context, J? row) async {
    final t = tr(context);
    final desk = pos.desk;
    final amount = TextEditingController(text: row == null ? '' : ghNum(row['amount']));
    final note = TextEditingController(text: js(row?['note']));
    var day = row == null ? pos.today : js(row['day']);
    var cat = js(row?['category']).isEmpty ? 'supplies' : js(row!['category']);
    var method = js(row?['method']).isEmpty ? 'cash' : js(row!['method']);
    var busy = false, sure = false;
    var error = '';
    final cats = _ex?['categories'] is List ? (_ex!['categories'] as List).map((e) => '$e').toList() : _cats;
    final ok = await posSheet<bool>(
      context,
      title: row == null ? t('gx.exAdd') : t('gx.exEdit'),
      maxWidth: 560,
      body: (ctx) => StatefulBuilder(
        builder: (ctx, set) {
          Future<void> run(Future<J> Function() fn) async {
            set(() {
              busy = true;
              error = '';
            });
            try {
              await fn();
              if (ctx.mounted) Navigator.pop(ctx, true);
            } catch (e) {
              set(() {
                busy = false;
                error = ghErr(ctx, e);
              });
            }
          }

          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Expanded(
                    child: Field(
                      controller: amount,
                      label: '${t('gx.exAmount')} *',
                      hint: pos.currency == 'KHR' ? '40000' : '25',
                      keyboard: const TextInputType.numberWithOptions(decimal: true),
                      autofocus: true,
                      onChanged: (_) => set(() {}),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: DayField(label: t('gx.exDay'), value: day, show: (d) => ghDay(d, weekday: true), onPick: (v) => set(() => day = v.compareTo(pos.today) > 0 ? pos.today : v)),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Text(t('gx.exCat'), style: const TextStyle(fontWeight: FontWeight.w700)),
              const SizedBox(height: 6),
              ghChips(ctx, [for (final k in cats) (k, '${catIcon[k] ?? ''} ${t('gx.cats.$k')}')], cat, (k) => set(() => cat = k)),
              const SizedBox(height: 12),
              Text(t('gx.exMethod'), style: const TextStyle(fontWeight: FontWeight.w700)),
              const SizedBox(height: 6),
              ghChips(
                ctx,
                [
                  for (final k in ['cash', 'bank']) (k, t('gx.exMethods.$k')),
                ],
                method,
                (k) => set(() => method = k),
              ),
              const SizedBox(height: 12),
              Field(controller: note, label: t('gx.exNote'), hint: t('gx.exNotePh'), maxLength: 200),
              if (error.isNotEmpty) ...[const SizedBox(height: 8), Alert(error)],
              const SizedBox(height: 12),
              Row(
                children: [
                  if (row != null && !desk)
                    sure
                        ? FilledButton(
                            style: FilledButton.styleFrom(backgroundColor: ctx.c.danger),
                            onPressed: busy ? null : () => run(() => pos.api('DELETE', '/expenses/${row['_id']}')),
                            child: Text(t('gx.exSure')),
                          )
                        : TextButton.icon(
                            style: TextButton.styleFrom(foregroundColor: ctx.c.danger),
                            onPressed: busy ? null : () => set(() => sure = true),
                            icon: const Icon(LucideIcons.trash2, size: 16),
                            label: Text(t('gx.exDel')),
                          ),
                  const Spacer(),
                  Btn(
                    busy ? t('gx.saving') : t('gx.save'),
                    busy: busy,
                    onTap: busy || nz(amount.text) <= 0 || (row != null && desk)
                        ? null
                        : () {
                            final body = {'day': day, 'category': cat, 'amount': nz(amount.text), 'method': method, 'note': note.text.trim()};
                            run(() => row == null ? pos.api('POST', '/expenses', body) : pos.api('PUT', '/expenses/${row['_id']}', body));
                          },
                  ),
                ],
              ),
            ],
          );
        },
      ),
    );
    if (ok == true) {
      if (context.mounted) ghToast(context, t('gx.saved'));
      _load();
    }
  }
}
