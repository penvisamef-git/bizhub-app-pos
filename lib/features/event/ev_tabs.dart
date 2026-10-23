import 'dart:async';

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../core/app_state.dart';
import '../../core/format.dart';
import '../../core/printing/printer_settings.dart' show printErrorMessage;
import '../../core/theme.dart';
import '../../widgets/ui.dart';
import 'ev_api.dart';
import 'ev_ctl.dart';
import 'ev_print.dart';

String _err(ApiError e) => e.network ? AppState.i.t('app.offline') : e.message;

// ---------------------------------------------------------------- Guests (crew, cashier, manager)
class EvGuestsTab extends StatefulWidget {
  final EvCtl ctl;
  const EvGuestsTab({super.key, required this.ctl});
  @override
  State<EvGuestsTab> createState() => _EvGuestsTabState();
}

class _EvGuestsTabState extends State<EvGuestsTab> {
  final _q = TextEditingController();
  String _status = '';
  List<Json>? _rows;
  int _page = 1, _pages = 1, _total = 0;
  bool _more = false;
  String _error = '';
  Timer? _wait;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _wait?.cancel();
    _q.dispose();
    super.dispose();
  }

  Future<void> _load({bool more = false}) async {
    final page = more ? _page + 1 : 1;
    if (more) setState(() => _more = true);
    try {
      final r = await EvDoor.guests(widget.ctl.eid, {'q': _q.text.trim(), 'status': _status, 'page': '$page'});
      final p = obj(r['pagination']);
      if (!mounted) return;
      setState(() {
        _rows = [if (more) ...?_rows, ...objs(r['data'])];
        _page = page;
        _pages = n(p['totalPages']).toInt();
        _total = n(p['total']).toInt();
        _error = '';
        _more = false;
      });
    } on ApiError catch (e) {
      if (!mounted) return;
      setState(() {
        _error = _err(e);
        _rows ??= [];
        _more = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = AppState.i.t;
    final rows = _rows;
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
        children: [
          Field(
            controller: _q,
            hint: ev('search'),
            icon: LucideIcons.search,
            onChanged: (_) {
              _wait?.cancel();
              _wait = Timer(const Duration(milliseconds: 300), _load);
            },
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final s in ['', 'valid', 'used', 'cancelled'])
                ChoiceChip(
                  selected: _status == s,
                  label: Text(s.isEmpty ? t('evx.all') : ev('tstatus.$s')),
                  onSelected: (_) {
                    setState(() => _status = s);
                    _load();
                  },
                ),
            ],
          ),
          const SizedBox(height: 12),
          if (_error.isNotEmpty) Padding(padding: const EdgeInsets.only(bottom: 10), child: Alert(_error)),
          if (rows == null)
            const SkelList(rows: 6)
          else if (rows.isEmpty)
            Panel(child: Muted(ev('noGuests'), align: TextAlign.center))
          else
            Panel(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Column(children: [for (final g in rows) _GuestRow(g: g)]),
            ),
          if (rows != null && _page < _pages)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Center(
                child: Btn('${t('evx.loadMore')} (${rows.length}/$_total)', kind: BtnKind.ghost, small: true, busy: _more, onTap: () => _load(more: true)),
              ),
            ),
        ],
      ),
    );
  }
}

class _GuestRow extends StatelessWidget {
  final Json g;
  const _GuestRow({required this.g});
  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final st = str(g['status']);
    final dot = st == 'used' ? c.good : (st == 'cancelled' ? c.danger : c.lineStrong);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
      child: Row(
        children: [
          Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(color: dot, shape: BoxShape.circle),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  str(g['holder']).isEmpty ? '—' : str(g['holder']),
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontWeight: FontWeight.w700, decoration: st == 'cancelled' ? TextDecoration.lineThrough : null),
                ),
                Text(
                  [str(g['type_name']), str(g['code']), if (str(g['seat_label']).isNotEmpty) str(g['seat_label']), if (str(g['phone']).isNotEmpty) str(g['phone'])].join(' · '),
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: c.muted, fontSize: 12.5),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          st == 'used'
              ? Text(
                  fmtTime(g['used_at']),
                  style: TextStyle(color: c.good, fontWeight: FontWeight.w800),
                )
              : Chip2(ev('tstatus.$st'), tone: st == 'cancelled' ? Tone.danger : Tone.muted),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------- Sell at the gate (cashier, manager — ev_cashier)
class EvSellTab extends StatefulWidget {
  final EvCtl ctl;
  const EvSellTab({super.key, required this.ctl});
  @override
  State<EvSellTab> createState() => _EvSellTabState();
}

class _EvSellTabState extends State<EvSellTab> {
  final Map<String, int> _qty = {};
  final _name = TextEditingController();
  final _phone = TextEditingController();
  String _method = 'cash';
  bool _busy = false, _printing = false;
  String _error = '';
  Json? _done;

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    super.dispose();
  }

