import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/app_state.dart';
import '../../core/desktop.dart';
import '../../core/printing/printer_settings.dart' show InstalledPrinterList;
import '../../core/printing/printing.dart';
import '../../core/theme.dart';
import '../../widgets/ui.dart';
import 'engine/calc.dart';
import 'engine/rest_pos.dart';
import 'pos_ui.dart';
import 'rest_receipt.dart';

// Printing for the restaurant POS: bill, receipt, kitchen tickets, shift report.
//   Bill printer: the owner's network printer (dashboard) or what is set on this device (Bluetooth / Wi-Fi / phone print).
//   Kitchen: each station's network printer from the dashboard (or the bill printer, if chosen here).
// Printers need the "Printing" add-on; without it the phone's own print window still works (like the web's browser print).
class RestPrint extends ChangeNotifier {
  RestPrint._();
  static final RestPrint i = RestPrint._();
  static const _key = 'pos.rest.printers';

  PrinterConf bill = const PrinterConf();
  bool autoReceipt = false; // print the receipt as soon as a bill is paid
  bool autoKitchen = true; // print kitchen tickets when items are sent
  bool kitchenOnBill = false; // stations without a printer: their tickets come out of the bill printer
  bool _loaded = false;

  RestPos get pos => RestPos.i;
  bool get licensed => jmap(jmap(pos.setup?['license'])['addons'])['rest_printer'] == true;

  // the owner's bill printer (dashboard → Printing), used until this device chooses its own
  PrinterConf get ownerBill {
    final rp = jmap(pos.restaurant['receipt_printer']);
    final size = nz(jmap(pos.restaurant['receipt'])['size']) == 58 ? 58 : 80;
    return rp['type'] == 'network' && js(rp['address']).isNotEmpty ? PrinterConf(kind: PrinterKind.network, address: js(rp['address']), paper: size) : PrinterConf(paper: size);
  }

  // what bills really print on: direct printers only with the add-on
  PrinterConf get billPrinter {
    final c = bill.kind == PrinterKind.none ? ownerBill : bill;
    if (c.kind == PrinterKind.system) return c;
    return licensed ? c : const PrinterConf();
  }

  Future<void> load() async {
    if (_loaded) return;
    final v = await PrinterStore.load(_key);
    bill = PrinterConf.fromJson(v['bill']);
    autoReceipt = v['auto_receipt'] == true;
    autoKitchen = v['auto_kitchen'] != false;
    kitchenOnBill = v['kitchen_on_bill'] == true;
    _loaded = true;
    notifyListeners();
  }

  Future<void> save() async {
    await PrinterStore.save(_key, {'bill': bill.toJson(), 'auto_receipt': autoReceipt, 'auto_kitchen': autoKitchen, 'kitchen_on_bill': kitchenOnBill});
    notifyListeners();
  }

  Future<ui.Image?> _logo() => loadPicture(js(pos.restaurant['logo']));

  Future<Widget> receiptDoc(J order, {required bool paid}) async {
    final t = AppState.i.t;
    final cashier = paid ? js(jmap(order['closed_by'])['name']) : js(pos.staff?['name']);
    return ReceiptView(order: order, t: t, paidView: paid, restaurant: pos.restaurant, money: pos.moneyS, cashier: cashier, points: pos.pointsFor(order), logo: await _logo());
  }

  Future<void> receipt(J order, {required bool paid}) async {
    await load();
    await printWidget(await receiptDoc(order, paid: paid), billPrinter, title: '#${js(order['number'])}');
  }

  Future<void> shift(J shift, ShiftSum sum) async {
    await load();
    final t = AppState.i.t;
    await printWidget(
      ShiftTicket(shift: shift, sum: sum, restaurant: pos.restaurant, money: pos.moneyS, device: js(pos.device['name']), t: t),
      billPrinter,
      title: t('rpos.shiftClosed'),
    );
  }

