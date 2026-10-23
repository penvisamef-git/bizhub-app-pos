import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../core/app_state.dart';
import '../../core/format.dart' as f;
import '../../core/i18n.dart';
import '../../core/printing/printer_settings.dart';
import '../../core/printing/printing.dart';
import '../restaurant/engine/calc.dart' show J, jmap, jlist, js, nz;
import '../restaurant/rest_receipt.dart' show receiptWhen, TestTicket;
import 'engine/mart_pos.dart';

// The Mini Mart receipt — the same lines as the web's classic template (pos/mart/themes.js).
const _ink = Colors.black;

String qtyOf(Object? v) {
  final x = nz(v);
  return x == x.roundToDouble() ? x.toInt().toString() : x.toStringAsFixed(3).replaceFirst(RegExp(r'0+$'), '').replaceFirst(RegExp(r'\.$'), '');
}

String methodLabel(T t, J settings, String key, [String saved = '']) {
  final custom = jlist(settings['custom_methods']).where((x) => x['key'] == key).firstOrNull;
  return t.maybe('mart.methods.$key') ?? (saved.isNotEmpty ? saved : (custom != null ? js(custom['name']) : key));
}

class _Rule extends StatelessWidget {
  const _Rule();
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 5),
    child: LayoutBuilder(
      builder: (_, box) => Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [for (var i = 0; i < (box.maxWidth / 6).floor(); i++) const SizedBox(width: 3, height: 1, child: ColoredBox(color: _ink))],
      ),
    ),
  );
}

class _R extends StatelessWidget {
  final String a, b;
  final bool big;
  const _R(this.a, this.b, {this.big = false});
  @override
  Widget build(BuildContext context) {
    final st = TextStyle(color: _ink, fontSize: big ? 16 : 12.5, fontWeight: big ? FontWeight.w800 : FontWeight.w500, height: 1.35);
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

class MartReceipt extends StatelessWidget {
  final J sale;
  final J business;
  final J settings;
  final T t;
  final ui.Image? logo;
  const MartReceipt({super.key, required this.sale, required this.business, required this.settings, required this.t, this.logo});
  @override
  Widget build(BuildContext context) {
    final s = sale;
    final cur = js(s['currency']).isEmpty ? 'USD' : js(s['currency']);
    String m(Object? v) => f.money(v, cur);
    String khr(Object? v) => f.money(v, 'KHR');
    final km = t.km;
    String unitOf(J l) => km ? (js(l['unit_km']).isNotEmpty ? js(l['unit_km']) : js(l['unit_en'])) : (js(l['unit_en']).isNotEmpty ? js(l['unit_en']) : js(l['unit_km']));
    final method = js(s['method']);
    final paid = method == 'cash'
        ? [if (nz(s['paid_usd']) > 0) f.money(s['paid_usd'], 'USD'), if (nz(s['paid_khr']) > 0) khr(s['paid_khr'])].join(' + ')
        : (method == 'debt' ? js(s['debtor_name']) : m(s['total']));
    final phone = js(s['member_phone']);
    final note = js(settings['receipt_note']);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (logo != null)
            Center(
              child: RawImage(image: logo, width: 70, height: 70, fit: BoxFit.contain),
            ),
          Text(
            js(business['name']),
            textAlign: TextAlign.center,
            style: const TextStyle(color: _ink, fontSize: 16, fontWeight: FontWeight.w800),
          ),
          if (js(business['address']).isNotEmpty)
            Text(
              js(business['address']),
              textAlign: TextAlign.center,
              style: const TextStyle(color: _ink, fontSize: 11),
            ),
          if (js(business['phone']).isNotEmpty)
            Text(
              js(business['phone']),
              textAlign: TextAlign.center,
              style: const TextStyle(color: _ink, fontSize: 11),
            ),
          const _Rule(),
          _R(js(s['no']).isEmpty ? '—' : js(s['no']), receiptWhen(s['at'])),
          const _Rule(),
          for (final l in jlist(s['items'])) ...[
            _R(js(l['name']), m(l['total'] ?? nz(l['price']) * nz(l['qty']))),
            Padding(
              padding: const EdgeInsets.only(left: 10),
              child: Text('${qtyOf(l['qty'])}${unitOf(l).isNotEmpty ? ' ${unitOf(l)}' : ''} × ${m(l['price'])}', style: const TextStyle(color: _ink, fontSize: 11)),
            ),
          ],
          const _Rule(),
          if (nz(s['discount']) > 0 || nz(s['promo_discount']) > 0 || nz(s['points_value']) > 0) _R(t('mart.subtotal'), m(s['subtotal'])),
          for (final p in jlist(s['promos'])) _R(js(p['name']), '−${m(p['amount'])}'),
          if (nz(s['discount']) > 0) _R(t('mart.discount'), '−${m(s['discount'])}'),
          if (nz(s['points_value']) > 0) _R('${km ? 'ពិន្ទុ' : 'Points'} (${nz(s['points_used']).toInt()})', '−${m(s['points_value'])}'),
          _R(t('mart.total'), m(s['total']), big: true),
          if (cur == 'USD') _R('', khr(((nz(s['total']) * (nz(s['khr_rate']) == 0 ? 4100 : nz(s['khr_rate']))) / 100).round() * 100)),
          _R(methodLabel(t, settings, method, js(s['method_name'])), paid),
          if (method == 'cash' && nz(s['change']) > 0) _R(t('mart.change'), '${m(s['change'])}${cur == 'USD' ? ' = ${khr(s['change_khr'])}' : ''}'),
          if (s['status'] == 'void')
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                t('mart.voided'),
                textAlign: TextAlign.center,
                style: const TextStyle(color: _ink, fontSize: 16, fontWeight: FontWeight.w800),
              ),
            ),
          const _Rule(),
          if (phone.isNotEmpty)
            Text(
              '${km ? 'សមាជិក' : 'Member'}: ${js(s['member_name'])} ${phone.replaceAllMapped(RegExp(r'\d(?=\d{3})'), (_) => '•')}${nz(s['points_earned']) > 0 ? ' · +${nz(s['points_earned']).toInt()} ${km ? 'ពិន្ទុ' : 'points'}' : ''}',
              textAlign: TextAlign.center,
              style: const TextStyle(color: _ink, fontSize: 11),
            ),
          if (js(s['by']).isNotEmpty)
            Text(
              '${t('mart.cashier')}: ${js(s['by'])}',
              textAlign: TextAlign.center,
              style: const TextStyle(color: _ink, fontSize: 11),
            ),
          if (note.isNotEmpty)
            Text(
              note,
              textAlign: TextAlign.center,
              style: const TextStyle(color: _ink, fontSize: 12, fontWeight: FontWeight.w600),
            ),
        ],
      ),
    );
  }
}

