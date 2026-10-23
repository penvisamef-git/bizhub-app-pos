import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/app_state.dart';
import '../../../core/pos_api.dart';
import 'calc.dart';

// The restaurant POS engine (the web's pos/engine.js, in Dart).
// Setup, orders and shifts live on this device; every change is saved here first, then sent in the background,
// so selling never waits for the internet.
//   sync_mode "instant": send right away + check other devices' changes every few seconds
//   "5" / "15" / "30": every N minutes · "shift": only when the shift closes (or "Sync now")
class RestPos extends ChangeNotifier {
  RestPos._();
  static final RestPos i = RestPos._();

  static const _instantMs = 4000;
  static const _k = 'rp.'; // keys on this device

  String phase = 'loading'; // loading | nosetup | ready | unlinked
  String token = '';
  J device = {};
  J? setup; // bootstrap data without orders / shifts
  Map<String, J> orders = {};
  Map<String, J> shifts = {};
  Map<String, J> bookings = {};
  Map<String, J> members = {}; // reward points: what the POS last heard about members on bills { id: { member, rewards, coupons, moves } }
  List<J> guestAlerts = []; // table ordering: orders guests just sent [{ id, order_id, table_name, guest_name, count, at }]
  J? staff; // who is logged in
  bool online = true;
  bool syncing = false;
  int lastContact = 0;
  int lastSync = 0;
  int cursor = 0;
  int setupRev = 0;
  String error = '';
  ({J shift, ShiftSum sum, bool? synced})? shiftDone; // the shift just closed (synced null = still sending)

  late SharedPreferences _p;
  Timer? _loop;
  Timer? _soon;
  int _lastTick = 0;
  bool _started = false;

  void _set() => notifyListeners();

  // ---------- derived ----------
  J get moneyS => jmap(setup?['money']).isEmpty ? {'currency': 'USD', 'khr_rate': 4100, 'khr_rounding': 100, 'vat': {}, 'service_charge': {}} : jmap(setup?['money']);
  String get currency => cur(moneyS);
  J get restaurant => jmap(setup?['restaurant']);
  J get posS => jmap(setup?['pos']);
  List<J> get items => jlist(setup?['items']);
  List<J> get categories => jlist(setup?['categories']);
  List<J> get tables => jlist(setup?['tables']);
  List<J> get zones => jlist(setup?['zones']);
  List<J> get addonGroups => jlist(setup?['addon_groups']);
  List<J> get staffList => jlist(setup?['staff']);
  bool get noTables => restaurant['no_tables'] == true;
  bool get payFirst => restaurant['pay_mode'] == 'before';
  List<J> get payMethods {
    final m = jlist(restaurant['payment_methods']);
    return m.isEmpty
        ? [
            {'name': 'Cash', 'kind': 'cash'},
          ]
        : m;
  }

  int get pending => orders.values.where((o) => o['_dirty'] == true).length + shifts.values.where((x) => x['_dirty'] == true).length + bookings.values.where((x) => x['_dirty'] == true).length;
  List<J> get activeBookings => bookings.values.where((b) => b['status'] == 'active').toList();
  J? get openShift {
    for (final x in shifts.values) {
      if (x['status'] == 'open' && (js(x['device_id']).isEmpty || js(x['device_id']) == js(device['_id']))) return x;
    }
    return null;
  }

  Totals totals(J order) => calcOrder(order, moneyS);
  J? itemOf(String id) {
    for (final x in items) {
      if (js(x['_id']) == id) return x;
    }
    return null;
  }

  // how many of a tracked item can still be sold: the cloud's count, minus what open bills hold
  // and what paid bills here haven't taken out in the cloud yet. null = not tracked.
  double? stockLeft(J? item, [String? exceptLine]) {
    if (item == null || item['track_stock'] != true) return null;
    double held = 0;
    for (final o in orders.values) {
      final counts = o['status'] == 'open' || (o['status'] == 'paid' && o['stock_applied'] != true);
      if (!counts) continue;
      for (final l in jlist(o['lines'])) {
        if (js(l['item_id']) == js(item['_id']) && l['status'] != 'void' && l['id'] != exceptLine) held += nz(l['qty']);
      }
    }
    return nz(item['stock']) - held;
  }

  // may this device sell right now? (offline limits + licence) → "" | locked | offline_off | offline_long
  String get blockedReason {
    if (setup == null) return '';
    final lic = jmap(setup!['license']);
    final now = DateTime.now().millisecondsSinceEpoch;
    int? ms(Object? v) => DateTime.tryParse(js(v))?.millisecondsSinceEpoch;
    final grace = ms(lic['grace_until']), exp = ms(lic['expires_at']);
    if (lic['locked'] == true || (grace != null && now > grace && exp != null && now > exp)) return 'locked';
    if (!online) {
      if (posS['allow_offline'] == false) return 'offline_off';
      final hours = nz(posS['max_offline_hours']) == 0 ? 24 : nz(posS['max_offline_hours']);
      if (lastContact > 0 && now - lastContact > hours * 3600 * 1000) return 'offline_long';
    }
    return '';
  }

  int get graceDays {
    final lic = jmap(setup?['license']);
    final g = DateTime.tryParse(js(lic['grace_until']));
    if (lic['active'] == true || g == null) return 0;
    return max(0, (g.difference(DateTime.now()).inHours / 24).ceil());
  }

