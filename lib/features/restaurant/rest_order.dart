import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/app_state.dart';
import '../../core/theme.dart';
import '../../widgets/ui.dart';
import 'engine/calc.dart';
import 'engine/rest_pos.dart';
import 'pos_ui.dart';
import 'rest_member.dart';
import 'rest_pay.dart';
import 'rest_print.dart';

String lineName(J l, String lang) {
  final en = js(l['name_en']), km = js(l['name_km']);
  return lang != 'km' && en.isNotEmpty ? en : (km.isNotEmpty ? km : en);
}

// One order: the menu on the left, the ticket on the right (a phone switches between them with two tabs).
class OrderPage extends StatefulWidget {
  final String? orderId;
  final J? table; // new dine-in order for this table (null + no orderId = takeaway)
  const OrderPage({super.key, this.orderId, this.table});
  @override
  State<OrderPage> createState() => _OrderPageState();
}

class _OrderPageState extends State<OrderPage> {
  String? _id;
  String _cat = '';
  final _q = TextEditingController();
  bool _ticketTab = false;
  bool _paying = false;
  bool _closing = false;
  final pos = RestPos.i;

  @override
  void initState() {
    super.initState();
    _id = widget.orderId;
    pos.addListener(_watch);
  }

  @override
  void dispose() {
    pos.removeListener(_watch);
    _q.dispose();
    super.dispose();
  }

  J? get order => _id == null ? null : pos.orders[_id];

  // paid / cancelled on another device, staff locked, shift closed → leave
  void _watch() {
    if (_closing || !mounted) return;
    final o = order;
    final gone = (o != null && o['status'] != 'open' && !_paying) || pos.staff == null || pos.openShift == null || pos.setup == null;
    if (gone) _leave();
  }

  void _leave() {
    if (_closing) return;
    _closing = true;
    Navigator.of(context).popUntil((r) => r.isFirst);
  }

  Future<String> _ensure() async {
    if (_id != null) return _id!;
    final o = await pos.newOrder(table: widget.table, type: widget.table != null ? 'dine_in' : 'takeaway');
    setState(() => _id = js(o['_id']));
    return _id!;
  }

  Future<void> _add(J item, {J? size, List<J> addons = const [], int qty = 1, String note = ''}) async {
    final id = await _ensure();
    await pos.addLine(id, item: item, size: size, addons: addons, qty: qty, note: note);
  }

