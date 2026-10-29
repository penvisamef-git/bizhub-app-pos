import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../core/api.dart' show ApiError;
import '../../core/app_state.dart';
import '../../core/desktop.dart';
import '../../core/pos_split.dart';
import '../../core/format.dart' as f;
import '../../core/theme.dart';
import '../../widgets/ui.dart';
import '../restaurant/engine/calc.dart' show J, jmap, jlist, js, nz;
import '../restaurant/pos_ui.dart';
import 'engine/mart_calc.dart';
import 'engine/mart_pos.dart';
import 'mart_display.dart';
import 'mart_receipt.dart';

const _colors = [Color(0xFF0D9488), Color(0xFF2563EB), Color(0xFFD97706), Color(0xFFDB2777), Color(0xFF7C3AED), Color(0xFF059669), Color(0xFFDC2626), Color(0xFF0891B2)];
Color colorOf(String s) => _colors[s.codeUnits.fold<int>(0, (a, c) => a + c) % _colors.length];

// what the cart adds up to right now (promotions, discount, points)
class CartSum {
  final PromoResult promo;
  final SaleMoney money;
  final J? member;
  final int points; // points used now
  final int earn;
  final double count;
  const CartSum(this.promo, this.money, this.member, this.points, this.earn, this.count);
}

CartSum cartSum(J cart) {
  final pos = MartPos.i;
  final lines = jlist(cart['lines']);
  final promos = jlist(pos.boot['promos']);
  final catOf = {for (final x in pos.products) js(x['_id']): js(x['category_id'])};
  final promo = promos.isNotEmpty ? applyMartPromos(lines: lines, promos: promos, at: DateTime.now(), coupon: js(cart['coupon']), currency: pos.currency, categoryOf: catOf) : PromoResult.none;
  final base = saleMoney(lines: lines, promo: promo.discount, currency: pos.currency, rate: pos.rate, method: 'aba', khrRound: pos.khrRound);
  final d = jmap(cart['discount']);
  final discount = d.isEmpty ? 0.0 : (d['type'] == 'pct' ? (nz(d['value']) > 100 ? 100 : nz(d['value'])) * (base.subtotal - base.promoDiscount) / 100 : nz(d['value']));
  final rules = pos.boot['loyalty'] == null ? null : jmap(pos.boot['loyalty']);
  final member = rules != null && cart['member'] != null ? jmap(cart['member']) : null;
  final pts = member != null ? nz(cart['redeem']).floor() : 0;
  final m = saleMoney(
    lines: lines,
    discount: discount,
    promo: promo.discount,
    points: pts > 0 && rules != null ? pts * nz(rules['point_value']) : 0,
    currency: pos.currency,
    rate: pos.rate,
    method: 'aba',
    khrRound: pos.khrRound,
  );
  final earn = member != null && rules != null ? (m.total / (nz(rules['earn_per']) == 0 ? 1 : nz(rules['earn_per'])) + 1e-9).floor() : 0;
  final count = lines.fold<double>(0, (a, l) => a + nz(l['qty']));
  return CartSum(promo, m, member, pts, earn, (count * 1000).round() / 1000);
}

// The sale screen: scan / tap products → cart → pay (USD, riel or both; change in riel) → receipt
class MartSell extends StatefulWidget {
  const MartSell({super.key});
  @override
  State<MartSell> createState() => MartSellState();
}

class MartSellState extends State<MartSell> {
  final _q = TextEditingController();
  final _focus = FocusNode();
  String _cat = '';
  String _miss = '';
  final pos = MartPos.i;
  Timer? _tick; // happy hours start / end while the screen is open

  @override
  void initState() {
    super.initState();
    _tick = Timer.periodic(const Duration(minutes: 1), (_) => setState(() {}));
  }

  @override
  void dispose() {
    _tick?.cancel();
    _q.dispose();
    _focus.dispose();
    super.dispose();
  }

  J get cart => pos.cart;
  void _setCart(J c) => pos.saveCart(c);

  void add(J prod, [double qty = 1, bool separate = false]) {
    setState(() => _miss = '');
    final lines = jlist(cart['lines']);
    final i = separate ? -1 : lines.indexWhere((l) => l['product_id'] == prod['_id'] && nz(l['price']) == nz(prod['price']) && l['weighed'] != true);
    if (i >= 0) {
      lines[i] = {...lines[i], 'qty': ((nz(lines[i]['qty']) + qty) * 1000).round() / 1000};
    } else {
      lines.insert(0, {
        'key': '${prod['_id']}-${DateTime.now().microsecondsSinceEpoch}',
        'product_id': prod['_id'],
        'name': js(prod['name']),
        'barcode': js(prod['barcode']),
        'price': nz(prod['price']),
        'qty': qty,
        'photo': js(prod['photo']),
        if (separate) 'weighed': true,
      });
    }
    HapticFeedback.selectionClick();
    _setCart({...cart, 'lines': lines});
    if (isDesktop) _focus.requestFocus(); // the USB scanner keeps typing into the scan box
  }

  // a scanner types the code and presses Enter; "3*885…" = 3 of them
  void enter(String raw) {
    final v = raw.trim();
    if (v.isEmpty) return;
    final mq = RegExp(r'^(\d+(?:\.\d+)?)\s*[*xX]\s*(.+)$').firstMatch(v);
    final qty = mq != null ? double.parse(mq[1]!) : 1.0;
    final code = mq != null ? mq[2]!.trim() : v;
    final hit = pos.products.where((x) => js(x['barcode']).isNotEmpty && x['barcode'] == code).firstOrNull;
    if (hit != null) {
      add(hit, qty);
      _q.clear();
      return;
    }
    // a weighing-scale label: the weight (or price) is inside the barcode
    final sc = pos.boot['scale'] != null ? parseScale(code, jmap(pos.boot['scale']), pos.currency) : null;
    final weighed = sc != null ? byPlu(pos.products, sc.plu) : null;
    if (sc != null && weighed != null) {
      final n = sc.weight ?? (nz(weighed['price']) > 0 ? ((sc.price! / nz(weighed['price'])) * 1000).round() / 1000 : 1.0);
      add(weighed, n < 0.001 ? 0.001 : n, true);
      _q.clear();
      return;
    }
    final t = code.toLowerCase();
    final list = pos.products.where((x) => js(x['name']).toLowerCase().contains(t)).toList();
    if (list.length == 1) {
      add(list.first, qty);
      _q.clear();
      return;
    }
    if (list.isEmpty) {
      setState(() => _miss = code);
      _q.clear();
    }
  }

  void setQty(String key, double qty) {
    final lines = jlist(cart['lines']);
    _setCart({
      ...cart,
      'lines': qty <= 0
          ? lines.where((l) => l['key'] != key).toList()
          : [
              for (final l in lines) l['key'] == key ? {...l, 'qty': (qty * 1000).round() / 1000} : l,
            ],
    });
  }

  void reset() => _setCart({'lines': <J>[]});