  List<Json> get _types => objs(obj(obj(widget.ctl.info)['event'])['types']).where((x) => x['active'] != false).toList();
  num _price(Json x) => x['now'] ?? x['price'] ?? 0;

  Future<void> _sell() async {
    final lines = [
      for (final x in _types)
        if ((_qty[str(x['key'])] ?? 0) > 0) {'key': x['key'], 'qty': _qty[str(x['key'])]},
    ];
    setState(() {
      _busy = true;
      _error = '';
    });
    try {
      final d = obj(
        (await EvDoor.sell(widget.ctl.eid, {
          'lines': lines,
          'name': _name.text.trim(),
          'phone': _phone.text.trim(),
          'method': _method,
          if (widget.ctl.show.isNotEmpty) 'show': widget.ctl.show,
        }))['data'],
      );
      if (!mounted) return;
      setState(() {
        _done = d;
        _qty.clear();
        _name.clear();
        _phone.clear();
        _busy = false;
      });
      widget.ctl.refresh();
      await EvPrint.load();
      if (EvPrint.auto && EvPrint.conf.on) _print();
    } on ApiError catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = _err(e);
      });
    }
  }

  Future<void> _print() async {
    final t = AppState.i.t;
    await EvPrint.load();
    if (!mounted) return;
    if (!EvPrint.conf.on) {
      toast(context, t('evx.noPrinter'));
      return openEvPrinters(context);
    }
    setState(() => _printing = true);
    try {
      await EvPrint.tickets(
        ev: obj(obj(widget.ctl.info)['event']).isEmpty ? widget.ctl.event : obj(obj(widget.ctl.info)['event']),
        tickets: objs(_done?['tickets']),
        org: str(obj(widget.ctl.boot['org'])['name']),
        logo: str(obj(widget.ctl.boot['org'])['logo']),
      );
      if (mounted) toast(context, t('evx.printed'));
    } catch (e) {
      if (mounted) toast(context, '${t('rp.failed')} ${printErrorMessage(e)}');
    } finally {
      if (mounted) setState(() => _printing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final t = AppState.i.t;
    if (_done != null) {
      final tickets = objs(_done!['tickets']);
      return ListView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
        children: [
          Panel(
            child: Column(
              children: [
                Icon(LucideIcons.circleCheck, size: 60, color: c.good),
                const SizedBox(height: 8),
                Text(
                  ev('sold'),
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 18),
                ),
                const SizedBox(height: 4),
                Text(usd(obj(_done!['order'])['total']), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 32)),
                const SizedBox(height: 14),
                Wrap(
                  alignment: WrapAlignment.center,
                  spacing: 12,
                  runSpacing: 12,
                  children: [
                    for (final tk in tickets)
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: c.line),
                        ),
                        child: Column(
                          children: [
                            QrImageView(data: str(tk['code']), size: 132, padding: EdgeInsets.zero, backgroundColor: Colors.white),
                            const SizedBox(height: 6),
                            Text(
                              str(tk['code']),
                              style: const TextStyle(color: Colors.black, fontWeight: FontWeight.w800, letterSpacing: 1.5),
                            ),
                            Text(str(tk['type_name']), style: const TextStyle(color: Color(0xFF555555), fontSize: 12)),
                          ],
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 18),
                Btn(t('evx.print'), icon: LucideIcons.printer, kind: BtnKind.ghost, busy: _printing, expand: true, onTap: _printing ? null : _print),
                const SizedBox(height: 10),
                Btn(ev('soldMore'), icon: LucideIcons.plus, expand: true, onTap: () => setState(() => _done = null)),
              ],
            ),
          ),
        ],
      );
    }
    final types = _types;
    final count = types.fold<int>(0, (a, x) => a + (_qty[str(x['key'])] ?? 0));
    final total = types.fold<num>(0, (a, x) => a + (_qty[str(x['key'])] ?? 0) * _price(x));
    final readOnly = widget.ctl.boot['read_only'] == true;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
      children: [
        Text(ev('sellTitle'), style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 10),
        if (readOnly)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Alert(ev('readOnly'), tone: Tone.warn),
          ),
        if (widget.ctl.info == null) const SkelList(rows: 3),
        Panel(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Column(
            children: [
              for (final x in types)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 10, 8),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(str(x['name']), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15.5)),
                            Text('${usd(_price(x))} · ${n(x['left']).toInt()}', style: TextStyle(color: c.muted, fontSize: 13)),
                          ],
                        ),
                      ),
                      _Step(value: _qty[str(x['key'])] ?? 0, max: n(x['left']).toInt(), onChanged: (v) => setState(() => _qty[str(x['key'])] = v)),
                    ],
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        Field(controller: _name, hint: ev('sellName'), icon: LucideIcons.user, maxLength: 80),
        const SizedBox(height: 10),
        Field(controller: _phone, hint: t('evx.phone'), icon: LucideIcons.phone, keyboard: TextInputType.phone, maxLength: 20),
        const SizedBox(height: 12),
        Row(
          children: [
            for (final (k, icon, label) in [('cash', LucideIcons.banknote, ev('cash')), ('qr', LucideIcons.qrCode, ev('qr'))])
              Expanded(
                child: Padding(
                  padding: EdgeInsets.only(right: k == 'cash' ? 10 : 0),
                  child: Material(
                    color: _method == k ? c.active : c.card,
                    borderRadius: BorderRadius.circular(16),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(16),
                      onTap: () => setState(() => _method = k),
                      child: Container(
                        height: 52,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: _method == k ? c.brand : c.line, width: _method == k ? 1.6 : 1),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(icon, size: 18, color: _method == k ? c.brandInk : c.ink),
                            const SizedBox(width: 8),
                            Text(
                              label,
                              style: TextStyle(fontWeight: FontWeight.w700, color: _method == k ? c.brandInk : c.ink),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
        if (_error.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 12), child: Alert(_error)),
        const SizedBox(height: 16),
        Btn(ev('sellBtn', {'n': count, 'amt': usd(total)}), icon: LucideIcons.store, busy: _busy, expand: true, onTap: count == 0 || _busy || readOnly ? null : _sell),
      ],
    );
  }
}

class _Step extends StatelessWidget {
  final int value, max;
  final ValueChanged<int> onChanged;
  const _Step({required this.value, required this.max, required this.onChanged});
  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        RoundBtn(LucideIcons.minus, size: 40, bg: c.chip, onTap: value > 0 ? () => onChanged(value - 1) : null),
        SizedBox(
          width: 40,
          child: Text(
            '$value',
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
          ),
        ),
        RoundBtn(LucideIcons.plus, size: 40, bg: value < max ? c.active : c.chip, fg: value < max ? c.brandInk : c.muted, onTap: value < max ? () => onChanged(value + 1) : null),
      ],
    );
  }
}