  // kitchen tickets for the lines just sent, one per station printer. Returns problems (station name → error).
  Future<Map<String, String>> kitchen(J order, List<J> lines, {bool again = false}) async {
    await load();
    final out = <String, String>{};
    if (!licensed || lines.isEmpty) return out;
    final t = AppState.i.t;
    final stations = {for (final s in jlist(pos.setup?['stations'])) js(s['_id']): s};
    final byStation = <String, List<J>>{};
    for (final l in lines) {
      (byStation[js(l['station_id'])] ??= []).add(l);
    }
    for (final e in byStation.entries) {
      final st = stations[e.key];
      final sp = jmap(st?['printer']);
      final paper = nz(jmap(pos.restaurant['receipt'])['size']) == 58 ? 58 : 80;
      PrinterConf? conf;
      if (sp['type'] == 'network' && js(sp['address']).isNotEmpty) {
        conf = PrinterConf(kind: PrinterKind.network, address: js(sp['address']), paper: paper);
      } else if (kitchenOnBill && billPrinter.on && billPrinter.kind != PrinterKind.system) {
        conf = billPrinter;
      }
      if (conf == null) continue;
      try {
        await printWidget(
          KitchenTicket(order: order, lines: e.value, station: js(st?['name']), staff: js(pos.staff?['name']), t: t, again: again),
          conf,
          title: 'Kitchen',
        );
      } catch (err) {
        out[js(st?['name']).isEmpty ? t('rp.kitchen') : js(st?['name'])] = '$err';
      }
    }
    return out;
  }

  // does any kitchen ticket have somewhere to print?
  bool get hasKitchen =>
      licensed &&
      (jlist(pos.setup?['stations']).any((s) => jmap(s['printer'])['type'] == 'network' && js(jmap(s['printer'])['address']).isNotEmpty) ||
          (kitchenOnBill && billPrinter.on && billPrinter.kind != PrinterKind.system));
}

String printErrorText(Object e) {
  final t = AppState.i.t;
  final code = e is PrintError ? e.code : 'failed';
  return t.or('rp.err.$code', t('rp.err.failed'));
}

// print, with a short message when it doesn't work
Future<void> runPrint(BuildContext context, Future<void> Function() job) async {
  final bar = ScaffoldMessenger.of(context);
  final t = AppState.i.t;
  try {
    await job();
  } catch (e) {
    bar.showSnackBar(SnackBar(content: Text('${t('rp.failed')} ${printErrorText(e)}'), duration: const Duration(seconds: 5)));
  }
}

// see the bill / receipt on screen first, then print (onPrint can change the order first, e.g. "bill printed")
Future<void> previewReceipt(BuildContext context, J order, {required bool paid, Future<J> Function()? beforePrint}) async {
  final rp = RestPrint.i;
  await rp.load();
  final doc = await rp.receiptDoc(order, paid: paid);
  if (!context.mounted) return;
  final t = tr(context);
  final conf = rp.billPrinter;
  await posSheet(
    context,
    title: '${paid ? t('rpos.receipt') : t('rpos.billTitle')} · #${js(order['number'])}',
    maxWidth: 440,
    body: (ctx) => Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Center(
          child: PaperPreview(width: (conf.on ? conf : rp.ownerBill).logicalWidth, child: doc),
        ),
        const SizedBox(height: 10),
        if (!conf.on) Muted(t('rp.noPrinter'), align: TextAlign.center),
      ],
    ),
    footer: (ctx) => Row(
      children: [
        Expanded(
          child: Btn(t('rpos.close'), kind: BtnKind.ghost, onTap: () => Navigator.pop(ctx)),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: conf.on
              ? Btn(
                  t('rpos.print'),
                  icon: LucideIcons.printer,
                  onTap: () async {
                    Navigator.pop(ctx);
                    final o = beforePrint != null ? await beforePrint() : order;
                    if (context.mounted) await runPrint(context, () => rp.receipt(o, paid: paid));
                  },
                )
              : Btn(
                  t('rp.printers'),
                  icon: LucideIcons.settings,
                  onTap: () {
                    Navigator.pop(ctx);
                    openPrinters(context);
                  },
                ),
        ),
      ],
    ),
  );
}

// a strip of receipt paper on screen
class PaperPreview extends StatelessWidget {
  final double width;
  final Widget child;
  const PaperPreview({super.key, required this.width, required this.child});
  @override
  Widget build(BuildContext context) => Container(
    width: width,
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(6),
      boxShadow: const [BoxShadow(color: Color(0x22000000), blurRadius: 12, offset: Offset(0, 4))],
    ),
    child: DefaultTextStyle(
      style: const TextStyle(fontFamily: 'PlusJakartaSans', fontFamilyFallback: ['KantumruyPro'], color: Colors.black, fontSize: 13, height: 1.3),
      child: child,
    ),
  );
}

// ---------- the printers screen (this device) ----------
Future<void> openPrinters(BuildContext context) => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const RestPrinters()));

