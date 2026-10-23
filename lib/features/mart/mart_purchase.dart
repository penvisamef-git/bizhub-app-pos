import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/api.dart' show ApiError;
import '../../core/app_state.dart';
import '../../core/format.dart' as f;
import '../../core/i18n.dart';
import '../../core/theme.dart';
import '../../widgets/ui.dart';
import '../restaurant/engine/calc.dart' show J, jmap, jlist, js, nz;
import '../restaurant/pos_ui.dart';
import 'engine/mart_pos.dart';
import 'mart_kit.dart';
import 'mart_receipt.dart' show qtyOf;

// Purchase orders (mart_purchase, managers): the reorder list by supplier, orders (PO-0001…),
// send on Telegram / copy, and receive the delivery into the stock — the web's Purchase tab.
class MartPurchase extends StatefulWidget {
  const MartPurchase({super.key});
  @override
  State<MartPurchase> createState() => _MartPurchaseState();
}

class _MartPurchaseState extends State<MartPurchase> {
  final pos = MartPos.i;
  J? _re;
  List<J>? _pos;
  List<J> _sups = const [];
  String _status = 'open';
  String _error = '';

  @override
  void initState() {
    super.initState();
    _load();
    if (jmap(pos.boot['addons_on'])['mart_suppliers'] == true) {
      pos.api('GET', '/suppliers').then((r) {
        if (mounted) setState(() => _sups = jlist(r['data']));
      }, onError: (_) {});
    }
  }