  // ---------- storage ----------
  J? _getJ(String k) {
    final raw = _p.getString('$_k$k');
    if (raw == null || raw.isEmpty) return null;
    try {
      return jmap(jsonDecode(raw));
    } catch (_) {
      return null;
    }
  }

  Future<void> _putJ(String k, Object? v) => _p.setString('$_k$k', jsonEncode(v));
  Map<String, J> _getMap(String k) => (_getJ(k) ?? {}).map((id, v) => MapEntry(id, jmap(v)));
  Future<void> _saveOrders() => _putJ('orders', orders);
  Future<void> _saveShifts() => _putJ('shifts', shifts);
  Future<void> _saveBookings() => _putJ('bookings', bookings);

  // ---------- start ----------
  // token from AppState.link (the device was paired on the link screen)
  Future<void> start(String deviceToken, J dev) async {
    if (_started && token == deviceToken) return;
    _started = true;
    _p = await SharedPreferences.getInstance();
    token = deviceToken;
    // a different device token than what is saved (linked again): start clean
    if (_p.getString('${_k}token') != deviceToken) {
      await _clear();
      await _p.setString('${_k}token', deviceToken);
    }
    device = _getJ('device') ?? dev;
    setup = _getJ('setup');
    orders = _getMap('orders');
    shifts = _getMap('shifts');
    bookings = _getMap('bookings');
    guestAlerts = jlist(_getJ('guestAlerts')?['list']);
    cursor = _p.getInt('${_k}cursor') ?? 0;
    setupRev = _p.getInt('${_k}setupRev') ?? 0;
    lastContact = _p.getInt('${_k}lastContact') ?? 0;
    phase = setup != null ? 'ready' : 'loading';
    _set();
    try {
      await _bootstrap();
    } on ApiError catch (e) {
      if (e.status == 401 && e.code == 'device') return _gone();
      online = e.status != 0 ? online : false;
      if (setup == null) {
        phase = 'nosetup';
        error = e.network ? '' : e.message;
      }
      _set();
    }
    _prune();
    _startLoop();
  }

  Future<void> retry() async {
    phase = 'loading';
    _set();
    try {
      await _bootstrap();
    } on ApiError catch (e) {
      if (e.status == 401 && e.code == 'device') return _gone();
      phase = setup == null ? 'nosetup' : 'ready';
      error = e.network ? '' : e.message;
      online = !e.network;
      _set();
    }
  }

  Future<void> _bootstrap() async {
    final data = jmap((await PosApi(token).restBootstrap())['data']);
    final o = jlist(data.remove('orders'));
    final s = jlist(data.remove('shifts'));
    final b = jlist(data.remove('bookings'));
    final c = nz(data.remove('cursor')).toInt();
    final rev = nz(data.remove('setup_rev')).toInt();
    setup = data;
    device = jmap(data['device']);
    Map<String, J> mergeIn(Map<String, J> local, List<J> list) {
      final next = {...local};
      for (final x in list) {
        if (next[js(x['_id'])]?['_dirty'] != true) next[js(x['_id'])] = {...x, '_dirty': false};
      }
      return next;
    }

    orders = mergeIn(orders, o);
    shifts = mergeIn(shifts, s);
    final nb = {for (final x in bookings.values.where((x) => x['_dirty'] == true)) js(x['_id']): x};
    for (final x in b) {
      nb.putIfAbsent(js(x['_id']), () => {...x, '_dirty': false});
    }
    bookings = nb;
    cursor = cursor == 0 ? c : cursor;
    setupRev = rev;
    lastContact = DateTime.now().millisecondsSinceEpoch;
    online = true;
    error = '';
    phase = 'ready';
    await Future.wait([
      _putJ('setup', setup),
      _putJ('device', device),
      _saveOrders(),
      _saveShifts(),
      _saveBookings(),
      _p.setInt('${_k}cursor', cursor),
      _p.setInt('${_k}setupRev', setupRev),
      _p.setInt('${_k}lastContact', lastContact),
    ]);
    _set();
  }

  // keep the device light: paid / cancelled bills already in the cloud and older than 2 days go
  void _prune() {
    final cut = DateTime.now().subtract(const Duration(days: 2));
    final shiftId = openShift?['_id'];
    final old = orders.values.where((o) {
      final at = DateTime.tryParse(js(o['paid_at'] ?? o['opened_at']));
      return o['_dirty'] != true && o['status'] != 'open' && at != null && at.isBefore(cut) && o['shift_id'] != shiftId;
    }).toList();
    if (old.isEmpty) return;
    for (final o in old) {
      orders.remove(js(o['_id']));
    }
    _saveOrders();
    _set();
  }

  Future<void> _clear() async {
    for (final k in _p.getKeys().where((k) => k.startsWith(_k)).toList()) {
      await _p.remove(k);
    }
  }

  // the owner unlinked this device in the dashboard
  Future<void> _gone() async {
    await _clear();
    _stop();
    phase = 'unlinked';
    staff = null;
    _set();
  }

  // stops the background sync (tests; unlink stops it itself)
  void stop() => _stop();

  void _stop() {
    _ring?.cancel();
    _ring = null;
    _loop?.cancel();
    _loop = null;
    _soon?.cancel();
    _started = false;
  }

  // ---------- sync ----------
  int get _intervalMs {
    final mode = js(posS['sync_mode']).isEmpty ? 'instant' : js(posS['sync_mode']);
    if (mode == 'instant') return _instantMs;
    if (mode == 'shift') return 0;
    return (nz(mode) * 60000).toInt();
  }

