import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/api.dart' show ApiError;
import '../../core/format.dart' as f;
import '../../core/theme.dart';
import '../../widgets/ui.dart';
import '../restaurant/engine/calc.dart' show J, jmap, js, nz;
import '../restaurant/pos_ui.dart';
import 'engine/mart_pos.dart';
import 'mart_receipt.dart';

// Today's receipts: totals, by payment, every sale (reprint · void for a manager)
class MartSales extends StatefulWidget {
  const MartSales({super.key});
  @override
  State<MartSales> createState() => _MartSalesState();
}

class _MartSalesState extends State<MartSales> {
  final pos = MartPos.i;
  ({List<J> rows, J totals, bool offline})? _data;
  String _error = '';
  bool _loading = false;
  String _q = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = '';
    });
    try {
      final d = await pos.sales();
      if (mounted) setState(() => _data = d);
    } on ApiError catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = tr(context);
    final c = context.c;
    final cur = pos.currency;
    final d = _data;
    final tot = d?.totals ?? const {};
    final rows = (d?.rows ?? const <J>[]).where((x) => _q.isEmpty || '${x['no']} ${x['by'] ?? ''} ${x['member_phone'] ?? ''}'.toLowerCase().contains(_q)).toList();
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(12, 4, 12, 24),
        children: [
          Row(
            children: [
              Expanded(
                child: Text(t('mart.todaySales'), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 18)),
              ),
              if (d?.offline == true) Chip2(t('mpos.offline'), tone: Tone.warn, icon: LucideIcons.cloudOff),
              IconButton(onPressed: _loading ? null : _load, icon: const Icon(LucideIcons.refreshCw), tooltip: t('mpos.syncNow')),
            ],
          ),
          if (_error.isNotEmpty) Alert(_error),
          if (d != null) ...[
            Row(
              children: [
                Expanded(child: _Kpi(t('mpos.salesTotal'), f.money(tot['sales'], cur), main: true)),
                const SizedBox(width: 8),
                Expanded(child: _Kpi(t('mpos.receipts'), '${nz(tot['count']).toInt()}')),
                const SizedBox(width: 8),
                Expanded(child: _Kpi(t('mart.voids'), '${nz(tot['voids']).toInt()}')),
              ],
            ),
            const SizedBox(height: 10),
            if (jmap(tot['by_method']).isNotEmpty)
              Panel(
                padding: const EdgeInsets.all(14),
                margin: const EdgeInsets.only(bottom: 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(t('mart.byMethod'), style: const TextStyle(fontWeight: FontWeight.w800)),
                    const SizedBox(height: 4),
                    for (final e in jmap(tot['by_method']).entries) SumRow(methodLabel(t, pos.settings, e.key), f.money(e.value, cur)),
                  ],
                ),
              ),
            TextField(
              onChanged: (v) => setState(() => _q = v.trim().toLowerCase()),
              decoration: InputDecoration(
                hintText: t('mp.searchSales'),
                prefixIcon: Icon(LucideIcons.search, color: c.muted),
                isDense: true,
                filled: true,
                fillColor: c.card,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide(color: c.line),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide(color: c.line),
                ),
              ),
            ),
            const SizedBox(height: 8),
            if (rows.isEmpty)
              Padding(
                padding: const EdgeInsets.all(24),
                child: Muted(t('mart.noSales'), align: TextAlign.center),
              ),
            for (final s in rows) _SaleRow(s, onTap: () => _open(context, s)),
          ] else if (_loading)
            const Padding(
              padding: EdgeInsets.all(40),
              child: Center(child: CircularProgressIndicator()),
            ),
        ],
      ),
    );
  }

  Future<void> _open(BuildContext context, J sale) async {
    final t = tr(context);
    final doc = await MartPrint.doc(sale);
    if (!context.mounted) return;
    final canVoid = pos.manager && sale['status'] == 'paid';
    await posSheet(
      context,
      title: '${t('mart.receipt')} · ${js(sale['no'])}',
      maxWidth: 460,
      body: (ctx) => Center(
        child: Container(
          width: 300,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(6),
            boxShadow: const [BoxShadow(color: Color(0x22000000), blurRadius: 12, offset: Offset(0, 4))],
          ),
          child: DefaultTextStyle(
            style: const TextStyle(fontFamily: 'PlusJakartaSans', fontFamilyFallback: ['KantumruyPro'], color: Colors.black, fontSize: 13, height: 1.3),
            child: doc,
          ),
        ),
      ),
      footer: (ctx) => Row(
        children: [
          if (canVoid) ...[
            Expanded(
              child: Btn(
                t('mart.voidBtn'),
                icon: LucideIcons.ban,
                kind: BtnKind.danger,
                onTap: () async {
                  Navigator.pop(ctx);
                  await _void(context, sale);
                },
              ),
            ),
            const SizedBox(width: 8),
          ],
          Expanded(
            child: Btn(
              t('mpos.print'),
              icon: LucideIcons.printer,
              onTap: () async {
                final bar = ScaffoldMessenger.of(ctx);
                await MartPrint.load();
                if (!MartPrint.printer.on) {
                  if (ctx.mounted) Navigator.pop(ctx);
                  if (context.mounted) openMartPrinters(context);
                  return;
                }
                try {
                  await MartPrint.receipt(sale);
                } catch (e) {
                  bar.showSnackBar(SnackBar(content: Text('${t('rp.failed')} ${martPrintError(e)}')));
                }
              },
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _void(BuildContext context, J sale) async {
    final t = tr(context);
    final reason = TextEditingController();
    final ok = await posSheet<bool>(
      context,
      title: t('mart.voidTitle'),
      maxWidth: 420,
      body: (ctx) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Muted(t('mart.voidSub')),
          const SizedBox(height: 12),
          Field(controller: reason, hint: t('mart.voidReason'), maxLength: 200, autofocus: true),
        ],
      ),
      footer: (ctx) => Btn(t('mart.voidBtn'), icon: LucideIcons.ban, kind: BtnKind.danger, expand: true, onTap: () => Navigator.pop(ctx, true)),
    );
    if (ok != true) return;
    try {
      await pos.voidSale(js(sale['_id']), reason.text.trim());
      await _load();
    } on ApiError catch (e) {
      if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    }
  }
}

class _Kpi extends StatelessWidget {
  final String label, value;
  final bool main;
  const _Kpi(this.label, this.value, {this.main = false});
  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(gradient: main ? c.gradient : null, color: main ? null : c.card, borderRadius: BorderRadius.circular(16), boxShadow: main ? null : c.cardShadow),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(color: main ? Colors.white : c.muted, fontSize: 12.5, fontWeight: FontWeight.w600),
          ),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              value,
              style: TextStyle(color: main ? Colors.white : c.ink, fontSize: 20, fontWeight: FontWeight.w800),
            ),
          ),
        ],
      ),
    );
  }
}

