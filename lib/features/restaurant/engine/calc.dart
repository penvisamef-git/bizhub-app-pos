// POS money rules — the same as the web POS (bizhub/src/pos/calc.js) and the API (pos.calc.js).
// Keep the three the same: a bill must add up to the same total on the app, the web and the cloud.
//   settings (money) = { currency: "USD"|"KHR", khr_rate, khr_rounding, vat: {enabled, rate, included}, service_charge: {enabled, rate} }
// Orders, lines and payments are kept as JSON maps (exactly what is sent to the cloud).

typedef J = Map<String, dynamic>;

// JS Number(v) || 0
double nz(Object? v) {
  if (v is num) return v.isFinite ? v.toDouble() : 0;
  if (v is bool) return v ? 1 : 0;
  final x = double.tryParse('${v ?? ''}'.trim());
  return x == null || !x.isFinite ? 0 : x;
}

J jmap(Object? v) => v is Map ? Map<String, dynamic>.from(v) : <String, dynamic>{};
List<J> jlist(Object? v) => v is List ? v.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList() : <J>[];
String js(Object? v) => v == null ? '' : '$v';

// Math.round (halves go up, like JS)
double jsRound(double x) => (x + 0.5).floorToDouble();
const _eps = 2.220446049250313e-16;
double round2(Object? n) => jsRound((nz(n) + _eps) * 100) / 100;
double roundStep(Object? n, Object? step) {
  final s = nz(step) == 0 ? 1.0 : nz(step);
  return jsRound(nz(n) / s) * s;
}

double _khrStep(J s) => nz(s['khr_rounding']) == 0 ? 100 : nz(s['khr_rounding']);
double _rate(J s) => nz(s['khr_rate']) == 0 ? 4100 : nz(s['khr_rate']);
String cur(J s) => js(s['currency']).isEmpty ? 'USD' : js(s['currency']);

// money in the main currency, rounded the way that currency is paid
double money(Object? n, J s) => cur(s) == 'KHR' ? roundStep(n, _khrStep(s)) : round2(n);

// one line: qty × (price + add-ons); a cancelled line counts 0
double lineTotal(J? line) {
  if (line == null || line['status'] == 'void') return 0;
  final addons = jlist(line['addons']).fold<double>(0, (a, x) => a + nz(x['price']));
  return nz(line['qty']) * (nz(line['unit_price']) + addons);
}

// a payment's worth in the main currency
double paymentValue(J p, J s) {
  final amount = nz(p['amount']);
  if (js(p['currency']) == cur(s)) return amount;
  return cur(s) == 'USD' ? round2(amount / _rate(s)) : roundStep(amount * _rate(s), _khrStep(s));
}

// the other currency, shown beside a total
double otherCurrency(Object? n, J s) => cur(s) == 'USD' ? roundStep(nz(n) * _rate(s), _khrStep(s)) : round2(nz(n) / _rate(s));

double _clamp100(Object? v) => nz(v).clamp(0, 100).toDouble();

// money off one line: the cashier's discount, else the promotion's (never more than the line)
double lineOff(J line) {
  final t = lineTotal(line);
  if (t == 0) return 0;
  final d = jmap(line['discount']);
  double off;
  if (d['kind'] == 'percent') {
    off = (t * _clamp100(d['value'])) / 100;
  } else if (d['kind'] == 'amount') {
    off = nz(d['value']) < 0 ? 0 : nz(d['value']);
  } else {
    final p = nz(jmap(line['promo'])['off']);
    off = p < 0 ? 0 : p;
  }
  final r = round2(off);
  return t < r ? t : r;
}

class Totals {
  final double subtotal, discount, itemDiscount, rewardDiscount, billDiscount, service, vat, total, other, paid, due, change, changeOther;
  final bool vatIncluded, settled;
  final double items;
  const Totals({
    required this.subtotal,
    required this.discount,
    required this.itemDiscount,
    required this.rewardDiscount,
    required this.billDiscount,
    required this.service,
    required this.vat,
    required this.vatIncluded,
    required this.total,
    required this.other,
    required this.paid,
    required this.due,
    required this.change,
    required this.changeOther,
    required this.settled,
    required this.items,
  });
}

