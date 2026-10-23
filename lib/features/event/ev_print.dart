import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../core/app_state.dart';
import '../../core/format.dart';
import '../../core/i18n.dart';
import '../../core/printing/printer_settings.dart';
import '../../core/printing/printing.dart';
import '../restaurant/rest_receipt.dart' show TestTicket;
import 'ev_api.dart';

// Tickets sold at the gate, on a receipt printer: one paper per ticket with its QR (cut between).
class EvPrint {
  static const _key = 'ev.printer';
  static PrinterConf conf = const PrinterConf();
  static bool auto = false;
  static bool _loaded = false;

  static Future<void> load() async {
    if (_loaded) return;
    final v = await PrinterStore.load(_key);
    conf = v['conf'] == null ? const PrinterConf() : PrinterConf.fromJson(v['conf']);
    auto = v['auto'] == true;
    _loaded = true;
  }

  static Future<void> save() => PrinterStore.save(_key, {'conf': conf.toJson(), 'auto': auto});

  static Future<void> tickets({required Json ev, required List<Json> tickets, required String org, String logo = ''}) async {
    await load();
    final pic = logo.isEmpty ? null : await loadPicture(logo);
    final t = AppState.i.t;
    for (final tk in tickets) {
      await printWidget(
        GateTicket(ev: ev, ticket: tk, org: org, logo: pic, t: t),
        conf,
        title: str(tk['code']),
      );
    }
  }
}

Future<void> openEvPrinters(BuildContext context) async {
  await EvPrint.load();
  if (!context.mounted) return;
  final t = AppState.i.t;
  final org = str((AppState.i.link ?? const {})['shop']);
  await Navigator.of(context).push(
    MaterialPageRoute(
      builder: (_) => StatefulBuilder(
        builder: (ctx, set) => PrinterSettingsPage(
          conf: EvPrint.conf,
          licensed: true,
          lockedText: '',
          onChanged: (c) {
            EvPrint.conf = c;
            EvPrint.save();
          },
          testDoc: (c) => TestTicket(shop: org, printer: c.kind == PrinterKind.bluetooth || c.kind == PrinterKind.installed ? (c.name.isEmpty ? c.address : c.name) : c.address, t: t),
          extra: [
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: EvPrint.auto,
              onChanged: (v) {
                set(() => EvPrint.auto = v);
                EvPrint.save();
              },
              title: Text(t('evx.autoPrint'), style: const TextStyle(fontWeight: FontWeight.w700)),
              subtitle: Text(t('evx.autoPrintSub')),
            ),
          ],
        ),
      ),
    ),
  );
}

const _ink = Color(0xFF000000);

// one paper ticket (black on white, for thermal paper)
class GateTicket extends StatelessWidget {
  final Json ev, ticket;
  final String org;
  final ui.Image? logo;
  final T t;
  const GateTicket({super.key, required this.ev, required this.ticket, required this.org, required this.t, this.logo});
  @override
  Widget build(BuildContext context) {
    final lang = t.lang;
    final showAt = ticket['show_at'];
    final seat = str(ticket['seat_label']);
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (logo != null)
            Center(
              child: SizedBox(
                height: 46,
                child: RawImage(image: logo, fit: BoxFit.contain),
              ),
            ),
          Text(
            org,
            textAlign: TextAlign.center,
            style: const TextStyle(color: _ink, fontSize: 13, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 4),
          Text(
            str(ev['title']),
            textAlign: TextAlign.center,
            style: const TextStyle(color: _ink, fontSize: 18, fontWeight: FontWeight.w800, height: 1.3),
          ),
          const SizedBox(height: 4),
          Text(
            fmtDate(showAt ?? ev['starts_at'], time: true, lang: lang),
            textAlign: TextAlign.center,
            style: const TextStyle(color: _ink, fontSize: 13),
          ),
          if (str(ev['venue']).isNotEmpty)
            Text(
              str(ev['venue']),
              textAlign: TextAlign.center,
              style: const TextStyle(color: _ink, fontSize: 12.5),
            ),
          const _Dash(),
          Text(
            str(ticket['type_name']).toUpperCase(),
            textAlign: TextAlign.center,
            style: const TextStyle(color: _ink, fontSize: 17, fontWeight: FontWeight.w800, letterSpacing: .5),
          ),
          if (str(ticket['holder']).isNotEmpty)
            Text(
              str(ticket['holder']),
              textAlign: TextAlign.center,
              style: const TextStyle(color: _ink, fontSize: 14),
            ),
          if (seat.isNotEmpty)
            Text(
              seat,
              textAlign: TextAlign.center,
              style: const TextStyle(color: _ink, fontSize: 15, fontWeight: FontWeight.w700),
            ),
          const SizedBox(height: 8),
          Center(
            child: QrImageView(
              data: str(ticket['code']),
              size: 170,
              padding: EdgeInsets.zero,
              backgroundColor: Colors.white,
              eyeStyle: const QrEyeStyle(eyeShape: QrEyeShape.square, color: _ink),
              dataModuleStyle: const QrDataModuleStyle(dataModuleShape: QrDataModuleShape.square, color: _ink),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            str(ticket['code']),
            textAlign: TextAlign.center,
            style: const TextStyle(color: _ink, fontSize: 16, fontWeight: FontWeight.w800, letterSpacing: 2),
          ),
          Text(
            t('evx.showTicket'),
            textAlign: TextAlign.center,
            style: const TextStyle(color: _ink, fontSize: 12),
          ),
          const _Dash(),
          Text(
            '${fmtDate(DateTime.now(), time: true, lang: lang)} · Biz Hub',
            textAlign: TextAlign.center,
            style: const TextStyle(color: _ink, fontSize: 11),
          ),
        ],
      ),
    );
  }
}

class _Dash extends StatelessWidget {
  const _Dash();
  @override
  Widget build(BuildContext context) => const Padding(
    padding: EdgeInsets.symmetric(vertical: 8),
    child: Text(
      '- - - - - - - - - - - - - - - - - - - - - - - - - - - -',
      maxLines: 1,
      overflow: TextOverflow.clip,
      textAlign: TextAlign.center,
      style: TextStyle(color: _ink, fontSize: 12),
    ),
  );
}
