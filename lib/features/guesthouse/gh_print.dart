import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../core/app_state.dart';
import '../../core/i18n.dart';
import '../../core/printing/printer_settings.dart';
import '../../core/printing/printing.dart';
import '../restaurant/engine/calc.dart' show J, jmap, jlist, js, nz;
import '../restaurant/rest_receipt.dart' show TestTicket;
import 'engine/gh_pos.dart';
import 'gh_ui.dart';

// The Guest House bill / receipt — the web's classic template (pos/guesthouse/GhReceipt.jsx), in black for paper.
const _ink = Colors.black;
const _words = {
  'en': {
    'receipt': 'RECEIPT',
    'bill': 'BILL',
    'no': 'No.',
    'date': 'Date',
    'staff': 'Staff',
    'room': 'Room',
    'checkIn': 'Check-in',
    'checkOut': 'Check-out',
    'nights': 'Nights',
    'nightsV': '{n} night(s)',
    'roomLine': 'Room {room} · {n} night(s) × {rate}',
    'discount': 'Discount',
    'total': 'Total',
    'paid': 'Paid',
    'toPay': 'To pay',
    'change': 'Change',
    'payments': 'Payments',
    'scan': 'Scan to pay',
    'thanks': 'Thank you for staying with us!',
  },
  'km': {
    'receipt': 'វិក្កយបត្រ',
    'bill': 'វិក្កយបត្រត្រូវបង់',
    'no': 'លេខ',
    'date': 'កាលបរិច្ឆេទ',
    'staff': 'បុគ្គលិក',
    'room': 'បន្ទប់',
    'checkIn': 'ចូល',
    'checkOut': 'ចេញ',
    'nights': 'ចំនួនយប់',
    'nightsV': '{n} យប់',
    'roomLine': 'បន្ទប់ {room} · {n} យប់ × {rate}',
    'discount': 'បញ្ចុះតម្លៃ',
    'total': 'សរុប',
    'paid': 'បានបង់',
    'toPay': 'ត្រូវបង់',
    'change': 'អាប់',
    'payments': 'ការបង់ប្រាក់',
    'scan': 'ស្កេនដើម្បីបង់',
    'thanks': 'អរគុណដែលបានស្នាក់នៅជាមួយយើង!',
  },
};

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

class GhReceipt extends StatelessWidget {
  final J stay, boot;
  final T t;
  final ui.Image? logo, qr;
  const GhReceipt({super.key, required this.stay, required this.boot, required this.t, this.logo, this.qr});
  @override
  Widget build(BuildContext context) {
    final s = stay;
    final p = _words[t.km ? 'km' : 'en']!;
    final biz = jmap(boot['business']);
    final set = jmap(boot['settings']);
    final cur = js(set['currency']).isEmpty ? 'USD' : js(set['currency']);
    String m(Object? v) => ghMoney(v, cur);
    final b = jmap(s['bill']);
    final paidUp = nz(b['balance']) <= 0 && nz(b['total']) > 0;
    final contact = [biz['phone'], set['email'], set['website']].map(js).where((x) => x.isNotEmpty).join(' · ');
    final staff = js(jmap(boot['staff'])['name']).isNotEmpty ? js(jmap(boot['staff'])['name']) : js(s['by']);
    final g = jmap(s['guest']);
    final note = js(set['receipt_note']);
    const small = TextStyle(color: _ink, fontSize: 11);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (logo != null)
            Center(
              child: RawImage(image: logo, width: 64, height: 64, fit: BoxFit.contain),
            ),
          Text(
            js(biz['name']),
            textAlign: TextAlign.center,
            style: const TextStyle(color: _ink, fontSize: 16, fontWeight: FontWeight.w800),
          ),
          if (js(biz['address']).isNotEmpty) Text(js(biz['address']), textAlign: TextAlign.center, style: small),
          if (contact.isNotEmpty) Text(contact, textAlign: TextAlign.center, style: small),
          const SizedBox(height: 6),
          Text(
            paidUp ? p['receipt']! : p['bill']!,
            textAlign: TextAlign.center,
            style: const TextStyle(color: _ink, fontSize: 15, fontWeight: FontWeight.w800),
          ),
          const _Rule(),
          _R(p['no']!, js(s['no'])),
          _R(p['date']!, ghTime(DateTime.now().toUtc().toIso8601String())),
          if (staff.isNotEmpty) _R(p['staff']!, staff),
          const _Rule(),
          Text(
            '${p['room']} ${js(s['room_name'])} · ${js(g['name'])}',
            style: const TextStyle(color: _ink, fontSize: 13.5, fontWeight: FontWeight.w800),
          ),
          if (js(g['phone']).isNotEmpty) Text(js(g['phone']), style: small),
          _R(p['checkIn']!, ghDay(js(s['from']), year: true)),
          _R(p['checkOut']!, ghDay(js(s['to']), year: true)),
          _R(p['nights']!, p['nightsV']!.replaceAll('{n}', '${nz(b['nights']).toInt()}')),
          const _Rule(),
          if (s['lease'] == null) _R(p['roomLine']!.replaceAll('{room}', js(s['room_name'])).replaceAll('{n}', '${nz(b['nights']).toInt()}').replaceAll('{rate}', m(s['rate'])), m(b['room'])),
          for (final c in jlist(s['charges'])) _R('${js(c['label'])}${nz(c['qty']) > 1 ? ' × ${nz(c['qty']).toInt()}' : ''}', m(nz(c['amount']) * (nz(c['qty']) == 0 ? 1 : nz(c['qty'])))),
          if (nz(b['discount']) > 0) _R(p['discount']!, '−${m(b['discount'])}'),
          const _Rule(),
          _R(p['total']!, m(b['total']), big: true),
          if (jlist(s['payments']).isNotEmpty) ...[
            const SizedBox(height: 4),
            for (final x in jlist(s['payments'])) _R('${t.or('gh.methods.${js(x['method'])}', js(x['method']))}${js(x['note']).isNotEmpty ? ' · ${js(x['note'])}' : ''}', m(x['amount'])),
          ],
          _R(nz(b['balance']) > 0 ? p['toPay']! : (nz(b['balance']) < 0 ? p['change']! : p['paid']!), m(nz(b['balance']) == 0 ? b['paid'] : nz(b['balance']).abs()), big: nz(b['balance']) != 0),
          if (qr != null && nz(b['balance']) > 0) ...[
            const SizedBox(height: 8),
            Center(
              child: RawImage(image: qr, width: 150, height: 150, fit: BoxFit.contain),
            ),
            Text('${p['scan']}${js(set['pay_qr_label']).isNotEmpty ? ' · ${js(set['pay_qr_label'])}' : ''}', textAlign: TextAlign.center, style: small),
          ],
          const _Rule(),
          if (note.isNotEmpty)
            Text(
              note,
              textAlign: TextAlign.center,
              style: const TextStyle(color: _ink, fontSize: 12, fontWeight: FontWeight.w600),
            ),
          Text(p['thanks']!, textAlign: TextAlign.center, style: small),
        ],
      ),
    );
  }
}