  bool get shiftMode => js(posS['sync_mode']) == 'shift';

  void _startLoop() {
    if (_loop != null) return;
    _lastTick = DateTime.now().millisecondsSinceEpoch;
    _loop = Timer.periodic(const Duration(seconds: 1), (_) {
      final every = _intervalMs;
      final now = DateTime.now().millisecondsSinceEpoch;
      // table ordering: look for guests' orders every few seconds, whatever the sync mode
      if (setup?['table_order'] != null && now - _lastGuest >= 5000) {
        _lastGuest = now;
        _pollGuests();
      }
      if (every > 0 && now - _lastTick >= every) {
        _lastTick = now;
        syncNow();
      }
    });
    syncNow();
    _updateRing();
  }

  // the app came back to the front: catch up (unless it only sends at shift close)
  void resumed() {
    if (_intervalMs > 0) syncNow();
  }

  void _scheduleSync() {
    if ((js(posS['sync_mode']).isEmpty ? 'instant' : js(posS['sync_mode'])) != 'instant') return;
    _soon?.cancel();
    _soon = Timer(const Duration(milliseconds: 400), syncNow);
  }

  Future<bool>? _running;
  Future<bool> syncNow() {
    if (token.isEmpty) return Future.value(false);
    return _running ??= _doSync().whenComplete(() => _running = null);
  }

  Future<bool> _doSync() async {
    syncing = true;
    _set();
    try {
      for (var round = 0; round < 10; round++) {
        final dirtyOrders = orders.values.where((o) => o['_dirty'] == true).take(150).toList();
        final dirtyShifts = shifts.values.where((x) => x['_dirty'] == true).toList();
        final dirtyBookings = bookings.values.where((x) => x['_dirty'] == true).take(100).toList();
        final sent = {
          for (final x in [...dirtyOrders, ...dirtyShifts, ...dirtyBookings]) js(x['_id']): x['version'],
        };
        J strip(J x) => {...x}..remove('_dirty');
        final res = jmap(
          (await PosApi(token).call(
            'POST',
            '/api/pos/sync',
            body: {'since': cursor, 'orders': dirtyOrders.map(strip).toList(), 'shifts': dirtyShifts.map(strip).toList(), 'bookings': dirtyBookings.map(strip).toList(), 'pending': pending},
          ))['data'],
        );
        // what we sent is now in the cloud (unless it changed again meanwhile)
        sent.forEach((id, v) {
          if (orders[id]?['version'] == v) orders[id] = {...orders[id]!, '_dirty': false};
          if (shifts[id]?['version'] == v) shifts[id] = {...shifts[id]!, '_dirty': false};
          if (bookings[id]?['version'] == v) bookings[id] = {...bookings[id]!, '_dirty': false};
        });
        // changes from the cloud (other devices too)
        for (final o in jlist(res['orders'])) {
          if (orders[js(o['_id'])]?['_dirty'] != true) orders[js(o['_id'])] = {...o, '_dirty': false};
        }
        for (final x in jlist(res['shifts'])) {
          if (shifts[js(x['_id'])]?['_dirty'] != true) shifts[js(x['_id'])] = {...x, '_dirty': false};
        }
        for (final x in jlist(res['bookings'])) {
          if (bookings[js(x['_id'])]?['_dirty'] != true) bookings[js(x['_id'])] = {...x, '_dirty': false};
        }
        bookings.removeWhere((_, x) => x['status'] != 'active' && x['_dirty'] != true);
        cursor = nz(res['cursor']).toInt();
        lastContact = DateTime.now().millisecondsSinceEpoch;
        lastSync = lastContact;
        // stock left of every tracked item (after other devices' sales too)
        final stock = jmap(res['stock']);
        final s = {...?setup};
        if (stock.isNotEmpty) {
          s['items'] = [
            for (final i in items) stock.containsKey(js(i['_id'])) ? {...i, 'stock': stock[js(i['_id'])]} : i,
          ];
        }
        s['license'] = res['license'] ?? s['license'];
        s['pos'] = res['pos'] ?? s['pos'];
        s['table_order'] = res['table_order'] ?? s['table_order'];
        final rewardsChanged = res.containsKey('rewards_on') && (res['rewards_on'] == true) != (s['rewards'] != null);
        setup = s;
        online = true;
        error = '';
        await Future.wait([_saveOrders(), _saveShifts(), _saveBookings(), _putJ('setup', setup), _p.setInt('${_k}cursor', cursor), _p.setInt('${_k}lastContact', lastContact)]);
        _set();
        if (nz(res['setup_rev']).toInt() != setupRev || rewardsChanged) {
          try {
            await _bootstrap();
          } catch (_) {}
        }
        if (res['more'] != true && (pending == 0 || dirtyOrders.length < 150)) break;
      }
      syncing = false;
      _set();
      return true;
    } on ApiError catch (e) {
      if (e.status == 401 && e.code == 'device') {
        await _gone();
        return false;
      }
      syncing = false;
      if (e.network) online = false;
      error = e.network ? '' : e.message;
      _set();
      return false;
    } catch (e) {
      syncing = false;
      error = '$e';
      _set();
      return false;
    }
  }

