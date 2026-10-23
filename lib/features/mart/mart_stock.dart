import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/api.dart' show ApiError;
import '../../core/app_state.dart';
import '../../core/format.dart' as f;
import '../../core/theme.dart';
import '../../widgets/ui.dart';
import '../restaurant/engine/calc.dart' show J, jmap, jlist, js, nz;
import '../restaurant/pos_ui.dart';
import 'engine/mart_pos.dart';
import 'mart_receipt.dart' show qtyOf;

// Stock control (mart_stock): what is on the shelf, receive stock, count, history — the web's Stock tab.
// Needs the internet. Cashiers see it; receiving and counting are for managers (like the web).
class MartStock extends StatefulWidget {
  const MartStock({super.key});
  @override
  State<MartStock> createState() => _MartStockState();
}

class _MartStockState extends State<MartStock> {
  final pos = MartPos.i;
  J? _data;
  String _error = '', _filter = 'all', _q = '', _sort = 'name';
  final _search = TextEditingController();

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final r = jmap((await pos.api('GET', '/stock'))['data']);
      if (mounted) {
        setState(() {
          _data = r;
          _error = '';
        });
      }
    } on ApiError catch (e) {
      if (mounted) setState(() => _error = e.network ? tr(context)('rpos.needInternetShort') : e.message);
    }
  }

  String _unit(Object? id) {
    final u = jlist(pos.boot['units']).where((x) => js(x['_id']) == js(id)).firstOrNull;
    if (u == null) return '';
    return AppState.i.lang == 'km' ? (js(u['name_km']).isNotEmpty ? js(u['name_km']) : js(u['name_en'])) : (js(u['name_en']).isNotEmpty ? js(u['name_en']) : js(u['name_km']));
  }

  @override
  Widget build(BuildContext context) {
    final t = tr(context);
    final c = context.c;
    final cur = pos.currency;
    final d = _data;
    final canEdit = !pos.readOnly && pos.manager;
    final counts = jmap(d?['counts']);
    final q = _q.toLowerCase();
    double val(J p) => p['track_stock'] == true ? (nz(p['stock']) < 0 ? 0 : nz(p['stock'])) * nz(p['cost']) : 0;
    const order = {'out': 0, 'low': 1, 'ok': 2, 'off': 3};
    final rows = jlist(d?['rows']).where((p) => (_filter == 'all' || p['state'] == _filter) && (q.isEmpty || js(p['name']).toLowerCase().contains(q) || js(p['barcode']).contains(q))).toList();
    if (_sort == 'low') {
      rows.sort((a, b) {
        final x = (order[js(a['state'])] ?? 9).compareTo(order[js(b['state'])] ?? 9);
        return x != 0 ? x : nz(a['stock']).compareTo(nz(b['stock']));
      });
    } else if (_sort == 'value') {
      rows.sort((a, b) => val(b).compareTo(val(a)));
    } else {
      rows.sort((a, b) => js(a['name']).toLowerCase().compareTo(js(b['name']).toLowerCase()));
    }
    Widget card(String k, IconData icon, String n, String label, Color fg, Color bg) => Expanded(
      child: Material(
        color: _filter == k ? bg : c.card,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: k.isEmpty ? null : () => setState(() => _filter = k),
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: _filter == k ? fg : c.line),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(icon, size: 18, color: fg),
                const SizedBox(height: 4),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(n, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 18)),
                ),
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: c.muted, fontSize: 12),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(12, 4, 12, 24),
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(t('mart.tabs.stock'), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 18)),
                    Text(t('mart.stockSub'), maxLines: 2, style: TextStyle(color: c.muted, fontSize: 12.5)),
                  ],
                ),
              ),
              IconButton(onPressed: () => _history(context, null), icon: const Icon(LucideIcons.history), tooltip: t('mart.history')),
              if (canEdit) Btn(t('mart.receive'), icon: LucideIcons.packagePlus, small: true, onTap: d == null ? null : () => _receive(context, null)),
            ],
          ),
          const SizedBox(height: 10),
          if (_error.isNotEmpty)
            Alert(
              _error,
              tone: Tone.warn,
              action: TextButton(onPressed: _load, child: Text(t('rpos.retry'))),
            ),
          if (d == null && _error.isEmpty)
            const Padding(
              padding: EdgeInsets.all(40),
              child: Center(child: CircularProgressIndicator()),
            ),
          if (d != null) ...[
            Row(
              children: [
                card('all', LucideIcons.boxes, '${nz(counts['all']).toInt() - nz(counts['off']).toInt()}', t('mart.tracked'), c.brand, c.active),
                const SizedBox(width: 8),
                card('low', LucideIcons.triangleAlert, '${nz(counts['low']).toInt()}', t('mart.lowStock'), c.warn, c.warnBg),
                const SizedBox(width: 8),
                card('out', LucideIcons.packageX, '${nz(counts['out']).toInt()}', t('mart.outStock'), c.danger, c.dangerBg),
                if (wide(context)) ...[const SizedBox(width: 8), card('', LucideIcons.wallet, f.money(d['value'], cur), t('mart.stockValue'), c.good, c.goodBg)],
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: Field(controller: _search, hint: t('mart.search'), icon: LucideIcons.search, onChanged: (v) => setState(() => _q = v.trim())),
                ),
                const SizedBox(width: 8),
                PopupMenuButton<String>(
                  tooltip: t('mart.sortBy'),
                  icon: const Icon(LucideIcons.arrowDownUp),
                  initialValue: _sort,
                  onSelected: (v) => setState(() => _sort = v),
                  itemBuilder: (_) => [
                    PopupMenuItem(value: 'name', child: Text(t('mart.sortName'))),
                    PopupMenuItem(value: 'low', child: Text(t('mart.sortLow'))),
                    PopupMenuItem(value: 'value', child: Text(t('mart.sortValue'))),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 8),
            PosChips<String>(
              scroll: true,
              value: _filter,
              onTap: (v) => setState(() => _filter = v),
              options: [
                ('all', t('mart.allCats')),
                ('low', '${t('mart.lowStock')}${nz(counts['low']) > 0 ? ' ${nz(counts['low']).toInt()}' : ''}'),
                ('out', '${t('mart.outStock')}${nz(counts['out']) > 0 ? ' ${nz(counts['out']).toInt()}' : ''}'),
                ('off', t('mart.notTracked')),
              ],
            ),
            const SizedBox(height: 8),
            if (rows.isEmpty)
              Padding(
                padding: const EdgeInsets.all(24),
                child: Muted(t('mart.noProducts'), align: TextAlign.center),
              ),
            for (final p in rows) _row(context, p, canEdit),
          ],
        ],
      ),
    );
  }

  Widget _row(BuildContext context, J p, bool canEdit) {
    final t = tr(context);
    final c = context.c;
    final state = js(p['state']);
    final low = p['low_stock'] == null ? 5.0 : nz(p['low_stock']);
    final stock = nz(p['stock']);
    final photo = js(jmap(p['photo'])['url']);
    final (fg, bg) = switch (state) {
      'out' => (c.danger, c.dangerBg),
      'low' => (c.warn, c.warnBg),
      'ok' => (c.good, c.goodBg),
      _ => (c.muted, c.chip),
    };
    final pct = state == 'off' ? 0.0 : (stock / (low * 4 < 1 ? 1 : low * 4)).clamp(0, 1).toDouble();
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.fromLTRB(12, 10, 6, 10),
      decoration: BoxDecoration(color: c.card, borderRadius: BorderRadius.circular(16)),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(color: c.chip, borderRadius: BorderRadius.circular(12)),
            child: photo.isNotEmpty ? Image(image: netImage(photo), fit: BoxFit.cover, errorBuilder: (_, _, _) => const SizedBox()) : Icon(LucideIcons.package, size: 18, color: c.muted),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  js(p['name']),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                if (state != 'off') ...[
                  const SizedBox(height: 3),
                  Row(
                    children: [
                      Text(
                        '${qtyOf(stock)} ${_unit(p['unit_id'])}',
                        style: TextStyle(fontWeight: FontWeight.w800, color: fg),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(4),
                          child: LinearProgressIndicator(value: pct, minHeight: 6, color: fg, backgroundColor: c.chip),
                        ),
                      ),
                    ],
                  ),
                  Text(t('mart.lowAt', {'n': qtyOf(low)}), style: TextStyle(color: c.muted, fontSize: 11.5)),
                ] else
                  Text(js(p['barcode']).isEmpty ? '—' : js(p['barcode']), style: TextStyle(color: c.muted, fontSize: 12)),
              ],
            ),
          ),
          const SizedBox(width: 6),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(999)),
            child: Text(
              t({'ok': 'mart.okStock', 'low': 'mart.lowStock', 'out': 'mart.outStock'}[state] ?? 'mart.notTracked'),
              style: TextStyle(color: fg, fontSize: 11.5, fontWeight: FontWeight.w700),
            ),
          ),
          if (state != 'off')
            PopupMenuButton<String>(
              icon: const Icon(LucideIcons.ellipsisVertical, size: 18),
              onSelected: (v) => v == 'in' ? _receive(context, p) : (v == 'count' ? _count(context, p) : _history(context, p)),
              itemBuilder: (_) => [
                if (canEdit) PopupMenuItem(value: 'in', child: Text(t('mart.receive'))),
                if (canEdit) PopupMenuItem(value: 'count', child: Text(t('mart.countBtn'))),
                PopupMenuItem(value: 'history', child: Text(t('mart.history'))),
              ],
            ),
        ],
      ),
    );
  }

  // receive stock: products + qty (+ cost each, + expiry with that add-on)
  Future<void> _receive(BuildContext context, J? first) async {
    final t = tr(context);
    final cur = pos.currency;
    final products = jlist(_data?['rows']).where((p) => p['state'] != 'off').toList();
    final expOn = jmap(pos.boot['addons_on'])['mart_expiry'] == true;
    final lines = <J>[
      if (first != null) {'product_id': js(first['_id']), 'qty': TextEditingController(), 'cost': TextEditingController(text: nz(first['cost']) > 0 ? qtyOf(first['cost']) : ''), 'expires': ''},
    ];
    final find = TextEditingController();
    final note = TextEditingController();
    var busy = false;
    var error = '';
    String nameOf(String id) => js(products.where((p) => js(p['_id']) == id).firstOrNull?['name']);
    final done = await posSheet<bool>(
      context,
      title: t('mart.receive'),
      maxWidth: 640,
      body: (ctx) => StatefulBuilder(
        builder: (ctx, set) {
          final q = find.text.trim().toLowerCase();
          final exact = products.where((p) => js(p['barcode']) == find.text.trim()).toList();
          final found = q.isEmpty ? <J>[] : (exact.isNotEmpty ? exact : products.where((p) => js(p['name']).toLowerCase().contains(q) || js(p['barcode']).startsWith(q)).take(8).toList());
          void add(J p) => set(() {
            find.clear();
            if (!lines.any((l) => l['product_id'] == js(p['_id']))) {
              final focus = FocusNode();
              lines.add({'product_id': js(p['_id']), 'qty': TextEditingController(), 'cost': TextEditingController(text: nz(p['cost']) > 0 ? qtyOf(p['cost']) : ''), 'expires': '', 'focus': focus});
              WidgetsBinding.instance.addPostFrameCallback((_) => focus.requestFocus()); // type the qty next
            }
          });
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Field(
                controller: find,
                hint: t('mart.pickProduct'),
                icon: LucideIcons.search,
                autofocus: first == null,
                onChanged: (_) => set(() {}),
                onSubmit: (_) => found.isNotEmpty ? add(found.first) : null,
              ),
              for (final p in found) ListTile(dense: true, title: Text(js(p['name'])), subtitle: Text('${js(p['barcode'])} · ${qtyOf(p['stock'])}'), onTap: () => add(p)),
              const SizedBox(height: 8),
              for (var i = 0; i < lines.length; i++)
                Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  padding: const EdgeInsets.all(10),
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
                            child: Text(nameOf(js(lines[i]['product_id'])), style: const TextStyle(fontWeight: FontWeight.w700)),
                          ),
                          IconButton(
                            onPressed: () => set(() => lines.removeAt(i)),
                            icon: Icon(LucideIcons.trash2, size: 17, color: ctx.c.danger),
                          ),
                        ],
                      ),
                      Row(
                        children: [
                          Expanded(
                            child: Field(
                              label: t('mart.qtyIn'),
                              controller: lines[i]['qty'] as TextEditingController,
                              focusNode: lines[i]['focus'] as FocusNode?,
                              keyboard: const TextInputType.numberWithOptions(decimal: true),
                              autofocus: first != null && i == 0,
                              onChanged: (_) => set(() {}),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Field(
                              label: '${t('mart.costEach')} (${cur == 'KHR' ? '៛' : '\$'})',
                              controller: lines[i]['cost'] as TextEditingController,
                              keyboard: const TextInputType.numberWithOptions(decimal: true),
                            ),
                          ),
                        ],
                      ),
                      if (expOn) ...[
                        const SizedBox(height: 8),
                        OutlinedButton.icon(
                          onPressed: () async {
                            final now = DateTime.now();
                            final v = await showDatePicker(
                              context: ctx,
                              firstDate: now.subtract(const Duration(days: 30)),
                              lastDate: DateTime(now.year + 10),
                              initialDate: now.add(const Duration(days: 90)),
                            );
                            if (v != null) set(() => lines[i]['expires'] = '${v.year}-${v.month.toString().padLeft(2, '0')}-${v.day.toString().padLeft(2, '0')}');
                          },
                          icon: const Icon(LucideIcons.calendarClock, size: 16),
                          label: Text(js(lines[i]['expires']).isEmpty ? t('mx.expiryOpt') : js(lines[i]['expires'])),
                        ),
                      ],
                    ],
                  ),
                ),
              Field(label: t('mart.stockNote'), controller: note, maxLength: 200),
              if (error.isNotEmpty) ...[const SizedBox(height: 8), Alert(error)],
              const SizedBox(height: 12),
              Btn(
                busy ? t('mart.saving') : t('mart.save'),
                busy: busy,
                expand: true,
                onTap: busy || lines.isEmpty || !lines.every((l) => nz((l['qty'] as TextEditingController).text) > 0)
                    ? null
                    : () async {
                        set(() {
                          busy = true;
                          error = '';
                        });
                        try {
                          await pos.api('POST', '/stock/in', {
                            'items': [
                              for (final l in lines)
                                {
                                  'product_id': l['product_id'],
                                  'qty': nz((l['qty'] as TextEditingController).text),
                                  if ((l['cost'] as TextEditingController).text.trim().isNotEmpty) 'cost': nz((l['cost'] as TextEditingController).text),
                                  if (expOn && js(l['expires']).isNotEmpty) 'expires': l['expires'],
                                },
                            ],
                            'note': note.text.trim(),
                          });
                          if (ctx.mounted) Navigator.pop(ctx, true);
                        } on ApiError catch (e) {
                          set(() {
                            error = e.message;
                            busy = false;
                          });
                        }
                      },
              ),
            ],
          );
        },
      ),
    );
    if (done == true) {
      if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(t('mart.saved'))));
      _load();
      pos.syncNow();
    }
  }

  Future<void> _count(BuildContext context, J p) async {
    final t = tr(context);
    var value = qtyOf(p['stock']);
    final note = TextEditingController();
    var error = '';
    final done = await posSheet<bool>(
      context,
      title: '${t('mart.countTitle')} · ${js(p['name'])}',
      maxWidth: 420,
      body: (ctx) => StatefulBuilder(
        builder: (ctx, set) {
          final diff = ((nz(value) - nz(p['stock'])) * 1000).round() / 1000;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Muted('${t('mart.inStock')}: ${qtyOf(p['stock'])}'),
              const SizedBox(height: 8),
              Text(
                value.isEmpty ? '0' : value,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 34, fontWeight: FontWeight.w800),
              ),
              if (value.isNotEmpty && diff != 0)
                Text(
                  diff > 0 ? '+${qtyOf(diff)}' : qtyOf(diff),
                  textAlign: TextAlign.center,
                  style: TextStyle(color: diff < 0 ? ctx.c.danger : ctx.c.good, fontWeight: FontWeight.w800),
                ),
              const SizedBox(height: 8),
              Keypad(value: value, onChanged: (v) => set(() => value = v), dot: true, max: 9, keyHeight: 50),
              Field(label: t('mart.stockNote'), controller: note, maxLength: 200),
              if (error.isNotEmpty) ...[const SizedBox(height: 8), Alert(error)],
              const SizedBox(height: 12),
              Btn(
                t('mart.save'),
                expand: true,
                onTap: value.isEmpty
                    ? null
                    : () async {
                        try {
                          await pos.api('POST', '/stock/count', {'product_id': p['_id'], 'count': nz(value), 'note': note.text.trim()});
                          if (ctx.mounted) Navigator.pop(ctx, true);
                        } on ApiError catch (e) {
                          set(() => error = e.message);
                        }
                      },
              ),
            ],
          );
        },
      ),
    );
    if (done == true) {
      _load();
      pos.syncNow();
    }
  }

  Future<void> _history(BuildContext context, J? p) async {
    final t = tr(context);
    await posSheet(
      context,
      title: '${t('mart.history')}${p != null ? ' · ${js(p['name'])}' : ''}',
      maxWidth: 640,
      body: (ctx) => FutureBuilder<J>(
        future: pos.api('GET', '/stock/moves${p != null ? '?product_id=${p['_id']}' : ''}'),
        builder: (ctx, snap) {
          if (snap.hasError) return Alert(snap.error is ApiError ? (snap.error as ApiError).message : '${snap.error}');
          if (!snap.hasData) {
            return const Padding(
              padding: EdgeInsets.all(30),
              child: Center(child: CircularProgressIndicator()),
            );
          }
          final rows = jlist(snap.data!['data']);
          if (rows.isEmpty) return Muted(t('mart.noMoves'));
          return Column(
            children: [
              for (final x in rows)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Chip2(t.or('mart.moveKinds.${x['kind']}', js(x['kind'])), tone: nz(x['qty']) < 0 ? Tone.danger : Tone.good),
                  title: Text(js(x['name']), style: const TextStyle(fontWeight: FontWeight.w700)),
                  subtitle: Text(
                    [f.fmtDate(x['created_date'], time: true, lang: AppState.i.lang), js(x['by']), js(x['sale_no']), js(x['note'])].where((s) => s.isNotEmpty).join(' · '),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  trailing: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        nz(x['qty']) > 0 ? '+${qtyOf(x['qty'])}' : qtyOf(x['qty']),
                        style: TextStyle(fontWeight: FontWeight.w800, color: nz(x['qty']) < 0 ? ctx.c.danger : ctx.c.good),
                      ),
                      Text('→ ${qtyOf(x['stock_after'])}', style: TextStyle(color: ctx.c.muted, fontSize: 12)),
                    ],
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}
