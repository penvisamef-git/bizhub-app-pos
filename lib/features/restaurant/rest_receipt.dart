import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../core/format.dart' as f;
import '../../core/i18n.dart';
import 'engine/calc.dart';

// The printed papers of the restaurant POS — the same as the web's receipt.jsx (themes classic / khmer / columns).
// Plain black-on-white widgets: drawn on screen for the preview and off-screen for the printer.

String _two(int x) => x.toString().padLeft(2, '0');
// 19/10/2026, 14:05 (this device's clock, like the web)
String receiptWhen(Object? d) {
  final x = (DateTime.tryParse('${d ?? ''}') ?? DateTime.now()).toLocal();
  return '${_two(x.day)}/${_two(x.month)}/${x.year}, ${_two(x.hour)}:${_two(x.minute)}';
}

String _n(Object? v) {
  final x = nz(v);
  return x == x.roundToDouble() ? x.toInt().toString() : x.toString();
}

const _ink = Colors.black;
const _rule = Padding(padding: EdgeInsets.symmetric(vertical: 5), child: _Dashes());

class _Dashes extends StatelessWidget {
  const _Dashes();
  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (_, box) {
      final n = (box.maxWidth / 6).floor();
      return Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [for (var i = 0; i < n; i++) const SizedBox(width: 3, height: 1, child: ColoredBox(color: _ink))],
      );
    },
  );
}

class _Row extends StatelessWidget {
  final String a, b;
  final bool bold, big, sub;
  const _Row(this.a, this.b, {this.bold = false, this.big = false, this.sub = false});
  @override
  Widget build(BuildContext context) {
    final st = TextStyle(color: _ink, fontSize: big ? 16 : (sub ? 11 : 12.5), fontWeight: bold || big ? FontWeight.w800 : FontWeight.w500, height: 1.35);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(child: Text(a, style: st)),
        const SizedBox(width: 6),
        Text(b, style: st),
      ],
    );
  }
}

class _Sub extends StatelessWidget {
  final String text;
  const _Sub(this.text);
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(left: 12),
    child: Text(text, style: const TextStyle(color: _ink, fontSize: 11, height: 1.3)),
  );
}

// the shop at the top: logo, names, address, phone, TIN (only with VAT)
class ReceiptHead extends StatelessWidget {
  final J restaurant;
  final J money;
  final ui.Image? logo;
  const ReceiptHead({super.key, required this.restaurant, required this.money, this.logo});
  @override
  Widget build(BuildContext context) {
    final r = restaurant;
    const center = TextAlign.center;
    return Column(
      children: [
        if (logo != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: RawImage(image: logo, width: 70, height: 70, fit: BoxFit.contain),
          ),
        if (js(r['name_km']).isNotEmpty)
          Text(
            js(r['name_km']),
            textAlign: center,
            style: const TextStyle(color: _ink, fontSize: 17, fontWeight: FontWeight.w800),
          ),
        if (js(r['name_en']).isNotEmpty)
          Text(
            js(r['name_en']),
            textAlign: center,
            style: const TextStyle(color: _ink, fontSize: 15, fontWeight: FontWeight.w800),
          ),
        if (js(r['address']).isNotEmpty)
          Text(
            js(r['address']),
            textAlign: center,
            style: const TextStyle(color: _ink, fontSize: 11),
          ),
        if (js(r['phone']).isNotEmpty)
          Text(
            js(r['phone']),
            textAlign: center,
            style: const TextStyle(color: _ink, fontSize: 11),
          ),
        if (js(r['tin']).isNotEmpty && jmap(money['vat'])['enabled'] == true)
          Text(
            'TIN: ${js(r['tin'])}',
            textAlign: center,
            style: const TextStyle(color: _ink, fontSize: 11),
          ),
      ],
    );
  }
}

Widget _title(String s) => Padding(
  padding: const EdgeInsets.symmetric(vertical: 6),
  child: Text(
    s,
    textAlign: TextAlign.center,
    style: TextStyle(color: _ink, fontSize: 15, fontWeight: FontWeight.w800, letterSpacing: RegExp(r"[\u1780-\u17FF]").hasMatch(s) ? 0 : 1.5),
  ),
);