  // ---------- staff ----------
  static String sha(String text) => sha256.convert(utf8.encode(text)).toString();
  bool _pinOk(J s, String pin) => js(s['pin_check']).isNotEmpty && sha('${s['pin_salt']}:$pin') == s['pin_check'];

  Future<J?> loginPin(String pin) async {
    for (final s in staffList) {
      if (_pinOk(s, pin)) {
        staff = s;
        _set();
        return s;
      }
    }
    // a PIN this device can't check yet (old staff record): ask the cloud once, then it works offline too
    try {
      final s = jmap((await PosApi(token).call('POST', '/api/pos/staff-pin', body: {'pin': pin}))['data']);
      setup = {
        ...?setup,
        'staff': [...staffList.where((x) => x['_id'] != s['_id']), s],
      };
      await _putJ('setup', setup);
      staff = s;
      online = true;
      _set();
      return s;
    } on ApiError catch (e) {
      if (e.network) {
        online = false;
        _set();
      }
    }
    return null;
  }

  void lock() {
    staff = null;
    _set();
  }

  J get _me => {'id': js(staff?['_id']), 'name': js(staff?['name'])};

  // ---------- saving ----------
  J _withPromos(J order) {
    if (order['status'] != 'open') return order;
    final promos = jlist(setup?['promos']);
    if (promos.isEmpty && !jlist(order['lines']).any((l) => nz(jmap(l['promo'])['off']) > 0)) return order;
    final cat = {for (final i in items) js(i['_id']): js(i['category_id'])};
    return applyPromos(order, promos, (id) => cat[id] ?? '');
  }

  Future<J> _saveOrder(J input) async {
    final order = _withPromos(input);
    final next = {...order, 'version': nz(order['version']).toInt() + 1, 'device_updated_at': DateTime.now().toUtc().toIso8601String(), '_dirty': true};
    orders[js(next['_id'])] = next;
    _set();
    await _saveOrders();
    _scheduleSync();
    return next;
  }

  Future<J> _saveShift(J shift) async {
    final next = {...shift, 'version': nz(shift['version']).toInt() + 1, '_dirty': true};
    shifts[js(next['_id'])] = next;
    _set();
    await _saveShifts();
    _scheduleSync();
    return next;
  }

  static String _two(int x) => x.toString().padLeft(2, '0');
  static String get today {
    final d = DateTime.now();
    return '${d.year}-${_two(d.month)}-${_two(d.day)}';
  }

  static final _rnd = Random.secure();
  static String uuid() {
    final b = List<int>.generate(16, (_) => _rnd.nextInt(256));
    b[6] = (b[6] & 0x0f) | 0x40;
    b[8] = (b[8] & 0x3f) | 0x80;
    final h = b.map((x) => x.toRadixString(16).padLeft(2, '0')).join();
    return '${h.substring(0, 8)}-${h.substring(8, 12)}-${h.substring(12, 16)}-${h.substring(16, 20)}-${h.substring(20)}';
  }

  static String get _now => DateTime.now().toUtc().toIso8601String();

  Future<String> _nextNumber() async {
    final daily = (js(jmap(restaurant['receipt'])['numbering']).isEmpty ? 'daily' : js(jmap(restaurant['receipt'])['numbering'])) == 'daily';
    final key = '${_k}num:${daily ? today : 'all'}';
    final n = (_p.getInt(key) ?? 0) + 1;
    await _p.setInt(key, n);
    final prefix = js(device['prefix']).isEmpty ? 'A' : js(device['prefix']);
    return '$prefix-${n.toString().padLeft(4, '0')}';
  }

  // ---------- shifts ----------
  Future<J> startShift(double usd, double khr) => _saveShift({
    '_id': uuid(),
    'device_id': device['_id'],
    'opened_by': _me,
    'opened_at': _now,
    'opening': {'usd': usd, 'khr': khr},
    'status': 'open',
    'version': 0,
  });

  ShiftSum shiftNumbers(J shift) => shiftSummary(shift, orders.values, moneyS);

  Future<void> endShift(J shift, double usd, double khr, String note) async {
    final sum = shiftNumbers(shift);
    final draft = {
      ...shift,
      'status': 'closed',
      'closed_at': _now,
      'closed_by': _me,
      'counted': {'usd': usd, 'khr': khr},
      'note': note,
      'totals': sum.toJson(),
      'expected': {'usd': sum.expUsd, 'khr': sum.expKhr},
    };
    shiftDone = (shift: draft, sum: sum, synced: null);
    _set();
    final closed = await _saveShift(draft);
    final ok = await syncNow(); // closing a shift always tries to send everything
    shiftDone = (shift: closed, sum: sum, synced: ok && pending == 0);
    _set();
  }

  // "Done" on the shift summary: log out → PIN screen for the next person
  void finishShift() {
    shiftDone = null;
    staff = null;
    _set();
  }

  // ---------- orders ----------
  List<J> get openOrders => orders.values.where((o) => o['status'] == 'open').toList()..sort((a, b) => js(a['opened_at']).compareTo(js(b['opened_at'])));

  Future<J> newOrder({J? table, String type = 'dine_in', int guests = 0}) async => _saveOrder({
    '_id': uuid(),
    'shift_id': js(openShift?['_id']),
    'number': await _nextNumber(),
    'type': type,
    'table_id': js(table?['_id']),
    'table_name': js(table?['name']),
    'guests': guests,
    'status': 'open',
    'lines': <J>[],
    'payments': <J>[],
    'discount': {'kind': '', 'value': 0, 'by': ''},
    'change': {'usd': 0, 'khr': 0},
    'opened_by': _me,
    'opened_at': _now,
    'version': 0,
  });