// printing for the desk: the owner turns printing on (gh_printer); each device picks its printer
class GhPrint {
  static const _key = 'pos.gh.printers';
  static PrinterConf conf = const PrinterConf();
  static bool autoHere = false;
  static bool _loaded = false;

  static GhPos get pos => GhPos.i;
  static J get _print => jmap(pos.boot['print']);
  static bool get licensed => _print['on'] == true;
  static bool get auto => autoHere || _print['auto'] == true;
  static bool get qrOn => _print['qr'] != false;

  static Future<void> load() async {
    if (_loaded) return;
    final v = await PrinterStore.load(_key);
    conf = v['conf'] == null ? PrinterConf(paper: js(_print['size']) == '58' ? 58 : 80) : PrinterConf.fromJson(v['conf']);
    autoHere = v['auto'] == true;
    _loaded = true;
  }

  static Future<void> save() => PrinterStore.save(_key, {'conf': conf.toJson(), 'auto': autoHere});

  // what really prints (Bluetooth / Wi-Fi only with the add-on)
  static PrinterConf get printer => conf.kind == PrinterKind.system || licensed ? conf : const PrinterConf();

  static Future<Widget> doc(J stay) async {
    final qrUrl = qrOn && nz(jmap(stay['bill'])['balance']) > 0 ? js(pos.settings['pay_qr']) : '';
    final imgs = await Future.wait([loadPicture(js(pos.business['logo_url'])), loadPicture(qrUrl)]);
    return GhReceipt(stay: stay, boot: pos.boot, t: AppState.i.t, logo: imgs[0], qr: imgs[1]);
  }

  static Future<void> receipt(J stay) async {
    await load();
    await printWidget(await doc(stay), printer, title: js(stay['no']));
  }
}

Future<void> openGhPrinters(BuildContext context) async {
  await GhPrint.load();
  if (!context.mounted) return;
  final t = AppState.i.t;
  await Navigator.of(context).push(
    MaterialPageRoute(
      builder: (_) => StatefulBuilder(
        builder: (ctx, set) => PrinterSettingsPage(
          conf: GhPrint.conf,
          licensed: GhPrint.licensed,
          lockedText: t('mart.printLocked'),
          onChanged: (c) {
            GhPrint.conf = c;
            GhPrint.save();
          },
          testDoc: (c) => TestTicket(shop: js(GhPos.i.business['name']), printer: c.kind == PrinterKind.bluetooth || c.kind == PrinterKind.installed ? (c.name.isEmpty ? c.address : c.name) : c.address, t: t),
          extra: [
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: GhPrint.auto,
              onChanged: jmap(GhPos.i.boot['print'])['auto'] == true
                  ? null
                  : (v) {
                      set(() => GhPrint.autoHere = v);
                      GhPrint.save();
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

String ghPrintError(Object e) => printErrorMessage(e);
