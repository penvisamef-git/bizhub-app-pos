import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/api.dart' show ApiError;
import '../../core/format.dart' as f;
import '../../core/i18n.dart';
import '../../core/printing/printing.dart';
import '../../core/theme.dart';
import '../../widgets/ui.dart';
import '../restaurant/engine/calc.dart' show J, jmap, js, nz;
import '../restaurant/pos_ui.dart';
import '../restaurant/rest_receipt.dart' show receiptWhen;
import 'engine/mart_pos.dart';
import 'mart_receipt.dart';

// Shifts & cash drawer (mart_shifts add-on), the same steps as the web:
// PIN → count the drawer (open) → sell → count again (close) → "Shift closed" → next person's PIN
String _usd(Object? v) => f.money(v, 'USD');
String _khr(Object? v) => f.money(v, 'KHR');
String _sign(double v, String Function(Object?) fm) => '${v > 0 ? '+' : (v < 0 ? '−' : '')}${fm(v.abs())}';

// USD + riel with one keypad
class TwoAmounts extends StatefulWidget {
  final String usd, khr;
  final ValueChanged<String> onUsd, onKhr;
  final String? usdLabel, khrLabel;
  const TwoAmounts({super.key, required this.usd, required this.khr, required this.onUsd, required this.onKhr, this.usdLabel, this.khrLabel});
  @override
  State<TwoAmounts> createState() => _TwoAmountsState();
}

class _TwoAmountsState extends State<TwoAmounts> {
  String _field = 'usd';
  @override
  Widget build(BuildContext context) {
    final t = tr(context);
    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: AmountBox(label: widget.usdLabel ?? t('mpos.cashUsd'), value: _usd(nz(widget.usd)), on: _field == 'usd', onTap: () => setState(() => _field = 'usd')),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: AmountBox(label: widget.khrLabel ?? t('mpos.cashKhr'), value: _khr(nz(widget.khr)), on: _field == 'khr', onTap: () => setState(() => _field = 'khr')),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Keypad(value: _field == 'usd' ? widget.usd : widget.khr, onChanged: _field == 'usd' ? widget.onUsd : widget.onKhr, dot: _field == 'usd', max: _field == 'usd' ? 9 : 11, keyHeight: 54),
      ],
    );
  }
}

// full screen after the PIN: no selling until the drawer is counted
class MartOpenShift extends StatefulWidget {
  final VoidCallback onLock, onSkip;
  const MartOpenShift({super.key, required this.onLock, required this.onSkip});
  @override
  State<MartOpenShift> createState() => _MartOpenShiftState();
}

class _MartOpenShiftState extends State<MartOpenShift> {
  String _u = '', _k = '', _error = '';
  bool _busy = false;
  @override
  Widget build(BuildContext context) {
    final t = tr(context);
    final c = context.c;
    final pos = MartPos.i;
    return Scaffold(
      backgroundColor: c.appBg,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 400),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Icon(LucideIcons.vault, size: 36, color: c.brand),
                  const SizedBox(height: 8),
                  Text(
                    t('mpos.openShiftTitle'),
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 6),
                  Muted('${js(pos.staff['name'])} · ${t('mpos.openShiftSub')}', align: TextAlign.center),
                  const SizedBox(height: 18),
                  TwoAmounts(usd: _u, khr: _k, onUsd: (v) => setState(() => _u = v), onKhr: (v) => setState(() => _k = v)),
                  if (_error.isNotEmpty) ...[const SizedBox(height: 10), Alert(_error)],
                  const SizedBox(height: 12),
                  Btn(
                    t('mpos.startShift'),
                    busy: _busy,
                    expand: true,
                    onTap: () async {
                      setState(() {
                        _busy = true;
                        _error = '';
                      });
                      try {
                        await pos.openShift(nz(_u), nz(_k));
                      } on ApiError catch (e) {
                        if (mounted) {
                          setState(() {
                            _error = e.network ? t('mpos.needOnline') : e.message;
                            _busy = false;
                          });
                        }
                      }
                    },
                  ),
                  const SizedBox(height: 8),
                  Center(child: Muted('1 USD = ${_khr(pos.rate)}')),
                  if (!pos.online) TextButton(onPressed: widget.onSkip, child: Text(t('mpos.skipOffline'))),
                  TextButton.icon(onPressed: _busy ? null : widget.onLock, icon: const Icon(LucideIcons.logOut, size: 16), label: Text(t('mpos.notYou', {'name': js(pos.staff['name'])}))),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// count again and close (returns the closed shift)
Future<J?> showMartCloseShift(BuildContext context) => posSheet<J>(context, title: tr(context)('mpos.closeShift'), maxWidth: 900, body: (_) => const _Close());

class _Close extends StatefulWidget {
  const _Close();
  @override
  State<_Close> createState() => _CloseState();
}

class _CloseState extends State<_Close> {
  J? _cur;
  String _u = '', _k = '', _error = '';
  final _note = TextEditingController();
  bool _busy = false;
  final pos = MartPos.i;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final r = await pos.shifts();
      if (mounted) setState(() => _cur = jmap(r['current']));
    } on ApiError catch (e) {
      if (mounted) setState(() => _error = e.network ? tr(context)('mpos.needOnline') : e.message);
    }
  }