  J _get(String id) => orders[id]!;
  List<J> _lines(String id) => jlist(_get(id)['lines']);

  // choice: { item, size?, addons, qty, note }
  Future<J> addLine(String orderId, {required J item, J? size, List<J> addons = const [], int qty = 1, String note = ''}) {
    final o = _get(orderId);
    final q = max(1, qty);
    final left = stockLeft(item);
    if (left != null && left < q) return Future.value(o); // sold out: nothing added
    // the same plain dish tapped again → one line with a bigger quantity
    final plain = size == null && addons.isEmpty && note.isEmpty;
    final lines = _lines(orderId);
    final same = plain ? lines.where((l) => l['item_id'] == item['_id'] && l['status'] == 'new' && js(l['size']).isEmpty && jlist(l['addons']).isEmpty && js(l['note']).isEmpty).firstOrNull : null;
    if (same != null) {
      return _saveOrder({
        ...o,
        'lines': [
          for (final l in lines) l['id'] == same['id'] ? {...l, 'qty': nz(l['qty']) + q} : l,
        ],
      });
    }
    final line = {
      'id': uuid(),
      'item_id': item['_id'],
      'name_km': js(item['name_km']),
      'name_en': js(item['name_en']),
      'size': js(size?['name']),
      'unit_price': size != null ? nz(size['price']) : nz(item['price']),
      'addons': [
        for (final a in addons) {'group': js(a['group']), 'name': js(a['name']), 'price': nz(a['price'])},
      ],
      'qty': q,
      'note': note,
      'status': 'new',
      'station_id': js(item['station_id']),
      'created_at': _now,
      'created_by': _me['name'],
      'cost': nz(item['cost']),
    };
    return _saveOrder({
      ...o,
      'lines': [...lines, line],
    });
  }

  Future<J> setLineQty(String orderId, String lineId, double qty) {
    final o = _get(orderId);
    final lines = _lines(orderId);
    final line = lines.where((l) => l['id'] == lineId).firstOrNull;
    final left = line == null ? null : stockLeft(itemOf(js(line['item_id'])), lineId);
    if (left != null && qty > left) qty = max(1, left);
    return _saveOrder({
      ...o,
      'lines': [
        for (final l in lines) l['id'] == lineId && l['status'] == 'new' ? {...l, 'qty': max(1.0, qty)} : l,
      ],
    });
  }

  // a line not sent yet just goes away (kept as "removed" so another device's copy can't bring it back)
  Future<J> removeLine(String orderId, String lineId) => _voidLine(orderId, lineId, 'removed');
  Future<J> voidLine(String orderId, String lineId, String reason) => _voidLine(orderId, lineId, reason.isEmpty ? 'cancelled' : reason);
  Future<J> _voidLine(String orderId, String lineId, String reason) => _saveOrder({
    ..._get(orderId),
    'lines': [
      for (final l in _lines(orderId)) l['id'] == lineId ? {...l, 'status': 'void', 'void_reason': reason, 'void_by': _me['name']} : l,
    ],
  });

  List<J> _sent(String id) => [
    for (final l in _lines(id)) l['status'] == 'new' ? {...l, 'status': 'sent'} : l,
  ];
  Future<J> sendLines(String orderId) => _saveOrder({..._get(orderId), 'lines': _sent(orderId)});
  Future<J> markBill(String orderId) => _saveOrder({..._get(orderId), 'bill_printed': true, 'lines': _sent(orderId)});

  // a discount on one item: % or amount off that line, never more than the owner's limit
  double get maxLineDiscount => posS.containsKey('max_line_discount') && posS['max_line_discount'] != null ? nz(posS['max_line_discount']) : 100;
  Future<J> setLineDiscount(String orderId, String lineId, String kind, double value, String reason) => _saveOrder({
    ..._get(orderId),
    'lines': [
      for (final l in _lines(orderId))
        if (l['id'] != lineId)
          l
        else if (kind.isEmpty || value <= 0)
          {
            ...l,
            'discount': {'kind': '', 'value': 0, 'by': '', 'reason': ''},
          }
        else
          {
            ...l,
            'discount': {'kind': kind, 'value': kind == 'percent' ? min(value, maxLineDiscount) : min(value, lineTotal(l) * maxLineDiscount / 100), 'by': _me['name'], 'reason': reason},
            'promo': {'id': '', 'name': '', 'off': 0},
          },
    ],
  });

  Future<J> setDiscount(String orderId, String kind, double value) => _saveOrder({
    ..._get(orderId),
    'discount': {'kind': kind, 'value': value, 'by': _me['name']},
  });
  Future<J> setNote(String orderId, String note) => _saveOrder({..._get(orderId), 'note': note.length > 300 ? note.substring(0, 300) : note});
  Future<J> setGuests(String orderId, int guests) => _saveOrder({..._get(orderId), 'guests': max(0, guests)});