  void _tap(J i) {
    if (i['available'] == false || pos.blockedReason.isNotEmpty) return;
    final left = pos.stockLeft(i);
    if (left != null && left <= 0) return;
    if (jlist(i['sizes']).isNotEmpty || (i['addon_group_ids'] is List && (i['addon_group_ids'] as List).isNotEmpty)) {
      showItemSheet(context, i, onAdd: _add);
    } else {
      _add(i);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: pos,
      builder: (context, _) {
        final c = context.c;
        final big = wide(context);
        final menu = _menu(context);
        final ticket = _ticket(context);
        return PopScope(
          canPop: true,
          child: Scaffold(
            backgroundColor: c.appBg,
            body: SafeArea(
              child: big
                  ? Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Expanded(child: menu),
                        Container(
                          width: 400,
                          margin: const EdgeInsets.fromLTRB(0, 10, 12, 12),
                          decoration: BoxDecoration(color: c.card, borderRadius: BorderRadius.circular(24), boxShadow: c.cardShadow),
                          clipBehavior: Clip.antiAlias,
                          child: ticket,
                        ),
                      ],
                    )
                  : (_ticketTab ? ticket : menu),
            ),
            bottomNavigationBar: big ? null : _phoneBar(context),
          ),
        );
      },
    );
  }

  Widget _phoneBar(BuildContext context) {
    final t = tr(context);
    final c = context.c;
    final o = order;
    final tot = o == null ? null : pos.totals(o);
    final n = o == null ? 0 : jlist(o['lines']).where((l) => l['status'] != 'void').length;
    Widget tab(bool on, String label, IconData icon, VoidCallback onTap) => Expanded(
      child: Material(
        color: on ? c.solid : c.card,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onTap,
          child: SizedBox(
            height: 52,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, size: 18, color: on ? c.onSolid : c.ink),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    label,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontWeight: FontWeight.w800, color: on ? c.onSolid : c.ink),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    return Container(
      padding: EdgeInsets.fromLTRB(12, 8, 12, 8 + MediaQuery.paddingOf(context).bottom),
      decoration: BoxDecoration(
        color: c.appBg,
        border: Border(top: BorderSide(color: c.line)),
      ),
      child: Row(
        children: [
          tab(!_ticketTab, t('rpos.menu'), LucideIcons.utensilsCrossed, () => setState(() => _ticketTab = false)),
          const SizedBox(width: 8),
          tab(_ticketTab, '${t('rpos.order')}${tot != null ? ' · ${m$(tot.total, pos.currency)}' : ''}${n > 0 ? ' ($n)' : ''}', LucideIcons.receipt, () => setState(() => _ticketTab = true)),
        ],
      ),
    );
  }

  // ---------- menu ----------
  Widget _menu(BuildContext context) {
    final app = AppScope.of(context);
    final t = app.t;
    final c = context.c;
    final items = pos.items;
    final cats = pos.categories.where((x) => items.any((i) => js(i['category_id']) == js(x['_id']))).toList();
    final q = _q.text.trim().toLowerCase();
    final shown = items.where((i) => (_cat.isEmpty || js(i['category_id']) == _cat) && (q.isEmpty || '${i['name_en']} ${i['name_km']} ${i['code'] ?? ''}'.toLowerCase().contains(q))).toList();
    final disabled = pos.blockedReason.isNotEmpty;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 8, 12, 8),
          child: Row(
            children: [
              IconButton(onPressed: _leave, icon: const Icon(LucideIcons.arrowLeft), tooltip: t('rpos.back')),
              Expanded(
                child: TextField(
                  controller: _q,
                  onChanged: (_) => setState(() {}),
                  decoration: InputDecoration(
                    hintText: t('rpos.search'),
                    prefixIcon: Icon(LucideIcons.search, size: 18, color: c.muted),
                    suffixIcon: q.isEmpty ? null : IconButton(onPressed: () => setState(_q.clear), icon: const Icon(LucideIcons.x, size: 16), tooltip: t('rpos.clear')),
                    isDense: true,
                    filled: true,
                    fillColor: c.card,
                    contentPadding: const EdgeInsets.symmetric(vertical: 12),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(999),
                      borderSide: BorderSide(color: c.line),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(999),
                      borderSide: BorderSide(color: c.line),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
          child: PosChips<String>(scroll: true, value: _cat, onTap: (v) => setState(() => _cat = v), options: [('', t('rpos.all')), for (final x in cats) (js(x['_id']), nameOf(x, app.lang))]),
        ),
        Expanded(
          child: GridView.builder(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 16),
            gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(maxCrossAxisExtent: 180, mainAxisExtent: 196, crossAxisSpacing: 10, mainAxisSpacing: 10),
            itemCount: shown.length,
            itemBuilder: (context, k) => _ItemCard(item: shown[k], disabled: disabled, onTap: () => _tap(shown[k])),
          ),
        ),
      ],
    );
  }

  // ---------- ticket ----------
  Widget _ticket(BuildContext context) {
    final app = AppScope.of(context);
    final t = app.t;
    final c = context.c;
    final o = order;
    final cur = pos.currency;
    final tot = o == null ? null : pos.totals(o);
    final lines = o == null ? <J>[] : jlist(o['lines']).where((l) => l['void_reason'] != 'removed').toList();
    final hasNew = lines.any((l) => l['status'] == 'new');
    final disabled = pos.blockedReason.isNotEmpty;
    final tableName = js(o?['table_name']).isNotEmpty ? js(o?['table_name']) : js(widget.table?['name']);
    final photo = {for (final i in pos.items) js(i['_id']): js(i['photo'])};
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 6, 6),
          child: Row(
            children: [
              if (!wide(context)) IconButton(onPressed: _leave, icon: const Icon(LucideIcons.arrowLeft), tooltip: t('rpos.back')),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(tableName.isNotEmpty ? '${t('rpos.table')} $tableName' : t('rpos.takeaway'), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 18)),
                    Text(o != null ? '#${js(o['number'])} · ${js(jmap(o['opened_by'])['name'])}' : js(pos.staff?['name']), style: TextStyle(color: c.muted, fontSize: 12.5)),
                  ],
                ),
              ),
              if (pos.rewardsRules != null)
                IconButton(
                  onPressed: disabled ? null : () => showMemberSheet(context, orderId: () => _id, ensureOrder: _ensure),
                  icon: Icon(LucideIcons.star, color: js(jmap(o?['member'])['id']).isNotEmpty ? c.brand : c.ink),
                  tooltip: t('rpos.member'),
                ),
              IconButton(
                onPressed: disabled ? null : () => _noteSheet(context),
                icon: Icon(LucideIcons.stickyNote, color: js(o?['note']).isNotEmpty ? c.brand : c.ink),
                tooltip: t('rpos.tableNote'),
              ),
              if (o != null) IconButton(onPressed: disabled ? null : () => _moreSheet(context), icon: const Icon(LucideIcons.ellipsis), tooltip: t('rpos.more')),
            ],
          ),
        ),
        if (pos.rewardsRules != null && js(jmap(o?['member'])['id']).isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 6),
            child: Material(
              color: c.active,
              borderRadius: BorderRadius.circular(12),
              child: InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: () => showMemberSheet(context, orderId: () => _id, ensureOrder: _ensure),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  child: Row(
                    children: [
                      Icon(LucideIcons.star, size: 15, color: c.brandInk),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          '${js(jmap(o!['member'])['name']).isNotEmpty ? js(jmap(o['member'])['name']) : js(jmap(o['member'])['phone'])} · ${js(jmap(o['member'])['phone'])}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(color: c.brandInk, fontWeight: FontWeight.w700),
                        ),
                      ),
                      if (pos.pointsFor(o) > 0)
                        Text(
                          t('rpos.earnThisBill', {'n': pos.pointsFor(o)}),
                          style: TextStyle(color: c.good, fontWeight: FontWeight.w700, fontSize: 12.5),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        if (js(o?['note']).isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 6),
            child: Material(
              color: c.warnBg,
              borderRadius: BorderRadius.circular(12),
              child: InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: () => _noteSheet(context),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  child: Text(
                    '📝 ${js(o!['note'])}',
                    style: TextStyle(color: c.warn, fontWeight: FontWeight.w600),
                  ),
                ),
              ),
            ),
          ),
        Divider(height: 1, color: c.line),
        Expanded(
          child: lines.isEmpty
              ? Center(child: Muted(t('rpos.emptyTicket')))
              : ListView.separated(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  itemCount: lines.length,
                  separatorBuilder: (_, _) => Divider(height: 1, indent: 16, endIndent: 16, color: c.line),
                  itemBuilder: (context, k) => _LineRow(
                    line: lines[k],
                    photo: photo[js(lines[k]['item_id'])] ?? '',
                    currency: cur,
                    onTap: disabled || lines[k]['status'] == 'void' ? null : () => _lineSheet(context, js(lines[k]['id'])),
                  ),
                ),
        ),
        if (o != null && tot != null)
          Container(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 4),
            decoration: BoxDecoration(
              border: Border(top: BorderSide(color: c.line)),
            ),
            child: Column(
              children: [
                SumRow(t('rpos.subtotal'), m$(tot.subtotal, cur)),
                if (tot.itemDiscount > 0) SumRow(t('rpos.itemDiscounts'), '−${m$(tot.itemDiscount, cur)}', color: c.good),
                if (tot.rewardDiscount > 0)
                  SumRow('★ ${js(jmap(o['reward_discount'])['name']).isEmpty ? t('rpos.reward') : js(jmap(o['reward_discount'])['name'])}', '−${m$(tot.rewardDiscount, cur)}', color: c.good),
                if (tot.billDiscount > 0)
                  SumRow('${t('rpos.discount')}${jmap(o['discount'])['kind'] == 'percent' ? ' ${_n(jmap(o['discount'])['value'])}%' : ''}', '−${m$(tot.billDiscount, cur)}', color: c.good),
                if (tot.service > 0) SumRow(t('rpos.service'), m$(tot.service, cur)),
                if (tot.vat > 0) SumRow(tot.vatIncluded ? t('rpos.vatIncl') : t('rpos.vat'), m$(tot.vat, cur)),
                const SizedBox(height: 4),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Expanded(
                      child: Text(t('rpos.total'), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 20)),
                    ),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(m$(tot.total, cur), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 22)),
                        Text(
                          m$(tot.other, other(cur)),
                          style: TextStyle(color: c.muted, fontSize: 12.5, fontWeight: FontWeight.w600),
                        ),
                      ],
                    ),
                  ],
                ),
              ],
            ),
          ),
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
          child: Row(
            children: [
              if (!pos.payFirst) ...[
                Expanded(
                  flex: 2, // "Pay $17.00" needs the wider part (the bill is narrow on a tablet too)
                  child: Btn(
                    t('rpos.send'),
                    icon: LucideIcons.send,
                    kind: BtnKind.ghost,
                    onTap: o == null || !hasNew || disabled
                        ? null
                        : () async {
                            final bar = ScaffoldMessenger.of(context);
                            final fresh = jlist(o['lines']).where((l) => l['status'] == 'new').toList();
                            final sent = await pos.sendLines(js(o['_id']));
                            bar.showSnackBar(SnackBar(content: Text(t('rpos.sent'))));
                            if (context.mounted) printKitchenFor(context, sent, fresh);
                            _leave();
                          },
                  ),
                ),
                const SizedBox(width: 8),
                RoundBtn(
                  LucideIcons.printer,
                  size: 50,
                  tip: t('rpos.bill'),
                  onTap: o == null || !lines.any((l) => l['status'] != 'void') || disabled
                      ? null
                      : () => previewReceipt(
                          context,
                          o,
                          paid: false,
                          beforePrint: () async {
                            final fresh = jlist(pos.orders[js(o['_id'])]!['lines']).where((l) => l['status'] == 'new').toList();
                            final marked = await pos.markBill(js(o['_id']));
                            if (context.mounted) printKitchenFor(context, marked, fresh);
                            return marked;
                          },
                        ),
                ),
                const SizedBox(width: 8),
              ],
              Expanded(
                flex: 3,
                child: Btn(
                  '${t('rpos.pay')} ${tot != null ? m$(tot.total, cur) : ''}',
                  icon: LucideIcons.wallet,
                  onTap: o == null || tot == null || tot.total <= 0 || disabled ? null : () => _pay(context),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Future<void> _pay(BuildContext context) async {
    _paying = true;
    final fresh = jlist(order!['lines']).where((l) => l['status'] == 'new').toList(); // paying sends them to the kitchen too
    final done = await showPay(context, js(order!['_id']));
    if (done == true && context.mounted && order != null) printKitchenFor(context, order!, fresh);
    _paying = false;
    if (done == true) {
      _leave();
    } else {
      _watch();
    }
  }

  void _lineSheet(BuildContext context, String lineId) {
    final app = AppScope.of(context);
    final t = app.t;
    final first = jlist(order!['lines']).firstWhere((l) => l['id'] == lineId);
    final reason = TextEditingController();
    posSheet(
      context,
      title: '${_n(first['qty'])}× ${lineName(first, app.lang)}${js(first['size']).isNotEmpty ? ' · ${js(first['size'])}' : ''}',
      body: (ctx) => ListenableBuilder(
        listenable: pos,
        builder: (ctx, _) {
          final c = ctx.c;
          final o = order;
          final l = o == null ? null : jlist(o['lines']).where((x) => x['id'] == lineId).firstOrNull;
          if (o == null || l == null) return const SizedBox.shrink();
          final id = js(o['_id']);
          final isNew = l['status'] == 'new';
          final left = pos.stockLeft(pos.itemOf(js(l['item_id'])), lineId);
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _LineDiscount(orderId: id, lineId: lineId),
              const SizedBox(height: 18),
              if (isNew) ...[
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    RoundBtn(LucideIcons.minus, size: 54, onTap: nz(l['qty']) <= 1 ? null : () => pos.setLineQty(id, lineId, nz(l['qty']) - 1)),
                    SizedBox(
                      width: 90,
                      child: Text(
                        _n(l['qty']),
                        textAlign: TextAlign.center,
                        style: const TextStyle(fontSize: 30, fontWeight: FontWeight.w800),
                      ),
                    ),
                    RoundBtn(LucideIcons.plus, size: 54, onTap: left != null && nz(l['qty']) + 1 > left ? null : () => pos.setLineQty(id, lineId, nz(l['qty']) + 1)),
                  ],
                ),
                const SizedBox(height: 16),
                Btn(
                  t('rpos.cancelItem'),
                  icon: LucideIcons.trash2,
                  kind: BtnKind.danger,
                  expand: true,
                  onTap: () {
                    pos.removeLine(id, lineId);
                    Navigator.pop(ctx);
                  },
                ),
              ] else ...[
                // already sent: anyone can cancel it; the reason and who did it stay on the bill
                Field(controller: reason, hint: t('rpos.cancelReason'), maxLength: 120),
                const SizedBox(height: 10),
                Btn(
                  t('rpos.cancelItem'),
                  icon: LucideIcons.trash2,
                  kind: BtnKind.danger,
                  expand: true,
                  onTap: () {
                    pos.voidLine(id, lineId, reason.text.trim().isEmpty ? t('rpos.statusVoid') : reason.text.trim());
                    Navigator.pop(ctx);
                  },
                ),
                const SizedBox(height: 6),
                Center(
                  child: Text(t('rpos.statusSent'), style: TextStyle(color: c.muted, fontSize: 12.5)),
                ),
              ],
            ],
          );
        },
      ),
    );
  }

  void _moreSheet(BuildContext context) {
    final t = tr(context);
    final o = order!;
    posSheet(
      context,
      title: '#${js(o['number'])}',
      body: (ctx) {
        final c = ctx.c;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ListTile(
              leading: const Icon(LucideIcons.percent),
              title: Text(t('rpos.addDiscount'), style: const TextStyle(fontWeight: FontWeight.w700)),
              onTap: () {
                Navigator.pop(ctx);
                _discountSheet(context);
              },
            ),
            ListTile(
              leading: Icon(LucideIcons.trash2, color: c.danger),
              title: Text(
                t('rpos.cancelOrder'),
                style: TextStyle(fontWeight: FontWeight.w700, color: c.danger),
              ),
              onTap: () {
                Navigator.pop(ctx);
                _cancelSheet(context);
              },
            ),
          ],
        );
      },
    );
  }

  // cancel the whole order: no manager PIN, the reason and who did it stay on the bill
  void _cancelSheet(BuildContext context) {
    final t = tr(context);
    final o = order!;
    final reason = TextEditingController();
    posSheet(
      context,
      title: '${t('rpos.cancelOrder')} · #${js(o['number'])}',
      body: (ctx) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Field(controller: reason, hint: t('rpos.cancelReason'), maxLength: 120, autofocus: true),
          const SizedBox(height: 12),
          Btn(
            t('rpos.cancelOrder'),
            icon: LucideIcons.trash2,
            kind: BtnKind.danger,
            expand: true,
            onTap: () async {
              Navigator.pop(ctx);
              await pos.voidOrder(js(o['_id']), reason.text.trim().isEmpty ? t('rpos.statusVoid') : reason.text.trim());
              _leave();
            },
          ),
        ],
      ),
    );
  }

  void _discountSheet(BuildContext context) {
    final t = tr(context);
    final o = order!;
    final d = jmap(o['discount']);
    var kind = js(d['kind']).isEmpty ? 'percent' : js(d['kind']);
    var value = nz(d['value']) > 0 ? _n(d['value']) : '';
    final cur = pos.currency;
    posSheet(
      context,
      title: t('rpos.addDiscount'),
      maxWidth: 440,
      body: (ctx) => StatefulBuilder(
        builder: (ctx, set) => Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            PosChips<String>(value: kind, onTap: (v) => set(() => kind = v), options: [('percent', t('rpos.percent')), ('amount', '${t('rpos.amount')} (${cur == 'KHR' ? '៛' : '\$'})')]),
            const SizedBox(height: 14),
            Text(
              kind == 'percent' ? '${value.isEmpty ? 0 : value}%' : m$(nz(value), cur),
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 34, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 10),
            if (kind == 'percent') ...[
              Center(
                child: PosChips<String>(
                  value: value,
                  onTap: (v) => set(() => value = v),
                  options: [
                    for (final p in [5, 10, 15, 20, 50]) ('$p', '$p%'),
                  ],
                ),
              ),
              const SizedBox(height: 12),
            ],
            Keypad(value: value, onChanged: (v) => set(() => value = v), dot: cur == 'USD' || kind == 'percent', max: 8),
          ],
        ),
      ),
      footer: (ctx) => Row(
        children: [
          if (js(d['kind']).isNotEmpty) ...[
            Expanded(
              child: Btn(
                t('rpos.removeDiscount'),
                kind: BtnKind.ghost,
                onTap: () {
                  pos.setDiscount(js(o['_id']), '', 0);
                  Navigator.pop(ctx);
                },
              ),
            ),
            const SizedBox(width: 8),
          ],
          Expanded(
            child: Btn(
              t('rpos.apply'),
              onTap: () {
                if (nz(value) <= 0) return;
                pos.setDiscount(js(o['_id']), kind, nz(value));
                Navigator.pop(ctx);
              },
            ),
          ),
        ],
      ),
    );
  }

  void _noteSheet(BuildContext context) {
    final t = tr(context);
    final text = TextEditingController(text: js(order?['note']));
    posSheet(
      context,
      title: t('rpos.tableNote'),
      body: (ctx) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Field(controller: text, hint: t('rpos.tableNotePh'), maxLength: 300, maxLines: 4, autofocus: true),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final q in t.list('rpos.noteQuick'))
                ActionChip(
                  label: Text(q),
                  onPressed: () {
                    text.text = text.text.trim().isEmpty ? q : '${text.text.trim()}, $q';
                  },
                ),
            ],
          ),
        ],
      ),
      footer: (ctx) => Row(
        children: [
          Expanded(
            child: Btn(t('rpos.cancel'), kind: BtnKind.ghost, onTap: () => Navigator.pop(ctx)),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Btn(
              t('rpos.save'),
              onTap: () async {
                Navigator.pop(ctx);
                final v = text.text.trim();
                if (_id == null && v.isEmpty) return;
                await pos.setNote(await _ensure(), v);
              },
            ),
          ),
        ],
      ),
    );
  }
}

