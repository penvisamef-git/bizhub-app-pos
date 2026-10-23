import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/api.dart' show ApiError;
import '../../core/i18n.dart';
import '../../core/theme.dart';
import '../../widgets/ui.dart';
import '../mart/mart_kit.dart' show DayField;
import '../restaurant/engine/calc.dart' show J, jmap, jlist, js, nz;
import '../restaurant/pos_ui.dart';
import 'engine/gh_pos.dart';
import 'gh_book.dart';
import 'gh_display.dart';
import 'gh_member.dart';
import 'gh_print.dart';
import 'gh_ui.dart';

String _dayShow(String d) => ghDay(d, weekday: true);

// One booking (the web's StayModal): the guest, the bill (room + extras − discount), payments, and the actions
// (check in / out, cancel, no-show, move). Changes go to the cloud, or are saved here with no internet.
Future<void> openStay(BuildContext context, Object? stayId) {
  final no = js(GhPos.i.cachedStay(stayId)?['no']);
  return posSheet<void>(
    context,
    title: no.isEmpty ? tr(context)('gh.bill') : tr(context)('gh.stayTitle', {'no': no}),
    maxWidth: 720,
    body: (ctx) => _StayView(stayId: js(stayId)),
  );
}

const svcEmoji = {'laundry': '🧺', 'bike': '🛵', 'tour': '🗺️', 'minibar': '🥤', 'food': '🍳', 'coffee': '☕', 'transfer': '🚐', 'spa': '💆', 'other': '✨'};

class _StayView extends StatefulWidget {
  final String stayId;
  const _StayView({required this.stayId});
  @override
  State<_StayView> createState() => _StayViewState();
}

class _StayViewState extends State<_StayView> {
  final pos = GhPos.i;
  J? s;
  bool busy = false;
  String error = '';
  J? ask; // { code, balance, nights, total } from a refused check-out
  String sure = '';
  bool edit = false;
  J? charge; // { label, amount, qty }
  J? pay; // { method, amount, note }
  final _disc = TextEditingController();
  final _cLabel = TextEditingController(), _cAmount = TextEditingController(), _cQty = TextEditingController(text: '1');
  final _pAmount = TextEditingController(), _pNote = TextEditingController();

  @override
  void initState() {
    super.initState();
    pos
        .stay(widget.stayId)
        .then(
          (r) {
            if (mounted) _got(r);
          },
          onError: (e) {
            if (mounted) setState(() => error = ghErr(context, e));
          },
        );
  }

  @override
  void dispose() {
    GhDisplayFeed.i.show(null);
    for (final c in [_disc, _cLabel, _cAmount, _cQty, _pAmount, _pNote]) {
      c.dispose();
    }
    super.dispose();
  }

  void _got(J d) => setState(() {
    s = d;
    GhDisplayFeed.i.show(d); // the guest sees this bill
    final dv = nz(d['discount']);
    _disc.text = dv == 0 ? '' : (dv == dv.roundToDouble() ? dv.toInt().toString() : '$dv');
  });

  Future<bool> run(Future<J> Function() fn, [String msg = '']) async {
    setState(() {
      busy = true;
      error = '';
    });
    try {
      final r = await fn();
      if (!mounted) return true;
      if (js(r['_id']).isNotEmpty) _got(r);
      if (msg.isNotEmpty) ghToast(context, msg);
      return true;
    } on ApiError catch (e) {
      if (!mounted) return false;
      final code = js(e.body['code']).isEmpty ? (e.code ?? '') : js(e.body['code']);
      setState(() {
        if (e.status == 409 && ['unpaid', 'refund'].contains(code)) {
          ask = {'code': code, 'balance': e.body['balance'], 'nights': e.body['nights'], 'total': e.body['total']};
        } else {
          error = ghErr(context, e);
        }
      });
      return false;
    } finally {
      if (mounted) {
        setState(() {
          busy = false;
          sure = '';
        });
      }
    }
  }