// bill (before paying), receipt (paid) or a cancelled bill
class ReceiptView extends StatelessWidget {
  final J order;
  final T t;
  final bool paidView;
  final J restaurant;
  final J money;
  final String cashier;
  final int points;
  final ui.Image? logo;
  const ReceiptView({super.key, required this.order, required this.t, required this.paidView, required this.restaurant, required this.money, required this.cashier, this.points = 0, this.logo});

  @override
  Widget build(BuildContext context) {
    final o = order;
    final m = money;
    final tot = calcOrder(o, m);
    final c = cur(m);
    final other = c == 'USD' ? 'KHR' : 'USD';
    final look = js(jmap(restaurant['receipt'])['theme']).isEmpty ? 'classic' : js(jmap(restaurant['receipt'])['theme']);
    final khmerFirst = look == 'khmer', columns = look == 'columns';
    final lines = jlist(o['lines']).where((l) => l['status'] != 'void').toList();
    final rc = jmap(restaurant['receipt']);
    final ch = jmap(o['change']);
    final mem = jmap(o['member']);
    final earned = o['points_applied'] == true ? nz(o['points_earned']).toInt() : points;
    String p(Object? v, [String? cc]) => f.money(v, cc ?? c);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          ReceiptHead(restaurant: restaurant, money: m, logo: logo),
          _title(paidView ? t('rpos.receiptTitle') : t('rpos.billTitle')),
          if (o['status'] == 'void') _title(t('rpos.cancelledTitle')),
          _Row('#${js(o['number'])}', js(o['table_name']).isNotEmpty ? '${t('rpos.table')} ${js(o['table_name'])}' : t('rpos.takeaway')),
          _Row(receiptWhen(paidView ? (o['paid_at'] ?? o['opened_at']) : (o['paid_at'] ?? DateTime.now().toIso8601String())), '${t('rpos.cashier')}: $cashier'),
          _rule,
          if (columns) _Row('${t('rpos.qty')}  ${t('rpos.order')}', t('rpos.amount'), bold: true),
          for (final l in lines) ...[
            () {
              final km = js(l['name_km']), en = js(l['name_en']);
              final main = khmerFirst ? (km.isNotEmpty ? km : en) : (en.isNotEmpty ? en : km);
              final size = js(l['size']).isNotEmpty ? ' (${js(l['size'])})' : '';
              return _Row(columns ? '${_n(l['qty'])}   $main$size' : '${_n(l['qty'])} × $main$size', p(lineTotal(l)));
            }(),
            () {
              final km = js(l['name_km']), en = js(l['name_en']);
              final sub = khmerFirst ? (km.isNotEmpty ? en : '') : (en.isNotEmpty ? km : '');
              return sub.isEmpty ? const SizedBox.shrink() : _Sub(sub);
            }(),
            for (final a in jlist(l['addons'])) _Sub('+ ${js(a['name'])}${nz(a['price']) > 0 ? ' ${p(a['price'])}' : ''}'),
            if (js(l['note']).isNotEmpty) _Sub('“${js(l['note'])}”'),
            if (lineOff(l) > 0)
              Padding(
                padding: const EdgeInsets.only(left: 12),
                child: _Row(
                  js(jmap(l['discount'])['kind']).isNotEmpty
                      ? '${t('rpos.discount')}${jmap(l['discount'])['kind'] == 'percent' ? ' ${_n(jmap(l['discount'])['value'])}%' : ''}${js(jmap(l['discount'])['reason']).isNotEmpty ? ' · ${js(jmap(l['discount'])['reason'])}' : ''}'
                      : js(jmap(l['promo'])['name']),
                  '−${p(lineOff(l))}',
                  sub: true,
                ),
              ),
          ],
          _rule,
          _Row(t('rpos.subtotal'), p(tot.subtotal)),
          if (tot.discount > 0) _Row(t('rpos.discount'), '−${p(tot.discount)}'),
          if (tot.service > 0) _Row('${t('rpos.service')} ${_n(jmap(m['service_charge'])['rate'])}%', p(tot.service)),
          if (tot.vat > 0) _Row('${tot.vatIncluded ? t('rpos.vatIncl') : t('rpos.vat')} ${_n(jmap(m['vat'])['rate'])}%', p(tot.vat)),
          const SizedBox(height: 2),
          _Row(t('rpos.total'), p(tot.total), big: true),
          _Row('', p(tot.other, other)),
          if (paidView) ...[
            _rule,
            for (final pay in jlist(o['payments'])) _Row(js(pay['method']), p(pay['amount'], js(pay['currency']))),
            if (nz(ch['usd']) > 0 || nz(ch['khr']) > 0) _Row(t('rpos.change'), [if (nz(ch['usd']) > 0) p(ch['usd'], 'USD'), if (nz(ch['khr']) > 0) p(ch['khr'], 'KHR')].join(' + ')),
          ],
          if (js(mem['id']).isNotEmpty) ...[
            _rule,
            _Row('★ ${t('rpos.member')}', '${js(mem['name'])} ${js(mem['phone'])}'),
            for (final r in jlist(o['redemptions'])) _Row(js(r['name']), js(r['code']).isNotEmpty ? js(r['code']) : '−${nz(r['points']).toInt()} ${t('rpos.pts')}'),
            if (earned > 0) _Row(t('rpos.pointsEarned'), '+$earned'),
          ],
          _rule,
          Text(
            '${t('rpos.rate')}: 1 USD = ${f.money(nz(m['khr_rate']) == 0 ? 4100 : m['khr_rate'], 'KHR')}',
            textAlign: TextAlign.center,
            style: const TextStyle(color: _ink, fontSize: 11),
          ),
          if (js(rc['footer']).isNotEmpty)
            Text(
              js(rc['footer']),
              textAlign: TextAlign.center,
              style: const TextStyle(color: _ink, fontSize: 12, fontWeight: FontWeight.w600),
            ),
          if (js(rc['wifi_name']).isNotEmpty)
            Text(
              'Wi-Fi: ${js(rc['wifi_name'])}${js(rc['wifi_pass']).isNotEmpty ? ' · ${js(rc['wifi_pass'])}' : ''}',
              textAlign: TextAlign.center,
              style: const TextStyle(color: _ink, fontSize: 11),
            ),
          if (js(rc['footer']).isEmpty)
            Text(
              t('rpos.thanks'),
              textAlign: TextAlign.center,
              style: const TextStyle(color: _ink, fontSize: 12, fontWeight: FontWeight.w600),
            ),
        ],
      ),
    );
  }
}

