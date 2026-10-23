import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../app_state.dart';
import '../customer_display.dart';
import '../desktop.dart';
import '../theme.dart';
import '../../widgets/ui.dart';
import 'printing.dart';

String printErrorMessage(Object e) {
  final t = AppState.i.t;
  final code = e is PrintError ? e.code : 'failed';
  return t.or('rp.err.$code', t('rp.err.failed'));
}

// The receipt printer of this device: none / Bluetooth / Wi-Fi / the phone's print window, paper, test page.
// Used by the POS kinds that print one kind of paper (Mini Mart…). `licensed` = the shop has its printing add-on.
class PrinterSettingsPage extends StatefulWidget {
  final PrinterConf conf;
  final bool licensed;
  final String lockedText;
  final ValueChanged<PrinterConf> onChanged;
  final Widget Function(PrinterConf conf) testDoc;
  final List<Widget> extra; // switches under the printer (auto print…)
  const PrinterSettingsPage({super.key, required this.conf, required this.licensed, required this.lockedText, required this.onChanged, required this.testDoc, this.extra = const []});
  @override
  State<PrinterSettingsPage> createState() => _PrinterSettingsPageState();
}

class _PrinterSettingsPageState extends State<PrinterSettingsPage> {
  late PrinterConf _c = widget.conf;
  late final _addr = TextEditingController(text: widget.conf.kind == PrinterKind.network ? widget.conf.address : '');
  List<({String name, String mac})>? _paired;
  String _btError = '';
  bool _testing = false;

  @override
  void initState() {
    super.initState();
    if (_c.kind == PrinterKind.bluetooth) _loadPaired();
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
      if (mounted) setState(() => _btError = printErrorMessage(e));
    }
  }

  void _set(PrinterConf c) {
    setState(() => _c = c);
    widget.onChanged(c);
  }

  // what really prints: Bluetooth / Wi-Fi only with the add-on
  PrinterConf get _effective => _c.kind == PrinterKind.system || widget.licensed ? _c : const PrinterConf();

  @override
  Widget build(BuildContext context) {
    final t = AppScope.of(context).t;
    final c = context.c;
    Widget kind(PrinterKind k, IconData icon, String title, String sub, {bool needAddon = true}) {
      final on = _c.kind == k;
      final locked = needAddon && !widget.licensed;
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
                    _set(_c.copyWith(kind: k, address: k == PrinterKind.network ? _addr.text.trim() : ((k == PrinterKind.bluetooth || k == PrinterKind.installed) && _c.kind == k ? _c.address : '')));
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
              if (!widget.licensed) ...[Alert(widget.lockedText, tone: Tone.warn), const SizedBox(height: 12)],
              Text(t('rp.billPrinter'), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
              const SizedBox(height: 10),
              kind(PrinterKind.none, LucideIcons.monitorSmartphone, t('rp.none'), t('rp.noneSub'), needAddon: false),
              if (!kIsWeb) kind(PrinterKind.bluetooth, LucideIcons.bluetooth, t('rp.bluetooth'), t('rp.bluetoothSub')),
              if (_c.kind == PrinterKind.bluetooth) ...[
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
                    onTap: () => _set(_c.copyWith(address: d.mac, name: d.name)),
                    leading: Icon(_c.address == d.mac ? LucideIcons.circleCheck : LucideIcons.circle, color: _c.address == d.mac ? c.brand : c.muted),
                    title: Text(d.name.isEmpty ? d.mac : d.name),
                    subtitle: Text(d.mac),
                  ),
                const SizedBox(height: 8),
              ],
              if (!kIsWeb) kind(PrinterKind.network, LucideIcons.wifi, t('rp.network'), t('rp.networkSub')),
              if (_c.kind == PrinterKind.network) ...[
                Field(
                  controller: _addr,
                  hint: '192.168.1.100',
                  label: t('rp.address'),
                  keyboard: TextInputType.url,
                  onChanged: (v) => _set(_c.copyWith(address: v.trim())),
                ),
                const SizedBox(height: 12),
              ],
              if (isDesktop) kind(PrinterKind.installed, LucideIcons.usb, t('rp.installed'), t('rp.installedSub')),
              if (isDesktop && _c.kind == PrinterKind.installed) ...[
                InstalledPrinterList(
                  selected: _c.address,
                  onPick: (url, name) => _set(_c.copyWith(address: url, name: name)),
                ),
                const SizedBox(height: 8),
              ],
              kind(PrinterKind.system, LucideIcons.printer, t('rp.system'), t('rp.systemSub'), needAddon: false),
              const SizedBox(height: 8),
              Text(t('rp.paper'), style: const TextStyle(fontWeight: FontWeight.w700)),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                children: [
                  for (final p in [80, 58])
                    ChoiceChip(
                      label: Text('$p mm'),
                      selected: _c.paper == p,
                      onSelected: (_) => _set(_c.copyWith(paper: p)),
                    ),
                ],
              ),
              const SizedBox(height: 14),
              Btn(
                t('rp.test'),
                icon: LucideIcons.printer,
                kind: BtnKind.ghost,
                busy: _testing,
                expand: true,
                onTap: !_effective.on || _testing
                    ? null
                    : () async {
                        setState(() => _testing = true);
                        final bar = ScaffoldMessenger.of(context);
                        try {
                          await printWidget(widget.testDoc(_effective), _effective, title: t('rp.testTitle'));
                        } catch (e) {
                          bar.showSnackBar(SnackBar(content: Text('${t('rp.failed')} ${printErrorMessage(e)}')));
                        }
                        if (mounted) setState(() => _testing = false);
                      },
              ),
              const SizedBox(height: 16),
              ...widget.extra,
              if (isDesktop) const DesktopCustomerScreenSwitch(),
            ],
          ),
        ),
      ),
    );
  }
}