class _SaleRow extends StatelessWidget {
  final J s;
  final VoidCallback onTap;
  const _SaleRow(this.s, {required this.onTap});
  @override
  Widget build(BuildContext context) {
    final t = tr(context);
    final c = context.c;
    final pos = MartPos.i;
    final voided = s['status'] == 'void';
    final when = DateTime.tryParse(js(s['at']))?.toUtc().add(const Duration(hours: 7));
    final hm = when == null ? '' : '${when.hour.toString().padLeft(2, '0')}:${when.minute.toString().padLeft(2, '0')}';
    return Card(
      margin: const EdgeInsets.only(bottom: 6),
      elevation: 0,
      color: c.card,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: ListTile(
        onTap: onTap,
        leading: Icon(voided ? LucideIcons.ban : (s['pending'] == true ? LucideIcons.cloudUpload : LucideIcons.receiptText), color: voided ? c.danger : (s['pending'] == true ? c.warn : c.brand)),
        title: Text(
          '${js(s['no'])} · $hm',
          style: TextStyle(fontWeight: FontWeight.w700, decoration: voided ? TextDecoration.lineThrough : null),
        ),
        subtitle: Text(
          '${methodLabel(t, pos.settings, js(s['method']), js(s['method_name']))} · ${js(s['by'])}${voided ? ' · ${t('mart.voided')}' : ''}',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        trailing: Text(
          f.money(s['total'], js(s['currency']).isEmpty ? pos.currency : js(s['currency'])),
          style: TextStyle(fontWeight: FontWeight.w800, color: voided ? c.muted : c.ink),
        ),
      ),
    );
  }
}
