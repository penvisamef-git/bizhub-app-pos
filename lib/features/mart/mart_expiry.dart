import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/app_state.dart';
import '../../core/format.dart' as f;
import '../../core/i18n.dart';
import '../../core/theme.dart';
import '../../widgets/ui.dart';
import '../restaurant/engine/calc.dart' show J, jmap, jlist, js, nz;
import '../restaurant/pos_ui.dart';
import 'engine/mart_pos.dart';
import 'mart_kit.dart';
import 'mart_receipt.dart' show qtyOf;

// Expiry dates (mart_expiry, managers): what is on the shelf with a day, the soonest first (sell these first),
// throw away what went bad, and the waste record of the month — the web's Expiry tab.
class MartExpiry extends StatefulWidget {
  const MartExpiry({super.key});
  @override
  State<MartExpiry> createState() => _MartExpiryState();
}

class _MartExpiryState extends State<MartExpiry> {
  final pos = MartPos.i;
  J? _data, _waste;
  String _show = 'soon';
  String _error = '';
  late String _month;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now().toUtc().add(const Duration(hours: 7));
    _month = '${now.year}-${now.month.toString().padLeft(2, '0')}';
    _load();
  }

  Future<void> _load() async {
    try {
      final r = await Future.wait([pos.api('GET', '/expiry'), pos.api('GET', '/waste?month=$_month')]);
      if (mounted) {
        setState(() {
          _data = jmap(r[0]['data']);
          _waste = jmap(r[1]['data']);
          _error = '';
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = martErr(context, e));
    }
  }

  Future<void> _loadWaste() async {
    setState(() => _waste = null);
    try {
      final r = await pos.api('GET', '/waste?month=$_month');
      if (mounted) setState(() => _waste = jmap(r['data']));
    } catch (e) {
      if (mounted) setState(() => _error = martErr(context, e));
    }
  }

  String _when(T t, int d) => d == -1
      ? t('mx.yesterday')
      : d == 1
      ? t('mx.tomorrow')
      : d < 0
      ? t('mx.agoDays', {'n': '${-d}'})
      : d == 0
      ? t('mx.todayExp')
      : t('mx.inDays', {'n': '$d'});

  @override
  Widget build(BuildContext context) {
    final t = tr(context);
    final c = context.c;
    final cur = pos.currency;
    final d = _data;
    final counts = jmap(d?['counts']);
    int n(String k) => nz(counts[k]).toInt();
    final rows = jlist(d?['rows']).where((r) => _show == 'all' || (_show == 'expired' ? r['state'] == 'expired' : r['state'] != 'ok')).toList();
    final big = wide(context);
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
        children: [
          MartHead(
            title: '', // the page's top bar has the name
            sub: t('mx.expHint'),
            actions: [Btn(t('mx.addExpiry'), icon: LucideIcons.plus, small: true, onTap: d == null ? null : () => _add(context))],
          ),
          const SizedBox(height: 10),
          if (_error.isNotEmpty)
            Alert(
              _error,
              tone: Tone.warn,
              action: TextButton(onPressed: _load, child: Text(t('rpos.retry'))),
            ),
          if (d == null && _error.isEmpty)
            const Padding(
              padding: EdgeInsets.all(40),
              child: Center(child: CircularProgressIndicator()),
            ),
          if (d != null) ...[
            LayoutBuilder(
              builder: (_, box) {
                final per = big ? 5 : 2;
                final w = (box.maxWidth - 8 * (per - 1)) / per;
                final boxes = [
                  MartBox(icon: LucideIcons.calendarX, value: '${n('expired')}', label: t('mx.expired'), fg: c.danger),
                  MartBox(icon: LucideIcons.hourglass, value: '${n('soon')}', label: t('mx.soon'), fg: c.warn),
                  MartBox(icon: LucideIcons.calendarCheck, value: '${n('ok')}', label: t('mx.okLeft'), fg: c.good),
                  MartBox(icon: LucideIcons.wallet, value: f.money(d['at_risk'], cur), label: t('mx.atRisk'), fg: c.ink),
                  if (big) MartBox(icon: LucideIcons.tag, value: f.money(d['at_risk_sale'], cur), label: t('mx.atRiskSale'), fg: c.ink),
                ];
                return Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [for (final b in boxes) SizedBox(width: w, child: b)],
                );
              },
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: PosChips<String>(
                    scroll: true,
                    value: _show,
                    onTap: (v) => setState(() => _show = v),
                    options: [('soon', '${t('mx.sellFirst')} ${n('expired') + n('soon')}'), ('expired', '${t('mx.expired')} ${n('expired')}'), ('all', '${t('mx.all')} ${n('all')}')],
                  ),
                ),
                const SizedBox(width: 6),
                TextButton.icon(
                  onPressed: () => _days(context, nz(d['days']).toInt()),
                  icon: const Icon(LucideIcons.bellRing, size: 16),
                  label: Text('${nz(d['days']).toInt()} ${t('mx.warnDaysUnit')}'),
                ),
              ],
            ),
            const SizedBox(height: 8),
            if (rows.isEmpty)
              Padding(
                padding: const EdgeInsets.all(24),
                child: Muted(n('all') > 0 ? t('mx.none') : t('mx.noBatches'), align: TextAlign.center),
              ),
            for (final r in rows) _row(context, r),
            const SizedBox(height: 18),
            _wastePart(context),
          ],
        ],
      ),
    );
  }

  Widget _row(BuildContext context, J r) {
    final t = tr(context);
    final c = context.c;
    final state = js(r['state']);
    final (fg, bg) = switch (state) {
      'expired' => (c.danger, c.dangerBg),
      'soon' => (c.warn, c.warnBg),
      _ => (c.good, c.goodBg),
    };
    final lang = AppState.i.lang;
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.fromLTRB(12, 10, 4, 10),
      decoration: BoxDecoration(
        color: c.card,
        borderRadius: BorderRadius.circular(16),
        border: state == 'expired' ? Border.all(color: c.danger.withValues(alpha: .5)) : null,
      ),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(12)),
            child: js(r['photo']).isNotEmpty
                ? Image(image: netImage(js(r['photo'])), fit: BoxFit.cover, errorBuilder: (_, _, _) => const SizedBox())
                : Icon(LucideIcons.calendarClock, size: 18, color: fg),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  js(r['name']),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 2),
                Text(
                  '${t('mx.expires')} ${f.fmtDate(r['expires'], lang: lang)} · ${t('mx.left')} ${qtyOf(r['left'])}${js(r['note']).isNotEmpty ? ' · ${js(r['note'])}' : ''}',
                  maxLines: 2,
                  style: TextStyle(color: c.muted, fontSize: 12),
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    MartPill(_when(t, nz(r['days_left']).toInt()), fg: fg, bg: bg),
                    const SizedBox(width: 8),
                    Text(f.money(r['value'], pos.currency), style: const TextStyle(fontWeight: FontWeight.w800)),
                  ],
                ),
              ],
            ),
          ),
          TextButton.icon(
            onPressed: () => _throw(context, r),
            style: TextButton.styleFrom(foregroundColor: c.danger),
            icon: const Icon(LucideIcons.trash2, size: 16),
            label: Text(t('mx.waste')),
          ),
          IconButton(onPressed: () => _edit(context, r), icon: const Icon(LucideIcons.pencil, size: 17), tooltip: t('mx.edit')),
        ],
      ),
    );
  }

  Widget _wastePart(BuildContext context) {
    final t = tr(context);
    final c = context.c;
    final w = _waste;
    final lang = AppState.i.lang;
    final parts = _month.split('-').map(int.parse).toList();
    final now = DateTime.now().toUtc().add(const Duration(hours: 7));
    final thisMonth = parts[0] == now.year && parts[1] == now.month;
    void shift(int by) {
      final m = DateTime(parts[0], parts[1] + by);
      _month = '${m.year}-${m.month.toString().padLeft(2, '0')}';
      _loadWaste();
    }

    return Panel(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(t('mx.wasteRecord'), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
              ),
              IconButton(onPressed: () => shift(-1), icon: const Icon(LucideIcons.chevronLeft, size: 18)),
              Text(
                f.fmtDate('$_month-01', lang: lang).substring(3),
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              IconButton(onPressed: thisMonth ? null : () => shift(1), icon: const Icon(LucideIcons.chevronRight, size: 18)),
            ],
          ),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: () => _throw(context, null),
              style: TextButton.styleFrom(foregroundColor: c.danger, padding: EdgeInsets.zero),
              icon: const Icon(LucideIcons.trash2, size: 16),
              label: Text(t('mx.wasteOther')),
            ),
          ),
          if (w == null)
            const Padding(
              padding: EdgeInsets.all(16),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (jlist(w['rows']).isEmpty)
            Padding(
              padding: const EdgeInsets.all(12),
              child: Muted(t('mx.noWaste'), align: TextAlign.center),
            )
          else ...[
            Text(
              t('mx.wasteTotal', {'amt': f.money(w['total'], pos.currency)}),
              style: TextStyle(fontWeight: FontWeight.w800, color: c.danger),
            ),
            const SizedBox(height: 6),
            for (final x in jlist(w['rows']))
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('${js(x['name'])} × ${qtyOf(x['qty'])}', style: const TextStyle(fontWeight: FontWeight.w700)),
                          Text(
                            '${f.fmtDate(x['created_date'], time: true, lang: lang)} · ${js(x['note'])}${js(x['by']).isNotEmpty ? ' · ${js(x['by'])}' : ''}',
                            style: TextStyle(color: c.muted, fontSize: 12),
                          ),
                        ],
                      ),
                    ),
                    Text(f.money(x['value'], pos.currency), style: const TextStyle(fontWeight: FontWeight.w700)),
                  ],
                ),
              ),
          ],
        ],
      ),
    );
  }

  Future<void> _done(String msg) async {
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(content: Text(msg)));
    await _load();
  }

  // how many days before to warn
  Future<void> _days(BuildContext context, int now) async {
    final t = tr(context);
    final ctrl = TextEditingController(text: '$now');
    final v = await posSheet<int>(
      context,
      title: t('mx.warnDays'),
      maxWidth: 380,
      body: (ctx) => Field(controller: ctrl, label: t('mx.warnDaysUnit'), keyboard: TextInputType.number, autofocus: true),
      footer: (ctx) => Btn(
        t('mx.save'),
        expand: true,
        onTap: () {
          final n = int.tryParse(ctrl.text.trim()) ?? 0;
          if (n >= 1 && n <= 365) Navigator.pop(ctx, n);
        },
      ),
    );
    if (v == null || v == now) return;
    try {
      await pos.api('PUT', '/expiry/settings', {'days': v});
      await _done(t('mx.saved'));
    } catch (e) {
      if (mounted) setState(() => _error = martErr(this.context, e));
    }
  }

  // a day for stock already on the shelf (the stock does not change)
  Future<void> _add(BuildContext context) async {
    final t = tr(context);
    J? prod;
    final qty = TextEditingController();
    final note = TextEditingController();
    var day = '';
    var busy = false;
    var error = '';
    final ok = await posSheet<bool>(
      context,
      title: t('mx.addExpiry'),
      maxWidth: 480,
      body: (ctx) => StatefulBuilder(
        builder: (ctx, set) => Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(t('mx.product'), style: const TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(height: 6),
            OutlinedButton.icon(
              onPressed: () async {
                final p = await pickMartProduct(ctx);
                if (p != null) set(() => prod = p);
              },
              style: OutlinedButton.styleFrom(alignment: Alignment.centerLeft, padding: const EdgeInsets.all(14)),
              icon: const Icon(LucideIcons.package, size: 18),
              label: Text(prod == null ? t('mx.pickProduct') : js(prod!['name']), style: const TextStyle(fontWeight: FontWeight.w700)),
            ),
            const SizedBox(height: 10),
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  child: Field(controller: qty, label: t('mx.qty'), keyboard: const TextInputType.numberWithOptions(decimal: true), onChanged: (_) => set(() {})),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: DayField(label: t('mx.expires'), value: day, onPick: (v) => set(() => day = v)),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Field(controller: note, label: t('mx.note'), maxLength: 200),
            if (error.isNotEmpty) ...[const SizedBox(height: 8), Alert(error)],
            const SizedBox(height: 12),
            Btn(
              busy ? t('mx.saving') : t('mx.save'),
              busy: busy,
              expand: true,
              onTap: busy || prod == null || nz(qty.text) <= 0 || day.isEmpty
                  ? null
                  : () async {
                      set(() => busy = true);
                      try {
                        await pos.api('POST', '/expiry', {'product_id': js(prod!['_id']), 'qty': nz(qty.text), 'expires': day, 'note': note.text.trim()});
                        if (ctx.mounted) Navigator.pop(ctx, true);
                      } catch (e) {
                        set(() {
                          busy = false;
                          error = martErr(ctx, e);
                        });
                      }
                    },
            ),
          ],
        ),
      ),
    );
    if (ok == true) await _done(t('mx.saved'));
  }

  Future<void> _edit(BuildContext context, J r) async {
    final t = tr(context);
    final left = TextEditingController(text: qtyOf(r['left']));
    final note = TextEditingController(text: js(r['note']));
    var day = js(r['expires']);
    var busy = false;
    var error = '';
    final ok = await posSheet<bool>(
      context,
      title: '${t('mx.batchEdit')} · ${js(r['name'])}',
      maxWidth: 480,
      body: (ctx) => StatefulBuilder(
        builder: (ctx, set) {
          Future<void> run(Future<void> Function() fn) async {
            set(() => busy = true);
            try {
              await fn();
              if (ctx.mounted) Navigator.pop(ctx, true);
            } catch (e) {
              set(() {
                busy = false;
                error = martErr(ctx, e);
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
                    child: Field(controller: left, label: t('mx.left'), keyboard: const TextInputType.numberWithOptions(decimal: true)),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: DayField(label: t('mx.expires'), value: day, onPick: (v) => set(() => day = v)),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Field(controller: note, label: t('mx.note'), maxLength: 200),
              if (error.isNotEmpty) ...[const SizedBox(height: 8), Alert(error)],
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: Btn(t('mx.remove'), kind: BtnKind.danger, icon: LucideIcons.trash2, onTap: busy ? null : () => run(() => pos.api('DELETE', '/expiry/${js(r['_id'])}'))),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Btn(
                      busy ? t('mx.saving') : t('mx.save'),
                      busy: busy,
                      onTap: busy || day.isEmpty ? null : () => run(() => pos.api('PUT', '/expiry/${js(r['_id'])}', {'left': nz(left.text), 'expires': day, 'note': note.text.trim()})),
                    ),
                  ),
                ],
              ),
            ],
          );
        },
      ),
    );
    if (ok == true) await _done(t('mx.saved'));
  }

  // thrown away: from a batch (expired) or any product (damaged / broken)
  Future<void> _throw(BuildContext context, J? batch) async {
    final t = tr(context);
    final reasons = t.list('mx.wasteReasons');
    J? prod;
    final qty = TextEditingController(text: batch == null ? '' : qtyOf(batch['left']));
    final why = TextEditingController(text: reasons.isEmpty ? '' : reasons[batch == null && reasons.length > 1 ? 1 : 0]);
    var busy = false;
    var error = '';
    final ok = await posSheet<bool>(
      context,
      title: t('mx.wasteTitle', {'name': batch == null ? '' : js(batch['name'])}),
      maxWidth: 480,
      body: (ctx) => StatefulBuilder(
        builder: (ctx, set) {
          final n = nz(qty.text);
          final can = !busy && n > 0 && (batch == null ? prod != null : n <= nz(batch['left']) + 1e-9);
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (batch == null) ...[
                OutlinedButton.icon(
                  onPressed: () async {
                    final p = await pickMartProduct(ctx);
                    if (p != null) set(() => prod = p);
                  },
                  style: OutlinedButton.styleFrom(alignment: Alignment.centerLeft, padding: const EdgeInsets.all(14)),
                  icon: const Icon(LucideIcons.package, size: 18),
                  label: Text(prod == null ? t('mx.pickProduct') : js(prod!['name']), style: const TextStyle(fontWeight: FontWeight.w700)),
                ),
                const SizedBox(height: 10),
              ],
              Field(
                controller: qty,
                label: batch == null ? t('mx.qty') : '${t('mx.qty')} (${t('mx.left')} ${qtyOf(batch['left'])})',
                keyboard: const TextInputType.numberWithOptions(decimal: true),
                autofocus: batch != null,
                onChanged: (_) => set(() {}),
              ),
              const SizedBox(height: 10),
              Text(t('mx.wasteReason'), style: const TextStyle(fontWeight: FontWeight.w700)),
              const SizedBox(height: 6),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [for (final r in reasons) ChoiceChip(label: Text(r), selected: why.text == r, onSelected: (_) => set(() => why.text = r))],
              ),
              const SizedBox(height: 8),
              Field(controller: why, maxLength: 200, onChanged: (_) => set(() {})),
              if (error.isNotEmpty) ...[const SizedBox(height: 8), Alert(error)],
              const SizedBox(height: 12),
              Btn(
                t('mx.waste'),
                icon: LucideIcons.trash2,
                kind: BtnKind.danger,
                busy: busy,
                expand: true,
                onTap: !can
                    ? null
                    : () async {
                        set(() => busy = true);
                        try {
                          if (batch == null) {
                            await pos.api('POST', '/waste', {'product_id': js(prod!['_id']), 'qty': n, 'reason': why.text.trim()});
                          } else {
                            await pos.api('POST', '/expiry/${js(batch['_id'])}/waste', {'qty': n, 'reason': why.text.trim()});
                          }
                          if (ctx.mounted) Navigator.pop(ctx, true);
                        } catch (e) {
                          set(() {
                            busy = false;
                            error = martErr(ctx, e);
                          });
                        }
                      },
              ),
            ],
          );
        },
      ),
    );
    if (ok == true) await _done(t('mx.wasteDone'));
  }
}