// a kitchen / bar ticket: only the items just sent, big and clear, no prices
class KitchenTicket extends StatelessWidget {
  final J order;
  final List<J> lines;
  final String station;
  final String staff;
  final T t;
  final bool again; // reprinted
  const KitchenTicket({super.key, required this.order, required this.lines, required this.station, required this.staff, required this.t, this.again = false});
  @override
  Widget build(BuildContext context) {
    final o = order;
    final where = js(o['table_name']).isNotEmpty ? '${t('rpos.table')} ${js(o['table_name'])}' : t('rpos.takeaway');
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (station.isNotEmpty)
            Text(
              station.toUpperCase(),
              textAlign: TextAlign.center,
              style: const TextStyle(color: _ink, fontSize: 13, fontWeight: FontWeight.w700, letterSpacing: 1.2),
            ),
          Text(
            where,
            textAlign: TextAlign.center,
            style: const TextStyle(color: _ink, fontSize: 26, fontWeight: FontWeight.w800),
          ),
          if (again)
            Text(
              '— ${t('rp.reprint')} —',
              textAlign: TextAlign.center,
              style: const TextStyle(color: _ink, fontSize: 12, fontWeight: FontWeight.w700),
            ),
          _Row('#${js(o['number'])}', receiptWhen(DateTime.now().toIso8601String())),
          _Row(staff, nz(o['guests']) > 0 ? '${t('rpos.guests')}: ${nz(o['guests']).toInt()}' : ''),
          _rule,
          for (final l in lines) ...[
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 36,
                    child: Text(
                      '${_n(l['qty'])}×',
                      style: const TextStyle(color: _ink, fontSize: 18, fontWeight: FontWeight.w800),
                    ),
                  ),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${js(l['name_km']).isNotEmpty ? js(l['name_km']) : js(l['name_en'])}${js(l['size']).isNotEmpty ? ' (${js(l['size'])})' : ''}',
                          style: const TextStyle(color: _ink, fontSize: 17, fontWeight: FontWeight.w800, height: 1.25),
                        ),
                        if (js(l['name_km']).isNotEmpty && js(l['name_en']).isNotEmpty) Text(js(l['name_en']), style: const TextStyle(color: _ink, fontSize: 12)),
                        for (final a in jlist(l['addons']))
                          Text(
                            '+ ${js(a['name'])}',
                            style: const TextStyle(color: _ink, fontSize: 14, fontWeight: FontWeight.w600),
                          ),
                        if (js(l['note']).isNotEmpty)
                          Text(
                            '“${js(l['note'])}”',
                            style: const TextStyle(color: _ink, fontSize: 14, fontWeight: FontWeight.w700, fontStyle: FontStyle.italic),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
          if (js(o['note']).isNotEmpty) ...[
            _rule,
            Text(
              '${t('rpos.noteItem')}: ${js(o['note'])}',
              style: const TextStyle(color: _ink, fontSize: 13, fontWeight: FontWeight.w600),
            ),
          ],
        ],
      ),
    );
  }
}