  // payments: [{method, kind, currency, amount}] · change: {usd, khr} handed back
  Future<J> pay(String orderId, List<J> payments, double changeUsd, double changeKhr) {
    final o = _get(orderId);
    final list = [
      for (final p in payments)
        {'id': uuid(), 'method': p['method'], 'kind': p['kind'], 'currency': p['currency'], 'amount': nz(p['amount']), 'value': paymentValue(p, moneyS), 'at': _now, 'by': _me['name']},
    ];
    return _saveOrder({
      ...o,
      'lines': _sent(orderId),
      'payments': [...jlist(o['payments']), ...list],
      'change': {'usd': changeUsd, 'khr': changeKhr},
      'status': 'paid',
      'paid_at': _now,
      'closed_by': _me,
    });
  }

  Future<J> voidOrder(String orderId, String reason) {
    final o = _get(orderId);
    final r = reason.isEmpty ? 'cancelled' : reason;
    return _saveOrder({
      ...o,
      'status': 'void',
      'void_reason': r,
      'closed_by': _me,
      'lines': [
        for (final l in _lines(orderId)) l['status'] == 'void' ? l : {...l, 'status': 'void', 'void_reason': r},
      ],
    });
  }

  // ---------- bookings ----------
  Future<J> _saveBooking(J b) async {
    final next = {...b, 'version': nz(b['version']).toInt() + 1, '_dirty': true};
    bookings[js(next['_id'])] = next;
    _set();
    await _saveBookings();
    _scheduleSync();
    return next;
  }

  Future<J> addBooking({required J table, required String name, String phone = '', String? time, int guests = 0, String note = ''}) => _saveBooking({
    '_id': uuid(),
    'table_id': js(table['_id']),
    'table_name': js(table['name']),
    'name': name.trim(),
    'phone': phone.trim(),
    'time': time,
    'guests': guests,
    'note': note,
    'status': 'active',
    'order_id': '',
    'created_by': _me['name'],
    'version': 0,
  });

  Future<J> cancelBooking(String id) => _saveBooking({...bookings[id]!, 'status': 'cancelled'});

  // guests arrived: start the table's order with the booking's name on it
  Future<J> seatBooking(String id) async {
    final b = bookings[id]!;
    final table = tables.where((x) => js(x['_id']) == js(b['table_id'])).firstOrNull ?? {'_id': b['table_id'], 'name': b['table_name']};
    final o = await newOrder(table: table, guests: nz(b['guests']).toInt());
    final who = '${js(b['name'])}${js(b['phone']).isNotEmpty ? ' · ${js(b['phone'])}' : ''}';
    final withNote = await _saveOrder({
      ...orders[js(o['_id'])]!,
      'note': [who, js(b['note'])].where((x) => x.isNotEmpty).join(' — '),
    });
    await _saveBooking({...b, 'status': 'seated', 'order_id': o['_id']});
    return withNote;
  }

  // ---------- table ordering (guests order from the QR on their table) ----------
  // The cloud gives this POS the orders guests sent; each goes onto that table's open bill (a new bill if none),
  // lines marked "from guest" and not sent yet, then the POS confirms. Line ids come from the guest order,
  // so adding the same one twice never doubles it.
  int _lastGuest = 0;
  bool _guestBusy = false;
  Future<void> _pollGuests() async {
    if (_guestBusy || token.isEmpty) return;
    _guestBusy = true;
    try {
      final acks = jlist(_getJ('guestAcks')?['list']);
      final openTables = {
        for (final o in orders.values)
          if (o['status'] == 'open' && js(o['table_id']).isNotEmpty) js(o['table_id']),
      }.toList();
      final res = jmap((await PosApi(token).call('POST', '/api/pos/guest-orders', body: {'acks': acks, 'open_tables': openTables}))['data']);
      final done = {for (final a in (res['acked'] is List ? res['acked'] as List : const [])) '$a'};
      var left = acks.where((a) => !done.contains(js(a['id']))).toList();
      final fresh = <J>[];
      for (final g in jlist(res['orders'])) {
        final placed = await _placeGuestOrder(g);
        if (placed == null) continue;
        left = [
          ...left.where((a) => a['id'] != g['_id']),
          {'id': g['_id'], 'order_id': placed.$1['_id'], 'order_number': placed.$1['number']},
        ];
        if (placed.$2) {
          fresh.add({
            'id': g['_id'],
            'order_id': placed.$1['_id'],
            'table_name': js(g['table_name']),
            'guest_name': js(g['guest_name']),
            'count': jlist(g['lines']).fold<double>(0, (a, l) => a + nz(l['qty'])).toInt(),
            'at': DateTime.now().millisecondsSinceEpoch,
          });
        }
      }
      await _putJ('guestAcks', {'list': left});
      if (res.containsKey('table_order') && jsonEncode(res['table_order']) != jsonEncode(setup?['table_order'])) {
        setup = {...?setup, 'table_order': res['table_order']};
        _set();
      }
      if (fresh.isNotEmpty) {
        guestAlerts = [...fresh, ...guestAlerts].take(8).toList();
        await _putJ('guestAlerts', {'list': guestAlerts});
        _set();
        _updateRing();
        if (left.isNotEmpty) _lastGuest = 0; // confirm right away
      }
    } catch (_) {
      // offline or a hiccup: next round
    } finally {
      _guestBusy = false;
    }
  }