// ---------------------------------------------------------------- Orders to check (manager)
class EvOrdersTab extends StatefulWidget {
  final EvCtl ctl;
  const EvOrdersTab({super.key, required this.ctl});
  @override
  State<EvOrdersTab> createState() => _EvOrdersTabState();
}

class _EvOrdersTabState extends State<EvOrdersTab> {
  List<Json>? _rows;
  String _busy = '';
  String _error = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final r = await EvDoor.orders({'event': widget.ctl.eid, 'status': 'review'});
      if (mounted) setState(() => _rows = objs(r['data']));
    } on ApiError catch (e) {
      if (mounted) {
        setState(() {
          _rows ??= [];
          _error = _err(e);
        });
      }
    }
  }

  Future<void> _act(Json o, bool ok) async {
    var reason = '';
    if (!ok) {
      final v = await _askReason();
      if (v == null) return;
      reason = v;
    }
    setState(() {
      _busy = str(o['_id']);
      _error = '';
    });
    try {
      if (ok) {
        await EvDoor.approve(str(o['_id']));
      } else {
        await EvDoor.reject(str(o['_id']), reason);
      }
      await _load();
      widget.ctl.refresh();
    } on ApiError catch (e) {
      if (mounted) setState(() => _error = _err(e));
      _load();
    } finally {
      if (mounted) setState(() => _busy = '');
    }
  }

  Future<String?> _askReason() {
    final ctl = TextEditingController();
    final t = AppState.i.t;
    return showDialog<String>(
      context: context,
      builder: (d) => AlertDialog(
        title: Text(ev('rejectWhy')),
        content: TextField(controller: ctl, autofocus: true, maxLength: 200, maxLines: 2),
        actions: [
          TextButton(onPressed: () => Navigator.pop(d), child: Text(t('app.cancel'))),
          TextButton(
            onPressed: () => Navigator.pop(d, ctl.text.trim()),
            child: Text(ev('reject'), style: TextStyle(color: d.c.danger)),
          ),
        ],
      ),
    ).whenComplete(ctl.dispose);
  }

  void _view(String url) => showDialog<void>(
    context: context,
    builder: (d) => Dialog(
      backgroundColor: Colors.black,
      insetPadding: const EdgeInsets.all(12),
      child: GestureDetector(
        onTap: () => Navigator.pop(d),
        child: InteractiveViewer(child: Image(image: netImage(url))),
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final rows = _rows;
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
        children: [
          Text(ev('ordersTitle'), style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 10),
          if (_error.isNotEmpty) Padding(padding: const EdgeInsets.only(bottom: 10), child: Alert(_error)),
          if (rows == null)
            const SkelList(rows: 3)
          else if (rows.isEmpty)
            Panel(
              child: Column(
                children: [
                  Icon(LucideIcons.circleCheck, color: c.good, size: 30),
                  const SizedBox(height: 8),
                  Muted(ev('noOrders'), align: TextAlign.center),
                ],
              ),
            )
          else
            for (final o in rows)
              Panel(
                margin: const EdgeInsets.only(bottom: 10),
                padding: const EdgeInsets.all(14),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (str(o['proof']).isNotEmpty) ...[
                      GestureDetector(
                        onTap: () => _view(str(o['proof'])),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(12),
                          child: Image(
                            image: netImage(str(o['proof'])),
                            width: 72,
                            height: 96,
                            fit: BoxFit.cover,
                            errorBuilder: (_, _, _) => Container(width: 72, height: 96, color: c.chip),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                    ],
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('#${o['no']} · ${usd(o['total'])}', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                          Text([str(obj(o['buyer'])['name']), str(obj(o['buyer'])['phone'])].where((x) => x.isNotEmpty).join(' · '), style: TextStyle(color: c.muted, fontSize: 13)),
                          Text('${objs(o['lines']).map((l) => '${l['qty']}× ${l['name']}').join(', ')} · ${evWhen(o['created_date'])}', style: TextStyle(color: c.muted, fontSize: 12.5)),
                          if (str(o['pay_label']).isNotEmpty || str(o['reference']).isNotEmpty)
                            Text([str(o['pay_label']), str(o['reference'])].where((x) => x.isNotEmpty).join(' · '), style: TextStyle(color: c.muted, fontSize: 12.5)),
                          const SizedBox(height: 10),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              Btn(ev('approve'), icon: LucideIcons.circleCheck, small: true, busy: _busy == str(o['_id']), onTap: _busy.isNotEmpty ? null : () => _act(o, true)),
                              Btn(ev('reject'), icon: LucideIcons.circleX, small: true, kind: BtnKind.ghost, onTap: _busy.isNotEmpty ? null : () => _act(o, false)),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
        ],
      ),
    );
  }
}
