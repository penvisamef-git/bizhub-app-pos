// Mini Mart money rules — the same as the web (pos/mart/calc.js, promo.js, scale.js) and the API (mart.calc.js,
// mart.promo-calc.js), so a sale made offline adds up exactly like the server will work it out.
import '../../restaurant/engine/calc.dart' show J, js, nz, jsRound;

double Function(num) roundOf(String currency) =>
    (v) => currency == 'KHR' ? jsRound(v.toDouble()) : jsRound(v * 100) / 100;

class SaleMoney {
  final List<J> items;
  final double subtotal, discount, promoDiscount, pointsValue, total, totalKhr, paid, change, changeKhr, short;
  const SaleMoney(this.items, this.subtotal, this.discount, this.promoDiscount, this.pointsValue, this.total, this.totalKhr, this.paid, this.change, this.changeKhr, this.short);
}

double _clampMin0(double v) => v < 0 ? 0 : v;
double _min(double a, double b) => a < b ? a : b;

//   lines: [{ price, qty }]  discount (shop currency)  promo (promotions)  points (loyalty money)  method  paidUsd + paidKhr (cash received)
SaleMoney saleMoney({
  required List<J> lines,
  double discount = 0,
  double promo = 0,
  double points = 0,
  String currency = 'USD',
  double rate = 4100,
  String method = 'cash',
  double paidUsd = 0,
  double paidKhr = 0,
  double khrRound = 100,
}) {
  final r = roundOf(currency);
  final items = [
    for (final l in lines) {...l, 'total': r(nz(l['price']) * nz(l['qty']))},
  ];
  final subtotal = r(items.fold<double>(0, (a, l) => a + nz(l['total'])));
  final promoOff = r(_min(_clampMin0(promo), subtotal));
  final disc = r(_min(_clampMin0(discount), subtotal - promoOff));
  final pointsOff = r(_min(_clampMin0(points), subtotal - promoOff - disc));
  final total = r(subtotal - promoOff - disc - pointsOff);
  final totalKhr = currency == 'KHR' ? total : jsRound((total * rate) / khrRound) * khrRound;
  if (method != 'cash') return SaleMoney(items, subtotal, disc, promoOff, pointsOff, total, totalKhr, total, 0, 0, 0);
  final usd = _clampMin0(paidUsd), khr = _clampMin0(paidKhr);
  final paid = currency == 'USD' ? usd + khr / rate : usd * rate + khr;
  // riel is rounded at the counter: up to one rounding step short still counts as paid
  final slack = currency == 'USD' ? khrRound / rate : khrRound;
  final diff = paid - total;
  final short = diff + slack / 2 < 0 ? r(-diff) : 0.0;
  final change = _clampMin0(r(diff));
  final inKhr = currency == 'USD' ? change * rate : change;
  final changeKhr = _clampMin0(jsRound(inKhr / khrRound) * khrRound);
  return SaleMoney(items, subtotal, disc, promoOff, pointsOff, total, totalKhr, r(paid), change, changeKhr, short);
}

// change in a USD shop as people give it: whole dollars + the rest in riel
({double usd, double khr}) changeSplit(double change, double rate, [double round = 100]) {
  final usd = (change + 1e-9).floorToDouble();
  final khr = jsRound(((change - usd) * rate) / round) * round;
  return (usd: usd, khr: khr);
}

// ---------- promotions ----------
String _two(int x) => x.toString().padLeft(2, '0');
({String day, String hm, int dow}) localParts(DateTime at) {
  final d = at.toUtc().add(const Duration(hours: 7)); // Cambodia time
  return (day: '${d.year}-${_two(d.month)}-${_two(d.day)}', hm: '${_two(d.hour)}:${_two(d.minute)}', dow: d.weekday % 7);
}

bool promoLive(J p, DateTime at, String where) {
  if (p['active'] == false) return false;
  final w = js(p['where']);
  if (where.isNotEmpty && w.isNotEmpty && w != 'both' && w != where) return false;
  if (nz(p['max_uses']) > 0 && nz(p['uses']) >= nz(p['max_uses'])) return false;
  final t = localParts(at);
  final from = js(p['date_from']), to = js(p['date_to']);
  if (from.isNotEmpty && t.day.compareTo(from) < 0) return false;
  if (to.isNotEmpty && t.day.compareTo(to) > 0) return false;
  final days = p['days'] is List ? (p['days'] as List).map((e) => nz(e).toInt()).toList() : const <int>[];
  if (days.isNotEmpty && !days.contains(t.dow)) return false;
  final tf = js(p['time_from']), tt = js(p['time_to']);
  if (tf.isNotEmpty && tt.isNotEmpty && tf != tt) {
    final inside = tf.compareTo(tt) < 0 ? (t.hm.compareTo(tf) >= 0 && t.hm.compareTo(tt) < 0) : (t.hm.compareTo(tf) >= 0 || t.hm.compareTo(tt) < 0);
    if (!inside) return false;
  }
  return true;
}

const _order = {'bxgy': 0, 'percent': 1, 'amount': 2};

class PromoResult {
  final double subtotal, discount;
  final List<J> applied; // [{ id, name, amount, code }]
  final String coupon; // "" | ok | invalid | expired | min_spend | no_match
  const PromoResult(this.subtotal, this.discount, this.applied, this.coupon);
  static const none = PromoResult(0, 0, [], '');
}

class _Row {
  final String pid;
  final double price, qty, total;
  double left;
  _Row(this.pid, this.price, this.qty, this.total) : left = total;
}

