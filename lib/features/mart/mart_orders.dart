import 'dart:async';

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/api.dart' show ApiError;
import '../../core/app_state.dart';
import '../../core/format.dart' as f;
import '../../core/theme.dart';
import '../../widgets/ui.dart';
import '../restaurant/engine/calc.dart' show J, jmap, jlist, js, nz;
import '../restaurant/pos_ui.dart';
import 'engine/mart_pos.dart';
import 'mart_receipt.dart' show qtyOf;

const _open = ['new', 'accepted', 'ready', 'delivering'];

// Online orders from the shop's website (mart_shop): accept → ready / out for delivery → done (or decline).
// The POS rings while new orders wait (MartPos.watchOrders). Needs the internet.
class MartOrders extends StatefulWidget {
  const MartOrders({super.key});
  @override
  State<MartOrders> createState() => _MartOrdersState();
}

class _MartOrdersState extends State<MartOrders> {
  final pos = MartPos.i;
  String _filter = 'open', _busy = '', _error = '';
  List<J>? _rows;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _load();
    _timer = Timer.periodic(const Duration(seconds: 20), (_) => _load());
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final r = jlist((await pos.api('GET', '/orders?status=$_filter'))['data']);
      if (mounted) {
        setState(() {
          _rows = r;
          _error = '';
        });
      }
    } on ApiError catch (e) {
      if (mounted) setState(() => _error = e.network ? tr(context)('rpos.needInternetShort') : e.message);
    }
  }

  Future<void> _step(J o, String k, [J? data]) async {
    final t = tr(context);
    final bar = ScaffoldMessenger.of(context);
    setState(() => _busy = '${o['_id']}:$k');
    try {
      await pos.api('POST', '/orders/${o['_id']}/$k', data ?? {});
      bar.showSnackBar(SnackBar(content: Text(t.or('mw.stepDone.$k', t('mart.saved')).replaceAll('{no}', js(o['no'])))));
      await _load();
      pos.checkOrders(); // the ringing stops once nothing is new
      if (k == 'accept' || k == 'done') pos.syncNow(); // stock / sales changed
    } on ApiError catch (e) {
      bar.showSnackBar(SnackBar(content: Text(e.message)));
      _load();
    } finally {
      if (mounted) setState(() => _busy = '');
    }
  }

  Future<void> _decline(J o) async {
    final t = tr(context);
    final reason = TextEditingController();
    final ok = await posSheet<bool>(
      context,
      title: '${o['status'] == 'new' ? t('mw.decline') : t('mw.cancelOrder')} · ${js(o['no'])}',
      maxWidth: 460,
      body: (ctx) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Muted(t('mw.declineSub')),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [for (final q in t.list('mw.reasons')) ActionChip(label: Text(q), onPressed: () => reason.text = q)],
          ),
          const SizedBox(height: 10),
          Field(controller: reason, hint: t('mw.reasonPh'), maxLength: 200, maxLines: 2),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: Btn(t('mw.back'), kind: BtnKind.ghost, onTap: () => Navigator.pop(ctx)),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Btn(o['status'] == 'new' ? t('mw.decline') : t('mw.cancelOrder'), kind: BtnKind.danger, onTap: () => Navigator.pop(ctx, true)),
              ),
            ],
          ),
        ],
      ),
    );
    if (ok == true) await _step(o, 'decline', {'reason': reason.text.trim()});
  }

  @override
  Widget build(BuildContext context) {
    final t = tr(context);
    final c = context.c;
    final rows = _rows;
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(12, 4, 12, 24),
        children: [
          Row(
            children: [
              Expanded(
                child: Text(t('mart.tabs.orders'), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 18)),
              ),
              IconButton(onPressed: _load, icon: const Icon(LucideIcons.refreshCw), tooltip: t('mpos.syncNow')),
            ],
          ),
          PosChips<String>(
            scroll: true,
            value: _filter,
            onTap: (v) {
              setState(() {
                _filter = v;
                _rows = null;
              });
              _load();
            },
            options: [
              for (final k in ['open', 'new', 'closed', 'all']) (k, t('mw.filters.$k')),
            ],
          ),
          const SizedBox(height: 10),
          if (_error.isNotEmpty)
            Alert(
              _error,
              tone: Tone.warn,
              action: TextButton(onPressed: _load, child: Text(t('rpos.retry'))),
            ),
          if (rows == null && _error.isEmpty)
            const Padding(
              padding: EdgeInsets.all(40),
              child: Center(child: CircularProgressIndicator()),
            ),
          if (rows != null && rows.isEmpty)
            Padding(
              padding: const EdgeInsets.all(30),
              child: Column(
                children: [
                  Icon(LucideIcons.shoppingBag, size: 34, color: c.muted),
                  const SizedBox(height: 8),
                  Muted(_filter == 'open' || _filter == 'new' ? t('mw.noOpen') : t('mw.noOrders'), align: TextAlign.center),
                ],
              ),
            ),
          for (final o in rows ?? const <J>[]) _card(context, o),
        ],
      ),
    );
  }

  Widget _card(BuildContext context, J o) {
    final t = tr(context);
    final c = context.c;
    final cur = js(o['currency']).isEmpty ? pos.currency : js(o['currency']);
    final st = js(o['status']);
    final km = AppState.i.lang == 'km';
    final (fg, bg) = switch (st) {
      'new' => (c.warn, c.warnBg),
      'accepted' || 'delivering' => (c.brandInk, c.active),
      'ready' => (c.good, c.goodBg),
      'declined' => (c.danger, c.dangerBg),
      _ => (c.muted, c.chip),
    };
    final delivery = o['fulfil'] == 'delivery';
    final addr = jmap(o['address']);
    Widget btn(String k, String label, {BtnKind kind = BtnKind.primary}) =>
        Btn(label, small: true, kind: kind, busy: _busy == '${o['_id']}:$k', onTap: pos.readOnly || _busy.isNotEmpty ? null : () => k == 'decline' ? _decline(o) : _step(o, k));
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: c.card,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: st == 'new' ? c.warn : c.line, width: st == 'new' ? 2 : 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Text(js(o['no']), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  f.fmtDate(o['created_date'], time: true, lang: AppState.i.lang),
                  style: TextStyle(color: c.muted, fontSize: 12.5),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(999)),
                child: Text(
                  t.or('mw.status.$st', st),
                  style: TextStyle(color: fg, fontWeight: FontWeight.w700, fontSize: 12),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Text(js(o['name']), style: const TextStyle(fontWeight: FontWeight.w700)),
              const SizedBox(width: 8),
              InkWell(
                onTap: () => launchUrl(Uri.parse('tel:${js(o['phone'])}')),
                child: Row(
                  children: [
                    Icon(LucideIcons.phone, size: 13, color: c.brand),
                    const SizedBox(width: 4),
                    Text(
                      js(o['phone']),
                      style: TextStyle(color: c.brand, fontWeight: FontWeight.w600),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              Chip2(delivery ? t('mw.delivery') : t('mw.pickup'), icon: delivery ? LucideIcons.truck : LucideIcons.store, tone: Tone.brand),
              Chip2(o['pay_method'] == 'qr' ? t('mw.paidQr') : t('mw.cash'), icon: o['pay_method'] == 'qr' ? LucideIcons.qrCode : LucideIcons.banknote),
              if (js(o['sale_no']).isNotEmpty) Chip2(js(o['sale_no'])),
            ],
          ),
          if (delivery && js(addr['address']).isNotEmpty) ...[
            const SizedBox(height: 6),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(LucideIcons.mapPin, size: 15, color: c.muted),
                const SizedBox(width: 6),
                Expanded(child: Text('${js(addr['address'])}${js(addr['note']).isNotEmpty ? ' · ${js(addr['note'])}' : ''}')),
                if (js(addr['map']).isNotEmpty)
                  TextButton(
                    onPressed: () => launchUrl(
                      Uri.parse(RegExp(r'^https?://', caseSensitive: false).hasMatch(js(addr['map'])) ? js(addr['map']) : 'https://maps.google.com/?q=${Uri.encodeQueryComponent(js(addr['map']))}'),
                      mode: LaunchMode.externalApplication,
                    ),
                    child: Text(t('mw.map')),
                  ),
              ],
            ),
          ],
          const Divider(height: 18),
          for (final x in jlist(o['items']))
            SumRow('${qtyOf(x['qty'])}× ${js(x['name'])}${(km ? js(x['unit_km']) : js(x['unit_en'])).isNotEmpty ? ' / ${km ? js(x['unit_km']) : js(x['unit_en'])}' : ''}', f.money(x['total'], cur)),
          for (final p in jlist(o['promos'])) SumRow('🏷 ${js(p['name'])}', '−${f.money(p['amount'], cur)}', color: c.good),
          if (nz(o['points_value']) > 0) SumRow('${t('mx.pointsOff')} (${nz(o['points_used']).toInt()})', '−${f.money(o['points_value'], cur)}', color: c.good),
          if (nz(o['delivery_fee']) > 0) SumRow('${t('mw.deliveryFee')}${js(o['zone_name']).isNotEmpty ? ' · ${js(o['zone_name'])}' : ''}', f.money(o['delivery_fee'], cur)),
          SumRow(t('mw.total'), f.money(o['total'], cur), big: true),
          if (js(o['note']).isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text('“${js(o['note'])}”', style: const TextStyle(fontStyle: FontStyle.italic)),
            ),
          if (js(o['reason']).isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(js(o['reason']), style: TextStyle(color: c.danger)),
            ),
          if (js(o['driver_name']).isNotEmpty) Padding(padding: const EdgeInsets.only(top: 6), child: Muted('🛵 ${js(o['driver_name'])}')),
          if (js(o['proof']).isNotEmpty)
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: () => posSheet(
                  context,
                  title: t('mw.proof'),
                  body: (_) => Image(image: netImage(js(o['proof']))),
                ),
                icon: const Icon(LucideIcons.image, size: 16),
                label: Text(t('mw.seeProof')),
              ),
            ),
          if (_open.contains(st)) ...[
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                if (st == 'new') ...[btn('accept', t('mw.accept')), btn('decline', t('mw.decline'), kind: BtnKind.ghost)],
                if (st == 'accepted') ...[btn('ready', delivery ? t('mw.sendOut') : t('mw.markReady')), btn('decline', t('mw.cancelOrder'), kind: BtnKind.ghost)],
                if (st == 'ready' || st == 'delivering') ...[
                  btn('done', o['pay_method'] == 'cash' ? t('mw.doneCash', {'amt': f.money(o['total'], cur)}) : t('mw.done')),
                  btn('decline', t('mw.cancelOrder'), kind: BtnKind.ghost),
                ],
              ],
            ),
          ],
        ],
      ),
    );
  }
}

// the band over every tab while new orders wait (Open · Quiet 2 min)
class MartOrderAlert extends StatelessWidget {
  final VoidCallback onOpen;
  const MartOrderAlert({super.key, required this.onOpen});
  @override
  Widget build(BuildContext context) {
    final t = tr(context);
    final c = context.c;
    final pos = MartPos.i;
    if (pos.newOrders == 0) return const SizedBox.shrink();
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 0, 12, 8),
      padding: const EdgeInsets.fromLTRB(14, 6, 6, 6),
      decoration: BoxDecoration(
        color: c.warnBg,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: c.warn),
      ),
      child: Row(
        children: [
          Icon(LucideIcons.bellRing, color: c.warn),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              pos.newOrders == 1 ? t('mw.alertOne') : t('mw.alertMany', {'n': pos.newOrders}),
              style: TextStyle(color: c.warn, fontWeight: FontWeight.w800),
            ),
          ),
          if (!pos.ringMuted) TextButton(onPressed: pos.muteOrders, child: Text(t('mw.alertMute'))),
          Btn(t('mw.alertOpen'), small: true, onTap: onOpen),
        ],
      ),
    );
  }
}