  Future<(J, bool)?> _placeGuestOrder(J g) async {
    final gl = jlist(g['lines']);
    if (gl.isEmpty) return null;
    final ids = [for (var i = 0; i < gl.length; i++) 'g-${g['_id']}-$i'];
    final already = orders.values.where((o) => jlist(o['lines']).any((l) => l['id'] == ids.first)).firstOrNull;
    if (already != null) return (already, false);
    final open = orders.values.where((o) => o['status'] == 'open' && js(o['table_id']) == js(g['table_id'])).toList()..sort((a, b) => js(b['opened_at']).compareTo(js(a['opened_at'])));
    var order = open.firstOrNull;
    if (order == null) {
      final table = tables.where((x) => js(x['_id']) == js(g['table_id'])).firstOrNull ?? {'_id': g['table_id'], 'name': g['table_name']};
      order = await newOrder(table: table);
    }
    final lines = [
      for (var i = 0; i < gl.length; i++)
        {
          'id': ids[i],
          'item_id': gl[i]['item_id'],
          'name_km': js(gl[i]['name_km']),
          'name_en': js(gl[i]['name_en']),
          'size': js(gl[i]['size']),
          'unit_price': nz(gl[i]['unit_price']),
          'addons': [
            for (final a in jlist(gl[i]['addons'])) {'group': js(a['group']), 'name': js(a['name']), 'price': nz(a['price'])},
          ],
          'qty': max(1, nz(gl[i]['qty']).toInt()),
          'note': js(gl[i]['note']),
          'status': 'new',
          'station_id': js(gl[i]['station_id']),
          'created_at': js(g['created_date']).isEmpty ? _now : js(g['created_date']),
          'created_by': js(g['guest_name']).isEmpty ? 'Guest' : js(g['guest_name']),
          'from': 'guest',
          'guest_name': js(g['guest_name']),
          'cost': nz(gl[i]['cost']),
        },
    ];
    final latest = orders[js(order['_id'])] ?? order;
    // reward points: the phone the guest gave puts their member card on the bill (if none yet)
    final member = js(jmap(latest['member'])['id']).isNotEmpty ? latest['member'] : (js(jmap(g['member'])['id']).isNotEmpty ? g['member'] : latest['member']);
    final saved = await _saveOrder({
      ...latest,
      'member': member,
      'lines': [...jlist(latest['lines']), ...lines],
    });
    return (saved, true);
  }

  // the cashier accepted it (or all of them): when none are left, the ringing stops
  void dismissGuestAlert([String? id]) {
    guestAlerts = id == null ? [] : guestAlerts.where((a) => a['id'] != id).toList();
    _putJ('guestAlerts', {'list': guestAlerts});
    _set();
    _updateRing();
  }

  // keeps ringing (and buzzing) while a guest order hasn't been accepted on this POS
  Timer? _ring;
  void _updateRing() {
    if (guestAlerts.isEmpty) {
      _ring?.cancel();
      _ring = null;
      return;
    }
    if (_ring != null) return;
    void ding() {
      SystemSound.play(SystemSoundType.alert);
      HapticFeedback.heavyImpact();
    }

    ding();
    _ring = Timer.periodic(const Duration(milliseconds: 3500), (_) => guestAlerts.isEmpty ? _updateRing() : ding());
  }

  // items guests ordered from the table QR that staff haven't sent yet
  static double guestNew(Iterable<J> list) =>
      list.fold<double>(0, (a, o) => a + jlist(o['lines']).where((l) => l['from'] == 'guest' && l['status'] == 'new').fold<double>(0, (b, l) => b + nz(l['qty'])));

  // ---------- reward points ----------
  // Finding a member, rewards and coupons need the internet (points can't be spent twice);
  // points for a paid bill are added by the cloud when the bill syncs, so selling offline is fine.
  J? get rewardsRules => setup?['rewards'] == null ? null : jmap(setup!['rewards']);

  J _keepMember(J data) {
    final id = js(jmap(data['member'])['_id']);
    if (id.isNotEmpty) {
      members[id] = data;
      _set();
    }
    return data;
  }

  Future<J> _api(String method, String path, [Object? body]) async {
    try {
      final r = jmap((await PosApi(token).call(method, path, body: body))['data']);
      online = true;
      return r;
    } on ApiError catch (e) {
      if (e.network) {
        online = false;
        _set();
      }
      rethrow;
    }
  }

  Future<List<J>> searchMembers(String q) async => jlist((await _api('GET', '/api/pos/members?q=${Uri.encodeQueryComponent(q)}'))['results']);
  Future<J> refreshMember(String id) async => _keepMember(await _api('GET', '/api/pos/members/$id'));
  Future<J> createMember({required String phone, String name = '', String birthday = ''}) async =>
      _keepMember(await _api('POST', '/api/pos/members', {'phone': phone, 'name': name, 'birthday': birthday}));

  Future<J> attachMember(String orderId, J? member) => _saveOrder({
    ..._get(orderId),
    'member': member == null ? {'id': '', 'name': '', 'phone': ''} : {'id': js(member['_id']), 'name': js(member['name']), 'phone': js(member['phone'])},
  });