  Future<void> _move(String kind) async {
    final t = tr(context);
    var u = '', k = '';
    final note = TextEditingController();
    final ok = await posSheet<bool>(
      context,
      title: kind == 'in' ? t('mpos.moneyIn') : t('mpos.moneyOut'),
      maxWidth: 440,
      body: (ctx) => StatefulBuilder(
        builder: (ctx, set) => Column(
          children: [
            TwoAmounts(usd: u, khr: k, onUsd: (v) => set(() => u = v), onKhr: (v) => set(() => k = v), usdLabel: 'USD', khrLabel: 'KHR'),
            const SizedBox(height: 10),
            Field(controller: note, hint: t('mpos.note'), maxLength: 200),
            const SizedBox(height: 12),
            Btn(
              kind == 'in' ? t('mpos.moneyIn') : t('mpos.moneyOut'),
              icon: kind == 'in' ? LucideIcons.arrowDownToLine : LucideIcons.arrowUpFromLine,
              expand: true,
              onTap: nz(u) > 0 || nz(k) > 0 ? () => Navigator.pop(ctx, true) : null,
            ),
          ],
        ),
      ),
    );
    if (ok != true || _cur == null) return;
    try {
      await pos.shiftCash(js(_cur!['_id']), kind, nz(u), nz(k), note.text.trim());
      await _load();
    } on ApiError catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = tr(context);
    final c = context.c;
    final cur = _cur;
    if (cur == null || cur.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(20),
        child: _error.isNotEmpty ? Alert(_error) : const Center(child: CircularProgressIndicator()),
      );
    }
    final l = jmap(cur['live']);
    final cc = pos.currency;
    final dU = ((nz(_u) - nz(l['expected_usd'])) * 100).round() / 100;
    final dK = nz(_k) - nz(l['expected_khr']);
    TableRow row(String a, String b, String d, {bool bold = false, Color? color}) => TableRow(
      children: [
        for (final (i, v) in [a, b, d].indexed)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Text(
              v,
              textAlign: i == 0 ? TextAlign.start : TextAlign.end,
              style: TextStyle(fontWeight: bold ? FontWeight.w800 : (i == 0 ? FontWeight.w500 : FontWeight.w700), color: i > 0 ? color : c.muted),
            ),
          ),
      ],
    );
    final left = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Muted(t('mpos.closeShiftSub')),
        const SizedBox(height: 10),
        SumRow(t('mpos.receipts'), '${nz(l['sales_count']).toInt()}'),
        SumRow(t('mpos.salesTotal'), f.money(l['sales_total'], cc), big: true),
        for (final e in jmap(l['by_method']).entries) SumRow(methodLabel(tr(context), pos.settings, e.key), f.money(e.value, cc)),
        const SizedBox(height: 8),
        Table(
          columnWidths: const {0: FlexColumnWidth(1.3), 1: FlexColumnWidth(1), 2: FlexColumnWidth(1.2)},
          children: [
            row('', 'USD', 'KHR', bold: true),
            row(t('mpos.float'), _usd(cur['float_usd']), _khr(cur['float_khr'])),
            row(t('mpos.cashSales'), '+${_usd(l['cash_usd'])}', '+${_khr(l['cash_khr'])}'),
            if (nz(l['change_khr']) > 0) row(t('mpos.changeOut'), '', '−${_khr(l['change_khr'])}'),
            if (nz(l['in_usd']) > 0 || nz(l['in_khr']) > 0) row(t('mpos.moneyIn'), nz(l['in_usd']) > 0 ? '+${_usd(l['in_usd'])}' : '', nz(l['in_khr']) > 0 ? '+${_khr(l['in_khr'])}' : ''),
            if (nz(l['out_usd']) > 0 || nz(l['out_khr']) > 0) row(t('mpos.moneyOut'), nz(l['out_usd']) > 0 ? '−${_usd(l['out_usd'])}' : '', nz(l['out_khr']) > 0 ? '−${_khr(l['out_khr'])}' : ''),
            row(t('mpos.expected'), _usd(l['expected_usd']), _khr(l['expected_khr']), bold: true),
            row(t('mpos.counted'), _usd(nz(_u)), _khr(nz(_k))),
            row(t('mpos.difference'), _sign(dU, _usd), _sign(dK, _khr), bold: true, color: dU < 0 || dK < 0 ? c.danger : c.good),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: Btn(t('mpos.moneyIn'), icon: LucideIcons.arrowDownToLine, small: true, kind: BtnKind.ghost, onTap: _busy ? null : () => _move('in')),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Btn(t('mpos.moneyOut'), icon: LucideIcons.arrowUpFromLine, small: true, kind: BtnKind.ghost, onTap: _busy ? null : () => _move('out')),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Field(controller: _note, hint: t('mpos.note'), maxLength: 300),
        if (_error.isNotEmpty) ...[const SizedBox(height: 8), Alert(_error)],
        const SizedBox(height: 12),
        SizedBox(
          height: 54,
          child: Btn(
            t('mpos.closeNow'),
            icon: LucideIcons.lock,
            busy: _busy,
            expand: true,
            onTap: () async {
              setState(() {
                _busy = true;
                _error = '';
              });
              try {
                final done = await pos.closeShift(js(cur['_id']), nz(_u), nz(_k), _note.text.trim());
                if (context.mounted) Navigator.pop(context, done);
                pos.loadBoot();
              } on ApiError catch (e) {
                if (mounted) {
                  setState(() {
                    _error = e.network ? t('mpos.needOnline') : e.message;
                    _busy = false;
                  });
                }
              }
            },
          ),
        ),
      ],
    );
    final right = TwoAmounts(
      usd: _u,
      khr: _k,
      onUsd: (v) => setState(() => _u = v),
      onKhr: (v) => setState(() => _k = v),
      usdLabel: '${t('mpos.counted')} · USD',
      khrLabel: '${t('mpos.counted')} · KHR',
    );
    if (wide(context)) {
      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(child: left),
          const SizedBox(width: 18),
          Expanded(child: right),
        ],
      );
    }
    return Column(children: [right, const SizedBox(height: 16), left]);
  }
}