  Future<void> _print([J? stay]) async {
    final t = tr(context);
    await GhPrint.load();
    if (!mounted) return;
    if (!GhPrint.printer.on) {
      await openGhPrinters(context);
      return;
    }
    try {
      await GhPrint.receipt(stay ?? s!);
    } catch (e) {
      if (mounted) ghToast(context, '${t('rp.failed')} ${ghPrintError(e)}');
    }
  }

  Future<void> _checkOut(T t, [J body = const {}]) async {
    final ok = await run(() => pos.action(s!['_id'], 'check-out', body), t('gh.checkedOut'));
    if (ok && mounted) {
      await GhPrint.load();
      if (GhPrint.auto && GhPrint.printer.on) _print();
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = tr(context);
    final c = context.c;
    final st = s;
    if (st == null) {
      return Padding(
        padding: const EdgeInsets.all(24),
        child: error.isNotEmpty ? Alert(error) : const Center(child: CircularProgressIndicator()),
      );
    }
    final cur = pos.currency;
    final today = pos.today;
    final b = jmap(st['bill']);
    final status = js(st['status']);
    final live = GhPos.live.contains(status);
    final type = pos.typeOf(st['type_id']);
    final open = !pos.readOnly && status != 'cancelled';
    final desk = pos.desk;
    final g = jmap(st['guest']);
    final lease = st['lease'] != null;
    final (sfg, sbg) = ghStatusColors(context, status);
    final col = ghColor(js(type?['color']));
    final bal = nz(b['balance']);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            GhPill(t('gh.status.$status'), fg: sfg, bg: sbg),
            const SizedBox(width: 8),
            Muted(js(st['no'])),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(color: col.withValues(alpha: .14), borderRadius: BorderRadius.circular(12)),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(LucideIcons.bedDouble, size: 18, color: col),
                  const SizedBox(width: 6),
                  Text(
                    js(st['room_name']),
                    style: TextStyle(fontWeight: FontWeight.w800, color: col, fontSize: 16),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(js(g['name']), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 17)),
                  if ([g['phone'], g['id_number'], g['nationality']].any((x) => js(x).isNotEmpty))
                    Text(
                      [js(g['phone']), if (js(g['id_number']).isNotEmpty) '${t('gh.idTypes.${js(g['id_type'])}')} ${js(g['id_number'])}', js(g['nationality'])].where((x) => x.isNotEmpty).join(' · '),
                      style: TextStyle(color: c.muted, fontSize: 12.5),
                    ),
                  Text(
                    '${lease ? '🔑 ' : ''}${ghDay(js(st['from']), weekday: true)} → ${lease && jmap(st['lease'])['end'] == null ? '…' : ghDay(js(lease ? jmap(st['lease'])['end'] : st['to']), weekday: true)}'
                    '${lease ? '' : ' · ${t('gh.nights', {'n': nz(b['nights']).toInt()})}'} · ${nz(st['adults']).toInt()}${nz(st['children']) > 0 ? ' + ${nz(st['children']).toInt()}' : ''} 👤 · ${t('gh.sources.${js(st['source'])}')}',
                    style: const TextStyle(fontSize: 13),
                  ),
                ],
              ),
            ),
          ],
        ),
        if (st['offline'] == true || js(st['_id']).startsWith('local-')) ...[const SizedBox(height: 8), GhPill(t('ghp.offline'), fg: c.warn, bg: c.warnBg)],
        if (js(st['note']).isNotEmpty) ...[
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(color: c.warnBg, borderRadius: BorderRadius.circular(12)),
            child: Text(js(st['note'])),
          ),
        ],
        if (live && open && !edit && !lease)
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(onPressed: () => setState(() => edit = true), icon: const Icon(LucideIcons.pencil, size: 15), label: Text(t('gh.move'))),
          ),
        if (edit)
          _EditStay(
            s: st,
            busy: busy,
            onCancel: () => setState(() => edit = false),
            onSave: (body) async {
              if (await run(() => pos.updateStay(st['_id'], body), t('gh.saved'))) setState(() => edit = false);
            },
          ),
        if (ask != null) ...[
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: c.warnBg, borderRadius: BorderRadius.circular(14)),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (ask!['nights'] != null && nz(ask!['nights']) != nz(b['nights']))
                  Text(
                    t('gh.leavingEarly', {'n': nz(ask!['nights']).toInt(), 'total': ghMoney(ask!['total'], cur)}),
                    style: TextStyle(fontWeight: FontWeight.w800, color: c.warn),
                  ),
                Text(
                  t(ask!['code'] == 'refund' ? 'gh.refundAsk' : 'gh.unpaidAsk', {'amt': ghMoney(nz(ask!['balance']).abs(), cur)}),
                  style: TextStyle(color: c.warn, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    OutlinedButton(
                      onPressed: busy
                          ? null
                          : () {
                              setState(() => ask = null);
                              _checkOut(t, {'force': true});
                            },
                      child: Text(t('gh.forceOut')),
                    ),
                    FilledButton(
                      onPressed: () => setState(() {
                        final refund = ask!['code'] == 'refund';
                        pay = {'method': refund ? 'cash' : pos.methods.first};
                        _pAmount.text = ghNum(ask!['balance']);
                        _pNote.text = refund ? t('gh.refund') : '';
                        ask = null;
                      }),
                      child: Text(ask!['code'] == 'refund' ? t('gh.refund') : t('gh.takePayment')),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
        GhMemberBox(stay: st, onStay: _got),
        const SizedBox(height: 12),
        // ---------------- the bill ----------------
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(color: c.card, borderRadius: BorderRadius.circular(18)),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(t('gh.bill'), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
              const SizedBox(height: 6),
              if (!lease) _line(t('gh.roomCharge', {'n': nz(b['nights']).toInt(), 'rate': ghMoney(st['rate'], cur)}), ghMoney(b['room'], cur)),
              for (final ch in jlist(st['charges']))
                _line(
                  '${js(ch['label'])}${nz(ch['qty']) > 1 ? ' × ${nz(ch['qty']).toInt()}' : ''}',
                  ghMoney(nz(ch['amount']) * (nz(ch['qty']) == 0 ? 1 : nz(ch['qty'])), cur),
                  sub: ghTime(ch['at']),
                  onRemove: open && !desk && !busy ? () => run(() => pos.removeCharge(st['_id'], js(ch['_id']))) : null,
                ),
              if (open && jlist(pos.boot['services']).isNotEmpty && charge == null) ...[
                const SizedBox(height: 6),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final x in jlist(pos.boot['services']))
                      ActionChip(
                        avatar: Text(svcEmoji[js(x['icon'])] ?? svcEmoji['other']!),
                        label: Text('${js(x['name'])} · ${ghMoney(x['price'], cur)}'),
                        onPressed: busy ? null : () => run(() => pos.addCharge(st['_id'], {'service_id': x['_id'], 'label': x['name'], 'amount': nz(x['price']), 'qty': 1})),
                      ),
                  ],
                ),
              ],
              if (open) charge == null ? _addBtn(t('gh.addCharge'), () => setState(() => charge = {})) : _chargeForm(t),
              const Divider(height: 18),
              Row(
                children: [
                  Expanded(child: Text(t('gh.discount'))),
                  if (open && !desk)
                    SizedBox(
                      width: 110,
                      child: Focus(
                        onFocusChange: (f) {
                          if (!f && nz(_disc.text) != nz(st['discount'])) run(() => pos.discount(st['_id'], nz(_disc.text)));
                        },
                        child: TextField(
                          controller: _disc,
                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                          textAlign: TextAlign.right,
                          decoration: const InputDecoration(isDense: true, prefixText: '− ', hintText: '0'),
                          onSubmitted: (_) => nz(_disc.text) != nz(st['discount']) ? run(() => pos.discount(st['_id'], nz(_disc.text))) : null,
                        ),
                      ),
                    )
                  else
                    Text(nz(b['discount']) > 0 ? '−${ghMoney(b['discount'], cur)}' : '—', style: const TextStyle(fontWeight: FontWeight.w700)),
                ],
              ),
              const SizedBox(height: 6),
              SumRow(t('gh.total'), ghMoney(b['total'], cur), big: true),
              const SizedBox(height: 12),
              Text(t('gh.payments'), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
              const SizedBox(height: 4),
              for (final p in jlist(st['payments']))
                _line(
                  '${t('gh.methods.${js(p['method'])}')}${js(p['note']).isNotEmpty ? ' · ${js(p['note'])}' : ''}',
                  ghMoney(p['amount'], cur),
                  sub: ghTime(p['at']),
                  neg: nz(p['amount']) < 0,
                  onRemove: !pos.readOnly && !desk && !busy ? () => run(() => pos.removePayment(st['_id'], js(p['_id']))) : null,
                ),
              if (!pos.readOnly)
                pay == null
                    ? _addBtn(t('gh.takePayment'), () {
                        setState(() {
                          pay = {'method': pos.methods.first};
                          _pAmount.text = bal > 0 ? ghNum(bal) : '';
                          _pNote.text = '';
                        });
                      })
                    : _payForm(t),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(color: bal > 0 ? c.dangerBg : (bal < 0 ? c.warnBg : c.goodBg), borderRadius: BorderRadius.circular(12)),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        bal > 0 ? t('gh.balance') : (bal < 0 ? t('gh.change') : t('gh.settled')),
                        style: TextStyle(fontWeight: FontWeight.w800, color: bal > 0 ? c.danger : (bal < 0 ? c.warn : c.good)),
                      ),
                    ),
                    Text(
                      ghMoney(bal.abs(), cur),
                      style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18, color: bal > 0 ? c.danger : (bal < 0 ? c.warn : c.good)),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        if (js(st['by']).isNotEmpty) ...[
          const SizedBox(height: 8),
          Muted('${t('gh.by', {'name': js(st['by'])})} · ${ghTime(st['created_date'])}'),
        ],
        if (error.isNotEmpty) ...[const SizedBox(height: 8), Alert(error)],
        const SizedBox(height: 14),
        // ---------------- actions ----------------
        Wrap(
          spacing: 8,
          runSpacing: 8,
          alignment: WrapAlignment.end,
          children: [
            OutlinedButton.icon(onPressed: busy ? null : _print, icon: const Icon(LucideIcons.printer, size: 16), label: Text(t('gh.printBill'))),
            if (open && status == 'booked') ...[
              _sureBtn(t, 'cancel', t('gh.cancelBooking'), () => run(() => pos.action(st['_id'], 'cancel'))),
              if (js(st['from']).compareTo(today) <= 0) _sureBtn(t, 'noshow', t('gh.noShow'), () => run(() => pos.action(st['_id'], 'no-show'))),
              Btn(
                t('gh.checkIn'),
                icon: LucideIcons.logIn,
                small: true,
                onTap: busy || js(st['from']).compareTo(today) > 0 ? null : () => run(() => pos.action(st['_id'], 'check-in'), t('gh.checkedIn')),
              ),
            ],
            if (open && status == 'in' && !lease) Btn(t('gh.checkOut'), icon: LucideIcons.logOut, small: true, onTap: busy ? null : () => _checkOut(t)),
          ],
        ),
      ],
    );
  }

  Widget _sureBtn(T t, String k, String label, VoidCallback go) {
    final c = context.c;
    return sure == k
        ? FilledButton(
            style: FilledButton.styleFrom(backgroundColor: c.danger),
            onPressed: busy ? null : go,
            child: Text(t('gh.sure')),
          )
        : TextButton(
            style: TextButton.styleFrom(foregroundColor: k == 'cancel' ? c.danger : c.ink),
            onPressed: busy ? null : () => setState(() => sure = k),
            child: Text(label),
          );
  }

  Widget _line(String a, String v, {String sub = '', bool neg = false, VoidCallback? onRemove}) {
    final c = context.c;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Expanded(
            child: Text.rich(
              TextSpan(
                children: [
                  TextSpan(text: a),
                  if (sub.isNotEmpty)
                    TextSpan(
                      text: '  $sub',
                      style: TextStyle(color: c.muted, fontSize: 11.5),
                    ),
                ],
              ),
            ),
          ),
          Text(
            v,
            style: TextStyle(fontWeight: FontWeight.w700, color: neg ? c.danger : c.ink),
          ),
          if (onRemove != null)
            IconButton(
              visualDensity: VisualDensity.compact,
              onPressed: onRemove,
              icon: Icon(LucideIcons.x, size: 15, color: c.muted),
            ),
        ],
      ),
    );
  }

  Widget _addBtn(String label, VoidCallback onTap) => Align(
    alignment: Alignment.centerLeft,
    child: TextButton.icon(onPressed: busy ? null : onTap, icon: const Icon(LucideIcons.plus, size: 15), label: Text(label)),
  );

  Widget _chargeForm(T t) {
    final presets = t.list('gh.chargePresets');
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [for (final p in presets) ChoiceChip(label: Text(p), selected: _cLabel.text == p, showCheckmark: false, onSelected: (_) => setState(() => _cLabel.text = p))],
          ),
          const SizedBox(height: 8),
          Field(controller: _cLabel, hint: t('gh.chargePh'), maxLength: 80, autofocus: true, onChanged: (_) => setState(() {})),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                flex: 2,
                child: Field(controller: _cAmount, label: t('gh.amount'), keyboard: const TextInputType.numberWithOptions(decimal: true), onChanged: (_) => setState(() {})),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Field(controller: _cQty, label: t('gh.qty'), keyboard: TextInputType.number),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton(onPressed: () => setState(() => charge = null), child: Text(t('gh.cancel'))),
              const SizedBox(width: 6),
              Btn(
                t('gh.addCharge'),
                icon: LucideIcons.plus,
                small: true,
                onTap: busy || _cLabel.text.trim().isEmpty || _cAmount.text.trim().isEmpty
                    ? null
                    : () async {
                        final ok = await run(() => pos.addCharge(s!['_id'], {'label': _cLabel.text.trim(), 'amount': nz(_cAmount.text), 'qty': nz(_cQty.text) < 1 ? 1 : nz(_cQty.text).toInt()}));
                        if (ok && mounted) {
                          setState(() {
                            charge = null;
                            _cLabel.clear();
                            _cAmount.clear();
                            _cQty.text = '1';
                          });
                        }
                      },
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _payForm(T t) {
    final neg = nz(_pAmount.text) < 0;
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ghChips(context, [for (final k in pos.methods) (k, t('gh.methods.$k'))], js(pay!['method']), (k) => setState(() => pay!['method'] = k)),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: Field(
                  controller: _pAmount,
                  label: t('gh.amount'),
                  keyboard: const TextInputType.numberWithOptions(decimal: true, signed: true),
                  autofocus: true,
                  onChanged: (_) => setState(() {}),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Field(controller: _pNote, label: t('gh.note'), maxLength: 120),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton(onPressed: () => setState(() => pay = null), child: Text(t('gh.cancel'))),
              const SizedBox(width: 6),
              Btn(
                neg ? t('gh.refund') : t('gh.takePayment'),
                icon: neg ? LucideIcons.minus : LucideIcons.plus,
                small: true,
                onTap: busy || nz(_pAmount.text) == 0
                    ? null
                    : () async {
                        final ok = await run(() => pos.addPayment(s!['_id'], {'method': pay!['method'], 'amount': nz(_pAmount.text), 'note': _pNote.text.trim()}));
                        if (ok && mounted) setState(() => pay = null);
                      },
              ),
            ],
          ),
        ],
      ),
    );
  }
}