Totals calcOrder(J order, J s) {
  final lines = jlist(order['lines']);
  final subtotal = money(lines.fold<double>(0, (a, l) => a + lineTotal(l)), s);
  final itemDiscount = money(lines.fold<double>(0, (a, l) => a + lineOff(l)), s);
  final rw = jmap(order['reward_discount']);
  double rewardDiscount = 0;
  if (rw['kind'] == 'percent') {
    rewardDiscount = money(((subtotal - itemDiscount) * _clamp100(rw['value'])) / 100, s);
  } else if (rw['kind'] == 'amount') {
    final v = nz(rw['value']) < 0 ? 0.0 : nz(rw['value']);
    rewardDiscount = money((subtotal - itemDiscount) < v ? subtotal - itemDiscount : v, s);
  }
  final afterItems = subtotal - itemDiscount - rewardDiscount;
  final d = jmap(order['discount']);
  double billDiscount = 0;
  if (d['kind'] == 'percent') {
    billDiscount = money((afterItems * _clamp100(d['value'])) / 100, s);
  } else if (d['kind'] == 'amount') {
    final v = nz(d['value']) < 0 ? 0.0 : nz(d['value']);
    billDiscount = money(afterItems < v ? afterItems : v, s);
  }
  final discount = itemDiscount + rewardDiscount + billDiscount;
  final afterDiscount = subtotal - discount;
  final svc = jmap(s['service_charge']);
  final service = svc['enabled'] == true && order['type'] != 'takeaway' ? money((afterDiscount * nz(svc['rate'])) / 100, s) : 0.0;
  final base = afterDiscount + service;
  final vatS = jmap(s['vat']);
  final rate = nz(vatS['rate']);
  double vat = 0;
  var total = base;
  if (vatS['enabled'] == true && rate > 0) {
    if (vatS['included'] == true) {
      vat = money((base * rate) / (100 + rate), s);
    } else {
      vat = money((base * rate) / 100, s);
      total = base + vat;
    }
  }
  total = money(total, s);
  final paid = money(jlist(order['payments']).fold<double>(0, (a, p) => a + paymentValue(p, s)), s);
  final rawDue = total - paid;
  final step = _khrStep(s);
  final settled = rawDue <= 0 || (cur(s) == 'USD' ? otherCurrency(rawDue, s) == 0 : rawDue < step / 2);
  final due = settled ? 0.0 : money(rawDue, s);
  final change = rawDue < 0 ? money(-rawDue, s) : 0.0;
  final count = lines.where((l) => l['status'] != 'void').fold<double>(0, (a, l) => a + nz(l['qty']));
  return Totals(
    subtotal: subtotal,
    discount: discount,
    itemDiscount: itemDiscount,
    rewardDiscount: rewardDiscount,
    billDiscount: billDiscount,
    service: service,
    vat: vat,
    vatIncluded: vatS['enabled'] == true && vatS['included'] == true,
    total: total,
    other: otherCurrency(total, s),
    paid: paid,
    due: due,
    change: change,
    changeOther: otherCurrency(change, s),
    settled: settled,
    items: count,
  );
}

// ---------- promotions ----------
String _two(int x) => x.toString().padLeft(2, '0');

// is a promotion on at this moment? (dates "YYYY-MM-DD", days 0–6 Sunday first, hours "HH:MM", Cambodia time)
bool promoOn(J p, Object? at, [int tzHours = 7]) {
  final when = at is DateTime ? at : (DateTime.tryParse(js(at)) ?? DateTime.now());
  final local = when.toUtc().add(Duration(hours: tzHours));
  final day = '${local.year}-${_two(local.month)}-${_two(local.day)}';
  final hm = '${_two(local.hour)}:${_two(local.minute)}';
  final start = js(p['start_date']), end = js(p['end_date']);
  if (start.isNotEmpty && day.compareTo(start) < 0) return false;
  if (end.isNotEmpty && day.compareTo(end) > 0) return false;
  final days = p['days'] is List ? (p['days'] as List).map((e) => nz(e).toInt()).toList() : const <int>[];
  if (days.isNotEmpty && !days.contains(local.weekday % 7)) return false;
  final from = js(p['from']), to = js(p['to']);
  if (from.isNotEmpty && to.isNotEmpty) {
    final off = from.compareTo(to) <= 0 ? (hm.compareTo(from) < 0 || hm.compareTo(to) >= 0) : (hm.compareTo(from) < 0 && hm.compareTo(to) >= 0);
    if (off) return false;
  }
  return true;
}