  Future<void> _load() async {
    try {
      final r = await Future.wait([pos.api('GET', '/reorder'), pos.api('GET', '/po?status=$_status')]);
      if (mounted) {
        setState(() {
          _re = jmap(r[0]['data']);
          _pos = jlist(r[1]['data']);
          _error = '';
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = martErr(context, e));
    }
  }

  Future<void> _loadPos() async {
    setState(() => _pos = null);
    try {
      final r = await pos.api('GET', '/po?status=$_status');
      if (mounted) setState(() => _pos = jlist(r['data']));
    } catch (e) {
      if (mounted) setState(() => _error = martErr(context, e));
    }
  }

  bool get _stockOn => _re?['stock_on'] == true;

  @override
  Widget build(BuildContext context) {
    final t = tr(context);
    final re = _re;
    final groups = jlist(re?['groups']);
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
        children: [
          MartHead(
            title: '', // the page's top bar has the name
            sub: t('mx.reorderSub'),
            actions: [
              Btn(t('mx.makePo'), icon: LucideIcons.plus, small: true, onTap: re == null ? null : () => _editPo(context, {'items': <J>[]})),
            ],
          ),
          const SizedBox(height: 10),
          if (_error.isNotEmpty)
            Alert(
              _error,
              tone: Tone.warn,
              action: TextButton(onPressed: _load, child: Text(t('rpos.retry'))),
            ),
          if (re == null && _error.isEmpty)
            const Padding(
              padding: EdgeInsets.all(40),
              child: Center(child: CircularProgressIndicator()),
            ),
          if (re != null) ...[
            Text(t('mx.reorder'), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
            const SizedBox(height: 6),
            if (groups.isEmpty)
              Panel(
                padding: const EdgeInsets.all(18),
                margin: const EdgeInsets.only(bottom: 8),
                child: Muted(t('mx.noReorder'), align: TextAlign.center),
              ),
            for (final g in groups) _group(context, g),
            const SizedBox(height: 14),
            Text(t('mx.orders'), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
            const SizedBox(height: 6),
            PosChips<String>(
              scroll: true,
              value: _status,
              onTap: (v) {
                _status = v;
                _loadPos();
              },
              options: [('open', t('mx.open')), ('received', t('mx.poStatus.received')), ('cancelled', t('mx.poStatus.cancelled')), ('all', t('mx.all'))],
            ),
            const SizedBox(height: 8),
            if (_pos == null)
              const Padding(
                padding: EdgeInsets.all(20),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (_pos!.isEmpty)
              Padding(
                padding: const EdgeInsets.all(20),
                child: Muted(t('mx.noPos'), align: TextAlign.center),
              )
            else
              for (final po in _pos!) _poRow(context, po),
            if (!_stockOn) Padding(padding: const EdgeInsets.only(top: 8), child: Muted(t('mx.needStock'))),
          ],
        ],
      ),
    );
  }

  Widget _group(BuildContext context, J g) {
    final t = tr(context);
    final c = context.c;
    return Panel(
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 8),
      margin: const EdgeInsets.only(bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 16,
                backgroundColor: c.active,
                child: Icon(LucideIcons.truck, size: 16, color: c.brandInk),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(js(g['supplier']).isEmpty ? t('mx.noSupplier') : js(g['supplier']), style: const TextStyle(fontWeight: FontWeight.w800)),
                    if (js(g['phone']).isNotEmpty) Text(js(g['phone']), style: TextStyle(color: c.muted, fontSize: 12)),
                  ],
                ),
              ),
              Btn(
                t('mx.makePo'),
                icon: LucideIcons.plus,
                small: true,
                onTap: () => _editPo(context, {
                  'supplier_id': g['supplier_id'],
                  'items': [
                    for (final i in jlist(g['items'])) {'product_id': i['product_id'], 'name': i['name'], 'qty': i['qty'], 'cost': i['cost']},
                  ],
                }),
              ),
            ],
          ),
          const SizedBox(height: 4),
          for (final i in jlist(g['items']))
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 5),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(js(i['name']), style: const TextStyle(fontWeight: FontWeight.w700)),
                        Text(
                          '${t('mx.stockNow', {'n': qtyOf(i['stock'])})} · ${t('mx.lowAt', {'n': qtyOf(i['low_stock'])})}${nz(i['coming']) > 0 ? ' · ${t('mx.coming', {'n': qtyOf(i['coming'])})}' : ''}',
                          style: TextStyle(color: c.muted, fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                  MartPill(qtyOf(i['stock']), fg: nz(i['stock']) <= 0 ? c.danger : c.warn, bg: nz(i['stock']) <= 0 ? c.dangerBg : c.warnBg),
                  const SizedBox(width: 10),
                  SizedBox(
                    width: 48,
                    child: Text(
                      '+${qtyOf(i['qty'])}',
                      textAlign: TextAlign.right,
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  (Color, Color) _tone(BuildContext context, String s) {
    final c = context.c;
    return switch (s) {
      'sent' => (c.brandInk, c.active),
      'partial' => (c.warn, c.warnBg),
      'received' => (c.good, c.goodBg),
      'cancelled' => (c.danger, c.dangerBg),
      _ => (c.muted, c.chip),
    };
  }

  Widget _poRow(BuildContext context, J po) {
    final t = tr(context);
    final c = context.c;
    final (fg, bg) = _tone(context, js(po['status']));
    final items = jlist(po['items']);
    return Card(
      margin: const EdgeInsets.only(bottom: 6),
      elevation: 0,
      color: c.card,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ListTile(
        onTap: () => _view(context, po),
        leading: CircleAvatar(
          backgroundColor: bg,
          child: Icon(LucideIcons.clipboardCheck, size: 18, color: fg),
        ),
        title: Text(
          '${js(po['no'])} · ${js(po['supplier_name']).isEmpty ? t('mx.noSupplier') : js(po['supplier_name'])}',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontWeight: FontWeight.w800),
        ),
        subtitle: Text(
          '${f.fmtDate(po['created_date'], lang: AppState.i.lang)} · ${items.length}× · ${items.take(3).map((i) => js(i['name'])).join(', ')}',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        trailing: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(f.money(po['total'], pos.currency), style: const TextStyle(fontWeight: FontWeight.w800)),
            const SizedBox(height: 3),
            MartPill(t('mx.poStatus.${js(po['status'])}'), fg: fg, bg: bg),
          ],
        ),
      ),
    );
  }

  // make / change an order: supplier, products with qty + cost, note
  Future<void> _editPo(BuildContext context, J po) async {
    final t = tr(context);
    final cur = pos.currency;
    var sup = js(po['supplier_id']);
    final lines = [
      for (final i in jlist(po['items']))
        {'product_id': js(i['product_id']), 'name': js(i['name']), 'qty': TextEditingController(text: qtyOf(i['qty'])), 'cost': TextEditingController(text: i['cost'] == null ? '' : qtyOf(i['cost']))},
    ];
    final note = TextEditingController(text: js(po['note']));
    var busy = false;
    var error = '';
    final editing = js(po['_id']).isNotEmpty;
    final ok = await posSheet<bool>(
      context,
      title: editing ? js(po['no']) : t('mx.makePo'),
      maxWidth: 640,
      body: (ctx) => StatefulBuilder(
        builder: (ctx, set) {
          final total = lines.fold<double>(0, (a, l) => a + nz((l['qty'] as TextEditingController).text) * nz((l['cost'] as TextEditingController).text));
          final send = [
            for (final l in lines)
              if (nz((l['qty'] as TextEditingController).text) > 0)
                {
                  'product_id': l['product_id'],
                  'qty': nz((l['qty'] as TextEditingController).text),
                  if ((l['cost'] as TextEditingController).text.trim().isNotEmpty) 'cost': nz((l['cost'] as TextEditingController).text),
                },
          ];
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (_sups.isNotEmpty || sup.isNotEmpty) ...[
                Text(t('mx.supplier'), style: const TextStyle(fontWeight: FontWeight.w700)),
                const SizedBox(height: 6),
                DropdownButtonFormField<String>(
                  initialValue: _sups.any((s) => js(s['_id']) == sup) || sup.isEmpty ? sup : '',
                  isExpanded: true,
                  decoration: InputDecoration(
                    isDense: true,
                    filled: true,
                    fillColor: ctx.c.bg2,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: BorderSide(color: ctx.c.line),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: BorderSide(color: ctx.c.line),
                    ),
                  ),
                  items: [
                    DropdownMenuItem(value: '', child: Text(t('mx.noSupplier'))),
                    for (final s in _sups) DropdownMenuItem(value: js(s['_id']), child: Text(js(s['name']))),
                  ],
                  onChanged: (v) => set(() => sup = v ?? ''),
                ),
                const SizedBox(height: 10),
              ],
              for (var i = 0; i < lines.length; i++)
                Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  padding: const EdgeInsets.fromLTRB(12, 6, 4, 10),
                  decoration: BoxDecoration(
                    color: ctx.c.card,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: ctx.c.line),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(js(lines[i]['name']), style: const TextStyle(fontWeight: FontWeight.w700)),
                          ),
                          IconButton(
                            onPressed: () => set(() => lines.removeAt(i)),
                            icon: Icon(LucideIcons.x, size: 17, color: ctx.c.muted),
                            tooltip: t('mx.remove'),
                          ),
                        ],
                      ),
                      Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: Row(
                          children: [
                            Expanded(
                              child: Field(
                                label: t('mx.qty'),
                                controller: lines[i]['qty'] as TextEditingController,
                                keyboard: const TextInputType.numberWithOptions(decimal: true),
                                onChanged: (_) => set(() {}),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Field(
                                label: '${t('mx.cost')} (${cur == 'KHR' ? '៛' : '\$'})',
                                controller: lines[i]['cost'] as TextEditingController,
                                keyboard: const TextInputType.numberWithOptions(decimal: true),
                                onChanged: (_) => set(() {}),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              OutlinedButton.icon(
                onPressed: () async {
                  final p = await pickMartProduct(ctx, exclude: {for (final l in lines) js(l['product_id'])});
                  if (p != null) {
                    set(() => lines.add({'product_id': js(p['_id']), 'name': js(p['name']), 'qty': TextEditingController(text: '1'), 'cost': TextEditingController()}));
                  }
                },
                style: OutlinedButton.styleFrom(padding: const EdgeInsets.all(14)),
                icon: const Icon(LucideIcons.plus, size: 18),
                label: Text(t('mx.addLine')),
              ),
              const SizedBox(height: 10),
              Field(controller: note, label: t('mx.note'), maxLength: 500),
              if (error.isNotEmpty) ...[const SizedBox(height: 8), Alert(error)],
              const SizedBox(height: 10),
              SumRow(t('mx.total'), f.money(total, cur)),
              const SizedBox(height: 10),
              Btn(
                busy ? t('mx.saving') : t('mx.save'),
                busy: busy,
                expand: true,
                onTap: busy || send.isEmpty
                    ? null
                    : () async {
                        set(() => busy = true);
                        try {
                          final body = {'supplier_id': sup.isEmpty ? null : sup, 'note': note.text.trim(), 'items': send};
                          await (editing ? pos.api('PUT', '/po/${js(po['_id'])}', body) : pos.api('POST', '/po', body));
                          if (ctx.mounted) Navigator.pop(ctx, true);
                        } catch (e) {
                          set(() {
                            busy = false;
                            error = martErr(ctx, e);
                          });
                        }
                      },
              ),
            ],
          );
        },
      ),
    );
    if (ok == true) {
      if (context.mounted) ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(content: Text(t('mx.saved'))));
      await _load();
    }
  }

  String _text(T t, J po) {
    final cur = pos.currency;
    return t('mx.poText', {
      'no': js(po['no']),
      'shop': js(pos.business['name']),
      'date': f.fmtDate(po['created_date'], lang: AppState.i.lang),
      'lines': jlist(po['items']).map((i) => '• ${js(i['name'])} × ${qtyOf(i['qty'])}${nz(i['cost']) > 0 ? ' @ ${f.money(i['cost'], cur)}' : ''}').join('\n'),
      'total': f.money(po['total'], cur),
      'note': js(po['note']).isNotEmpty ? '\n${js(po['note'])}' : '',
    });
  }

  // one order: lines, share (Telegram / copy), edit, receive, cancel / delete
  Future<void> _view(BuildContext context, J first) async {
    final t = tr(context);
    final cur = pos.currency;
    var po = first;
    var busy = false;
    final messenger = ScaffoldMessenger.maybeOf(context);
    final next = await posSheet<String>(
      context,
      title: js(po['no']),
      maxWidth: 600,
      body: (ctx) => StatefulBuilder(
        builder: (ctx, set) {
          final c = ctx.c;
          final st = js(po['status']);
          final open = ['draft', 'sent', 'partial'].contains(st);
          Future<void> act(String path, {bool close = false}) async {
            set(() => busy = true);
            try {
              final r = await pos.api(path.startsWith('DELETE ') ? 'DELETE' : 'POST', path.replaceFirst('DELETE ', ''));
              if (close) {
                if (ctx.mounted) Navigator.pop(ctx, 'reload');
                return;
              }
              set(() {
                if (r['data'] is Map) po = jmap(r['data']);
                busy = false;
              });
              _load();
            } catch (e) {
              final msg = e is ApiError ? (e.network ? t('rpos.needInternetShort') : e.message) : '$e';
              set(() => busy = false);
              messenger?.showSnackBar(SnackBar(content: Text(msg)));
            }
          }

          Future<void> markSent() async {
            if (js(po['status']) == 'draft') await act('/po/${js(po['_id'])}/send');
          }

          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  Builder(
                    builder: (_) {
                      final (fg, bg) = _tone(ctx, st);
                      return MartPill(t('mx.poStatus.$st'), fg: fg, bg: bg);
                    },
                  ),
                  Chip2(js(po['supplier_name']).isEmpty ? t('mx.noSupplier') : js(po['supplier_name']), icon: LucideIcons.truck),
                  Chip2(f.fmtDate(po['created_date'], lang: AppState.i.lang), icon: LucideIcons.calendarDays),
                  if (js(po['invoice_no']).isNotEmpty) Chip2('${t('mx.invoiceNo')} ${js(po['invoice_no'])}', icon: LucideIcons.receiptText),
                ],
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      t('mx.product'),
                      style: TextStyle(color: c.muted, fontSize: 12, fontWeight: FontWeight.w700),
                    ),
                  ),
                  SizedBox(
                    width: 64,
                    child: Text(
                      t('mx.ordered'),
                      textAlign: TextAlign.right,
                      style: TextStyle(color: c.muted, fontSize: 12, fontWeight: FontWeight.w700),
                    ),
                  ),
                  SizedBox(
                    width: 70,
                    child: Text(
                      t('mx.received'),
                      textAlign: TextAlign.right,
                      style: TextStyle(color: c.muted, fontSize: 12, fontWeight: FontWeight.w700),
                    ),
                  ),
                  SizedBox(
                    width: 70,
                    child: Text(
                      t('mx.cost'),
                      textAlign: TextAlign.right,
                      style: TextStyle(color: c.muted, fontSize: 12, fontWeight: FontWeight.w700),
                    ),
                  ),
                ],
              ),
              const Divider(height: 12),
              for (final i in jlist(po['items']))
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(js(i['name']), style: const TextStyle(fontWeight: FontWeight.w600)),
                      ),
                      SizedBox(width: 64, child: Text(qtyOf(i['qty']), textAlign: TextAlign.right)),
                      SizedBox(
                        width: 70,
                        child: Text(
                          qtyOf(i['received'] ?? 0),
                          textAlign: TextAlign.right,
                          style: TextStyle(fontWeight: FontWeight.w700, color: nz(i['received']) >= nz(i['qty']) - 1e-9 ? c.good : c.ink),
                        ),
                      ),
                      SizedBox(width: 70, child: Text(f.money(i['cost'], cur), textAlign: TextAlign.right)),
                    ],
                  ),
                ),
              const Divider(height: 14),
              SumRow(t('mx.total'), f.money(po['total'], cur)),
              if (js(po['note']).isNotEmpty) Muted(js(po['note'])),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  FilledButton.icon(
                    style: FilledButton.styleFrom(backgroundColor: const Color(0xFF229ED9)),
                    onPressed: busy
                        ? null
                        : () async {
                            await launchUrl(Uri.parse('https://t.me/share/url?url=${Uri.encodeComponent(' ')}&text=${Uri.encodeComponent(_text(t, po))}'), mode: LaunchMode.externalApplication);
                            await markSent();
                          },
                    icon: const Icon(LucideIcons.send, size: 16),
                    label: Text(t('mx.sendTg')),
                  ),
                  OutlinedButton.icon(
                    onPressed: busy
                        ? null
                        : () async {
                            await Clipboard.setData(ClipboardData(text: _text(t, po)));
                            messenger?.showSnackBar(SnackBar(content: Text(t('mx.copied'))));
                            await markSent();
                          },
                    icon: const Icon(LucideIcons.copy, size: 16),
                    label: Text(t('mx.copy')),
                  ),
                ],
              ),
              if (open) ...[
                const SizedBox(height: 14),
                if (!_stockOn) Muted(t('mx.needStock')),
                Row(
                  children: [
                    if (st == 'draft')
                      TextButton.icon(
                        onPressed: busy ? null : () => act('DELETE /po/${js(po['_id'])}', close: true),
                        style: TextButton.styleFrom(foregroundColor: c.danger),
                        icon: const Icon(LucideIcons.trash2, size: 16),
                        label: Text(t('mx.deletePo')),
                      )
                    else
                      TextButton(
                        onPressed: busy ? null : () => act('/po/${js(po['_id'])}/cancel'),
                        style: TextButton.styleFrom(foregroundColor: c.danger),
                        child: Text(t('mx.cancelPo')),
                      ),
                    const Spacer(),
                    if (['draft', 'sent'].contains(st))
                      TextButton.icon(onPressed: busy ? null : () => Navigator.pop(ctx, 'edit:${js(po['_id'])}'), icon: const Icon(LucideIcons.pencil, size: 16), label: Text(t('mx.edit'))),
                    const SizedBox(width: 6),
                    Btn(t('mx.receive'), icon: LucideIcons.packageCheck, small: true, onTap: busy || !_stockOn ? null : () => Navigator.pop(ctx, 'receive')),
                  ],
                ),
              ],
            ],
          );
        },
      ),
    );
    if (!context.mounted) return;
    if (next == 'receive') {
      await _receive(context, po);
    } else if (next != null && next.startsWith('edit:')) {
      await _editPo(context, po);
    } else if (next == 'reload') {
      await _load();
    }
  }

  // the delivery came: what arrived (part is fine), cost, expiry, invoice no.
  Future<void> _receive(BuildContext context, J po) async {
    final t = tr(context);
    final cur = pos.currency;
    final expOn = jmap(pos.boot['addons_on'])['mart_expiry'] == true;
    final lines = [
      for (final i in jlist(po['items']))
        {
          'product_id': js(i['product_id']),
          'name': js(i['name']),
          'qty': TextEditingController(text: qtyOf((nz(i['qty']) - nz(i['received'])).clamp(0, double.infinity))),
          'cost': TextEditingController(text: qtyOf(i['cost'] ?? 0)),
          'expires': '',
        },
    ];
    final inv = TextEditingController();
    var busy = false;
    var error = '';
    final ok = await posSheet<bool>(
      context,
      title: t('mx.receiveTitle', {'no': js(po['no'])}),
      maxWidth: 640,
      body: (ctx) => StatefulBuilder(
        builder: (ctx, set) {
          final send = [
            for (final l in lines)
              if (nz((l['qty'] as TextEditingController).text) > 0)
                {
                  'product_id': l['product_id'],
                  'qty': nz((l['qty'] as TextEditingController).text),
                  'cost': nz((l['cost'] as TextEditingController).text),
                  if (js(l['expires']).isNotEmpty) 'expires': l['expires'],
                },
          ];
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final l in lines)
                Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: ctx.c.card,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: ctx.c.line),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(js(l['name']), style: const TextStyle(fontWeight: FontWeight.w700)),
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          Expanded(
                            child: Field(
                              label: t('mx.received'),
                              controller: l['qty'] as TextEditingController,
                              keyboard: const TextInputType.numberWithOptions(decimal: true),
                              onChanged: (_) => set(() {}),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Field(
                              label: '${t('mx.cost')} (${cur == 'KHR' ? '៛' : '\$'})',
                              controller: l['cost'] as TextEditingController,
                              keyboard: const TextInputType.numberWithOptions(decimal: true),
                            ),
                          ),
                        ],
                      ),
                      if (expOn) ...[
                        const SizedBox(height: 8),
                        OutlinedButton.icon(
                          onPressed: () async {
                            final d = await pickMartDay(ctx, initial: js(l['expires']), back: 30);
                            if (d != null) set(() => l['expires'] = d);
                          },
                          icon: const Icon(LucideIcons.calendarClock, size: 16),
                          label: Text(js(l['expires']).isEmpty ? t('mx.expiryOpt') : js(l['expires'])),
                        ),
                      ],
                    ],
                  ),
                ),
              Field(controller: inv, label: t('mx.invoiceNo'), maxLength: 60),
              if (error.isNotEmpty) ...[const SizedBox(height: 8), Alert(error)],
              const SizedBox(height: 12),
              Btn(
                t('mx.receive'),
                icon: LucideIcons.packageCheck,
                busy: busy,
                expand: true,
                onTap: busy || send.isEmpty
                    ? null
                    : () async {
                        set(() => busy = true);
                        try {
                          await pos.api('POST', '/po/${js(po['_id'])}/receive', {'invoice_no': inv.text.trim(), 'items': send});
                          if (ctx.mounted) Navigator.pop(ctx, true);
                        } catch (e) {
                          set(() {
                            busy = false;
                            error = martErr(ctx, e);
                          });
                        }
                      },
              ),
            ],
          );
        },
      ),
    );
    if (ok == true) {
      if (context.mounted) ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(content: Text(t('mx.saved'))));
      pos.syncNow(); // the new stock shows on the sale screen
      await _load();
    }
  }
}
