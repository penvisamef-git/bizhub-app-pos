import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/theme.dart';
import '../../widgets/ui.dart';
import '../mart/mart_kit.dart' show DayField, MartBox;
import '../restaurant/engine/calc.dart' show J, jmap, jlist, js, jsRound, nz;
import '../restaurant/pos_ui.dart';
import 'engine/gh_pos.dart';
import 'gh_book.dart' show ghChips;
import 'gh_stay.dart' show ghNum, openStay;
import 'gh_ui.dart';

// Long stay / monthly rent (gh_longstay) — the web's GhLease.jsx: tenants, the monthly bill (rent + meters + fixed), move out
class GhLeases extends StatefulWidget {
  const GhLeases({super.key});
  @override
  State<GhLeases> createState() => _GhLeasesState();
}

class _GhLeasesState extends State<GhLeases> {
  final pos = GhPos.i;
  J? _d;
  String _error = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final r = await pos.api('GET', '/leases');
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

  // to bill first, then who owes, then paid up, then moved out
  static int _rank(J x) => !GhPos.live.contains(x['status']) ? 3 : (x['bill_due'] == true ? 0 : (nz(jmap(x['bill'])['balance']) > 0 ? 1 : 2));

  @override
  Widget build(BuildContext context) {
    final t = tr(context);
    final c = context.c;
    final cur = pos.currency;
    final d = _d;
    final counts = jmap(d?['counts']);
    final list = [...jlist(d?['list'])]..sort((a, b) => _rank(a).compareTo(_rank(b)));
    final desk = pos.desk;
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
                    Text(t('gx.lsTitle'), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 18)),
                    Text(t('gx.lsSub'), maxLines: 2, style: TextStyle(color: c.muted, fontSize: 12.5)),
                  ],
                ),
              ),
              if (!desk) Btn(t('gx.lsNew'), icon: LucideIcons.plus, small: true, onTap: pos.readOnly || d == null ? null : () => _editLease(context, null)),
            ],
          ),
          const SizedBox(height: 8),
          if (_error.isNotEmpty) Alert(_error, tone: Tone.warn),
          if (d == null && _error.isEmpty)
            const Padding(
              padding: EdgeInsets.all(40),
              child: Center(child: CircularProgressIndicator()),
            ),
          if (d != null) ...[
            LayoutBuilder(
              builder: (_, box) {
                final per = box.maxWidth > 760 ? 4 : 2;
                final w = (box.maxWidth - 8 * (per - 1)) / per;
                return Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final b in [
                      MartBox(icon: LucideIcons.keyRound, value: '${nz(counts['tenants']).toInt()}', label: t('gx.lsTenants'), fg: const Color(0xFF1D4ED8)),
                      MartBox(icon: LucideIcons.house, value: ghMoney(d['rent_month'], cur), label: t('gx.lsRentMonth'), fg: c.ink),
                      MartBox(icon: LucideIcons.receiptText, value: '${nz(counts['to_bill']).toInt()}', label: t('gx.lsToBill'), fg: nz(counts['to_bill']) > 0 ? c.warn : c.ink),
                      MartBox(icon: LucideIcons.wallet, value: ghMoney(d['owed'], cur), label: t('gx.lsOwed'), fg: nz(d['owed']) > 0 ? c.danger : c.good),
                    ])
                      SizedBox(width: w, child: b),
                  ],
                );
              },
            ),
            const SizedBox(height: 10),
            if (list.isEmpty)
              Padding(
                padding: const EdgeInsets.all(30),
                child: Muted(t('gx.lsNone'), align: TextAlign.center),
              ),
            for (final x in list) _card(context, x, js(d['month'])),
          ],
        ],
      ),
    );
  }

  Widget _card(BuildContext context, J x, String month) {
    final t = tr(context);
    final c = context.c;
    final cur = pos.currency;
    final l = jmap(x['lease']);
    final b = jmap(x['bill']);
    final g = jmap(x['guest']);
    final liveNow = GhPos.live.contains(x['status']);
    final (key, label) = !liveNow
        ? ('out', t('gx.lsEnded'))
        : (x['bill_due'] == true
              ? ('due', t('gx.lsToMake', {'month': ghMonth(month)}))
              : (nz(b['balance']) > 0 ? ('owe', t('gx.lsOwes', {'amt': ghMoney(b['balance'], cur)})) : ('ok', t('gx.lsPaid'))));
    final (fg, bg) = switch (key) {
      'due' => (c.warn, c.warnBg),
      'owe' => (c.danger, c.dangerBg),
      'ok' => (c.good, c.goodBg),
      _ => (c.muted, c.chip),
    };
    final meter = jmap(l['meter']);
    return Panel(
      padding: const EdgeInsets.all(14),
      margin: const EdgeInsets.only(bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                decoration: BoxDecoration(color: c.chip, borderRadius: BorderRadius.circular(10)),
                child: Text(js(x['room_name']), style: const TextStyle(fontWeight: FontWeight.w800)),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(js(g['name']), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                    Text(
                      [
                        js(g['phone']),
                        t('gx.lsSince', {'date': ghDay(js(l['start']), year: true)}),
                        js(l['end']).isNotEmpty ? t('gx.lsUntil', {'date': ghDay(js(l['end']), year: true)}) : t('gx.lsOpen'),
                      ].where((s) => s.isNotEmpty).join(' · '),
                      style: TextStyle(color: c.muted, fontSize: 12),
                    ),
                  ],
                ),
              ),
              GhPill(label, fg: fg, bg: bg),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 12,
            runSpacing: 4,
            children: [
              Text('${ghMoney(l['rent'], cur)} / ${t('gx.lsMonth').toLowerCase()}', style: const TextStyle(fontWeight: FontWeight.w800)),
              if (nz(l['elec_rate']) > 0) Text('⚡ ${ghMoney(l['elec_rate'], cur)}/kWh'),
              if (nz(l['water_rate']) > 0) Text('💧 ${ghMoney(l['water_rate'], cur)}/m³'),
              for (final f in jlist(l['fixed'])) Text('${js(f['label'])} ${ghMoney(f['amount'], cur)}'),
              Text(t('gx.lsMeterNow', {'e': ghNum(meter['elec']), 'w': ghNum(meter['water'])}), style: TextStyle(color: c.muted)),
            ],
          ),
          if (liveNow) ...[
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                if (x['billed_this'] != true && x['status'] == 'in')
                  Btn(
                    t('gx.lsMakeBill'),
                    icon: LucideIcons.receiptText,
                    small: true,
                    kind: x['bill_due'] == true ? BtnKind.primary : BtnKind.ghost,
                    onTap: pos.readOnly ? null : () => _bill(context, x),
                  ),
                OutlinedButton(
                  onPressed: () async {
                    await openStay(context, x['_id']);
                    _load();
                  },
                  child: Text(t('gx.lsPay')),
                ),
                if (!pos.desk) ...[
                  TextButton.icon(onPressed: pos.readOnly ? null : () => _editLease(context, x), icon: const Icon(LucideIcons.pencil, size: 15), label: Text(t('gx.lsEdit'))),
                  TextButton.icon(
                    style: TextButton.styleFrom(foregroundColor: c.danger),
                    onPressed: pos.readOnly ? null : () => _end(context, x),
                    icon: const Icon(LucideIcons.logOut, size: 15),
                    label: Text(t('gx.lsEndBtn')),
                  ),
                ],
              ],
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _done(bool? ok) async {
    if (ok == true) {
      if (mounted) ghToast(context, tr(context)('gx.saved'));
      await _load();
    }
  }

  // new tenant / change the terms
  Future<void> _editLease(BuildContext context, J? row) async {
    final t = tr(context);
    final l = jmap(row?['lease']);
    final g = jmap(row?['guest']);
    final name = TextEditingController(text: js(g['name']));
    final phone = TextEditingController(text: js(g['phone']));
    final rent = TextEditingController(text: row == null ? '' : ghNum(l['rent']));
    final deposit = TextEditingController();
    final elecRate = TextEditingController(text: row == null ? '' : ghNum(l['elec_rate']));
    final waterRate = TextEditingController(text: row == null ? '' : ghNum(l['water_rate']));
    final billDay = TextEditingController(text: row == null ? '1' : ghNum(l['bill_day']));
    final mElec = TextEditingController(), mWater = TextEditingController();
    final fixed = [for (final f in jlist(l['fixed'])) (TextEditingController(text: js(f['label'])), TextEditingController(text: ghNum(f['amount'])))];
    var room = js(row?['room_id']);
    var start = row == null ? pos.today : js(l['start']);
    var end = js(l['end']);
    var depMethod = pos.methods.first;
    var busy = false;
    var error = '';
    final taken = {
      for (final x in jlist(_d?['list']))
        if (GhPos.live.contains(x['status'])) js(x['room_id']),
    };
    final rooms = pos.rooms.where((r) => r['active'] == true && r['usable'] != false && !taken.contains(js(r['_id']))).toList();
    final ok = await posSheet<bool>(
      context,
      title: row == null ? t('gx.lsNew') : t('gx.lsEdit'),
      maxWidth: 640,
      body: (ctx) => StatefulBuilder(
        builder: (ctx, set) {
          Widget num(TextEditingController c, String label, [String hint = '']) =>
              Field(controller: c, label: label, hint: hint.isEmpty ? null : hint, keyboard: const TextInputType.numberWithOptions(decimal: true), onChanged: (_) => set(() {}));
          Widget pair(Widget a, Widget b) => Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(child: a),
              const SizedBox(width: 8),
              Expanded(child: b),
            ],
          );
          final can = !busy && name.text.trim().isNotEmpty && nz(rent.text) > 0 && (row != null || room.isNotEmpty);
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (row == null) ...[
                Text('${t('gx.lsRoom')} *', style: const TextStyle(fontWeight: FontWeight.w700)),
                const SizedBox(height: 6),
                ghChips(ctx, [for (final r in rooms) (js(r['_id']), js(r['name']))], room, (k) => set(() => room = k)),
                const SizedBox(height: 12),
              ],
              pair(
                Field(controller: name, label: '${t('gh.guestName')} *', maxLength: 80, onChanged: (_) => set(() {})),
                Field(controller: phone, label: t('gh.phone'), keyboard: TextInputType.phone, maxLength: 30),
              ),
              const SizedBox(height: 10),
              pair(
                row != null
                    ? Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(t('gx.lsStart'), style: const TextStyle(fontWeight: FontWeight.w700)),
                          const SizedBox(height: 6),
                          Text(ghDay(start, year: true)),
                        ],
                      )
                    : DayField(label: t('gx.lsStart'), value: start, show: (d) => ghDay(d, year: true), onPick: (v) => set(() => start = v)),
                DayField(label: t('gx.lsEnd'), value: end, show: (d) => ghDay(d, year: true), onPick: (v) => set(() => end = v.compareTo(start) < 0 ? start : v)),
              ),
              const SizedBox(height: 10),
              pair(num(rent, '${t('gx.lsRent')} *'), row == null ? num(deposit, t('gx.lsDeposit')) : num(billDay, t('gx.lsBillDay'))),
              const SizedBox(height: 10),
              pair(num(elecRate, t('gx.lsElecRate'), '0.25'), num(waterRate, t('gx.lsWaterRate'), '0.5')),
              if (row == null) ...[
                const SizedBox(height: 10),
                pair(num(billDay, t('gx.lsBillDay')), const SizedBox()),
                if (nz(deposit.text) > 0) ...[
                  const SizedBox(height: 8),
                  ghChips(ctx, [for (final k in pos.methods) (k, t('gh.methods.$k'))], depMethod, (k) => set(() => depMethod = k)),
                ],
                const SizedBox(height: 12),
                Muted(t('gx.lsMeters')),
                const SizedBox(height: 6),
                pair(num(mElec, '⚡ ${t('gx.lsElec')}'), num(mWater, '💧 ${t('gx.lsWater')}')),
              ],
              const SizedBox(height: 12),
              Text(t('gx.lsFixed'), style: const TextStyle(fontWeight: FontWeight.w700)),
              for (var i = 0; i < fixed.length; i++)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Row(
                    children: [
                      Expanded(
                        flex: 2,
                        child: Field(controller: fixed[i].$1, hint: 'Internet', maxLength: 60),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Field(controller: fixed[i].$2, hint: '0', keyboard: const TextInputType.numberWithOptions(decimal: true)),
                      ),
                      IconButton(onPressed: () => set(() => fixed.removeAt(i)), icon: const Icon(LucideIcons.trash2, size: 16)),
                    ],
                  ),
                ),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: fixed.length >= 10 ? null : () => set(() => fixed.add((TextEditingController(), TextEditingController()))),
                  icon: const Icon(LucideIcons.plus, size: 15),
                  label: Text(t('gx.lsAddFixed')),
                ),
              ),
              if (error.isNotEmpty) ...[const SizedBox(height: 8), Alert(error)],
              const SizedBox(height: 12),
              Btn(
                busy ? t('gx.saving') : t('gx.save'),
                busy: busy,
                expand: true,
                onTap: !can
                    ? null
                    : () async {
                        set(() {
                          busy = true;
                          error = '';
                        });
                        final body = {
                          'guest': {'name': name.text.trim(), 'phone': phone.text.trim(), 'id_number': js(g['id_number'])},
                          'end': end,
                          'rent': nz(rent.text),
                          'elec_rate': nz(elecRate.text),
                          'water_rate': nz(waterRate.text),
                          'fixed': [
                            for (final (a, b) in fixed)
                              if (a.text.trim().isNotEmpty) {'label': a.text.trim(), 'amount': nz(b.text)},
                          ],
                          'bill_day': nz(billDay.text) < 1 ? 1 : nz(billDay.text).toInt(),
                          if (row == null) ...{
                            'room_id': room,
                            'start': start,
                            'deposit': nz(deposit.text),
                            'deposit_method': depMethod,
                            'meter': {'elec': nz(mElec.text), 'water': nz(mWater.text)},
                          },
                        };
                        try {
                          await (row == null ? pos.api('POST', '/leases', body) : pos.api('PUT', '/leases/${row['_id']}', body));
                          if (ctx.mounted) Navigator.pop(ctx, true);
                        } catch (e) {
                          set(() {
                            busy = false;
                            error = ghErr(ctx, e);
                          });
                        }
                      },
              ),
            ],
          );
        },
      ),
    );
    await _done(ok);
  }

  // this month's bill: the meters now → units × rate, + rent + fixed
  Future<void> _bill(BuildContext context, J row) async {
    final t = tr(context);
    final cur = pos.currency;
    final l = jmap(row['lease']);
    final meter = jmap(l['meter']);
    final month = pos.today.substring(0, 7);
    final elec = TextEditingController(text: ghNum(meter['elec']));
    final water = TextEditingController(text: ghNum(meter['water']));
    double r(double v) => cur == 'KHR' ? jsRound(v) : jsRound(v * 100) / 100;
    var busy = false;
    var error = '';
    final ok = await posSheet<bool>(
      context,
      title: t('gx.lsBillTitle', {'month': ghMonth(month)}),
      maxWidth: 520,
      body: (ctx) => StatefulBuilder(
        builder: (ctx, set) {
          final eU = (nz(elec.text) - nz(meter['elec'])).clamp(0, double.infinity).toDouble();
          final wU = (nz(water.text) - nz(meter['water'])).clamp(0, double.infinity).toDouble();
          final lines = <(String, double)>[
            (t('gx.lsRent').split(' /').first, nz(l['rent'])),
            ('⚡ ${t('gx.lsUnits', {'n': ghNum(eU)})}', r(eU * nz(l['elec_rate']))),
            ('💧 ${t('gx.lsUnits', {'n': ghNum(wU)})}', r(wU * nz(l['water_rate']))),
            for (final f in jlist(l['fixed'])) (js(f['label']), nz(f['amount'])),
          ].where((x) => x.$2 > 0).toList();
          final total = lines.fold<double>(0, (a, x) => a + x.$2);
          final back = nz(elec.text) < nz(meter['elec']) || nz(water.text) < nz(meter['water']);
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('${js(row['room_name'])} · ${js(jmap(row['guest'])['name'])}', style: const TextStyle(fontWeight: FontWeight.w700)),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: Field(
                      controller: elec,
                      label: '⚡ ${t('gx.lsElec')} · ${t('gx.lsPrev', {'n': ghNum(meter['elec'])})}',
                      keyboard: const TextInputType.numberWithOptions(decimal: true),
                      autofocus: true,
                      onChanged: (_) => set(() {}),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Field(
                      controller: water,
                      label: '💧 ${t('gx.lsWater')} · ${t('gx.lsPrev', {'n': ghNum(meter['water'])})}',
                      keyboard: const TextInputType.numberWithOptions(decimal: true),
                      onChanged: (_) => set(() {}),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              for (final (a, v) in lines) SumRow(a, ghMoney(v, cur)),
              const Divider(height: 14),
              SumRow(t('gx.lsTotal'), ghMoney(total, cur), big: true),
              if (error.isNotEmpty) ...[const SizedBox(height: 8), Alert(error)],
              const SizedBox(height: 12),
              Btn(
                '${t('gx.lsMakeBill')} · ${ghMoney(total, cur)}',
                icon: LucideIcons.receiptText,
                busy: busy,
                expand: true,
                onTap: busy || back
                    ? null
                    : () async {
                        set(() => busy = true);
                        try {
                          await pos.api('POST', '/leases/${row['_id']}/bill', {'month': month, 'elec': nz(elec.text), 'water': nz(water.text)});
                          if (ctx.mounted) Navigator.pop(ctx, true);
                        } catch (e) {
                          set(() {
                            busy = false;
                            error = ghErr(ctx, e);
                          });
                        }
                      },
              ),
            ],
          );
        },
      ),
    );
    await _done(ok);
  }

  Future<void> _end(BuildContext context, J row) async {
    final t = tr(context);
    final cur = pos.currency;
    final dep = nz(jmap(row['lease'])['deposit']);
    final left = nz(jmap(row['bill'])['balance']);
    var refund = dep > 0;
    var method = 'cash';
    var busy = false;
    var error = '';
    final ok = await posSheet<bool>(
      context,
      title: t('gx.lsEndTitle', {'name': js(jmap(row['guest'])['name'])}),
      maxWidth: 480,
      body: (ctx) => StatefulBuilder(
        builder: (ctx, set) => Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Muted(t('gx.lsEndNote')),
            if (left > 0) ...[
              const SizedBox(height: 8),
              Alert(t('gx.lsOwes', {'amt': ghMoney(left, cur)}), tone: Tone.warn),
            ],
            if (dep > 0) ...[
              SwitchListTile(contentPadding: EdgeInsets.zero, value: refund, onChanged: (v) => set(() => refund = v), title: Text(t('gx.lsRefund', {'amt': ghMoney(dep, cur)}))),
              if (refund) ghChips(ctx, [for (final k in pos.methods) (k, t('gh.methods.$k'))], method, (k) => set(() => method = k)),
            ],
            if (error.isNotEmpty) ...[const SizedBox(height: 8), Alert(error)],
            const SizedBox(height: 12),
            Btn(
              t('gx.lsEndBtn'),
              icon: LucideIcons.logOut,
              kind: BtnKind.danger,
              busy: busy,
              expand: true,
              onTap: busy
                  ? null
                  : () async {
                      set(() => busy = true);
                      try {
                        await pos.api('POST', '/leases/${row['_id']}/end', {'refund_deposit': refund, 'method': method});
                        if (ctx.mounted) Navigator.pop(ctx, true);
                      } catch (e) {
                        set(() {
                          busy = false;
                          error = ghErr(ctx, e);
                        });
                      }
                    },
            ),
          ],
        ),
      ),
    );
    await _done(ok);
  }
}