String ghNum(Object? v) {
  final x = nz(v);
  return x == x.roundToDouble() ? x.toInt().toString() : x.toString();
}

// change dates / room / guest / rate (the web's EditStay)
class _EditStay extends StatefulWidget {
  final J s;
  final bool busy;
  final VoidCallback onCancel;
  final ValueChanged<J> onSave;
  const _EditStay({required this.s, required this.busy, required this.onCancel, required this.onSave});
  @override
  State<_EditStay> createState() => _EditStayState();
}

class _EditStayState extends State<_EditStay> {
  late final J f = {
    'from': widget.s['from'],
    'to': widget.s['to'],
    'room_id': js(widget.s['room_id']),
    'adults': nz(widget.s['adults']).toInt(),
    'children': nz(widget.s['children']).toInt(),
    'guest': {...jmap(widget.s['guest'])},
  };
  late final _rate = TextEditingController(text: ghNum(widget.s['rate']));
  late final _note = TextEditingController(text: js(widget.s['note']));
  Set<String>? _busy;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _rate.dispose();
    _note.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _busy = null);
    final b = await busyRooms(js(f['from']), js(f['to']), js(widget.s['_id']));
    if (mounted) setState(() => _busy = b);
  }

  @override
  Widget build(BuildContext context) {
    final t = tr(context);
    final c = context.c;
    final s = widget.s;
    final nights = js(f['to']).compareTo(js(f['from'])) > 0 ? GhPos.nightsOf(js(f['from']), js(f['to'])) : 0;
    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: c.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: c.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: s['status'] == 'in'
                    ? Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(t('gh.arrive'), style: const TextStyle(fontWeight: FontWeight.w700)),
                          const SizedBox(height: 6),
                          Text(ghDay(js(f['from']), weekday: true)),
                        ],
                      )
                    : DayField(
                        show: _dayShow,
                        label: t('gh.arrive'),
                        value: js(f['from']),
                        onPick: (v) {
                          f['from'] = v;
                          if (js(f['to']).compareTo(v) <= 0) f['to'] = GhPos.addDays(v, 1);
                          _load();
                        },
                      ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: DayField(
                  show: _dayShow,
                  label: '${t('gh.leave')}${nights > 0 ? ' · ${t('gh.nights', {'n': nights})}' : ''}',
                  value: js(f['to']),
                  onPick: (v) {
                    if (v.compareTo(js(f['from'])) > 0) {
                      f['to'] = v;
                      _load();
                    }
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(t('gh.room'), style: const TextStyle(fontWeight: FontWeight.w700)),
          const SizedBox(height: 6),
          GhRoomPicker(value: js(f['room_id']), busy: _busy, onPick: (r, _) => setState(() => f['room_id'] = js(r['_id']))),
          const SizedBox(height: 10),
          GhGuestFields(f: f, lookup: false, onChanged: () => setState(() {})),
          const SizedBox(height: 10),
          Field(controller: _rate, label: '${t('gh.rate')} (${GhPos.i.currency})', keyboard: const TextInputType.numberWithOptions(decimal: true)),
          const SizedBox(height: 8),
          Field(controller: _note, label: t('gh.note'), maxLength: 500),
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton(onPressed: widget.busy ? null : widget.onCancel, child: Text(t('gh.cancel'))),
              const SizedBox(width: 6),
              Btn(
                widget.busy ? t('gh.saving') : t('gh.save'),
                small: true,
                onTap: widget.busy || nights == 0 || js(jmap(f['guest'])['name']).trim().isEmpty
                    ? null
                    : () => widget.onSave({
                        if (s['status'] == 'booked') 'from': f['from'],
                        'to': f['to'],
                        if (js(f['room_id']) != js(s['room_id'])) 'room_id': f['room_id'],
                        'rate': nz(_rate.text),
                        'adults': f['adults'],
                        'children': f['children'],
                        'note': _note.text.trim(),
                        'guest': f['guest'],
                      }),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