List<String> _strs(Object? v) => v is List ? v.map((e) => '$e').toList() : const [];
bool _promoHits(J p, J line, String Function(String) catOf) =>
    p['all_items'] == true || _strs(p['item_ids']).contains(js(line['item_id'])) || _strs(p['category_ids']).contains(catOf(js(line['item_id'])));

Map<String, double> promoOffs(J p, List<J> lines) {
  final offs = <String, double>{};
  if (p['kind'] == 'percent') {
    for (final l in lines) {
      offs[js(l['id'])] = (lineTotal(l) * (nz(p['value']) > 100 ? 100 : nz(p['value']))) / 100;
    }
  } else if (p['kind'] == 'amount') {
    for (final l in lines) {
      final v = nz(p['value']) * nz(l['qty']);
      offs[js(l['id'])] = lineTotal(l) < v ? lineTotal(l) : v;
    }
  } else if (p['kind'] == 'bxgy') {
    final units = <(String, double)>[];
    for (final l in lines) {
      final q = nz(l['qty']).toInt();
      for (var i = 0; i < q; i++) {
        units.add((js(l['id']), lineTotal(l) / (nz(l['qty']) == 0 ? 1 : nz(l['qty']))));
      }
    }
    units.sort((a, b) => b.$2.compareTo(a.$2));
    final buy = nz(p['buy']) == 0 ? 1 : nz(p['buy']).toInt();
    final getQty = nz(p['get_qty']) == 0 ? 1 : nz(p['get_qty']).toInt();
    final size = buy + getQty;
    final gp = nz(p['get_percent']) == 0 ? 100.0 : nz(p['get_percent']);
    final pct = (gp > 100 ? 100 : gp) / 100;
    for (var g = 0; g + size <= units.length; g += size) {
      for (var k = g + size - getQty; k < g + size; k++) {
        offs[units[k].$1] = (offs[units[k].$1] ?? 0) + units[k].$2 * pct;
      }
    }
  }
  return offs.map((k, v) => MapEntry(k, round2(v)));
}

const _noPromo = {'id': '', 'name': '', 'off': 0};

// give an open order's lines their promotion (the one that saves the guest most). Lines with a cashier's discount keep it.
J applyPromos(J order, List<J> promos, [String Function(String)? catOf, int tzHours = 7]) {
  final cat = catOf ?? (_) => '';
  final lines = jlist(order['lines']);
  final live = lines.where((l) => l['status'] != 'void' && js(jmap(l['discount'])['kind']).isEmpty && js(l['item_id']).isNotEmpty).toList();
  final best = <String, (J, double)>{};
  for (final p in promos) {
    final hits = live.where((l) => _promoHits(p, l, cat) && promoOn(p, l['created_at'] ?? DateTime.now(), tzHours)).toList();
    if (hits.isEmpty) continue;
    final offs = promoOffs(p, hits);
    for (final l in hits) {
      final id = js(l['id']);
      final o = offs[id] ?? 0;
      if (o > (best[id]?.$2 ?? 0) || (p['kind'] == 'bxgy' && best[id] == null)) best[id] = (p, o);
    }
  }
  final byPromo = <J, List<String>>{};
  best.forEach((id, b) => (byPromo[b.$1] ??= []).add(id));
  final result = <String, J>{};
  byPromo.forEach((p, ids) {
    final offs = promoOffs(p, live.where((l) => ids.contains(js(l['id']))).toList());
    for (final id in ids) {
      result[id] = {'id': js(p['_id']), 'name': js(p['name']), 'off': offs[id] ?? 0};
    }
  });
  return {
    ...order,
    'lines': [
      for (final l in lines)
        () {
          final promo = jmap(l['promo']);
          if (js(jmap(l['discount'])['kind']).isNotEmpty || l['status'] == 'void') {
            return nz(promo['off']) > 0
                ? {
                    ...l,
                    'promo': {..._noPromo},
                  }
                : l;
          }
          final r = result[js(l['id'])];
          final next = r != null && (nz(r['off']) > 0 || js(r['id']).isNotEmpty) ? r : {..._noPromo};
          return nz(next['off']) > 0
              ? {...l, 'promo': next}
              : (js(promo['id']).isNotEmpty
                    ? {
                        ...l,
                        'promo': {..._noPromo},
                      }
                    : l);
        }(),
    ],
  };
}

