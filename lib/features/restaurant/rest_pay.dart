import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/theme.dart';
import '../../widgets/ui.dart';
import 'engine/calc.dart';
import 'engine/rest_pos.dart';
import 'pos_ui.dart';
import 'rest_print.dart';

const _notes = {
  'USD': [1, 5, 10, 20, 50, 100],
  'KHR': [5000, 10000, 20000, 50000, 100000],
};

// Take payment: one or more methods, USD and riel, change worked out in the currency chosen.
// Returns true when the bill was paid ("Done").
Future<bool?> showPay(BuildContext context, String orderId) {
  final t = tr(context);
  final o = RestPos.i.orders[orderId]!;
  return posSheet<bool>(context, title: '${t('rpos.payTitle')} · #${js(o['number'])}', maxWidth: 900, body: (_) => _Pay(orderId));
}

class _Pay extends StatefulWidget {
  final String orderId;
  const _Pay(this.orderId);
  @override
  State<_Pay> createState() => _PayState();
}

class _PayState extends State<_Pay> {
  final pos = RestPos.i;
  late J _method = pos.payMethods.first;
  late String _currency = pos.currency;
  String _input = '';
  final List<J> _list = [];
  String _changeIn = 'KHR';
  bool _busy = false;
  ({J order, double usd, double khr})? _done;

  J get m => pos.moneyS;
  String get main => pos.currency;
  J get order => pos.orders[widget.orderId]!;

  List<J> get _draft => nz(_input) > 0
      ? [
          {'method': js(_method['name']), 'kind': js(_method['kind']), 'currency': _currency, 'amount': nz(_input)},
        ]
      : [];
  List<J> get _all => [..._list, ..._draft];

  double _remainIn(String c) {
    final base = calcOrder(order, m);
    final paid = [..._list, ...jlist(order['payments'])].fold<double>(0, (a, p) => a + paymentValue(p, m));
    final left = (base.total - paid) < 0 ? 0.0 : base.total - paid;
    final rate = nz(m['khr_rate']) == 0 ? 4100 : nz(m['khr_rate']);
    if (c == main) return left;
    return c == 'KHR' ? roundStep(left * rate, nz(m['khr_rounding']) == 0 ? 100 : nz(m['khr_rounding'])) : (left / rate * 100).ceilToDouble() / 100;
  }

  (double, double) _changeOut(Totals tot) {
    if (tot.change <= 0) return (0, 0);
    final rate = nz(m['khr_rate']) == 0 ? 4100 : nz(m['khr_rate']);
    if (main == 'USD') return _changeIn == 'KHR' ? (0, roundStep(tot.change * rate, nz(m['khr_rounding']) == 0 ? 100 : nz(m['khr_rounding']))) : (tot.change, 0);
    return _changeIn == 'USD' ? ((tot.change / rate * 100).floorToDouble() / 100, 0) : (0, tot.change);
  }

  String _fmtInput(String v) {
    if (v.isEmpty) return '';
    final x = nz(v);
    if (_currency == 'KHR') return x.toInt().toString();
    return x == x.roundToDouble() ? x.toInt().toString() : x.toStringAsFixed(2);
  }

  void _pickMethod(J mm) => setState(() {
    _method = mm;
    if (mm['kind'] != 'cash') {
      _currency = main;
      _input = _fmtInput('${_remainIn(main)}');
    }
  });

  void _add() {
    if (_draft.isEmpty) return;
    setState(() {
      _list.addAll(_draft);
      _input = '';
    });
  }

  Future<void> _complete(Totals tot) async {
    setState(() => _busy = true);
    final (usd, khr) = _changeOut(tot);
    final paid = await pos.pay(widget.orderId, _all, usd, khr);
    if (mounted) setState(() => _done = (order: paid, usd: usd, khr: khr));
    await RestPrint.i.load();
    if (RestPrint.i.autoReceipt && RestPrint.i.billPrinter.on && mounted) runPrint(context, () => RestPrint.i.receipt(paid, paid: true));
  }