  // ---------- Mac / Windows keyboard ----------
  void _find() {
    _focus.requestFocus();
    _q.selection = TextSelection(baseOffset: 0, extentOffset: _q.text.length);
  }

  // F4: the quantity of the item scanned last
  Future<void> _qtyLast(BuildContext context) async {
    final lines = jlist(cart['lines']);
    if (lines.isEmpty) return;
    final l = lines.first;
    final t = tr(context);
    final ctl = TextEditingController(text: qtyOf(l['qty']));
    ctl.selection = TextSelection(baseOffset: 0, extentOffset: ctl.text.length);
    final v = await showDialog<double>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(t('ks.qtyFor', {'name': js(l['name'])})),
        content: TextField(controller: ctl, autofocus: true, keyboardType: const TextInputType.numberWithOptions(decimal: true), onSubmitted: (s) => Navigator.pop(ctx, double.tryParse(s.trim()))),
        actions: [TextButton(onPressed: () => Navigator.pop(ctx, double.tryParse(ctl.text.trim())), child: Text(t('ks.ok')))],
      ),
    );
    if (v != null && v >= 0) setQty(js(l['key']), v);
    _focus.requestFocus();
  }

  Future<void> _payNow(BuildContext context) async {
    await showMartPay(context, this);
    if (mounted) _focus.requestFocus();
  }

  // Esc: clear the scan box first, then (asked) the cart
  void _escape(BuildContext context, CartSum sum) {
    if (_q.text.isNotEmpty || _miss.isNotEmpty) {
      setState(() {
        _q.clear();
        _miss = '';
      });
      return;
    }
    if (jlist(cart['lines']).isNotEmpty) MartCart(sell: this, sum: sum).clear(context);
  }

  Future<void> _camera() async {
    final code = await showModalBottomSheet<String>(context: context, isScrollControlled: true, backgroundColor: Colors.black, builder: (_) => const _Scan());
    if (code != null && code.isNotEmpty) enter(code);
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: pos,
      builder: (context, _) {
        final big = wide(context);
        final sum = cartSum(cart);
        final left = _left(context);
        final has = jlist(cart['lines']).isNotEmpty;
        final cartView = MartCart(sell: this, sum: sum);
        final keys = <LogicalKeyboardKey, VoidCallback?>{
          LogicalKeyboardKey.f2: _find,
          LogicalKeyboardKey.f4: has ? () => _qtyLast(context) : null,
          LogicalKeyboardKey.f6: has ? () => cartView.discount(context, sum) : null,
          LogicalKeyboardKey.f9: has ? () => cartView.hold(context) : null,
          LogicalKeyboardKey.f12: has && !pos.readOnly ? () => _payNow(context) : null,
          LogicalKeyboardKey.escape: () => _escape(context, sum),
        };
        if (big) {
          return DesktopKeys(
            autofocus: false,
            keys: keys,
            child: PosSplit(
              scope: 'mart',
              who: js(pos.staff['_id']),
              whoName: js(pos.staff['name']),
              thing: 'cart',
              main: left,
              // the cashier moves it: wider / narrower, left / right (kept for them on this device)
              panel: (onLeft) => Container(
                margin: onLeft ? const EdgeInsets.fromLTRB(12, 0, 0, 12) : const EdgeInsets.fromLTRB(0, 0, 12, 12),
                decoration: BoxDecoration(color: context.c.card, borderRadius: BorderRadius.circular(22), boxShadow: context.c.cardShadow),
                clipBehavior: Clip.antiAlias,
                child: cartView,
              ),
            ),
          );
        }
        final lines = jlist(cart['lines']);
        return Stack(
          children: [
            left,
            if (lines.isNotEmpty)
              Positioned(
                left: 12,
                right: 12,
                bottom: 12,
                child: Material(
                  elevation: 6,
                  color: context.c.solid,
                  borderRadius: BorderRadius.circular(20),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(20),
                    onTap: () => _openCart(context),
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 10, 10, 10),
                      child: Row(
                        children: [
                          Icon(LucideIcons.shoppingCart, color: context.c.onSolid),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(tr(context)('mpos.items', {'n': qtyOf(sum.count)}), style: TextStyle(color: context.c.onSolid.withValues(alpha: .8), fontSize: 12.5)),
                                Text(
                                  f.money(sum.money.total, pos.currency),
                                  style: TextStyle(color: context.c.onSolid, fontWeight: FontWeight.w800, fontSize: 18),
                                ),
                              ],
                            ),
                          ),
                          Btn(tr(context)('mpos.pay'), onTap: pos.readOnly ? null : () => showMartPay(context, this)),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }

  void _openCart(BuildContext context) => Navigator.of(context).push(
    MaterialPageRoute(
      builder: (_) => ListenableBuilder(
        listenable: pos,
        builder: (ctx, _) => Scaffold(
          backgroundColor: ctx.c.card,
          appBar: AppBar(
            backgroundColor: ctx.c.card,
            surfaceTintColor: Colors.transparent,
            title: Text(tr(ctx)('mpos.cart'), style: const TextStyle(fontWeight: FontWeight.w800)),
          ),
          body: SafeArea(
            child: MartCart(sell: this, sum: cartSum(cart), page: true),
          ),
        ),
      ),
    ),
  );

  Widget _left(BuildContext context) {
    final t = tr(context);
    final c = context.c;
    final q = _q.text.trim().toLowerCase();
    final products = pos.products;
    final shown = products
        .where((x) => (_cat.isEmpty || (_cat == 'fav' ? x['fav'] == true : js(x['category_id']) == _cat)) && (q.isEmpty || js(x['name']).toLowerCase().contains(q) || js(x['barcode']).startsWith(q)))
        .take(240)
        .toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _q,
                  focusNode: _focus,
                  autofocus: wide(context),
                  autocorrect: false,
                  enableSuggestions: false,
                  textInputAction: TextInputAction.done,
                  onChanged: (_) => setState(() => _miss = ''),
                  onSubmitted: (v) {
                    enter(v);
                    _focus.requestFocus();
                  },
                  decoration: InputDecoration(
                    hintText: t('mpos.scanPh'),
                    prefixIcon: Icon(LucideIcons.scanBarcode, color: c.muted),
                    suffixIcon: _q.text.isEmpty ? null : IconButton(onPressed: () => setState(_q.clear), icon: const Icon(LucideIcons.x, size: 16), tooltip: t('mpos.clear')),
                    isDense: true,
                    filled: true,
                    fillColor: c.card,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(16),
                      borderSide: BorderSide(color: c.line),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(16),
                      borderSide: BorderSide(color: c.line),
                    ),
                  ),
                ),
              ),
              if (!kIsWeb && hasCameraScanner) ...[const SizedBox(width: 8), RoundBtn(LucideIcons.camera, size: 48, tip: t('mpos.scanCamera'), onTap: _camera)],
            ],
          ),
        ),
        if (_miss.isNotEmpty)
          Container(
            margin: const EdgeInsets.fromLTRB(12, 0, 12, 8),
            padding: const EdgeInsets.fromLTRB(12, 6, 4, 6),
            decoration: BoxDecoration(color: c.warnBg, borderRadius: BorderRadius.circular(14)),
            child: Row(
              children: [
                Icon(LucideIcons.search, size: 15, color: c.warn),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    t('mpos.noMatch', {'q': _miss}),
                    style: TextStyle(color: c.warn, fontWeight: FontWeight.w600),
                  ),
                ),
                IconButton(
                  onPressed: () => setState(() => _miss = ''),
                  icon: Icon(LucideIcons.x, size: 16, color: c.warn),
                ),
              ],
            ),
          ),
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
          child: PosChips<String>(
            scroll: true,
            value: _cat,
            onTap: (v) => setState(() => _cat = v),
            options: [('', t('mpos.all')), if (products.any((x) => x['fav'] == true)) ('fav', '★ ${t('mpos.favs')}'), for (final x in pos.categories) (js(x['_id']), js(x['name']))],
          ),
        ),
        Expanded(
          child: shown.isEmpty
              ? Center(child: Icon(LucideIcons.package, size: 36, color: c.muted))
              : GridView.builder(
                  padding: EdgeInsets.fromLTRB(12, 0, 12, wide(context) ? 16 : 96),
                  gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(maxCrossAxisExtent: 170, mainAxisExtent: 176, crossAxisSpacing: 10, mainAxisSpacing: 10),
                  itemCount: shown.length,
                  itemBuilder: (context, i) => _Product(shown[i], onTap: () => add(shown[i])),
                ),
        ),
        if (isDesktop && wide(context)) KeyHints([('F2', t('ks.find')), ('F4', t('ks.qty')), ('F6', t('ks.discount')), ('F9', t('ks.hold')), ('F12', t('ks.pay')), ('Esc', t('ks.clear'))]),
      ],
    );
  }
}

