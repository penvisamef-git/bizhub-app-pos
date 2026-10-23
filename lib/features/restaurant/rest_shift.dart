import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/theme.dart';
import '../../widgets/ui.dart';
import 'engine/calc.dart';
import 'engine/rest_pos.dart';
import 'pos_ui.dart';
import 'rest_print.dart';

// count the drawer → close → send → back to the PIN screen
Future<void> showCloseShift(BuildContext context) {
  final pos = RestPos.i;
  if (pos.openShift == null) return Future.value();
  return posSheet(context, title: tr(context)('rpos.closeShift'), maxWidth: 900, body: (_) => const _CloseShift());
}

class _CloseShift extends StatefulWidget {
  const _CloseShift();
  @override
  State<_CloseShift> createState() => _CloseShiftState();
}

class _CloseShiftState extends State<_CloseShift> {
  String _usd = '', _khr = '', _field = 'usd';
  final _note = TextEditingController();
  bool _busy = false;

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = tr(context);
    final c = context.c;
    final pos = RestPos.i;
    final shift = pos.openShift;
    if (shift == null) return const SizedBox.shrink();
    final sum = pos.shiftNumbers(shift);
    final cur = pos.currency;
    final dUsd = nz(_usd) - sum.expUsd, dKhr = nz(_khr) - sum.expKhr;
    String sign(double v, String cc) => '${v > 0 ? '+' : (v < 0 ? '−' : '')}${m$(v.abs(), cc)}';