class RestPrinters extends StatefulWidget {
  const RestPrinters({super.key});
  @override
  State<RestPrinters> createState() => _RestPrintersState();
}

class _RestPrintersState extends State<RestPrinters> {
  final rp = RestPrint.i;
  final _addr = TextEditingController();
  List<({String name, String mac})>? _paired;
  String _btError = '';
  bool _testing = false;

  @override
  void initState() {
    super.initState();
    rp.load().then((_) {
      if (!mounted) return;
      _addr.text = rp.bill.kind == PrinterKind.network ? rp.bill.address : '';
      setState(() {});
      if (rp.bill.kind == PrinterKind.bluetooth) _loadPaired();
    });
  }

  @override
  void dispose() {
    _addr.dispose();
    super.dispose();
  }

  Future<void> _loadPaired() async {
    setState(() => _btError = '');
    try {
      final list = await pairedBluetoothPrinters();
      if (mounted) setState(() => _paired = list);
    } catch (e) {
      if (mounted) setState(() => _btError = printErrorText(e));
    }
  }

  void _set(PrinterConf c) {
    rp.bill = c;
    rp.save();
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final t = app.t;
    final c = context.c;
    final b = rp.bill;
    final owner = rp.ownerBill;
    final pos = RestPos.i;
    final stations = jlist(pos.setup?['stations']);
    Widget kind(PrinterKind k, IconData icon, String title, String sub, {bool needAddon = true}) {
      final on = b.kind == k;
      final locked = needAddon && !rp.licensed;
      return Opacity(
        opacity: locked ? .5 : 1,
        child: Container(
          margin: const EdgeInsets.only(bottom: 8),
          decoration: BoxDecoration(
            color: on ? c.active : c.card,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: on ? c.brand : c.line, width: on ? 2 : 1),
          ),
          child: ListTile(
            enabled: !locked,
            leading: Icon(icon, color: on ? c.brand : c.ink),
            title: Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
            subtitle: Text(sub),
            trailing: on ? Icon(LucideIcons.circleCheck, color: c.brand) : null,
            onTap: locked
                ? null
                : () {
                    _set(b.copyWith(kind: k, address: k == PrinterKind.network ? _addr.text.trim() : ((k == PrinterKind.bluetooth || k == PrinterKind.installed) && b.kind == k ? b.address : '')));
                    if (k == PrinterKind.bluetooth) _loadPaired();
                  },
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: c.appBg,
      appBar: AppBar(
        backgroundColor: c.appBg,
        surfaceTintColor: Colors.transparent,
        title: Text(t('rp.printers'), style: const TextStyle(fontWeight: FontWeight.w800)),
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 620),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
            children: [
              if (!rp.licensed) ...[Alert(t('rp.needAddon'), tone: Tone.warn), const SizedBox(height: 12)],
              Text(t('rp.billPrinter'), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
              const SizedBox(height: 4),
              Muted(t('rp.billPrinterSub')),
              const SizedBox(height: 10),
              kind(PrinterKind.none, LucideIcons.monitorSmartphone, owner.on ? t('rp.useOwner') : t('rp.none'), owner.on ? t('rp.ownerAt', {'a': owner.address}) : t('rp.noneSub'), needAddon: false),
              if (!kIsWeb) kind(PrinterKind.bluetooth, LucideIcons.bluetooth, t('rp.bluetooth'), t('rp.bluetoothSub')),
              if (b.kind == PrinterKind.bluetooth) ...[
                if (_btError.isNotEmpty)
                  Alert(
                    _btError,
                    tone: Tone.warn,
                    action: TextButton(onPressed: _loadPaired, child: Text(t('rpos.retry'))),
                  ),
                if (_paired != null && _paired!.isEmpty)
                  Alert(
                    t('rp.noPaired'),
                    tone: Tone.warn,
                    action: TextButton(onPressed: _loadPaired, child: Text(t('rpos.retry'))),
                  ),
                for (final d in _paired ?? const <({String name, String mac})>[])
                  ListTile(
                    onTap: () => _set(b.copyWith(address: d.mac, name: d.name)),
                    leading: Icon(b.address == d.mac ? LucideIcons.circleCheck : LucideIcons.circle, color: b.address == d.mac ? c.brand : c.muted),
                    title: Text(d.name.isEmpty ? d.mac : d.name),
                    subtitle: Text(d.mac),
                  ),
                const SizedBox(height: 8),
              ],
              if (!kIsWeb) kind(PrinterKind.network, LucideIcons.wifi, t('rp.network'), t('rp.networkSub')),
              if (b.kind == PrinterKind.network) ...[
                Field(
                  controller: _addr,
                  hint: '192.168.1.100',
                  label: t('rp.address'),
                  keyboard: TextInputType.url,
                  onChanged: (v) => _set(b.copyWith(address: v.trim())),
                ),
                const SizedBox(height: 12),
              ],
              if (isDesktop) kind(PrinterKind.installed, LucideIcons.usb, t('rp.installed'), t('rp.installedSub')),
              if (isDesktop && b.kind == PrinterKind.installed) ...[
                InstalledPrinterList(
                  selected: b.address,
                  onPick: (url, name) => _set(b.copyWith(address: url, name: name)),
                ),
                const SizedBox(height: 8),
              ],
              kind(PrinterKind.system, LucideIcons.printer, t('rp.system'), t('rp.systemSub'), needAddon: false),
              const SizedBox(height: 8),
              Text(t('rp.paper'), style: const TextStyle(fontWeight: FontWeight.w700)),
              const SizedBox(height: 8),
              PosChips<int>(
                value: b.paper,
                onTap: (v) => _set(b.copyWith(paper: v)),
                options: const [(80, '80 mm'), (58, '58 mm')],
              ),
              const SizedBox(height: 14),
              Btn(
                t('rp.test'),
                icon: LucideIcons.printer,
                kind: BtnKind.ghost,
                busy: _testing,
                expand: true,
                onTap: !rp.billPrinter.on || _testing
                    ? null
                    : () async {
                        setState(() => _testing = true);
                        final conf = rp.billPrinter;
                        await runPrint(
                          context,
                          () => printWidget(
                            TestTicket(
                              shop: nameOf(pos.restaurant, app.lang),
                              printer: conf.kind == PrinterKind.bluetooth || conf.kind == PrinterKind.installed ? (b.name.isEmpty ? b.address : b.name) : conf.address,
                              t: t,
                            ),
                            conf,
                            title: t('rp.testTitle'),
                          ),
                        );
                        if (mounted) setState(() => _testing = false);
                      },
              ),
              const SizedBox(height: 22),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: rp.autoReceipt,
                onChanged: (v) {
                  rp.autoReceipt = v;
                  rp.save();
                  setState(() {});
                },
                title: Text(t('rp.autoReceipt'), style: const TextStyle(fontWeight: FontWeight.w700)),
                subtitle: Text(t('rp.autoReceiptSub')),
              ),
              const Divider(height: 28),
              Text(t('rp.kitchen'), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
              const SizedBox(height: 4),
              Muted(t('rp.kitchenSub')),
              const SizedBox(height: 8),
              for (final s in stations)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(LucideIcons.chefHat),
                  title: Text(js(s['name'])),
                  subtitle: Text(jmap(s['printer'])['type'] == 'network' && js(jmap(s['printer'])['address']).isNotEmpty ? js(jmap(s['printer'])['address']) : t('rp.noStationPrinter')),
                ),
              if (stations.isEmpty) Muted(t('rp.noStations')),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: rp.autoKitchen,
                onChanged: (v) {
                  rp.autoKitchen = v;
                  rp.save();
                  setState(() {});
                },
                title: Text(t('rp.autoKitchen'), style: const TextStyle(fontWeight: FontWeight.w700)),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: rp.kitchenOnBill,
                onChanged: (v) {
                  rp.kitchenOnBill = v;
                  rp.save();
                  setState(() {});
                },
                title: Text(t('rp.kitchenOnBill'), style: const TextStyle(fontWeight: FontWeight.w700)),
                subtitle: Text(t('rp.kitchenOnBillSub')),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// kitchen tickets for items just sent (Send, or paid with items not sent yet); a short message if a station failed
Future<void> printKitchenFor(BuildContext context, J order, List<J> sentLines) async {
  final rp = RestPrint.i;
  final bar = ScaffoldMessenger.of(context);
  await rp.load();
  if (!rp.autoKitchen || sentLines.isEmpty || !rp.hasKitchen) return;
  final t = AppState.i.t;
  final bad = await rp.kitchen(order, sentLines);
  if (bad.isNotEmpty) bar.showSnackBar(SnackBar(content: Text(t('rp.kitchenFailed', {'s': bad.keys.join(', ')})), duration: const Duration(seconds: 6)));
}