// printing for the Mini Mart POS: the owner turns printing on (mart_printer); each device picks its printer
class MartPrint {
  static const _key = 'pos.mart.printers';
  static PrinterConf conf = const PrinterConf();
  static bool autoHere = false; // this device prints after each sale (also on when the owner set "auto")
  static bool _loaded = false;

  static MartPos get pos => MartPos.i;
  static J get _print => jmap(pos.boot['print']);
  static bool get licensed => _print['on'] == true;
  static bool get auto => autoHere || _print['auto'] == true;
  static int get _paper => js(_print['size']) == '58' ? 58 : 80;

  static Future<void> load() async {
    if (_loaded) return;
    final v = await PrinterStore.load(_key);
    conf = v['conf'] == null ? PrinterConf(paper: _paper) : PrinterConf.fromJson(v['conf']);
    autoHere = v['auto'] == true;
    _loaded = true;
  }

  static Future<void> save() => PrinterStore.save(_key, {'conf': conf.toJson(), 'auto': autoHere});

  // what really prints (Bluetooth / Wi-Fi only with the add-on)
  static PrinterConf get printer => conf.kind == PrinterKind.system || licensed ? conf : const PrinterConf();

  static Future<Widget> doc(J sale) async => MartReceipt(sale: sale, business: pos.business, settings: pos.settings, t: AppState.i.t, logo: await loadPicture(js(pos.business['logo_url'])));

  static Future<void> receipt(J sale) async {
    await load();
    await printWidget(await doc(sale), printer, title: js(sale['no']));
  }
}

Future<void> openMartPrinters(BuildContext context) async {
  await MartPrint.load();
  if (!context.mounted) return;
  final t = AppState.i.t;
  await Navigator.of(context).push(
    MaterialPageRoute(
      builder: (_) => StatefulBuilder(
        builder: (ctx, set) => PrinterSettingsPage(
          conf: MartPrint.conf,
          licensed: MartPrint.licensed,
          lockedText: t('mart.printLocked'),
          onChanged: (c) {
            MartPrint.conf = c;
            MartPrint.save();
          },
          testDoc: (c) => TestTicket(shop: js(MartPos.i.business['name']), printer: c.kind == PrinterKind.bluetooth ? (c.name.isEmpty ? c.address : c.name) : c.address, t: t),
          extra: [
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: MartPrint.auto,
              onChanged: jmap(MartPos.i.boot['print'])['auto'] == true
                  ? null
                  : (v) {
                      set(() => MartPrint.autoHere = v);
                      MartPrint.save();
                    },
              title: Text(t('rp.autoReceipt'), style: const TextStyle(fontWeight: FontWeight.w700)),
              subtitle: Text(t('rp.autoReceiptSub')),
            ),
          ],
        ),
      ),
    ),
  );
}

String martPrintError(Object e) => printErrorMessage(e);