String _n(Object? v) {
  final x = nz(v);
  return x == x.roundToDouble() ? x.toInt().toString() : x.toString();
}

class _ItemCard extends StatelessWidget {
  final J item;
  final bool disabled;
  final VoidCallback onTap;
  const _ItemCard({required this.item, required this.disabled, required this.onTap});
  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final t = app.t;
    final c = context.c;
    final pos = RestPos.i;
    final left = pos.stockLeft(item);
    final out = item['available'] == false || (left != null && left <= 0);
    final low = left != null && left > 0 && left <= (item['low_stock'] == null ? 5 : nz(item['low_stock']));
    final photo = js(item['photo']);
    final prices = [nz(item['price']), for (final s in jlist(item['sizes'])) nz(s['price'])];
    final price = prices.reduce((a, b) => a < b ? a : b);
    return Opacity(
      opacity: out || disabled ? .5 : 1,
      child: Material(
        color: c.card,
        borderRadius: BorderRadius.circular(20),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: out || disabled ? null : onTap,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    if (photo.isNotEmpty)
                      Image(
                        image: netImage(photo),
                        fit: BoxFit.cover,
                        errorBuilder: (_, _, _) => Container(
                          color: c.chip,
                          child: Icon(LucideIcons.utensilsCrossed, color: c.muted),
                        ),
                      )
                    else
                      Container(
                        color: c.chip,
                        child: Icon(LucideIcons.utensilsCrossed, color: c.muted, size: 28),
                      ),
                    if (left != null) Positioned(left: 6, top: 6, child: Chip2(out ? t('rpos.soldOut') : t('rpos.left', {'n': left.toInt()}), tone: out ? Tone.danger : (low ? Tone.warn : Tone.good))),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      nameOf(item, app.lang),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14, height: 1.25),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      out ? t('rpos.soldOut') : m$(price, pos.currency),
                      style: TextStyle(color: out ? c.danger : c.brand, fontWeight: FontWeight.w800),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _LineRow extends StatelessWidget {
  final J line;
  final String photo;
  final String currency;
  final VoidCallback? onTap;
  const _LineRow({required this.line, required this.photo, required this.currency, this.onTap});
  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final t = app.t;
    final c = context.c;
    final l = line;
    final isVoid = l['status'] == 'void';
    final off = lineOff(l);
    final full = isVoid ? nz(l['qty']) * nz(l['unit_price']) : lineTotal(l);
    final extras = [for (final a in jlist(l['addons'])) '+ ${js(a['name'])}', if (js(l['note']).isNotEmpty) '“${js(l['note'])}”'];
    final d = jmap(l['discount']);
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 40,
              height: 40,
              clipBehavior: Clip.antiAlias,
              decoration: BoxDecoration(color: c.chip, borderRadius: BorderRadius.circular(12)),
              child: photo.isNotEmpty ? Image(image: netImage(photo), fit: BoxFit.cover, errorBuilder: (_, _, _) => const SizedBox()) : Icon(LucideIcons.utensilsCrossed, size: 16, color: c.muted),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text.rich(
                    TextSpan(
                      children: [
                        if (nz(l['qty']) > 1)
                          TextSpan(
                            text: '${_n(l['qty'])}× ',
                            style: TextStyle(color: c.brand, fontWeight: FontWeight.w800),
                          ),
                        TextSpan(text: lineName(l, app.lang)),
                        if (js(l['size']).isNotEmpty)
                          TextSpan(
                            text: ' · ${js(l['size'])}',
                            style: TextStyle(color: c.muted, fontStyle: FontStyle.italic),
                          ),
                      ],
                    ),
                    style: TextStyle(fontWeight: FontWeight.w700, decoration: isVoid ? TextDecoration.lineThrough : null, color: isVoid ? c.muted : c.ink),
                  ),
                  if (extras.isNotEmpty) Text(extras.join(' · '), style: TextStyle(color: c.muted, fontSize: 12.5)),
                  if (l['from'] == 'guest') Text('📱 ${t('rpos.guestTag')}${js(l['guest_name']).isNotEmpty ? ' · ${js(l['guest_name'])}' : ''}', style: TextStyle(color: c.limeInk, fontSize: 12)),
                  const SizedBox(height: 3),
                  Row(
                    children: [
                      if (l['status'] == 'new') Chip2(t('rpos.statusNew'), tone: Tone.brand),
                      if (l['status'] == 'sent') Chip2(t('rpos.statusSent'), tone: Tone.muted),
                      if (isVoid) Chip2(t('rpos.statusVoid'), tone: Tone.danger),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                if (off > 0)
                  Text(
                    m$(full, currency),
                    style: TextStyle(color: c.muted, fontSize: 12, decoration: TextDecoration.lineThrough),
                  ),
                Text(
                  m$(full - off, currency),
                  style: TextStyle(fontWeight: FontWeight.w800, color: isVoid ? c.muted : c.ink),
                ),
                if (off > 0)
                  Text(
                    js(d['kind']).isNotEmpty
                        ? '−${d['kind'] == 'percent' ? '${_n(d['value'])}%' : m$(d['value'], currency)}${js(d['reason']).isNotEmpty ? ' · ${js(d['reason'])}' : ''}'
                        : '🏷 ${js(jmap(l['promo'])['name'])}',
                    style: TextStyle(color: c.good, fontSize: 11.5, fontWeight: FontWeight.w700),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// a discount on one item: % or $ off, with a reason (the owner sets the biggest % allowed)
class _LineDiscount extends StatefulWidget {
  final String orderId, lineId;
  const _LineDiscount({required this.orderId, required this.lineId});
  @override
  State<_LineDiscount> createState() => _LineDiscountState();
}

class _LineDiscountState extends State<_LineDiscount> {
  late String _kind;
  final _value = TextEditingController();
  final _reason = TextEditingController();
  final pos = RestPos.i;

  J? get line => jlist(pos.orders[widget.orderId]?['lines']).where((l) => l['id'] == widget.lineId).firstOrNull;

  @override
  void initState() {
    super.initState();
    final d = jmap(line?['discount']);
    _kind = js(d['kind']).isEmpty ? 'percent' : js(d['kind']);
    if (nz(d['value']) > 0) _value.text = _n(d['value']);
    _reason.text = js(d['reason']);
  }

  @override
  void dispose() {
    _value.dispose();
    _reason.dispose();
    super.dispose();
  }

  void _apply(String k, double v) => pos.setLineDiscount(widget.orderId, widget.lineId, k, v, _reason.text.trim());

  @override
  Widget build(BuildContext context) {
    final t = tr(context);
    final c = context.c;
    final l = line;
    final cap = pos.maxLineDiscount;
    if (l == null || cap <= 0) return const SizedBox.shrink();
    final cur = pos.currency;
    final d = jmap(l['discount']);
    final promo = jmap(l['promo']);
    final quick = [10, 20, 50, 100].where((p) => p <= cap).toList();
    if (!quick.contains(cap.toInt())) quick.add(cap.toInt());
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: c.card,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: c.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(LucideIcons.percent, size: 16, color: c.brand),
              const SizedBox(width: 6),
              Expanded(
                child: Text(t('rpos.itemDiscount'), style: const TextStyle(fontWeight: FontWeight.w800)),
              ),
              if (nz(promo['off']) > 0 && js(d['kind']).isEmpty)
                Text(
                  '🏷 ${js(promo['name'])} · −${m$(promo['off'], cur)}',
                  style: TextStyle(color: c.good, fontSize: 12, fontWeight: FontWeight.w700),
                ),
            ],
          ),
          const SizedBox(height: 10),
          PosChips<int>(
            value: d['kind'] == 'percent' ? nz(d['value']).toInt() : null,
            onTap: (p) => _apply('percent', p.toDouble()),
            options: [for (final p in quick) (p, p == 100 ? t('rpos.free') : '$p%')],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              PosChips<String>(value: _kind, onTap: (v) => setState(() => _kind = v), options: [('percent', '%'), ('amount', cur == 'KHR' ? '៛' : '\$')]),
              const SizedBox(width: 8),
              Expanded(
                child: TextField(
                  controller: _value,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  onChanged: (_) => setState(() {}),
                  decoration: InputDecoration(
                    isDense: true,
                    hintText: _kind == 'percent' ? '≤ ${cap.toInt()}' : '≤ ${m$(lineTotal(l) * cap / 100, cur)}',
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Btn(t('rpos.apply'), small: true, onTap: nz(_value.text) > 0 ? () => _apply(_kind, nz(_value.text)) : null),
            ],
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _reason,
            maxLength: 80,
            decoration: InputDecoration(
              isDense: true,
              counterText: '',
              hintText: t('rpos.discountReasonPh'),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
            ),
          ),
          if (js(d['kind']).isNotEmpty) ...[
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerLeft,
              child: Btn(t('rpos.removeItemDiscount'), icon: LucideIcons.x, small: true, kind: BtnKind.ghost, onTap: () => _apply('', 0)),
            ),
          ],
          if (cap < 100) ...[
            const SizedBox(height: 6),
            Text(t('rpos.maxDiscountHint', {'n': cap.toInt()}), style: TextStyle(color: c.muted, fontSize: 12)),
          ],
        ],
      ),
    );
  }
}

// choose size, add-ons, note, qty
typedef AddFn = Future<void> Function(J item, {J? size, List<J> addons, int qty, String note});

Future<void> showItemSheet(BuildContext context, J item, {required AddFn onAdd}) {
  final app = AppScope.of(context);
  final t = app.t;
  final pos = RestPos.i;
  final cur = pos.currency;
  final groups = [for (final id in (item['addon_group_ids'] is List ? item['addon_group_ids'] as List : const [])) ...pos.addonGroups.where((g) => js(g['_id']) == '$id')];
  final sizes = jlist(item['sizes']);
  final left = pos.stockLeft(item);
  J? size;
  final picked = <String, List<String>>{};
  var qty = 1;
  final note = TextEditingController();

  int need(J g) => (g['required'] == true ? 1 : 0) > nz(g['min']).toInt() ? 1 : nz(g['min']).toInt();
  List<J> addons() => [
    for (final g in groups)
      for (final name in picked[js(g['_id'])] ?? const <String>[]) {'group': js(g['name']), 'name': name, 'price': nz(jlist(g['options']).where((o) => o['name'] == name).firstOrNull?['price'])},
  ];
  bool missing() => groups.any((g) => (picked[js(g['_id'])] ?? const []).length < need(g));
  double unit() => (size != null ? nz(size!['price']) : nz(item['price'])) + addons().fold<double>(0, (a, x) => a + nz(x['price']));

  return posSheet(
    context,
    title: nameOf(item, app.lang),
    body: (ctx) => StatefulBuilder(
      builder: (ctx, set) {
        final c = ctx.c;
        void toggle(J g, J o) => set(() {
          final id = js(g['_id']);
          final now = [...?picked[id]];
          final name = js(o['name']);
          final maxN = nz(g['max']).toInt();
          if (now.contains(name)) {
            now.remove(name);
          } else if (maxN == 1) {
            now
              ..clear()
              ..add(name);
          } else if (maxN == 0 || now.length < maxN) {
            now.add(name);
          }
          picked[id] = now;
        });
        Widget head(String title, [String sub = '']) => Padding(
          padding: const EdgeInsets.only(bottom: 8, top: 4),
          child: Text.rich(
            TextSpan(
              children: [
                TextSpan(
                  text: title,
                  style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
                ),
                if (sub.isNotEmpty)
                  TextSpan(
                    text: '  $sub',
                    style: TextStyle(color: c.muted, fontSize: 12.5),
                  ),
              ],
            ),
          ),
        );
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (sizes.isNotEmpty) ...[
              head(t('rpos.size')),
              PosChips<String>(
                value: js(size?['name']),
                onTap: (v) => set(() => size = v.isEmpty ? null : sizes.firstWhere((s) => s['name'] == v)),
                options: [('', '${t('rpos.regular')} · ${m$(item['price'], cur)}'), for (final s in sizes) (js(s['name']), '${js(s['name'])} · ${m$(s['price'], cur)}')],
              ),
              const SizedBox(height: 14),
            ],
            for (final g in groups) ...[
              head(
                js(g['name']),
                [
                  if (g['required'] == true || nz(g['min']) > 0) t('rpos.pickAtLeast', {'n': need(g) < 1 ? 1 : need(g)}),
                  if (nz(g['max']) > 0) t('rpos.pickUpTo', {'n': nz(g['max']).toInt()}),
                ].join(' · '),
              ),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final o in jlist(g['options']))
                    FilterChip(
                      selected: (picked[js(g['_id'])] ?? const []).contains(js(o['name'])),
                      onSelected: (_) => toggle(g, o),
                      label: Text('${js(o['name'])}${nz(o['price']) > 0 ? ' +${m$(o['price'], cur)}' : ''}'),
                    ),
                ],
              ),
              const SizedBox(height: 14),
            ],
            head(t('rpos.noteItem')),
            Field(controller: note, hint: t('rpos.notePh'), maxLength: 200),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                RoundBtn(LucideIcons.minus, size: 48, onTap: qty <= 1 ? null : () => set(() => qty--)),
                SizedBox(
                  width: 70,
                  child: Text(
                    '$qty',
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w800),
                  ),
                ),
                RoundBtn(LucideIcons.plus, size: 48, onTap: left != null && qty >= left ? null : () => set(() => qty++)),
              ],
            ),
            if (left != null)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Muted(t('rpos.onlyLeft', {'n': left.toInt()}), align: TextAlign.center),
              ),
            const SizedBox(height: 16),
            Btn(
              '${t('rpos.add')} · ${m$(unit() * qty, cur)}',
              icon: LucideIcons.plus,
              expand: true,
              onTap: missing() || (left != null && qty > left)
                  ? null
                  : () async {
                      Navigator.pop(ctx);
                      await onAdd(item, size: size, addons: addons(), qty: qty, note: note.text.trim());
                    },
            ),
          ],
        );
      },
    ),
  );
}