// after closing: the summary, print, Done → PIN screen for the next person
class MartShiftDone extends StatelessWidget {
  final J shift;
  final VoidCallback onDone;
  const MartShiftDone({super.key, required this.shift, required this.onDone});
  @override
  Widget build(BuildContext context) {
    final t = tr(context);
    final c = context.c;
    final pos = MartPos.i;
    final s = shift;
    final cc = pos.currency;
    final off = nz(s['diff_usd']).abs() >= 0.01 || nz(s['diff_khr']).abs() >= 1;
    return Scaffold(
      backgroundColor: c.appBg,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Icon(LucideIcons.circleCheck, size: 60, color: c.good),
                  const SizedBox(height: 8),
                  Text(
                    t('mpos.shiftClosedTitle'),
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800),
                  ),
                  Muted('${t('mpos.shiftNo', {'no': js(s['no'])})} · ${js(s['closed_by'])}', align: TextAlign.center),
                  const SizedBox(height: 10),
                  Text(
                    f.money(s['sales_total'], cc),
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 34, fontWeight: FontWeight.w800),
                  ),
                  Muted('${t('mpos.receipts')}: ${nz(s['sales_count']).toInt()}', align: TextAlign.center),
                  const SizedBox(height: 14),
                  Panel(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      children: [
                        SumRow(t('mpos.expected'), '${_usd(s['expected_usd'])} · ${_khr(s['expected_khr'])}'),
                        SumRow(t('mpos.counted'), '${_usd(s['counted_usd'])} · ${_khr(s['counted_khr'])}'),
                        SumRow(t('mpos.difference'), '${_sign(nz(s['diff_usd']), _usd)} · ${_sign(nz(s['diff_khr']), _khr)}', color: off ? c.danger : c.good),
                      ],
                    ),
                  ),
                  if (!off)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Center(child: Chip2(t('mart.exact2'), tone: Tone.good)),
                    ),
                  const SizedBox(height: 16),
                  Btn(
                    t('mpos.printShift'),
                    icon: LucideIcons.printer,
                    kind: BtnKind.ghost,
                    expand: true,
                    onTap: () async {
                      final bar = ScaffoldMessenger.of(context);
                      await MartPrint.load();
                      try {
                        await printWidget(
                          _ShiftPaper(shift: s, t: t),
                          MartPrint.printer,
                          title: t('mpos.shiftClosedTitle'),
                        );
                      } catch (e) {
                        bar.showSnackBar(SnackBar(content: Text('${t('rp.failed')} ${martPrintError(e)}')));
                      }
                    },
                  ),
                  const SizedBox(height: 10),
                  SizedBox(height: 56, child: Btn(t('mpos.doneNext'), expand: true, onTap: onDone)),
                  const SizedBox(height: 10),
                  Muted(t('mpos.nextPerson'), align: TextAlign.center),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ShiftPaper extends StatelessWidget {
  final J shift;
  final T t; // drawn off-screen: no app scope there
  const _ShiftPaper({required this.shift, required this.t});
  @override
  Widget build(BuildContext context) {
    final pos = MartPos.i;
    final s = shift;
    final cc = pos.currency;
    Widget r(String a, String b, {bool bold = false}) => Row(
      children: [
        Expanded(
          child: Text(
            a,
            style: TextStyle(color: Colors.black, fontWeight: bold ? FontWeight.w800 : FontWeight.w500),
          ),
        ),
        Text(
          b,
          style: TextStyle(color: Colors.black, fontWeight: bold ? FontWeight.w800 : FontWeight.w500),
        ),
      ],
    );
    const rule = Divider(color: Colors.black, height: 12);
    return Padding(
      padding: const EdgeInsets.all(10),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            js(pos.business['name']),
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.black, fontSize: 15, fontWeight: FontWeight.w800),
          ),
          Text(
            t('mpos.shiftNo', {'no': js(s['no'])}),
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.black),
          ),
          rule,
          r(receiptWhen(s['opened_at']), js(s['opened_by'])),
          r(receiptWhen(s['closed_at']), js(s['closed_by'])),
          rule,
          r(t('mpos.receipts'), '${nz(s['sales_count']).toInt()}'),
          r(t('mpos.salesTotal'), f.money(s['sales_total'], cc), bold: true),
          for (final e in jmap(s['by_method']).entries) r(methodLabel(t, pos.settings, e.key), f.money(e.value, cc)),
          rule,
          r(t('mpos.float'), '${_usd(s['float_usd'])} · ${_khr(s['float_khr'])}'),
          r(t('mpos.expected'), '${_usd(s['expected_usd'])} · ${_khr(s['expected_khr'])}'),
          r(t('mpos.counted'), '${_usd(s['counted_usd'])} · ${_khr(s['counted_khr'])}'),
          r(t('mpos.difference'), '${_sign(nz(s['diff_usd']), _usd)} · ${_sign(nz(s['diff_khr']), _khr)}', bold: true),
          if (js(s['note']).isNotEmpty) ...[rule, Text(js(s['note']), style: const TextStyle(color: Colors.black))],
        ],
      ),
    );
  }
}