class _Product extends StatelessWidget {
  final J p;
  final VoidCallback onTap;
  const _Product(this.p, {required this.onTap});
  @override
  Widget build(BuildContext context) {
    final t = tr(context);
    final c = context.c;
    final pos = MartPos.i;
    final photo = js(p['photo']);
    final name = js(p['name']);
    final stock = p['stock'] == null ? null : nz(p['stock']);
    final low = p['low_stock'] == null ? 5.0 : nz(p['low_stock']);
    return Material(
      color: c.card,
      borderRadius: BorderRadius.circular(18),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: Stack(
                fit: StackFit.expand,
                children: [
                  if (photo.isNotEmpty)
                    Image(image: netImage(photo), fit: BoxFit.cover, errorBuilder: (_, _, _) => const SizedBox())
                  else
                    Container(
                      color: colorOf(name),
                      alignment: Alignment.center,
                      child: Text(
                        name.length > 2 ? name.substring(0, 2) : name,
                        style: const TextStyle(color: Colors.white, fontSize: 26, fontWeight: FontWeight.w800),
                      ),
                    ),
                  if (stock != null)
                    Positioned(
                      left: 6,
                      top: 6,
                      child: Chip2(stock <= 0 ? t('mpos.outStock') : t('mpos.left', {'n': qtyOf(stock)}), tone: stock <= 0 ? Tone.danger : (stock <= low ? Tone.warn : Tone.good)),
                    ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 7, 10, 9),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5, height: 1.25),
                  ),
                  Text(
                    f.money(p['price'], pos.currency),
                    style: TextStyle(color: c.brand, fontWeight: FontWeight.w800),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// the cart: lines, promotions, member, coupon, discount, total, Pay (side panel on a tablet, its own page on a phone)
class MartCart extends StatelessWidget {
  final MartSellState sell;
  final CartSum sum;
  final bool page;
  const MartCart({super.key, required this.sell, required this.sum, this.page = false});

  @override
  Widget build(BuildContext context) {
    final t = tr(context);
    final c = context.c;
    final pos = MartPos.i;
    final cart = pos.cart;
    final lines = jlist(cart['lines']);
    final cur = pos.currency;
    final d = jmap(cart['discount']);
    final rules = pos.boot['loyalty'];
    final hasCodes = jlist(pos.boot['promos']).any((p) => js(p['code']).isNotEmpty);
    final units = {for (final u in jlist(pos.boot['units'])) js(u['_id']): u};
    String unitOf(J l) {
      final p = pos.products.where((x) => x['_id'] == l['product_id']).firstOrNull;
      final u = jmap(units[js(p?['unit_id'])]);
      if (u.isEmpty) return '';
      return AppState.i.lang == 'km' ? (js(u['name_km']).isNotEmpty ? js(u['name_km']) : js(u['name_en'])) : (js(u['name_en']).isNotEmpty ? js(u['name_en']) : js(u['name_km']));
    }

    Widget pill(IconData icon, String label, VoidCallback? onTap, {bool on = false}) => Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Material(
        color: on ? c.active : c.bg2,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Row(
              children: [
                Icon(icon, size: 16, color: on ? c.brandInk : c.muted),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    label,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontWeight: FontWeight.w600, color: on ? c.brandInk : c.ink),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: EdgeInsets.fromLTRB(14, page ? 4 : 12, 6, 4),
          child: Row(
            children: [
              if (!page) ...[
                Icon(LucideIcons.shoppingCart, size: 18, color: c.brand),
                const SizedBox(width: 6),
                Text(t('mpos.cart'), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                const SizedBox(width: 6),
              ],
              Text(t('mpos.items', {'n': qtyOf(sum.count)}), style: TextStyle(color: c.muted)),
              const Spacer(),
              if (pos.heldCarts.isNotEmpty)
                TextButton.icon(onPressed: () => _held(context), icon: const Icon(LucideIcons.circlePause, size: 15), label: Text('${t('mpos.held')} ${pos.heldCarts.length}')),
              if (lines.isNotEmpty) IconButton(onPressed: () => hold(context), icon: const Icon(LucideIcons.circlePause, size: 18), tooltip: t('mpos.hold')),
              if (lines.isNotEmpty)
                IconButton(
                  onPressed: () => clear(context),
                  icon: Icon(LucideIcons.trash2, size: 18, color: c.danger),
                  tooltip: t('mpos.clear'),
                ),
            ],
          ),
        ),
        Divider(height: 1, color: c.line),
        Expanded(
          child: lines.isEmpty
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(LucideIcons.scanBarcode, size: 34, color: c.muted),
                      const SizedBox(height: 8),
                      Muted(t('mpos.emptyCart')),
                    ],
                  ),
                )
              : ListView.separated(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  itemCount: lines.length,
                  separatorBuilder: (_, _) => Divider(height: 1, indent: 14, endIndent: 14, color: c.line),
                  itemBuilder: (context, i) {
                    final l = lines[i];
                    final u = unitOf(l);
                    return Padding(
                      padding: const EdgeInsets.fromLTRB(14, 8, 10, 8),
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  js(l['name']),
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(fontWeight: FontWeight.w700),
                                ),
                                Text('${f.money(l['price'], cur)}${u.isNotEmpty ? ' / $u' : ''}', style: TextStyle(color: c.muted, fontSize: 12.5)),
                              ],
                            ),
                          ),
                          _QtyBox(
                            qty: nz(l['qty']),
                            onMinus: () => sell.setQty(js(l['key']), nz(l['qty']) - 1),
                            onPlus: () => sell.setQty(js(l['key']), nz(l['qty']) + 1),
                            onType: (v) => sell.setQty(js(l['key']), v),
                          ),
                          SizedBox(
                            width: 76,
                            child: Text(
                              f.money(nz(l['price']) * nz(l['qty']), cur),
                              textAlign: TextAlign.end,
                              style: const TextStyle(fontWeight: FontWeight.w800),
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
        ),
        Container(
          padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
          decoration: BoxDecoration(
            border: Border(top: BorderSide(color: c.line)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final a in sum.promo.applied) SumRow('🏷 ${js(a['name'])}', '−${f.money(a['amount'], cur)}', color: c.good),
              if (rules != null)
                pill(
                  LucideIcons.gift,
                  sum.member != null
                      ? '${js(sum.member!['name']).isNotEmpty ? js(sum.member!['name']) : js(sum.member!['phone'])} · ${t('mx.pointsHave', {'n': nz(sum.member!['points']).round()})}${sum.points > 0 ? ' · −${f.money(sum.money.pointsValue, cur)}' : ''}${sum.earn > 0 ? ' · ${t('mx.willEarn', {'n': sum.earn})}' : ''}'
                      : t('mx.member'),
                  lines.isEmpty ? null : () => _member(context),
                  on: sum.member != null,
                ),
              if (hasCodes)
                pill(
                  LucideIcons.ticket,
                  js(cart['coupon']).isNotEmpty ? '${t('mx.coupon')}: ${js(cart['coupon'])}' : t('mx.coupon'),
                  lines.isEmpty ? null : () => _coupon(context),
                  on: js(cart['coupon']).isNotEmpty,
                ),
              pill(
                LucideIcons.badgePercent,
                d.isNotEmpty ? '${t('mpos.discount')}: −${f.money(sum.money.discount, cur)}${d['type'] == 'pct' ? ' (${qtyOf(d['value'])}%)' : ''}' : t('mpos.addDiscount'),
                lines.isEmpty ? null : () => discount(context, sum),
                on: d.isNotEmpty,
              ),
              const SizedBox(height: 4),
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Expanded(
                    child: Text(t('mpos.total'), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 20)),
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(f.money(sum.money.total, cur), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 24)),
                      if (cur == 'USD')
                        Text(
                          f.money(sum.money.totalKhr, 'KHR'),
                          style: TextStyle(color: c.muted, fontWeight: FontWeight.w600),
                        ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 10),
              SizedBox(
                height: 56,
                child: Btn(t('mpos.pay'), icon: LucideIcons.wallet, expand: true, onTap: lines.isEmpty || pos.readOnly ? null : () => showMartPay(context, sell)),
              ),
            ],
          ),
        ),
      ],
    );
  }