    Widget stat(String label, String value) => Expanded(
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: c.card,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: c.line),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: TextStyle(color: c.muted, fontSize: 12.5, fontWeight: FontWeight.w600),
            ),
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(value, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 20)),
            ),
          ],
        ),
      ),
    );

    TableRow row(String a, String b, String cc, {Color? color, bool bold = false}) => TableRow(
      children: [
        for (final (i, v) in [a, b, cc].indexed)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 7),
            child: Text(
              v,
              textAlign: i == 0 ? TextAlign.start : TextAlign.end,
              style: TextStyle(fontWeight: bold || i > 0 ? FontWeight.w700 : FontWeight.w500, color: i > 0 ? color : c.muted),
            ),
          ),
      ],
    );

    final left = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Muted(t('rpos.closeShiftSub')),
        const SizedBox(height: 12),
        Row(
          children: [
            stat(t('rpos.bills'), '${sum.bills}'),
            const SizedBox(width: 8),
            stat(t('rpos.sales'), m$(sum.sales, cur)),
            if (sum.discounts > 0) ...[const SizedBox(width: 8), stat(t('rpos.discounts'), m$(sum.discounts, cur))],
          ],
        ),
        if (sum.byMethod.isNotEmpty) ...[const SizedBox(height: 12), for (final e in sum.byMethod.entries) SumRow(e.key, m$(e.value, cur))],
        const SizedBox(height: 10),
        Table(
          columnWidths: const {0: FlexColumnWidth(1.2), 1: FlexColumnWidth(1), 2: FlexColumnWidth(1.2)},
          children: [
            row('', 'USD', 'KHR', bold: true),
            row(t('rpos.expected'), m$(sum.expUsd, 'USD'), m$(sum.expKhr, 'KHR')),
            row(t('rpos.counted'), m$(nz(_usd), 'USD'), m$(nz(_khr), 'KHR')),
            TableRow(
              decoration: BoxDecoration(
                border: Border(top: BorderSide(color: c.line)),
              ),
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Text(t('rpos.difference'), style: const TextStyle(fontWeight: FontWeight.w800)),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Text(
                    sign(dUsd, 'USD'),
                    textAlign: TextAlign.end,
                    style: TextStyle(fontWeight: FontWeight.w800, color: dUsd < 0 ? c.danger : c.good),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Text(
                    sign(dKhr, 'KHR'),
                    textAlign: TextAlign.end,
                    style: TextStyle(fontWeight: FontWeight.w800, color: dKhr < 0 ? c.danger : c.good),
                  ),
                ),
              ],
            ),
          ],
        ),
        if (sum.openOrders > 0) ...[
          const SizedBox(height: 8),
          Alert(t('rpos.openBillsWarn', {'n': sum.openOrders}), tone: Tone.warn),
        ],
        if (!pos.online) ...[const SizedBox(height: 8), Alert(t('rpos.closingOffline'), tone: Tone.warn)],
        const SizedBox(height: 10),
        Field(controller: _note, hint: t('rpos.note'), maxLength: 300),
        const SizedBox(height: 12),
        SizedBox(
          height: 56,
          child: Btn(
            _busy ? t('rpos.syncing') : t('rpos.closeAndSend'),
            icon: LucideIcons.wallet,
            busy: _busy,
            expand: true,
            onTap: _busy
                ? null
                : () async {
                    setState(() => _busy = true);
                    Navigator.pop(context);
                    await pos.endShift(shift, nz(_usd), nz(_khr), _note.text.trim()); // → ShiftDone screen
                  },
          ),
        ),
      ],
    );

    final right = Column(
      children: [
        Row(
          children: [
            Expanded(
              child: AmountBox(label: t('rpos.cashUsd'), value: m$(nz(_usd), 'USD'), on: _field == 'usd', onTap: () => setState(() => _field = 'usd')),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: AmountBox(label: t('rpos.cashKhr'), value: m$(nz(_khr), 'KHR'), on: _field == 'khr', onTap: () => setState(() => _field = 'khr')),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Keypad(value: _field == 'usd' ? _usd : _khr, onChanged: (v) => setState(() => _field == 'usd' ? _usd = v : _khr = v), dot: _field == 'usd', max: 10, keyHeight: 54),
      ],
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
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [right, const SizedBox(height: 16), left]);
  }
}

// after closing: the shift summary as its own screen, then "Done" → PIN screen for the next person
class ShiftDone extends StatelessWidget {
  const ShiftDone({super.key});
  @override
  Widget build(BuildContext context) {
    final t = tr(context);
    final c = context.c;
    final pos = RestPos.i;
    final done = pos.shiftDone!;
    final sending = done.synced == null;
    final cur = pos.currency;
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
                  Text(
                    t('rpos.shiftClosed'),
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 18),
                  Center(
                    child: sending
                        ? SizedBox(width: 56, height: 56, child: CircularProgressIndicator(color: c.brand))
                        : Icon(done.synced! ? LucideIcons.circleCheck : LucideIcons.cloudOff, size: 60, color: done.synced! ? c.good : c.warn),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    m$(done.sum.sales, cur),
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 34, fontWeight: FontWeight.w800),
                  ),
                  Muted(sending ? t('rpos.sending') : (done.synced! ? t('rpos.shiftSent') : t('rpos.shiftWaiting')), align: TextAlign.center),
                  const SizedBox(height: 16),
                  Panel(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      children: [
                        SumRow(t('rpos.bills'), '${done.sum.bills}'),
                        if (done.sum.discounts > 0) SumRow(t('rpos.discounts'), m$(done.sum.discounts, cur)),
                        for (final e in done.sum.byMethod.entries) SumRow(e.key, m$(e.value, cur)),
                        SumRow(t('rpos.expected'), '${m$(done.sum.expUsd, 'USD')} · ${m$(done.sum.expKhr, 'KHR')}'),
                        SumRow(t('rpos.counted'), '${m$(jmap(done.shift['counted'])['usd'], 'USD')} · ${m$(jmap(done.shift['counted'])['khr'], 'KHR')}'),
                      ],
                    ),
                  ),
                  const SizedBox(height: 18),
                  SizedBox(
                    height: 52,
                    child: Btn(t('rpos.printShift'), icon: LucideIcons.printer, kind: BtnKind.ghost, expand: true, onTap: () => runPrint(context, () => RestPrint.i.shift(done.shift, done.sum))),
                  ),
                  const SizedBox(height: 10),
                  SizedBox(height: 56, child: Btn(t('rpos.done'), expand: true, onTap: sending ? null : pos.finishShift)),
                  const SizedBox(height: 10),
                  Muted(t('rpos.shiftDoneNext'), align: TextAlign.center),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