  // what a reward does to the bill
  Future<J> _applyReward(String orderId, J x) {
    final o = _get(orderId);
    final entry = {'id': x['id'], 'reward_id': x['reward_id'], 'name': js(x['name']), 'kind': js(x['kind']), 'points': nz(x['points']), 'item_id': js(x['item_id']), 'code': js(x['code'])};
    final next = {
      ...o,
      'redemptions': [...jlist(o['redemptions']), entry],
    };
    if (x['kind'] == 'free_item') {
      final item = itemOf(js(x['item_id']));
      next['lines'] = [
        ...jlist(o['lines']),
        {
          'id': uuid(),
          'item_id': x['item_id'],
          'name_km': js(item?['name_km']),
          'name_en': js(item?['name_en']).isEmpty ? js(x['name']) : js(item?['name_en']),
          'size': '',
          'unit_price': nz(item?['price']),
          'addons': <J>[],
          'qty': 1,
          'note': '',
          'status': 'new',
          'station_id': js(item?['station_id']),
          'created_at': _now,
          'created_by': _me['name'],
          'cost': nz(item?['cost']),
          'discount': {'kind': 'percent', 'value': 100, 'by': _me['name'], 'reason': '★ ${js(x['name'])}'},
          'reward_id': x['id'],
        },
      ];
    } else if (x['kind'] == 'amount' || x['kind'] == 'percent') {
      next['reward_discount'] = {'kind': x['kind'], 'value': nz(x['value']), 'name': js(x['name']), 'redemption_id': x['id']};
    }
    return _saveOrder(next);
  }

  // one money-off reward per bill ($ or %), any number of free items and gifts
  bool billRewardTaken(String orderId) => js(jmap(orders[orderId]?['reward_discount'])['kind']).isNotEmpty;

  Future<J> redeemReward(String orderId, String rewardId) async {
    final o = _get(orderId);
    final data = _keepMember(await _api('POST', '/api/pos/rewards/redeem', {'member_id': jmap(o['member'])['id'], 'reward_id': rewardId, 'order_id': o['_id'], 'order_number': o['number']}));
    final r = jmap(data['redemption']);
    if (r['coupon'] != true) await _applyReward(orderId, r);
    return data;
  }

  Future<J> useCoupon(String orderId, String redemptionId) async {
    final o = _get(orderId);
    final data = _keepMember(await _api('POST', '/api/pos/coupons/use', {'member_id': jmap(o['member'])['id'], 'redemption_id': redemptionId, 'order_id': o['_id'], 'order_number': o['number']}));
    await _applyReward(orderId, jmap(data['redemption']));
    return data;
  }

  Future<J> undoRedemption(String orderId, String redemptionId) async {
    final data = _keepMember(await _api('POST', '/api/pos/rewards/undo', {'redemption_id': redemptionId}));
    final o = _get(orderId);
    final rd = jmap(o['reward_discount']);
    await _saveOrder({
      ...o,
      'redemptions': jlist(o['redemptions']).where((r) => r['id'] != redemptionId).toList(),
      'reward_discount': rd['redemption_id'] == redemptionId ? {'kind': '', 'value': 0, 'name': '', 'redemption_id': ''} : o['reward_discount'],
      'lines': [
        for (final l in jlist(o['lines'])) l['reward_id'] == redemptionId && l['status'] != 'void' ? {...l, 'status': 'void', 'void_reason': 'removed', 'void_by': _me['name']} : l,
      ],
    });
    return data;
  }

  // points this bill should give (the cloud works out the real number when it's paid)
  int pointsFor(J? order) {
    final r = rewardsRules;
    if (r == null || order == null || js(jmap(order['member'])['id']).isEmpty) return 0;
    final t = calcOrder(order, moneyS);
    double pts = 0;
    final spent = t.subtotal - t.discount;
    if (r['by_amount'] == true && nz(r['points_per_step']) > 0 && spent >= nz(r['min_bill'])) {
      pts += ((spent / (nz(r['step']) == 0 ? 1 : nz(r['step']))) * nz(r['points_per_step']) + 1e-9).floorToDouble();
    }
    if (r['by_item'] == true) {
      for (final l in jlist(order['lines'])) {
        if (l['status'] != 'void' && js(l['reward_id']).isEmpty) pts += nz(itemOf(js(l['item_id']))?['reward_points']) * nz(l['qty']);
      }
    }
    return max(0, pts.floor());
  }

  // ---------- reports (all devices, any days: needs the internet) ----------
  Future<J> report(String from, String to) => _api('GET', '/api/pos/report?from=$from&to=$to');

  // ---------- unlink ----------
  bool get hasManager => staffList.any((x) => x['role'] == 'manager');
  bool unlinkPinOk(String pin) => hasManager ? staffList.any((x) => x['role'] == 'manager' && _pinOk(x, pin)) : staffList.any((x) => _pinOk(x, pin));

  // Online: the cloud checks the PIN and removes the device from the dashboard too.
  // Offline: the PIN is checked here and only this device forgets the shop.
  // returns "cloud" | "local"; throws "manager" | "pin"
  Future<String> unlink(String pin) async {
    var where = 'local';
    try {
      // a "Try demo" sample shop: its device is shared, so only this device forgets it
      if (AppState.i.demo) throw const ApiError(0, 'demo');
      await PosApi(token).call('POST', '/api/pos/unlink', body: {'pin': pin});
      where = 'cloud';
    } on ApiError catch (e) {
      if (e.status == 401 && e.code == 'device') {
        where = 'cloud';
      } else if (e.status == 403) {
        throw 'manager';
      } else if (e.status != 0 && e.status < 500) {
        throw 'pin';
      }
    }
    if (where == 'local' && setup != null && !unlinkPinOk(pin)) throw 'pin';
    await _clear();
    _stop();
    token = '';
    setup = null;
    orders = {};
    shifts = {};
    bookings = {};
    members = {};
    guestAlerts = [];
    staff = null;
    cursor = 0;
    shiftDone = null;
    phase = 'loading';
    return where;
  }
}