  void clear(BuildContext context) {
    final t = tr(context);
    posSheet(
      context,
      title: t('mpos.clearSure'),
      maxWidth: 420,
      body: (ctx) => Muted('${t('mpos.items', {'n': qtyOf(sum.count)})} · ${f.money(sum.money.total, MartPos.i.currency)}'),
      footer: (ctx) => Row(
        children: [
          Expanded(
            child: Btn(t('mpos.close'), kind: BtnKind.ghost, onTap: () => Navigator.pop(ctx)),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Btn(
              t('mpos.clear'),
              icon: LucideIcons.trash2,
              kind: BtnKind.danger,
              onTap: () {
                sell.reset();
                Navigator.pop(ctx);
              },
            ),
          ),
        ],
      ),
    );
  }

  void hold(BuildContext context) {
    final t = tr(context);
    final pos = MartPos.i;
    final name = TextEditingController();
    final n = pos.heldCarts.length + 1;
    posSheet(
      context,
      title: t('mpos.holdTitle'),
      maxWidth: 440,
      body: (ctx) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Muted(t('mpos.holdSub')),
          const SizedBox(height: 12),
          Field(label: t('mpos.holdName'), controller: name, hint: t('mpos.holdDefault', {'n': n}), maxLength: 40, autofocus: true),
        ],
      ),
      footer: (ctx) => Btn(
        t('mpos.holdSave'),
        icon: LucideIcons.circlePause,
        expand: true,
        onTap: () {
          pos.saveHeld(
            [
              {
                'id': 'h${DateTime.now().millisecondsSinceEpoch}',
                'name': name.text.trim().isEmpty ? t('mpos.holdDefault', {'n': n}) : name.text.trim(),
                'at': DateTime.now().toUtc().toIso8601String(),
                'lines': pos.cart['lines'],
                'discount': pos.cart['discount'],
              },
              ...pos.heldCarts,
            ].take(30).toList(),
          );
          sell.reset();
          Navigator.pop(ctx);
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(t('mpos.heldSaved'))));
        },
      ),
    );
  }

  void _held(BuildContext context) {
    final t = tr(context);
    final pos = MartPos.i;
    posSheet(
      context,
      title: t('mpos.held'),
      body: (ctx) => ListenableBuilder(
        listenable: pos,
        builder: (ctx, _) => Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (pos.heldCarts.isEmpty) Muted(t('mpos.heldEmpty')),
            if (jlist(pos.cart['lines']).isNotEmpty && pos.heldCarts.isNotEmpty) Padding(padding: const EdgeInsets.only(bottom: 8), child: Muted(t('mpos.swapHint'))),
            for (final h in pos.heldCarts)
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(LucideIcons.circlePause),
                title: Text(js(h['name']), style: const TextStyle(fontWeight: FontWeight.w700)),
                subtitle: Text(
                  '${t('mpos.items', {'n': qtyOf(jlist(h['lines']).fold<double>(0, (a, l) => a + nz(l['qty'])))})} · ${jlist(h['lines']).map((l) => js(l['name'])).take(3).join(', ')}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Btn(
                      t('mpos.resume'),
                      small: true,
                      onTap: () {
                        final rest = pos.heldCarts.where((x) => x['id'] != h['id']).toList();
                        // what is in the cart now goes on hold, so nothing is lost
                        if (jlist(pos.cart['lines']).isNotEmpty) {
                          rest.insert(0, {
                            'id': 'h${DateTime.now().millisecondsSinceEpoch}',
                            'name': t('mpos.holdDefault', {'n': rest.length + 1}),
                            'at': DateTime.now().toUtc().toIso8601String(),
                            'lines': pos.cart['lines'],
                            'discount': pos.cart['discount'],
                          });
                        }
                        pos.saveHeld(rest);
                        pos.saveCart({'lines': h['lines'], 'discount': h['discount']});
                        Navigator.pop(ctx);
                      },
                    ),
                    IconButton(onPressed: () => pos.saveHeld(pos.heldCarts.where((x) => x['id'] != h['id']).toList()), icon: const Icon(LucideIcons.trash2, size: 17)),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  void discount(BuildContext context, CartSum sum) {
    final t = tr(context);
    final pos = MartPos.i;
    final cur = pos.currency;
    final d = jmap(pos.cart['discount']);
    var type = js(d['type']).isEmpty ? 'amt' : js(d['type']);
    var value = d.isEmpty ? '' : qtyOf(d['value']);
    final subtotal = sum.money.subtotal - sum.money.promoDiscount;
    posSheet(
      context,
      title: t('mpos.discount'),
      maxWidth: 420,
      body: (ctx) => StatefulBuilder(
        builder: (ctx, set) {
          final v = nz(value);
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              PosChips<String>(value: type, onTap: (x) => set(() => type = x), options: [('amt', cur == 'KHR' ? '៛' : '\$'), ('pct', t('mpos.percent'))]),
              const SizedBox(height: 12),
              Text(
                type == 'pct' ? '${value.isEmpty ? 0 : value}%' : f.money(v, cur),
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 34, fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 10),
              Keypad(value: value, onChanged: (x) => set(() => value = x), dot: type == 'pct' || cur == 'USD', max: 9),
              const SizedBox(height: 8),
              Row(
                children: [
                  if (d.isNotEmpty) ...[
                    Expanded(
                      child: Btn(
                        t('mpos.noDiscount'),
                        kind: BtnKind.ghost,
                        onTap: () {
                          pos.saveCart({...pos.cart, 'discount': null});
                          Navigator.pop(ctx);
                        },
                      ),
                    ),
                    const SizedBox(width: 8),
                  ],
                  Expanded(
                    child: Btn(
                      t('mpos.apply'),
                      onTap: v > 0 && (type == 'pct' ? v <= 100 : v <= subtotal)
                          ? () {
                              pos.saveCart({
                                ...pos.cart,
                                'discount': {'type': type, 'value': v},
                              });
                              Navigator.pop(ctx);
                            }
                          : null,
                    ),
                  ),
                ],
              ),
            ],
          );
        },
      ),
    );
  }

  // loyalty: the customer's phone → their points; use some now
  void _member(BuildContext context) {
    final t = tr(context);
    final pos = MartPos.i;
    final rules = jmap(pos.boot['loyalty']);
    final cur = pos.currency;
    final m0 = jmap(pos.cart['member']);
    final phone = TextEditingController(text: js(m0['phone']));
    final name = TextEditingController(text: m0.isNotEmpty && js(m0['_id']).isEmpty ? js(m0['name']) : '');
    final redeem = TextEditingController(text: nz(pos.cart['redeem']) > 0 ? '${nz(pos.cart['redeem']).toInt()}' : '');
    J? found = js(m0['_id']).isNotEmpty ? m0 : null;
    var looked = m0.isNotEmpty;
    Timer? deb;
    final left = sum.money.subtotal - sum.money.promoDiscount - sum.money.discount;
    posSheet(
      context,
      title: t('mx.member'),
      maxWidth: 440,
      body: (ctx) => StatefulBuilder(
        builder: (ctx, set) {
          final digits = phone.text.replaceAll(RegExp(r'\D'), '');
          final have = nz(found?['points']).floor();
          final pv = nz(rules['point_value']);
          final maxUse = pv > 0 ? [have, (left / pv - 1e-9).ceil()].reduce((a, b) => a < b ? a : b) : 0;
          final n = nz(redeem.text).floor();
          final okRedeem = n == 0 || (found != null && n >= nz(rules['min_redeem']) && n <= have);
          final ok = digits.length >= 8 && looked && okRedeem;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Field(
                controller: phone,
                hint: t('mx.memberPh'),
                keyboard: TextInputType.phone,
                autofocus: true,
                onChanged: (_) {
                  final dg = phone.text.replaceAll(RegExp(r'\D'), '');
                  deb?.cancel();
                  if (dg.length < 8) {
                    set(() {
                      found = null;
                      looked = false;
                    });
                    return;
                  }
                  deb = Timer(const Duration(milliseconds: 250), () async {
                    final r = await pos.lookupMember(dg);
                    set(() {
                      found = r;
                      looked = true;
                    });
                  });
                },
              ),
              const SizedBox(height: 10),
              if (found != null)
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(color: ctx.c.active, borderRadius: BorderRadius.circular(14)),
                  child: Row(
                    children: [
                      Icon(LucideIcons.gift, color: ctx.c.brandInk),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(js(found!['name']).isNotEmpty ? js(found!['name']) : js(found!['phone']), style: const TextStyle(fontWeight: FontWeight.w800)),
                            Text('${t('mx.pointsHave', {'n': have})} ${pv > 0 ? t('mx.pointsWorth', {'amt': f.money(have * pv, cur)}) : ''}'),
                          ],
                        ),
                      ),
                    ],
                  ),
                )
              else if (looked && digits.length >= 8)
                Field(label: '${t('mx.newMember')} · ${t('mx.name')}', controller: name, maxLength: 80),
              if (found != null && have >= nz(rules['min_redeem']) && maxUse > 0) ...[
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: Field(label: '${t('mx.usePoints')} (≥ ${nz(rules['min_redeem']).toInt()})', controller: redeem, keyboard: TextInputType.number, onChanged: (_) => set(() {})),
                    ),
                    const SizedBox(width: 8),
                    Padding(
                      padding: const EdgeInsets.only(top: 26),
                      child: TextButton(onPressed: () => set(() => redeem.text = '$maxUse'), child: Text('$maxUse = −${f.money(left < maxUse * pv ? left : maxUse * pv, cur)}')),
                    ),
                  ],
                ),
              ],
              if (!okRedeem)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text('≥ ${nz(rules['min_redeem']).toInt()} · ≤ $have', style: TextStyle(color: ctx.c.danger)),
                ),
              const SizedBox(height: 14),
              Row(
                children: [
                  if (m0.isNotEmpty) ...[
                    Expanded(
                      child: Btn(
                        t('mx.remove'),
                        kind: BtnKind.ghost,
                        onTap: () {
                          pos.saveCart({...pos.cart, 'member': null, 'redeem': 0});
                          Navigator.pop(ctx);
                        },
                      ),
                    ),
                    const SizedBox(width: 8),
                  ],
                  Expanded(
                    child: Btn(
                      t('mx.save'),
                      icon: LucideIcons.check,
                      onTap: ok
                          ? () {
                              pos.saveCart({
                                ...pos.cart,
                                'member': found != null
                                    ? {'_id': found!['_id'], 'phone': found!['phone'], 'name': found!['name'], 'points': found!['points']}
                                    : {'phone': digits, 'name': name.text.trim(), 'points': 0},
                                'redeem': found != null ? n : 0,
                              });
                              Navigator.pop(ctx);
                            }
                          : null,
                    ),
                  ),
                ],
              ),
            ],
          );
        },
      ),
    );
  }

  void _coupon(BuildContext context) {
    final t = tr(context);
    final pos = MartPos.i;
    final code = TextEditingController(text: js(pos.cart['coupon']));
    var state = '';
    posSheet(
      context,
      title: t('mx.coupon'),
      maxWidth: 420,
      body: (ctx) => StatefulBuilder(
        builder: (ctx, set) => Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Field(controller: code, hint: t('mx.couponPh'), autofocus: true, onChanged: (_) => set(() => state = '')),
            if (state.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(t.or('mx.couponBad.$state', t('mx.couponBad.invalid')), style: TextStyle(color: ctx.c.danger)),
              ),
            const SizedBox(height: 14),
            Row(
              children: [
                if (js(pos.cart['coupon']).isNotEmpty) ...[
                  Expanded(
                    child: Btn(
                      t('mx.remove'),
                      kind: BtnKind.ghost,
                      onTap: () {
                        pos.saveCart({...pos.cart, 'coupon': ''});
                        Navigator.pop(ctx);
                      },
                    ),
                  ),
                  const SizedBox(width: 8),
                ],
                Expanded(
                  child: Btn(
                    t('mx.save'),
                    icon: LucideIcons.check,
                    onTap: () {
                      final c = code.text.trim().toUpperCase();
                      if (c.isEmpty) {
                        pos.saveCart({...pos.cart, 'coupon': ''});
                        Navigator.pop(ctx);
                        return;
                      }
                      final catOf = {for (final x in pos.products) js(x['_id']): js(x['category_id'])};
                      final st = applyMartPromos(lines: jlist(pos.cart['lines']), promos: jlist(pos.boot['promos']), at: DateTime.now(), coupon: c, currency: pos.currency, categoryOf: catOf).coupon;
                      if (st != 'ok') return set(() => state = st);
                      pos.saveCart({...pos.cart, 'coupon': c});
                      Navigator.pop(ctx);
                    },
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _QtyBox extends StatelessWidget {
  final double qty;
  final VoidCallback onMinus, onPlus;
  final ValueChanged<double> onType;
  const _QtyBox({required this.qty, required this.onMinus, required this.onPlus, required this.onType});
  @override
  Widget build(BuildContext context) {
    final c = context.c;
    Widget b(IconData i, VoidCallback f) => InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: f,
      child: SizedBox(width: 34, height: 34, child: Icon(i, size: 16)),
    );
    return Container(
      decoration: BoxDecoration(color: c.bg2, borderRadius: BorderRadius.circular(12)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          b(LucideIcons.minus, onMinus),
          InkWell(
            onTap: () async {
              var v = qtyOf(qty);
              final r = await posSheet<double>(
                context,
                title: tr(context)('mpos.qty'),
                maxWidth: 380,
                body: (ctx) => StatefulBuilder(
                  builder: (ctx, set) => Column(
                    children: [
                      Text(v.isEmpty ? '0' : v, style: const TextStyle(fontSize: 34, fontWeight: FontWeight.w800)),
                      const SizedBox(height: 10),
                      Keypad(value: v, onChanged: (x) => set(() => v = x), dot: true, max: 8, enterLabel: tr(ctx)('mpos.apply'), onEnter: () => Navigator.pop(ctx, nz(v))),
                    ],
                  ),
                ),
              );
              if (r != null) onType(r);
            },
            child: SizedBox(
              width: 40,
              child: Text(
                qtyOf(qty),
                textAlign: TextAlign.center,
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
            ),
          ),
          b(LucideIcons.plus, onPlus),
        ],
      ),
    );
  }
}

// camera scanning (phones / tablets); USB / Bluetooth scanners type into the scan box
class _Scan extends StatefulWidget {
  const _Scan();
  @override
  State<_Scan> createState() => _ScanState();
}

class _ScanState extends State<_Scan> {
  final _cam = MobileScannerController(detectionSpeed: DetectionSpeed.noDuplicates);
  bool _done = false;
  @override
  void dispose() {
    _cam.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = tr(context);
    return SizedBox(
      height: MediaQuery.sizeOf(context).height * .7,
      child: Stack(
        children: [
          Positioned.fill(
            child: MobileScanner(
              controller: _cam,
              onDetect: (cap) {
                final v = cap.barcodes.map((b) => b.rawValue ?? '').firstWhere((x) => x.isNotEmpty, orElse: () => '');
                if (v.isEmpty || _done) return;
                _done = true;
                HapticFeedback.mediumImpact();
                Navigator.pop(context, v.trim());
              },
              errorBuilder: (_, e) => Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(
                    t('mpos.cameraNo'),
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.white),
                  ),
                ),
              ),
            ),
          ),
          Center(
            child: Container(
              width: 260,
              height: 150,
              decoration: BoxDecoration(
                border: Border.all(color: Colors.white, width: 3),
                borderRadius: BorderRadius.circular(16),
              ),
            ),
          ),
          Positioned(
            left: 16,
            right: 16,
            bottom: 24,
            child: Text(
              t('mpos.cameraHint'),
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
            ),
          ),
          Positioned(
            top: 8,
            right: 8,
            child: IconButton(
              onPressed: () => Navigator.pop(context),
              icon: const Icon(LucideIcons.x, color: Colors.white),
            ),
          ),
        ],
      ),
    );
  }
}

// ---------- pay ----------
Future<void> showMartPay(BuildContext context, MartSellState sell) async {
  final t = tr(context);
  final done = await posSheet<(J, bool)>(context, title: t('mpos.pay'), maxWidth: 900, body: (_) => const _Pay());
  if (done == null || !context.mounted) return;
  sell.reset();
  if (Navigator.of(context).canPop()) Navigator.of(context).popUntil((r) => r.isFirst); // the cart page on a phone
  await showMartDone(context, done.$1, offline: done.$2);
}

class _Pay extends StatefulWidget {
  const _Pay();
  @override
  State<_Pay> createState() => _PayState();
}

class _PayState extends State<_Pay> {
  final pos = MartPos.i;
  // the shop's payment methods (cash when none) + "debt" with the debt book add-on
  late final List<String> methods = () {
    final raw = pos.settings['methods'] is List ? (pos.settings['methods'] as List).map((e) => '$e').toList() : <String>[];
    return [
      ...(raw.isEmpty ? ['cash'] : raw),
      if (pos.boot['debt'] == true) 'debt',
    ];
  }();
  late String method = methods.contains('cash') ? 'cash' : (methods.isEmpty ? 'cash' : methods.first);
  String _usd = '', _khr = '', _field = 'usd', _error = '';
  bool _busy = false;
  J? debtor;
  final _dq = TextEditingController();

  @override
  void initState() {
    super.initState();
    _field = pos.currency == 'KHR' ? 'khr' : 'usd';
  }

  @override
  void dispose() {
    _dq.dispose();
    MartDisplayFeed.i.paying(false);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = tr(context);
    final c = context.c;
    final cur = pos.currency;
    final sum = cartSum(pos.cart);
    final lines = jlist(pos.cart['lines']);
    final m = saleMoney(
      lines: lines,
      discount: sum.money.discount,
      promo: sum.promo.discount,
      points: sum.money.pointsValue,
      currency: cur,
      rate: pos.rate,
      method: method,
      paidUsd: nz(_usd),
      paidKhr: nz(_khr),
      khrRound: pos.khrRound,
    );
    final nothing = method == 'cash' && !(nz(_usd) > 0) && !(nz(_khr) > 0);
    final can = !_busy && (method == 'debt' ? (js(debtor?['_id']).isNotEmpty || js(debtor?['name']).isNotEmpty) : (method != 'cash' || nothing || m.short == 0));
    final custom = jlist(pos.settings['custom_methods']).where((x) => x['key'] == method).firstOrNull;
    final qr = method != 'cash' && method != 'debt' && (custom != null ? js(custom['qr']).isNotEmpty : ['aba', 'khqr', 'acleda', 'wing'].contains(method));
    final qrImg = custom != null ? js(custom['qr']) : js(pos.settings['pay_qr']);
    final qrLabel = custom != null ? js(custom['name']) : js(pos.settings['pay_qr_label']);
    final split = cur == 'USD' ? changeSplit(m.change, pos.rate, pos.khrRound) : null;
    // the customer screen shows the QR to scan
    WidgetsBinding.instance.addPostFrameCallback((_) => MartDisplayFeed.i.paying(true, qr: qr ? qrImg : '', label: qr ? qrLabel : ''));

    Future<void> confirm() async {
      if (!can) return;
      setState(() {
        _busy = true;
        _error = '';
      });
      final exact = method == 'cash' && nothing; // nothing typed = the customer paid the exact amount
      final cart = pos.cart;
      final member = sum.member;
      try {
        final r = await pos.sell({
          'items': [
            for (final l in lines) {'product_id': l['product_id'], 'name': l['name'], 'barcode': js(l['barcode']), 'price': l['price'], 'qty': l['qty']},
          ],
          'discount': sum.money.discount,
          if (js(cart['coupon']).isNotEmpty && sum.promo.coupon == 'ok') 'coupon': cart['coupon'],
          if (member != null) ...{
            'member_phone': member['phone'],
            if (js(member['_id']).isNotEmpty) 'member_id': member['_id'] else 'member_name': js(member['name']),
            if (sum.points > 0) 'redeem': sum.points,
          },
          'method': method,
          'paid_usd': exact ? (cur == 'USD' ? m.total : 0) : nz(_usd),
          'paid_khr': exact ? (cur == 'KHR' ? m.total : 0) : nz(_khr),
          if (method == 'debt')
            ...(js(debtor!['_id']).isNotEmpty
                ? {'debtor_id': debtor!['_id']}
                : {
                    'new_debtor': {'name': debtor!['name'], 'phone': js(debtor!['phone'])},
                  }),
        });
        if (context.mounted) Navigator.pop(context, r);
      } on ApiError catch (e) {
        if (mounted) {
          setState(() {
            _error = e.code == 'short' ? t('mpos.short', {'amt': f.money(e.body['short'], cur)}) : e.message;
            _busy = false;
          });
        }
      }
    }

    final small = !wide(context); // a phone: everything must fit above the Confirm button
    final due = Container(
      padding: EdgeInsets.all(small ? 10 : 14),
      decoration: BoxDecoration(gradient: c.gradient, borderRadius: BorderRadius.circular(20)),
      child: Column(
        children: [
          Text(
            t('mpos.total'),
            style: TextStyle(color: Colors.white.withValues(alpha: .85), fontWeight: FontWeight.w600),
          ),
          FittedBox(
            child: Text(
              f.money(m.total, cur),
              style: TextStyle(color: Colors.white, fontSize: small ? 28 : 34, fontWeight: FontWeight.w800),
            ),
          ),
          if (cur == 'USD')
            Text(
              f.money(m.totalKhr, 'KHR'),
              style: TextStyle(color: Colors.white.withValues(alpha: .85), fontWeight: FontWeight.w700),
            ),
        ],
      ),
    );
    final methodChips = PosChips<String>(value: method, onTap: (v) => setState(() => method = v), options: [for (final k in methods) (k, methodLabel(t, pos.settings, k))]);

    Widget cashPart() {
      final change = nothing
          ? const SizedBox.shrink()
          : Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(color: m.short > 0 ? c.dangerBg : c.goodBg, borderRadius: BorderRadius.circular(16)),
              child: m.short > 0
                  ? Text(
                      t('mpos.short', {'amt': cur == 'USD' ? '${f.money(m.short, cur)} (${f.money((m.short * pos.rate / pos.khrRound).ceil() * pos.khrRound, 'KHR')})' : f.money(m.short, cur)}),
                      textAlign: TextAlign.center,
                      style: TextStyle(color: c.danger, fontWeight: FontWeight.w800, fontSize: 16),
                    )
                  : Column(
                      children: [
                        Text(
                          t('mpos.giveBack'),
                          style: TextStyle(color: c.good, fontWeight: FontWeight.w600),
                        ),
                        Text(
                          cur == 'USD' ? f.money(m.changeKhr, 'KHR') : f.money(m.change, cur),
                          style: TextStyle(color: c.good, fontWeight: FontWeight.w800, fontSize: 26),
                        ),
                        if (cur == 'USD' && m.change > 0)
                          Text(
                            '= ${f.money(m.change, cur)}${split!.usd > 0 && split.khr > 0 ? ' · \$${split.usd.toInt()} + ${f.money(split.khr, 'KHR')}' : ''}',
                            style: TextStyle(color: c.good, fontWeight: FontWeight.w600),
                          ),
                      ],
                    ),
            );
      final quick = _field == 'usd' ? [1, 5, 10, 20, 50, 100] : [1000, 5000, 10000, 20000, 50000, 100000];
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: AmountBox(label: t('mpos.usdIn'), value: f.money(nz(_usd), 'USD'), on: _field == 'usd', onTap: () => setState(() => _field = 'usd')),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: AmountBox(label: t('mpos.khrIn'), value: f.money(nz(_khr), 'KHR'), on: _field == 'khr', onTap: () => setState(() => _field = 'khr')),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              ActionChip(
                label: Text(t('mpos.exact'), style: const TextStyle(fontWeight: FontWeight.w800)),
                onPressed: () => setState(() {
                  if (cur == 'USD') {
                    _usd = qtyOf(m.total);
                    _khr = '';
                  } else {
                    _khr = qtyOf(m.total);
                    _usd = '';
                  }
                }),
              ),
              for (final n in quick)
                ActionChip(
                  label: Text(_field == 'usd' ? '+\$$n' : '+${n >= 1000 ? '${n ~/ 1000}k' : n}'),
                  onPressed: () => setState(() => _field == 'usd' ? _usd = qtyOf(((nz(_usd) + n) * 100).round() / 100) : _khr = qtyOf(nz(_khr) + n)),
                ),
              ActionChip(label: Text(t('mpos.reset')), onPressed: () => setState(() => _usd = _khr = '')),
            ],
          ),
          const SizedBox(height: 8),
          Keypad(value: _field == 'usd' ? _usd : _khr, onChanged: (v) => setState(() => _field == 'usd' ? _usd = v : _khr = v), dot: _field == 'usd', max: 10, keyHeight: wide(context) ? 50 : 42),
          const SizedBox(height: 8),
          change,
        ],
      );
    }

    Widget debtPart() {
      final debtors = jlist(pos.boot['debtors']);
      final q = _dq.text.trim().toLowerCase();
      final found = (q.isEmpty ? debtors : debtors.where((d) => js(d['name']).toLowerCase().contains(q) || js(d['phone']).contains(q))).take(6).toList();
      String owes(J d) => nz(d['balance']) > 0 ? t('mart.debtOwes', {'amt': f.money(d['balance'], cur)}) : t('mart.clear2');
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(t('mart.debtPickTitle'), style: const TextStyle(fontWeight: FontWeight.w800)),
          const SizedBox(height: 8),
          if (debtor != null)
            ListTile(
              tileColor: c.active,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              title: Text(js(debtor!['name']), style: const TextStyle(fontWeight: FontWeight.w800)),
              subtitle: Text(js(debtor!['_id']).isNotEmpty ? owes(debtor!) : t('mart.debtNew')),
              trailing: IconButton(onPressed: () => setState(() => debtor = null), icon: const Icon(LucideIcons.x)),
            )
          else ...[
            Field(controller: _dq, hint: t('mart.debtPick'), icon: LucideIcons.search, onChanged: (_) => setState(() {})),
            const SizedBox(height: 6),
            for (final d in found)
              ListTile(
                dense: true,
                title: Text(js(d['name']), style: const TextStyle(fontWeight: FontWeight.w700)),
                subtitle: Text('${js(d['phone']).isNotEmpty ? '${js(d['phone'])} · ' : ''}${owes(d)}'),
                onTap: () => setState(() => debtor = d),
              ),
            if (q.isNotEmpty && !debtors.any((d) => js(d['name']).toLowerCase() == q))
              ListTile(
                dense: true,
                leading: const Icon(LucideIcons.plus),
                title: Text(t('mart.debtNew'), style: const TextStyle(fontWeight: FontWeight.w700)),
                subtitle: Text('“${_dq.text.trim()}”'),
                onTap: () => setState(() => debtor = {'name': _dq.text.trim()}),
              ),
          ],
          const SizedBox(height: 6),
          Muted(t('mart.debtConfirmHint')),
        ],
      );
    }

    final body = method == 'cash'
        ? cashPart()
        : method == 'debt'
        ? debtPart()
        : qr
        ? Column(
            children: [
              if (qrImg.isNotEmpty) ...[
                Container(
                  color: Colors.white,
                  padding: const EdgeInsets.all(8),
                  child: Image(image: netImage(qrImg), width: 220, height: 220, fit: BoxFit.contain),
                ),
                if (qrLabel.isNotEmpty) Text(qrLabel, style: const TextStyle(fontWeight: FontWeight.w700)),
                Muted(t('mpos.scanQr')),
              ] else
                Muted(t('mpos.noQr')),
            ],
          )
        : const SizedBox.shrink();

    final confirmBtn = SizedBox(
      height: 58,
      child: Btn(t('mpos.confirm'), icon: LucideIcons.check, busy: _busy, expand: true, onTap: can ? confirm : null),
    );
    if (wide(context)) {
      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                due,
                const SizedBox(height: 12),
                methodChips,
                if (_error.isNotEmpty) ...[const SizedBox(height: 10), Alert(_error)],
                const SizedBox(height: 14),
                confirmBtn,
              ],
            ),
          ),
          const SizedBox(width: 18),
          Expanded(child: body),
        ],
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        due,
        const SizedBox(height: 12),
        methodChips,
        const SizedBox(height: 12),
        body,
        if (_error.isNotEmpty) ...[const SizedBox(height: 10), Alert(_error)],
        const SizedBox(height: 12),
        confirmBtn,
      ],
    );
  }
}