// the shift report (printed when the shift closes)
class ShiftTicket extends StatelessWidget {
  final J shift;
  final ShiftSum sum;
  final J restaurant;
  final J money;
  final String device;
  final T t;
  const ShiftTicket({super.key, required this.shift, required this.sum, required this.restaurant, required this.money, required this.device, required this.t});
  @override
  Widget build(BuildContext context) {
    final c = cur(money);
    final counted = jmap(shift['counted']);
    final dUsd = nz(counted['usd']) - sum.expUsd, dKhr = nz(counted['khr']) - sum.expKhr;
    String sign(double v, String cc) => '${v >= 0 ? '+' : '−'}${f.money(v.abs(), cc)}';
    final who = js(jmap(shift['closed_by'])['name']).isNotEmpty ? js(jmap(shift['closed_by'])['name']) : js(jmap(shift['opened_by'])['name']);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          ReceiptHead(restaurant: restaurant, money: money),
          _title(t('rpos.shiftClosed')),
          _Row(device, who),
          _Row(receiptWhen(shift['opened_at']), '→ ${receiptWhen(shift['closed_at'])}'),
          _rule,
          _Row(t('rpos.bills'), '${sum.bills}'),
          _Row(t('rpos.sales'), f.money(sum.sales, c), big: true),
          if (sum.discounts > 0) _Row(t('rpos.discounts'), f.money(sum.discounts, c)),
          _rule,
          for (final e in sum.byMethod.entries) _Row(e.key, f.money(e.value, c)),
          _rule,
          _Row(t('rpos.expected'), '${f.money(sum.expUsd, 'USD')} · ${f.money(sum.expKhr, 'KHR')}'),
          _Row(t('rpos.counted'), '${f.money(counted['usd'], 'USD')} · ${f.money(counted['khr'], 'KHR')}'),
          _Row(t('rpos.difference'), '${sign(dUsd, 'USD')} · ${sign(dKhr, 'KHR')}', bold: true),
          if (sum.voidOrders > 0 || sum.voidLines > 0) _Row(t('rpos.cancelled'), '${sum.voidOrders} / ${sum.voidLines}'),
        ],
      ),
    );
  }
}

// "does it print?" — a short test page with Khmer and English
class TestTicket extends StatelessWidget {
  final String shop, printer;
  final T t;
  const TestTicket({super.key, required this.shop, required this.printer, required this.t});
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          shop,
          textAlign: TextAlign.center,
          style: const TextStyle(color: _ink, fontSize: 17, fontWeight: FontWeight.w800),
        ),
        _title(t('rp.testTitle')),
        Text(
          printer,
          textAlign: TextAlign.center,
          style: const TextStyle(color: _ink, fontSize: 12),
        ),
        _rule,
        const Text(
          'សួស្តី! ម៉ាស៊ីនព្រីននេះដំណើរការល្អ។',
          textAlign: TextAlign.center,
          style: TextStyle(color: _ink, fontSize: 15, fontWeight: FontWeight.w700),
        ),
        const Text(
          'Hello! This printer works.',
          textAlign: TextAlign.center,
          style: TextStyle(color: _ink, fontSize: 14),
        ),
        _rule,
        _Row('1 × Iced latte', f.money(2.5, 'USD')),
        _Row(receiptWhen(null), 'Biz Hub POS'),
      ],
    ),
  );
}