// ---------- shift ----------
class ShiftSum {
  final int bills, guests, voidOrders, voidLines, openOrders;
  final double sales, discounts;
  final Map<String, double> byMethod;
  final double expUsd, expKhr;
  const ShiftSum(this.bills, this.sales, this.discounts, this.guests, this.voidOrders, this.voidLines, this.openOrders, this.byMethod, this.expUsd, this.expKhr);
  J toJson() => {
    'bills': bills,
    'sales': sales,
    'discounts': discounts,
    'guests': guests,
    'void_orders': voidOrders,
    'void_lines': voidLines,
    'open_orders': openOrders,
    'by_method': byMethod,
    'expected': {'usd': expUsd, 'khr': expKhr},
  };
}

ShiftSum shiftSummary(J shift, Iterable<J> orders, J s) {
  final mine = orders.where((o) => o['shift_id'] == shift['_id']).toList();
  final paid = mine.where((o) => o['status'] == 'paid').toList();
  final byMethod = <String, double>{};
  final opening = jmap(shift['opening']);
  var cashUsd = nz(opening['usd']), cashKhr = nz(opening['khr']);
  double sales = 0, discounts = 0;
  var guests = 0, voidLines = 0;
  String key(J p) => js(p['method']).isNotEmpty ? js(p['method']) : js(p['kind']);
  for (final o in paid) {
    final t = calcOrder(o, s);
    sales += t.total;
    discounts += t.discount;
    guests += nz(o['guests']).toInt();
    final pays = jlist(o['payments']);
    for (final p in pays) {
      byMethod[key(p)] = (byMethod[key(p)] ?? 0) + paymentValue(p, s);
      if (p['kind'] == 'cash') {
        if (p['currency'] == 'KHR') {
          cashKhr += nz(p['amount']);
        } else {
          cashUsd += nz(p['amount']);
        }
      }
    }
    final ch = jmap(o['change']);
    cashUsd -= nz(ch['usd']);
    cashKhr -= nz(ch['khr']);
    final back = t.paid - t.total;
    if (back > 0 && pays.isNotEmpty) {
      final p = pays.firstWhere((x) => x['kind'] == 'cash', orElse: () => pays.first);
      byMethod[key(p)] = (byMethod[key(p)] ?? 0) - back;
    }
  }
  for (final o in mine) {
    voidLines += jlist(o['lines']).where((l) => l['status'] == 'void' && l['void_reason'] != 'removed').length;
  }
  return ShiftSum(
    paid.length,
    money(sales, s),
    money(discounts, s),
    guests,
    mine.where((o) => o['status'] == 'void').length,
    voidLines,
    mine.where((o) => o['status'] == 'open').length,
    byMethod.map((k, v) => MapEntry(k, money(v, s))),
    round2(cashUsd),
    roundStep(cashKhr, 1),
  );
}

