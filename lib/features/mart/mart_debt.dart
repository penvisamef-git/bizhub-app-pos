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
import 'mart_receipt.dart' show methodLabel;

// Debt book (mart_debt): who owes what, repayments at the counter, history — the web's Debt tab.
// The list also works offline (the copy on this device); repaying and history need the internet.
class MartDebt extends StatefulWidget {
  const MartDebt({super.key});
  @override
  State<MartDebt> createState() => _MartDebtState();
}

class _MartDebtState extends State<MartDebt> {
  final pos = MartPos.i;
  J? _data;
  String _error = '';
  final _q = TextEditingController();
  Timer? _deb;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _deb?.cancel();
    _q.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final r = await pos.debtors(_q.text.trim());
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

  @override
  Widget build(BuildContext context) {
    final t = tr(context);
    final c = context.c;
    final cur = pos.currency;
    final d = _data;
    final tot = jmap(d?['totals']);
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
                    Text(t('mart.tabs.debt'), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 18)),
                    Text(t('mart.debtSub'), maxLines: 2, style: TextStyle(color: c.muted, fontSize: 12.5)),
                  ],
                ),
              ),
              if (d?['offline'] == true) Chip2(t('mpos.offline'), tone: Tone.warn, icon: LucideIcons.cloudOff),
              const SizedBox(width: 6),
              Btn(t('mart.addDebtor'), icon: LucideIcons.plus, small: true, onTap: pos.readOnly || d == null ? null : () => _edit(context, null)),
            ],
          ),
          const SizedBox(height: 10),
          if (_error.isNotEmpty)
            Alert(
              _error,
              tone: Tone.warn,
              action: TextButton(onPressed: _load, child: Text(t('rpos.retry'))),
            ),
          if (d != null) ...[
            Row(
              children: [
                Expanded(
                  child: _Box(icon: LucideIcons.wallet, value: f.money(tot['owed'], cur), label: t('mart.totalOwed'), fg: c.danger),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _Box(icon: LucideIcons.userRound, value: '${nz(tot['people']).toInt()}', label: t('mart.debtPeople'), fg: c.brand),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Field(
              controller: _q,
              hint: t('mart.debtSearch'),
              icon: LucideIcons.search,
              onChanged: (_) {
                _deb?.cancel();
                _deb = Timer(const Duration(milliseconds: 300), _load);
              },
            ),
            const SizedBox(height: 8),
            if (jlist(d['rows']).isEmpty)
              Padding(
                padding: const EdgeInsets.all(24),
                child: Muted(t('mart.noDebtors'), align: TextAlign.center),
              ),
            for (final x in jlist(d['rows']))
              Container(
                margin: const EdgeInsets.only(bottom: 6),
                padding: const EdgeInsets.fromLTRB(12, 8, 6, 8),
                decoration: BoxDecoration(color: c.card, borderRadius: BorderRadius.circular(16)),
                child: Row(
                  children: [
                    CircleAvatar(
                      backgroundColor: c.active,
                      child: Icon(LucideIcons.userRound, size: 18, color: c.brandInk),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(js(x['name']), style: const TextStyle(fontWeight: FontWeight.w700)),
                          if (js(x['phone']).isNotEmpty || js(x['note']).isNotEmpty)
                            InkWell(
                              onTap: js(x['phone']).isEmpty ? null : () => launchUrl(Uri.parse('tel:${js(x['phone']).replaceAll(' ', '')}')),
                              child: Text([js(x['phone']), js(x['note'])].where((s) => s.isNotEmpty).join(' · '), style: TextStyle(color: c.muted, fontSize: 12.5)),
                            ),
                        ],
                      ),
                    ),
                    nz(x['balance']) > 0
                        ? Text(
                            f.money(x['balance'], cur),
                            style: TextStyle(color: c.danger, fontWeight: FontWeight.w800),
                          )
                        : Chip2(t('mart.clear2'), tone: Tone.good),
                    if (nz(x['balance']) > 0 && !pos.readOnly)
                      IconButton(
                        onPressed: () => _repay(context, x),
                        icon: Icon(LucideIcons.handCoins, color: c.good),
                        tooltip: t('mart.repay'),
                      ),
                    PopupMenuButton<String>(
                      icon: const Icon(LucideIcons.ellipsisVertical, size: 18),
                      onSelected: (v) => v == 'edit' ? _edit(context, x) : _history(context, x),
                      itemBuilder: (_) => [if (!pos.readOnly) PopupMenuItem(value: 'edit', child: Text(t('mart.editDebtor'))), PopupMenuItem(value: 'history', child: Text(t('mart.debtHistory')))],
                    ),
                  ],
                ),
              ),
          ] else if (_error.isEmpty)
            const Padding(
              padding: EdgeInsets.all(40),
              child: Center(child: CircularProgressIndicator()),
            ),
        ],
      ),
    );
  }

  Future<void> _edit(BuildContext context, J? row) async {
    final t = tr(context);
    final isNew = row == null;
    final name = TextEditingController(text: js(row?['name'])), phone = TextEditingController(text: js(row?['phone'])), note = TextEditingController(text: js(row?['note']));
    var error = '';
    final ok = await posSheet<bool>(
      context,
      title: isNew ? t('mart.addDebtor') : t('mart.editDebtor'),
      maxWidth: 460,
      body: (ctx) => StatefulBuilder(
        builder: (ctx, set) => Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Field(label: t('mart.debtorName'), controller: name, maxLength: 80, autofocus: true, onChanged: (_) => set(() {})),
            const SizedBox(height: 10),
            Field(label: t('mart.phone'), controller: phone, maxLength: 30, keyboard: TextInputType.phone),
            const SizedBox(height: 10),
            Field(label: t('mart.debtNote'), controller: note, maxLength: 200),
            if (error.isNotEmpty) ...[const SizedBox(height: 8), Alert(error)],
            const SizedBox(height: 12),
            Row(
              children: [
                if (!isNew && pos.manager) ...[
                  Expanded(
                    child: Btn(
                      t('mart.remove'),
                      icon: LucideIcons.trash2,
                      kind: BtnKind.danger,
                      onTap: () async {
                        try {
                          await pos.api('DELETE', '/debtors/${row['_id']}');
                          if (ctx.mounted) Navigator.pop(ctx, true);
                        } on ApiError catch (e) {
                          set(() => error = e.message);
                        }
                      },
                    ),
                  ),
                  const SizedBox(width: 8),
                ],
                Expanded(
                  child: Btn(
                    t('mart.save'),
                    onTap: name.text.trim().isEmpty
                        ? null
                        : () async {
                            final body = {'name': name.text.trim(), 'phone': phone.text.trim(), 'note': note.text.trim()};
                            try {
                              await (isNew ? pos.api('POST', '/debtors', body) : pos.api('PUT', '/debtors/${row['_id']}', body));
                              if (ctx.mounted) Navigator.pop(ctx, true);
                            } on ApiError catch (e) {
                              set(() => error = e.network ? t('rpos.needInternetShort') : e.message);
                            }
                          },
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
    if (ok == true) {
      _load();
      pos.syncNow();
    }
  }

  Future<void> _repay(BuildContext context, J d) async {
    final t = tr(context);
    final cur = pos.currency;
    final raw = pos.settings['methods'] is List ? (pos.settings['methods'] as List).map((e) => '$e').where((k) => k != 'debt').toList() : <String>[];
    final methods = raw.isEmpty ? ['cash'] : raw;
    var method = methods.first;
    var amount = '';
    final note = TextEditingController();
    var error = '';
    var busy = false;
    final ok = await posSheet<bool>(
      context,
      title: t('mart.repayTitle', {'name': js(d['name'])}),
      maxWidth: 440,
      body: (ctx) => StatefulBuilder(
        builder: (ctx, set) {
          final v = nz(amount);
          final good = v > 0 && v <= nz(d['balance']) + 0.005;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text.rich(
                TextSpan(
                  children: [
                    TextSpan(text: '${t('mart.owes')}: '),
                    TextSpan(
                      text: f.money(d['balance'], cur),
                      style: TextStyle(color: ctx.c.danger, fontWeight: FontWeight.w800),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              Text(
                f.money(v, cur),
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 34, fontWeight: FontWeight.w800),
              ),
              Center(
                child: ActionChip(label: Text('${t('mart.repayAll')} · ${f.money(d['balance'], cur)}'), onPressed: () => set(() => amount = '${nz(d['balance'])}')),
              ),
              const SizedBox(height: 6),
              Keypad(value: amount, onChanged: (x) => set(() => amount = x), dot: cur == 'USD', max: 10, keyHeight: 48),
              Text(t('mart.colPay'), style: const TextStyle(fontWeight: FontWeight.w700)),
              const SizedBox(height: 6),
              PosChips<String>(value: method, onTap: (x) => set(() => method = x), options: [for (final k in methods) (k, methodLabel(AppState.i.t, pos.settings, k))]),
              const SizedBox(height: 10),
              Field(label: t('mart.debtNote'), controller: note, maxLength: 200),
              if (error.isNotEmpty) ...[const SizedBox(height: 8), Alert(error)],
              const SizedBox(height: 12),
              Btn(
                '${t('mart.repay')}${good ? ' · ${f.money(v, cur)}' : ''}',
                icon: LucideIcons.handCoins,
                busy: busy,
                expand: true,
                onTap: !good || busy
                    ? null
                    : () async {
                        set(() => busy = true);
                        try {
                          await pos.api('POST', '/debtors/${d['_id']}/payments', {'amount': v, 'method': method, 'note': note.text.trim()});
                          if (ctx.mounted) Navigator.pop(ctx, true);
                        } on ApiError catch (e) {
                          set(() {
                            error = e.network ? t('rpos.needInternetShort') : e.message;
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
    if (ok == true) {
      if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(t('mart.saved'))));
      _load();
      pos.syncNow();
    }
  }

  Future<void> _history(BuildContext context, J d) async {
    final t = tr(context);
    final cur = pos.currency;
    await posSheet(
      context,
      title: '${t('mart.debtHistory')} · ${js(d['name'])}',
      maxWidth: 600,
      body: (ctx) => FutureBuilder<J>(
        future: pos.api('GET', '/debtors/${d['_id']}'),
        builder: (ctx, snap) {
          if (snap.hasError) return Alert(snap.error is ApiError && (snap.error as ApiError).network ? t('rpos.needInternetShort') : '${snap.error}');
          if (!snap.hasData) {
            return const Padding(
              padding: EdgeInsets.all(30),
              child: Center(child: CircularProgressIndicator()),
            );
          }
          final row = jmap(snap.data!['data']);
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SumRow(t('mart.owes'), f.money(row['balance'], cur), big: true, color: nz(row['balance']) > 0 ? ctx.c.danger : ctx.c.good),
              const SizedBox(height: 6),
              for (final x in jlist(row['txs']))
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Chip2(t.or('mart.debtKinds.${x['kind']}', js(x['kind'])), tone: x['kind'] == 'payment' ? Tone.good : (x['kind'] == 'sale' ? Tone.warn : Tone.muted)),
                  title: Text(
                    '${js(x['sale_no']).isNotEmpty ? js(x['sale_no']) : t.or('mart.debtKinds.${x['kind']}', js(x['kind']))}${js(x['method']).isNotEmpty ? ' · ${methodLabel(t, pos.settings, js(x['method']))}' : ''}',
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  subtitle: Text([f.fmtDate(x['created_date'], time: true, lang: AppState.i.lang), js(x['by']), js(x['note'])].where((s) => s.isNotEmpty).join(' · ')),
                  trailing: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        nz(x['amount']) > 0 ? '+${f.money(x['amount'], cur)}' : '−${f.money(-nz(x['amount']), cur)}',
                        style: TextStyle(fontWeight: FontWeight.w800, color: nz(x['amount']) > 0 ? ctx.c.danger : ctx.c.good),
                      ),
                      Text('→ ${f.money(x['balance_after'], cur)}', style: TextStyle(color: ctx.c.muted, fontSize: 12)),
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

class _Box extends StatelessWidget {
  final IconData icon;
  final String value, label;
  final Color fg;
  const _Box({required this.icon, required this.value, required this.label, required this.fg});
  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: c.card, borderRadius: BorderRadius.circular(16)),
      child: Row(
        children: [
          Icon(icon, color: fg),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    value,
                    style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18, color: fg),
                  ),
                ),
                Text(label, style: TextStyle(color: c.muted, fontSize: 12)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