PromoResult applyMartPromos({
  required List<J> lines,
  required List<J> promos,
  required DateTime at,
  String where = 'pos',
  String coupon = '',
  String currency = 'USD',
  Map<String, String> categoryOf = const {},
}) {
  final r = roundOf(currency);
  final code = coupon.trim().toUpperCase();
  final rows = [for (final l in lines) _Row(l['product_id'] == null ? '' : js(l['product_id']), nz(l['price']), nz(l['qty']), r(nz(l['price']) * nz(l['qty'])))];
  final subtotal = r(rows.fold<double>(0, (a, x) => a + x.total));
  var couponState = '';
  if (code.isNotEmpty) {
    final cp = promos.where((p) => js(p['code']).isNotEmpty && js(p['code']) == code).firstOrNull;
    couponState = cp == null
        ? 'invalid'
        : !promoLive(cp, at, where)
        ? 'expired'
        : (nz(cp['min_spend']) > 0 && subtotal < nz(cp['min_spend']))
        ? 'min_spend'
        : 'ok';
  }
  List<String> ids(Object? v) => v is List ? v.map((e) => '$e').toList() : const [];
  bool fits(J p, _Row row) {
    final target = js(p['target']);
    if (target.isEmpty || target == 'all') return true;
    if (row.pid.isEmpty) return false;
    if (target == 'products') return ids(p['product_ids']).contains(row.pid);
    return ids(p['category_ids']).contains(categoryOf[row.pid] ?? '');
  }

  final live = promos.where((p) => promoLive(p, at, where) && (js(p['code']).isEmpty || js(p['code']) == code) && !(nz(p['min_spend']) > 0 && subtotal < nz(p['min_spend']))).toList();
  // stable sort by kind (like Array.sort in JS engines today)
  final indexed = [for (var i = 0; i < live.length; i++) (i, live[i])];
  indexed.sort((a, b) {
    final c = (_order[js(a.$2['kind'])] ?? 9).compareTo(_order[js(b.$2['kind'])] ?? 9);
    return c != 0 ? c : a.$1.compareTo(b.$1);
  });
  final applied = <J>[];
  for (final (_, p) in indexed) {
    final mine = rows.where((row) => row.left > 0 && fits(p, row)).toList();
    double amount = 0;
    double take(_Row row, double v) {
      final x = r(_min(row.left, v));
      row.left = r(row.left - x);
      amount += x;
      return x;
    }

    final kind = js(p['kind']);
    if (kind == 'bxgy') {
      final buy = nz(p['buy_qty']), get = nz(p['get_qty']);
      if (!(buy > 0) || !(get > 0)) continue;
      final n = buy + get;
      final groups = <String, List<_Row>>{};
      for (final row in mine) {
        if (row.pid.isNotEmpty) (groups[row.pid] ??= []).add(row);
      }
      for (final g in groups.values) {
        final qty = (g.fold<double>(0, (a, x) => a + x.qty) + 1e-9).floorToDouble();
        final free = (qty / n).floorToDouble() * get;
        if (free == 0) continue;
        var want = r(free * g.map((x) => x.price).reduce(_min));
        for (final row in g) {
          if (want > 0) want = r(want - take(row, want));
        }
      }
    } else if (kind == 'percent') {
      final pct = nz(p['value']).clamp(0, 100).toDouble();
      for (final row in mine) {
        take(row, r((row.left * pct) / 100));
      }
    } else if (kind == 'amount') {
      var want = r(_clampMin0(nz(p['value'])));
      for (final row in mine) {
        if (want > 0) want = r(want - take(row, want));
      }
    }
    amount = r(amount);
    if (amount > 0) applied.add({'id': js(p['_id']), 'name': js(p['name']), 'amount': amount, 'code': js(p['code'])});
  }
  if (couponState == 'ok' && !applied.any((x) => x['code'] == code)) couponState = 'no_match';
  final discount = r(_min(subtotal, applied.fold<double>(0, (a, x) => a + nz(x['amount']))));
  return PromoResult(subtotal, discount, applied, couponState);
}

// ---------- weighing-scale labels ----------
// EAN-13 = prefix + item code (PLU) + weight in grams (or the price) + check digit → { plu, weight (kg) | price }
({String plu, double? weight, double? price})? parseScale(String code, J? cfg, [String currency = 'USD']) {
  final c = code.trim();
  if (cfg == null || !RegExp(r'^\d{13}$').hasMatch(c)) return null;
  final prefix = js(cfg['prefix']).isEmpty ? '2' : js(cfg['prefix']);
  if (!c.startsWith(prefix)) return null;
  var sum = 0;
  for (var i = 0; i < 12; i++) {
    sum += int.parse(c[i]) * (i.isOdd ? 3 : 1);
  }
  if ((10 - (sum % 10)) % 10 != int.parse(c[12])) return null;
  final p = js(cfg['prefix']).length;
  final len = nz(cfg['item_len']) == 0 ? 5 : nz(cfg['item_len']).toInt();
  final plu = c.substring(p, p + len);
  final value = double.parse(c.substring(p + len, 12));
  if (value == 0) return null;
  if (cfg['mode'] == 'price') return (plu: plu, weight: null, price: currency == 'KHR' ? value : value / 100);
  return (plu: plu, weight: value / 1000, price: null);
}

J? byPlu(List<J> products, String plu) {
  final n = int.tryParse(plu);
  for (final x in products) {
    if (js(x['plu']).isNotEmpty && int.tryParse(js(x['plu'])) == n) return x;
  }
  return null;
}