  @override
  Widget build(BuildContext context) {
    final t = tr(context);
    final c = context.c;
    if (_done != null) return _paid(context);
    final base = calcOrder(order, m);
    final tot = calcOrder({
      ...order,
      'payments': [...jlist(order['payments']), ..._all],
    }, m);
    final (chUsd, chKhr) = _changeOut(tot);
    final changeText = [if (chUsd > 0) m$(chUsd, 'USD'), if (chKhr > 0) m$(chKhr, 'KHR')].join(' + ');

    final dueCard = Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(gradient: c.gradient, borderRadius: BorderRadius.circular(20)),
      child: Column(
        children: [
          Text(
            t('rpos.due'),
            style: TextStyle(color: Colors.white.withValues(alpha: .85), fontWeight: FontWeight.w600),
          ),
          FittedBox(
            child: Text(
              m$(base.total, main),
              style: const TextStyle(color: Colors.white, fontSize: 36, fontWeight: FontWeight.w800),
            ),
          ),
          Text(
            m$(otherCurrency(base.total, m), other(main)),
            style: TextStyle(color: Colors.white.withValues(alpha: .85), fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );

    final summary = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < _list.length; i++)
          Container(
            margin: const EdgeInsets.only(bottom: 6),
            padding: const EdgeInsets.only(left: 14),
            decoration: BoxDecoration(
              color: c.card,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: c.line),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(js(_list[i]['method']), style: const TextStyle(fontWeight: FontWeight.w600)),
                ),
                Text(m$(_list[i]['amount'], js(_list[i]['currency'])), style: const TextStyle(fontWeight: FontWeight.w800)),
                IconButton(
                  onPressed: () => setState(() => _list.removeAt(i)),
                  icon: Icon(LucideIcons.trash2, size: 17, color: c.danger),
                  tooltip: t('rpos.clear'),
                ),
              ],
            ),
          ),
        SumRow(t('rpos.paid'), m$(tot.paid, main)),
        if (!tot.settled) SumRow(t('rpos.remaining'), '${m$(tot.due, main)} · ${m$(otherCurrency(tot.due, m), other(main))}', color: c.danger),
        if (tot.change > 0) ...[
          SumRow(t('rpos.change'), changeText, big: true, color: c.good),
          const SizedBox(height: 6),
          Row(
            children: [
              Text(
                t('rpos.changeIn'),
                style: TextStyle(color: c.muted, fontWeight: FontWeight.w600),
              ),
              const SizedBox(width: 10),
              PosChips<String>(value: _changeIn, onTap: (v) => setState(() => _changeIn = v), options: const [('KHR', '៛ Riel'), ('USD', '\$ USD')]),
            ],
          ),
        ],
        const SizedBox(height: 14),
        SizedBox(
          height: 58,
          child: Btn(t('rpos.complete'), icon: LucideIcons.circleCheck, busy: _busy, expand: true, onTap: tot.settled && !_busy ? () => _complete(tot) : null),
        ),
      ],
    );

    final cash = _method['kind'] == 'cash';
    final keypad = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        PosChips<String>(
          value: js(_method['name']),
          onTap: (v) => _pickMethod(pos.payMethods.firstWhere((x) => js(x['name']) == v)),
          options: [for (final mm in pos.payMethods) (js(mm['name']), js(mm['name']))],
        ),
        const SizedBox(height: 8),
        PosChips<String>(
          value: _currency,
          enabled: (v) => cash || v == main,
          onTap: (v) => setState(() {
            _currency = v;
            if (v == 'KHR') _input = _input.split('.').first;
          }),
          options: const [('USD', '\$ USD'), ('KHR', '៛ Riel')],
        ),
        const SizedBox(height: 10),
        Container(
          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 14),
          decoration: BoxDecoration(
            color: c.card,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: c.brand, width: 2),
          ),
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(m$(nz(_input), _currency), style: const TextStyle(fontSize: 32, fontWeight: FontWeight.w800)),
          ),
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            ActionChip(
              label: Text(t('rpos.exact'), style: const TextStyle(fontWeight: FontWeight.w800)),
              onPressed: () => setState(() => _input = _fmtInput('${_remainIn(_currency)}')),
            ),
            if (cash)
              for (final v in _notes[_currency]!)
                ActionChip(label: Text('+${_currency == 'KHR' ? '${v ~/ 1000}k' : '\$$v'}'), onPressed: () => setState(() => _input = _fmtInput('${nz(_input) + v}'))),
          ],
        ),
        const SizedBox(height: 10),
        Keypad(value: _input, onChanged: (v) => setState(() => _input = v), dot: _currency == 'USD', max: 10, keyHeight: 52, enterLabel: t('rpos.addPayment'), onEnter: _add),
      ],
    );

    if (wide(context)) {
      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [dueCard, const SizedBox(height: 10), summary]),
          ),
          const SizedBox(width: 18),
          Expanded(child: keypad),
        ],
      );
    }
    // phone: what to pay first, then the keypad, then what was paid + Complete
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [dueCard, const SizedBox(height: 12), keypad, const SizedBox(height: 14), summary]);
  }

  Widget _paid(BuildContext context) {
    final t = tr(context);
    final c = context.c;
    final d = _done!;
    final total = calcOrder(d.order, m).total;
    final change = [if (d.usd > 0) m$(d.usd, 'USD'), if (d.khr > 0) m$(d.khr, 'KHR')].join(' + ');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 10),
        Icon(LucideIcons.circleCheck, size: 64, color: c.good),
        const SizedBox(height: 8),
        Text(
          t('rpos.paidDone'),
          textAlign: TextAlign.center,
          style: TextStyle(color: c.good, fontWeight: FontWeight.w800, fontSize: 18),
        ),
        Text(
          m$(total, main),
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 34, fontWeight: FontWeight.w800),
        ),
        if (change.isNotEmpty) ...[
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(color: c.goodBg, borderRadius: BorderRadius.circular(18)),
            child: Text(
              t('rpos.giveChange', {'v': change}),
              textAlign: TextAlign.center,
              style: TextStyle(color: c.good, fontWeight: FontWeight.w800, fontSize: 22),
            ),
          ),
        ],
        const SizedBox(height: 22),
        Row(
          children: [
            Expanded(
              child: SizedBox(
                height: 56,
                child: Btn(t('rpos.printReceipt'), icon: LucideIcons.printer, kind: BtnKind.ghost, expand: true, onTap: () => previewReceipt(context, d.order, paid: true)),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: SizedBox(height: 56, child: Btn(t('rpos.done'), expand: true, onTap: () => Navigator.pop(context, true))),
            ),
          ],
        ),
      ],
    );
  }
}