// ---------- sales report (the same as calc.js salesReport, the parts the POS shows) ----------
// paid bills count as sales; cancelled ones are counted apart. Lists are JSON maps, like the cloud's /api/pos/report.
J salesReport(List<J> orders, J s, {int tzHours = 7}) {
  final paid = orders.where((o) => o['status'] == 'paid').toList();
  double sales = 0, discounts = 0, voidValue = 0;
  var voidOrders = 0, openOrders = 0;
  final methods = <String, J>{};
  final items = <String, J>{};
  final staff = <String, J>{};
  final types = {
    'dine_in': {'bills': 0, 'sales': 0.0},
    'takeaway': {'bills': 0, 'sales': 0.0},
  };
  for (final o in orders) {
    if (o['status'] == 'open') openOrders++;
    if (o['status'] != 'void') continue;
    voidOrders++;
    voidValue += jlist(o['lines']).where((l) => l['void_reason'] != 'removed').fold<double>(0, (a, l) => a + lineTotal({...l, 'status': ''}));
  }
  for (final o in paid) {
    final t = calcOrder(o, s);
    sales += t.total;
    discounts += t.discount;
    final type = o['type'] == 'takeaway' ? 'takeaway' : 'dine_in';
    types[type]!['bills'] = (types[type]!['bills'] as int) + 1;
    types[type]!['sales'] = (types[type]!['sales'] as double) + t.total;
    final cb = js(jmap(o['closed_by'])['name']), ob = js(jmap(o['opened_by'])['name']);
    final who = cb.isNotEmpty ? cb : (ob.isNotEmpty ? ob : '—');
    final st = staff[who] ??= {'name': who, 'bills': 0, 'sales': 0.0};
    st['bills'] = (st['bills'] as int) + 1;
    st['sales'] = (st['sales'] as double) + t.total;
    final pays = jlist(o['payments']);
    String key(J p) => js(p['method']).isNotEmpty ? js(p['method']) : (js(p['kind']).isNotEmpty ? js(p['kind']) : '—');
    for (final p in pays) {
      final m = methods[key(p)] ??= {'name': key(p), 'kind': js(p['kind']), 'value': 0.0, 'count': 0};
      m['value'] = (m['value'] as double) + paymentValue(p, s);
      m['count'] = (m['count'] as int) + 1;
    }
    final back = t.paid - t.total;
    if (back > 0 && pays.isNotEmpty) {
      final p = pays.firstWhere((x) => x['kind'] == 'cash', orElse: () => pays.first);
      methods[key(p)]!['value'] = (methods[key(p)]!['value'] as double) - back;
    }
    for (final l in jlist(o['lines'])) {
      if (l['status'] == 'void') continue;
      final k = '${js(l['item_id']).isNotEmpty ? js(l['item_id']) : (js(l['name_en']).isNotEmpty ? js(l['name_en']) : js(l['name_km']))}|${js(l['size'])}';
      final it = items[k] ??= {'key': k, 'item_id': js(l['item_id']), 'name_km': js(l['name_km']), 'name_en': js(l['name_en']), 'size': js(l['size']), 'qty': 0.0, 'sales': 0.0};
      it['qty'] = (it['qty'] as double) + nz(l['qty']);
      it['sales'] = (it['sales'] as double) + lineTotal(l) - lineOff(l);
    }
  }
  double m(Object? v) => money(v, s);
  return {
    'sales': m(sales),
    'bills': paid.length,
    'avg': paid.isEmpty ? 0 : m(sales / paid.length),
    'discounts': m(discounts),
    'void_orders': voidOrders,
    'void_value': m(voidValue),
    'open_orders': openOrders,
    'by_method': [
      for (final x in methods.values) {...x, 'value': m(x['value'])},
    ]..sort((a, b) => nz(b['value']).compareTo(nz(a['value']))),
    'by_item': [
      for (final x in items.values) {...x, 'sales': m(x['sales'])},
    ]..sort((a, b) => nz(b['qty']) != nz(a['qty']) ? nz(b['qty']).compareTo(nz(a['qty'])) : nz(b['sales']).compareTo(nz(a['sales']))),
    'by_staff': [
      for (final x in staff.values) {...x, 'sales': m(x['sales'])},
    ]..sort((a, b) => nz(b['sales']).compareTo(nz(a['sales']))),
    'by_type': {
      for (final e in types.entries) e.key: {'bills': e.value['bills'], 'sales': m(e.value['sales'])},
    },
  };
}