// Mac / Windows: the printers installed on this computer, to choose the receipt printer (shared by the settings pages)
class InstalledPrinterList extends StatefulWidget {
  final String selected; // the chosen printer's id (url)
  final void Function(String url, String name) onPick;
  const InstalledPrinterList({super.key, required this.selected, required this.onPick});
  @override
  State<InstalledPrinterList> createState() => _InstalledPrinterListState();
}

class _InstalledPrinterListState extends State<InstalledPrinterList> {
  List<({String url, String name, bool isDefault})>? _list;
  String _error = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _error = '');
    try {
      final list = await installedPrinters();
      if (mounted) setState(() => _list = list);
    } catch (e) {
      if (mounted) setState(() => _error = printErrorMessage(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = AppScope.of(context).t;
    final c = context.c;
    if (_error.isNotEmpty) {
      return Alert(
        _error,
        tone: Tone.warn,
        action: TextButton(onPressed: _load, child: Text(t('rpos.retry'))),
      );
    }
    final list = _list;
    if (list == null) {
      return const Padding(
        padding: EdgeInsets.all(12),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    if (list.isEmpty) {
      return Alert(
        t('rp.noInstalled'),
        tone: Tone.warn,
        action: TextButton(onPressed: _load, child: Text(t('rpos.retry'))),
      );
    }
    return Column(
      children: [
        for (final p in list)
          ListTile(
            onTap: () => widget.onPick(p.url, p.name),
            leading: Icon(widget.selected == p.url ? LucideIcons.circleCheck : LucideIcons.circle, color: widget.selected == p.url ? c.brand : c.muted),
            title: Text(p.name),
            subtitle: p.isDefault ? Text(t('rp.defaultPrinter')) : null,
          ),
        Align(
          alignment: Alignment.centerRight,
          child: TextButton.icon(onPressed: _load, icon: const Icon(LucideIcons.refreshCw, size: 16), label: Text(t('rpos.retry'))),
        ),
      ],
    );
  }
}

// Mac / Windows: use the second monitor as the customer screen (needs the shop's Customer screen add-on)
class DesktopCustomerScreenSwitch extends StatefulWidget {
  const DesktopCustomerScreenSwitch({super.key});
  @override
  State<DesktopCustomerScreenSwitch> createState() => _DesktopCustomerScreenSwitchState();
}

class _DesktopCustomerScreenSwitchState extends State<DesktopCustomerScreenSwitch> {
  bool? _on;
  @override
  void initState() {
    super.initState();
    CustomerDisplay.desktopOn().then((v) {
      if (mounted) setState(() => _on = v);
    });
  }

  @override
  Widget build(BuildContext context) {
    final t = AppScope.of(context).t;
    if (_on == null) return const SizedBox.shrink();
    return SwitchListTile(
      contentPadding: EdgeInsets.zero,
      value: _on!,
      onChanged: (v) async {
        setState(() => _on = v);
        await CustomerDisplay.setDesktopOn(v);
      },
      title: Text(t('cd.desktop'), style: const TextStyle(fontWeight: FontWeight.w700)),
      subtitle: Text(t('cd.desktopSub')),
    );
  }
}
