import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/app_state.dart';
import '../../core/format.dart';
import '../../core/printing/printer_settings.dart';
import '../../core/printing/printing.dart';
import '../restaurant/rest_receipt.dart' show TestTicket;
import 'ts_api.dart';
import 'ts_card.dart' show tsMoney;

// Telegram Store staff screen: the kitchen / counter ticket of an order on a receipt printer
// (same as the web's printTicket: number, how they get it, who, the items, total, PAID / NOT PAID)
class TsPrint {
  static const _key = 'ts.printer';
  static PrinterConf conf = const PrinterConf();
  static bool auto = false; // print when an order is accepted
  static bool _loaded = false;

  static Future<void> load() async {
    if (_loaded) return;
    final v = await PrinterStore.load(_key);
    conf = v['conf'] == null ? const PrinterConf() : PrinterConf.fromJson(v['conf']);
    auto = v['auto'] == true;
    _loaded = true;
  }

  static Future<void> save() => PrinterStore.save(_key, {'conf': conf.toJson(), 'auto': auto});

  static Future<void> ticket(Json o, String shop) async {
    await load();
    await printWidget(
      TsTicket(o: o, shop: shop),
      conf,
      title: '#${o['no']}',
    );
  }
}

Future<void> openTsPrinters(BuildContext context) async {
  await TsPrint.load();
  if (!context.mounted) return;
  final t = AppState.i.t;
  final shop = str((AppState.i.link ?? const {})['shop']);
  await Navigator.of(context).push(
    MaterialPageRoute(
      builder: (_) => StatefulBuilder(
        builder: (ctx, set) => PrinterSettingsPage(
          conf: TsPrint.conf,
          licensed: true,
          lockedText: '',
          onChanged: (c) {
            TsPrint.conf = c;
            TsPrint.save();
          },
          testDoc: (c) => TestTicket(shop: shop, printer: c.kind == PrinterKind.bluetooth || c.kind == PrinterKind.installed ? (c.name.isEmpty ? c.address : c.name) : c.address, t: t),
          extra: [
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: TsPrint.auto,
              onChanged: (v) {
                set(() => TsPrint.auto = v);
                TsPrint.save();
              },
              title: Text(tsa('autoPrint'), style: const TextStyle(fontWeight: FontWeight.w700)),
              subtitle: Text(tsa('autoPrintSub')),
            ),
          ],
        ),
      ),
    ),
  );
}

const _ink = Color(0xFF000000);

// one ticket (black on white, for thermal paper)
class TsTicket extends StatelessWidget {
  final Json o;
  final String shop;
  const TsTicket({super.key, required this.o, required this.shop});
  @override
  Widget build(BuildContext context) {
    final cur = str(o['currency']);
    final who = obj(o['customer']);
    final mode = str(o['mode']);
    const small = TextStyle(color: _ink, fontSize: 12.5);
    const text = TextStyle(color: _ink, fontSize: 14);
    Widget row(String a, String b, {bool bold = false}) => Row(
      children: [
        Expanded(
          child: Text(
            a,
            style: TextStyle(color: _ink, fontSize: bold ? 17 : 13.5, fontWeight: bold ? FontWeight.w800 : FontWeight.w600),
          ),
        ),
        Text(
          b,
          style: TextStyle(color: _ink, fontSize: bold ? 17 : 13.5, fontWeight: bold ? FontWeight.w800 : FontWeight.w600),
        ),
      ],
    );
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 10),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            '#${o['no']}',
            style: const TextStyle(color: _ink, fontSize: 30, fontWeight: FontWeight.w800, height: 1.1),
          ),
          Text(
            '$shop · ${tsm('modes.$mode')}${str(o['table']).isNotEmpty ? ' ${o['table']}' : ''}',
            style: const TextStyle(color: _ink, fontSize: 15, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 4),
          Text([fmtTime(o['created_date']), str(who['name']), str(who['phone'])].where((x) => x.isNotEmpty).join(' · '), style: text),
          if (str(o['address']).isNotEmpty) _IconLine(LucideIcons.mapPin, str(o['address'])),
          if (str(o['note']).isNotEmpty) _IconLine(LucideIcons.messageSquareText, str(o['note'])),
          const _Dash(),
          for (final l in objs(o['items']))
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 30,
                    child: Text(
                      '${fmt(n(l['qty']))}×',
                      style: const TextStyle(color: _ink, fontSize: 15, fontWeight: FontWeight.w800),
                    ),
                  ),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          str(l['name']),
                          style: const TextStyle(color: _ink, fontSize: 15, fontWeight: FontWeight.w600),
                        ),
                        if (objs(l['options']).isNotEmpty) Text(objs(l['options']).map((x) => str(x['choice'])).join(', '), style: small),
                        if (str(l['note']).isNotEmpty) Text('“${l['note']}”', style: small),
                      ],
                    ),
                  ),
                  Text(tsMoney(l['total'], cur), style: text),
                ],
              ),
            ),
          const _Dash(),
          if (n(o['discount']) > 0) row(tsm('discount', {'code': o['promo']}), '−${tsMoney(o['discount'], cur)}'),
          if (n(o['fee']) > 0) row(tsm('deliveryFee'), tsMoney(o['fee'], cur)),
          row(tsx('ticketTotal'), tsMoney(o['total'], cur), bold: true),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.symmetric(vertical: 4),
            decoration: BoxDecoration(border: Border.all(color: _ink, width: 2)),
            child: Text(
              obj(o['pay'])['status'] == 'paid' ? tsx('ticketPaid') : tsx('ticketUnpaid'),
              textAlign: TextAlign.center,
              style: const TextStyle(color: _ink, fontSize: 16, fontWeight: FontWeight.w800, letterSpacing: 1),
            ),
          ),
        ],
      ),
    );
  }
}

// an icon + words (no emoji: not every printer picture has the emoji font)
class _IconLine extends StatelessWidget {
  final IconData icon;
  final String text;
  const _IconLine(this.icon, this.text);
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 2),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 2, right: 5),
          child: Icon(icon, size: 15, color: _ink),
        ),
        Expanded(
          child: Text(text, style: const TextStyle(color: _ink, fontSize: 14)),
        ),
      ],
    ),
  );
}

class _Dash extends StatelessWidget {
  const _Dash();
  @override
  Widget build(BuildContext context) => const Padding(
    padding: EdgeInsets.symmetric(vertical: 6),
    child: Text(
      '- - - - - - - - - - - - - - - - - - - - - - - - - - - -',
      maxLines: 1,
      overflow: TextOverflow.clip,
      textAlign: TextAlign.center,
      style: TextStyle(color: _ink, fontSize: 12),
    ),
  );
}