// paid: the change to give back, the receipt, print, new sale
Future<void> showMartDone(BuildContext context, J sale, {required bool offline}) async {
  final t = tr(context);
  final pos = MartPos.i;
  final bar = ScaffoldMessenger.of(context);
  MartDisplayFeed.i.thanks(sale);
  await MartPrint.load();
  if (MartPrint.auto && MartPrint.printer.on) {
    MartPrint.receipt(sale).catchError((e) {
      bar.showSnackBar(SnackBar(content: Text('${t('rp.failed')} ${martPrintError(e)}')));
    });
  }
  final doc = await MartPrint.doc(sale);
  if (!context.mounted) return;
  final cur = pos.currency;
  final split = cur == 'USD' && nz(sale['change']) > 0 ? changeSplit(nz(sale['change']), nz(sale['khr_rate']) == 0 ? pos.rate : nz(sale['khr_rate']), pos.khrRound) : null;
  await posSheet(
    context,
    title: '${t('mpos.paidOk')} · ${js(sale['no'])}',
    maxWidth: 460,
    body: (ctx) {
      final c = ctx.c;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (sale['method'] == 'cash' && nz(sale['change']) > 0)
            Container(
              padding: const EdgeInsets.all(14),
              margin: const EdgeInsets.only(bottom: 12),
              decoration: BoxDecoration(color: c.goodBg, borderRadius: BorderRadius.circular(16)),
              child: Column(
                children: [
                  Text(
                    t('mpos.giveBack'),
                    style: TextStyle(color: c.good, fontWeight: FontWeight.w600),
                  ),
                  Text(
                    cur == 'USD' ? f.money(sale['change_khr'], 'KHR') : f.money(sale['change'], cur),
                    style: TextStyle(color: c.good, fontWeight: FontWeight.w800, fontSize: 30),
                  ),
                  if (split != null)
                    Text(
                      '= ${f.money(sale['change'], cur)}${split.usd > 0 && split.khr > 0 ? ' · \$${split.usd.toInt()} + ${f.money(split.khr, 'KHR')}' : ''}',
                      style: TextStyle(color: c.good, fontWeight: FontWeight.w600),
                    ),
                ],
              ),
            ),
          if (offline)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Alert(t('mpos.savedOffline'), tone: Tone.warn),
            ),
          Center(
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
        ],
      );
    },
    footer: (ctx) => Row(
      children: [
        Expanded(
          child: Btn(
            t('mpos.print'),
            icon: MartPrint.printer.on ? LucideIcons.printer : LucideIcons.lock,
            kind: BtnKind.ghost,
            onTap: () async {
              final bar = ScaffoldMessenger.of(ctx);
              if (!MartPrint.printer.on) {
                Navigator.pop(ctx);
                openMartPrinters(context);
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
        const SizedBox(width: 8),
        Expanded(child: Btn(t('mpos.newSale'), onTap: () => Navigator.pop(ctx))),
      ],
    ),
  );
}
