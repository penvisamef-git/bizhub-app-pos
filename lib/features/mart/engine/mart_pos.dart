import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import '../../../core/local_prefs.dart';

import '../../../core/api.dart' show ApiError, makeDio;
import '../../../core/config.dart';
import '../../restaurant/engine/calc.dart' show J, jmap, jlist, js, nz;
import 'mart_calc.dart';

// The Mini Mart POS engine (the web's pos/mart/martApi.js + offline.js, in Dart).
// - a linked device (x-mart-device) + a cashier PIN session (x-mart-session, 14 h)
// - products, settings and cashier PIN checks are kept on the device (and today's sales, so the day adds up)
// - with no internet a sale is saved here and queued; it gets its real receipt number when the internet is back
// - each sale carries a client_id, so sending it twice adds nothing
class MartPos extends ChangeNotifier {
  MartPos._();
  static final MartPos i = MartPos._();
  static const _k = 'mp.'; // keys on this device

  late LocalPrefs _p;
  String device = ''; // the device token (from the link screen)
  String session = '';
  String stage = 'loading'; // loading | pin | boot | nocache | main | unlinked
  J? cache; // { boot, staff, sales, at, offline_staff, idmap }
  List<J> queue = [];
  bool online = true, syncing = false, held = false;
  List<J> failed = [];
  String _heldPin = '';
  Timer? _timer;
  bool _started = false;

  void _set() => notifyListeners();

  // ---------- what the screens read ----------
  J get boot => jmap(cache?['boot']);
  J get settings => jmap(boot['settings']);
  String get currency => js(settings['currency']).isEmpty ? 'USD' : js(settings['currency']);
  double get rate => nz(settings['khr_rate']) == 0 ? 4100 : nz(settings['khr_rate']);
  double get khrRound => nz(settings['khr_round']) == 0 ? 100 : nz(settings['khr_round']);
  J get staff => jmap(boot['staff']);
  bool get manager => staff['role'] == 'manager';
  J get business => jmap(boot['business']);
  List<J> get products => jlist(boot['products']);
  List<J> get categories => jlist(boot['categories']);
  bool get readOnly => business['status'] == false || jmap(boot['license'])['locked'] == true;
  int get pending => queue.length;
  bool get hasCache => cache?['boot'] != null;
  bool get _needLogin => cache?['offline_staff'] != null && session.isEmpty;

  // ---------- storage ----------
  Object? _read(String k) {
    final raw = _p.getString('$_k$k');
    if (raw == null) return null;
    try {
      return jsonDecode(raw);
    } catch (_) {
      return null;
    }
  }

  void _write(String k, Object? v) => _p.setString('$_k$k', jsonEncode(v));
  void _saveCache() => _write('cache', cache);
  void _saveQueue() {
    _write('queue', queue);
    _set();
  }

  // ---------- start ----------
  Future<void> start(String deviceToken) async {
    if (_started && device == deviceToken) return;
    _started = true;
    _p = await LocalPrefs.getInstance();
    if (_p.getString('${_k}device') != deviceToken) {
      await _clearAll(keepCart: false);
      await _p.setString('${_k}device', deviceToken);
    }
    device = deviceToken;
    session = _p.getString('${_k}session') ?? '';
    cache = _read('cache') is Map ? jmap(_read('cache')) : null;
    queue = jlist(_read('queue'));
    cart = _read('cart') is Map ? jmap(_read('cart')) : {'lines': <J>[]};
    heldCarts = jlist(_read('held'));
    final offlineStaff = _p.getString('${_k}offline_staff') ?? '';
    stage = session.isNotEmpty || offlineStaff.isNotEmpty ? 'boot' : 'pin';
    _set();
    if (stage == 'boot') await loadBoot();
  }

  Future<void> _clearAll({bool keepCart = true}) async {
    for (final k in _p.getKeys().where((k) => k.startsWith(_k)).toList()) {
      await _p.remove(k);
    }
    cache = null;
    queue = [];
    session = '';
    if (!keepCart) {
      cart = {'lines': <J>[]};
      heldCarts = [];
    }
  }

  void stop() {
    watchOrders(false);
    _timer?.cancel();
    _timer = null;
    _started = false;
  }

  // ---------- talking to Biz Hub ----------
  static final Dio _dio = makeDio(BaseOptions(baseUrl: Config.apiHost, connectTimeout: const Duration(seconds: 12), receiveTimeout: const Duration(seconds: 40), validateStatus: (_) => true));

  // sess: null = the current session (a 401 sends the cashier back to the PIN screen); '' = none
  Future<J> _call(String method, String path, {Object? body, String? sess}) async {
    final s = sess ?? session;
    Response<dynamic> r;
    try {
      r = await _dio.request<dynamic>(
        '/api/martpos$path',
        data: method == 'GET' ? null : (body ?? const {}),
        options: Options(method: method, headers: {'x-api-key': Config.apiKey, if (device.isNotEmpty) 'x-mart-device': device, if (s.isNotEmpty) 'x-mart-session': s}),
      );
    } on DioException catch (e) {
      throw ApiError(0, e.message ?? 'network');
    }
    final json = r.data is Map ? Map<String, dynamic>.from(r.data as Map) : <String, dynamic>{};
    final status = r.statusCode ?? 0;
    if (status >= 400 || json['success'] == false) {
      final err = ApiError(status, '${json['message'] ?? 'Error $status'}', code: json['code'] as String?, body: json);
      if (status == 401 && sess == null) _on401(err.code ?? '');
      throw err;
    }
    return json;
  }

  void _on401(String code) {
    if (code == 'no_device') {
      _clearAll(keepCart: false);
      stop();
      stage = 'unlinked';
    } else {
      session = '';
      _p.remove('${_k}session');
      _p.remove('${_k}offline_staff');
      stage = 'pin';
    }
    _set();
  }

  // link (from the link screen): the 6-digit code → this device's token
  static Future<J> pair(String code, String name) async {
    try {
      final r = await _dio.post<dynamic>(
        '/api/martpos/pair',
        data: {'code': code, 'name': name},
        options: Options(headers: {'x-api-key': Config.apiKey}),
      );
      final json = r.data is Map ? Map<String, dynamic>.from(r.data as Map) : <String, dynamic>{};
      if ((r.statusCode ?? 0) >= 400 || json['success'] == false) throw ApiError(r.statusCode ?? 0, '${json['message'] ?? 'Error'}', code: json['code'] as String?);
      return jmap(json['data']);
    } on DioException catch (e) {
      throw ApiError(0, e.message ?? 'network');
    }
  }

  void _setOnline(bool v) {
    if (online != v) {
      online = v;
      _set();
    }
  }

  // ---------- PIN ----------
  static String _sha(String s) => sha256.convert(utf8.encode(s)).toString();

  // online: the server checks the PIN; no internet: the PIN check saved on this device
  Future<bool> login(String pin) async {
    try {
      final r = jmap((await _call('POST', '/login', body: {'pin': pin}, sess: ''))['data']);
      session = js(r['session']);
      await _p.setString('${_k}session', session);
      await _p.remove('${_k}offline_staff');
      final sid = js(jmap(r['staff'])['_id']);
      if (sid.isNotEmpty) _rememberSession(sid, session);
      _setOnline(true);
      unawaited(pull().then((_) {}, onError: (_) {}));
      stage = 'boot';
      _set();
      await loadBoot();
      return true;
    } on ApiError catch (e) {
      if (e.status == 401 && e.code == 'no_device') {
        _on401('no_device');
        return false;
      }
      if (e.network && hasCache) {
        _setOnline(false);
        for (final s in jlist(cache!['staff'])) {
          if (_sha('${s['pin_salt']}:$pin') == s['pin_check']) {
            _heldPin = pin;
            final who = {'_id': s['_id'], 'name': s['name'], 'role': s['role']};
            cache!['offline_staff'] = who;
            cache!['boot'] = {...boot, 'staff': who};
            _saveCache();
            session = '';
            await _p.remove('${_k}session');
            await _p.setString('${_k}offline_staff', js(s['_id']));
            stage = 'boot';
            _set();
            await loadBoot();
            return true;
          }
        }
      }
      return false;
    }
  }

  void lock() {
    watchOrders(false);
    session = '';
    _heldPin = '';
    _p.remove('${_k}session');
    _p.remove('${_k}offline_staff');
    if (cache?['offline_staff'] != null) {
      cache!['offline_staff'] = null;
      _saveCache();
    }
    stage = 'pin';
    _set();
  }

  // the owner's 6-digit device link is dropped here (the next person needs a new code)
  Future<void> unlinkHere() async {
    await _clearAll(keepCart: false);
    stop();
    stage = 'unlinked';
    _set();
  }

  void _rememberSession(String staffId, String sess) {
    final all = jmap(_read('sessions'));
    all[staffId] = sess;
    _write('sessions', all);
  }

  // ---------- boot / pull ----------
  Future<void> loadBoot() async {
    try {
      final r = await _tryServer(() async {
        final x = jmap((await _call('GET', '/boot'))['data']);
        if (cache != null) {
          cache!['boot'] = x;
          _saveCache();
        } else {
          cache = {'boot': x, 'staff': <J>[], 'sales': <J>[], 'at': 0};
          _saveCache();
        }
        return x;
      }, () => boot);
      if (r.isEmpty) throw const ApiError(0, 'network');
      stage = 'main';
      _set();
      _startSync();
    } on ApiError catch (e) {
      if (e.network) {
        stage = 'nocache';
        _set();
      }
    }
  }

  // fresh copy from the server (products, settings, PIN checks, today's sales)
  Future<void> pull() async {
    final res = await Future.wait([_call('GET', '/boot'), _call('GET', '/sync')]);
    final b = jmap(res[0]['data']), s = jmap(res[1]['data']);
    final waiting = jlist(cache?['sales']).where((x) => x['pending'] == true).toList();
    cache = {
      ...?cache,
      'boot': b,
      'staff': s['staff'],
      'sales': [...waiting, ...jlist(s['sales'])],
      'at': DateTime.now().millisecondsSinceEpoch,
      'offline_staff': null,
    };
    _saveCache();
    _setOnline(true);
    _set();
  }

  Future<T> _tryServer<T>(Future<T> Function() fn, T Function() local) async {
    if (online && queue.isEmpty && !_needLogin) {
      try {
        final r = await fn();
        _setOnline(true);
        return r;
      } on ApiError catch (e) {
        if (!e.network) rethrow;
        _setOnline(false);
      }
    }
    if (!hasCache) throw const ApiError(0, 'network');
    return local();
  }

  // ---------- the queue ----------
  static final _rnd = Random.secure();
  static String uid() => List.generate(24, (_) => '0123456789abcdef'[_rnd.nextInt(16)]).join();
  static String _localDay([DateTime? t]) {
    final d = (t ?? DateTime.now()).toUtc().add(const Duration(hours: 7));
    return '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
  }

  String get today => _localDay();
  J get _who => jmap(cache?['offline_staff']).isNotEmpty ? jmap(cache!['offline_staff']) : staff;

  J _putSale(J s) {
    if (cache == null) return s;
    final list = jlist(cache!['sales']).where((x) => js(x['_id']) != js(s['_id']) && !(js(s['client_id']).isNotEmpty && x['client_id'] == s['client_id'])).toList();
    final since = _localDay(DateTime.now().subtract(const Duration(days: 1)));
    cache!['sales'] = [s, ...list].where((x) => _localDay(DateTime.tryParse(js(x['at'])) ?? DateTime.now()).compareTo(since) >= 0).take(3000).toList();
    _saveCache();
    return s;
  }

  void _enqueue(J op) {
    queue.add({'id': uid(), 'at': DateTime.now().millisecondsSinceEpoch, 'staff': js(_who['_id']), ...op});
    _saveQueue();
  }

  Future<void> flush() async {
    if (syncing || queue.isEmpty) return;
    syncing = true;
    _set();
    final sessions = jmap(_read('sessions'));
    try {
      while (queue.isNotEmpty) {
        final op = queue.first;
        final sess = js(sessions[js(op['staff'])]).isNotEmpty ? js(sessions[js(op['staff'])]) : session;
        if (sess.isEmpty) break; // someone must log in with the internet on
        try {
          if (op['kind'] == 'sale') {
            final r = jmap((await _call('POST', '/sales', body: {...jmap(op['body']), 'offline': true}, sess: sess))['data']);
            if (cache != null) {
              cache!['idmap'] = {...jmap(cache!['idmap']), js(op['sid']): r['_id']};
              cache!['sales'] = jlist(cache!['sales']).where((x) => js(x['_id']) != js(op['sid'])).toList();
              _putSale(r);
            }
          } else if (op['kind'] == 'void') {
            final sid = js(jmap(cache?['idmap'])[js(op['sid'])]).isNotEmpty ? js(jmap(cache!['idmap'])[js(op['sid'])]) : js(op['sid']);
            final r = await _call('POST', '/sales/$sid/void', body: {'reason': op['reason']}, sess: sess);
            if (r['data'] != null) _putSale(jmap(r['data']));
          }
          held = false;
          _setOnline(true);
        } on ApiError catch (e) {
          if (e.network) {
            _setOnline(false);
            break;
          }
          if (e.status == 401) {
            sessions.remove(js(op['staff']));
            _write('sessions', sessions);
            if (session.isNotEmpty && session != sess) continue;
            break;
          }
          if (e.status == 402 || e.status == 403) {
            // license ended / shop suspended: keep the sales on the device until it is fixed
            held = true;
            failed = [
              ...failed.where((f) => f['code'] != 'held'),
              {'code': 'held', 'message': e.message, 'at': DateTime.now().millisecondsSinceEpoch},
            ].take(20).toList();
            break;
          }
          failed = [
            ...failed,
            {'kind': op['kind'], 'label': js(op['label']), 'message': e.message, 'at': DateTime.now().millisecondsSinceEpoch},
          ].take(20).toList();
        }
        queue.removeAt(0);
        _saveQueue();
      }
    } finally {
      syncing = false;
      _set();
    }
    if (queue.isEmpty) {
      try {
        await pull();
      } catch (_) {}
    }
  }

  void dismissFailed() {
    failed = [];
    _set();
  }

  // keep trying: every 20 s
  void _startSync() {
    if (_timer != null) return;
    Future<void> tick() async {
      if (_needLogin && _heldPin.isNotEmpty) {
        try {
          final r = jmap((await _call('POST', '/login', body: {'pin': _heldPin}, sess: ''))['data']);
          session = js(r['session']);
          await _p.setString('${_k}session', session);
          await _p.remove('${_k}offline_staff');
          _rememberSession(js(jmap(r['staff'])['_id']), session);
          cache!['offline_staff'] = null;
          _saveCache();
          _setOnline(true);
        } on ApiError catch (e) {
          if (e.network) return _setOnline(false);
          _heldPin = '';
        }
      }
      if (queue.isNotEmpty) {
        await flush();
      } else if (nz(cache?['at']) == 0 || DateTime.now().millisecondsSinceEpoch - nz(cache?['at']) > 60000 || !online) {
        try {
          await pull();
        } on ApiError catch (e) {
          if (e.network) _setOnline(false);
        } catch (_) {}
      }
    }

    _timer = Timer.periodic(const Duration(seconds: 20), (_) => tick());
    tick();
  }

  Future<void> syncNow() => queue.isNotEmpty ? flush() : pull().catchError((_) {});

  // ---------- selling ----------
  // stock control: the shelf count here follows offline sales until the server sends the real one
  void _moveStock(List<J> items, int sign) {
    if (boot['stock'] != true) return;
    final ps = products;
    for (final l in items) {
      final i = ps.indexWhere((x) => js(x['_id']) == js(l['product_id']));
      if (i >= 0 && ps[i]['stock'] != null) ps[i] = {...ps[i], 'stock': ((nz(ps[i]['stock']) + sign * nz(l['qty'])) * 1000).round() / 1000};
    }
    cache!['boot'] = {...boot, 'products': ps};
    _saveCache();
    _set();
  }

  // the member's points kept here follow each sale (used − earned), so the next lookup is right offline too
  void _memberPoints(J sale) {
    if (boot['loyalty'] == null || js(sale['member_phone']).isEmpty) return;
    final list = jlist(boot['members']);
    var i = list.indexWhere((x) => x['phone'] == sale['member_phone']);
    if (i < 0) {
      list.insert(0, {'_id': js(sale['member_id']), 'phone': sale['member_phone'], 'name': js(sale['member_name']), 'points': 0});
      i = 0;
    }
    list[i] = {...list[i], 'points': max(0, nz(list[i]['points']) - nz(sale['points_used']) + nz(sale['points_earned']))};
    cache!['boot'] = {...boot, 'members': list};
    _saveCache();
  }

  // a sale: online → the server gives the receipt number; offline → saved here, sent later. Returns (sale, offline)
  Future<(J, bool)> sell(J data) async {
    final body = {...data, 'client_id': js(data['client_id']).isNotEmpty ? data['client_id'] : uid(), 'at': js(data['at']).isNotEmpty ? data['at'] : DateTime.now().toUtc().toIso8601String()};
    if (online && queue.isEmpty && !_needLogin) {
      try {
        final r = jmap((await _call('POST', '/sales', body: body))['data']);
        _putSale(r);
        _moveStock(jlist(r['items']), -1);
        _memberPoints(r);
        _setOnline(true);
        return (r, false);
      } on ApiError catch (e) {
        if (!e.network) rethrow;
        _setOnline(false);
      }
    }
    if (!hasCache) throw const ApiError(0, 'network');
    final at = DateTime.parse(js(body['at']));
    final catOf = {for (final x in products) js(x['_id']): js(x['category_id'])};
    final promos = jlist(boot['promos']);
    final items = jlist(body['items']);
    final promo = promos.isNotEmpty ? applyMartPromos(lines: items, promos: promos, at: at, coupon: js(body['coupon']), currency: currency, categoryOf: catOf) : PromoResult.none;
    final rules = boot['loyalty'] == null ? null : jmap(boot['loyalty']);
    final phone = js(body['member_phone']).replaceAll(RegExp(r'\D'), '');
    final member = rules != null && phone.isNotEmpty ? jlist(boot['members']).where((x) => x['phone'] == phone).firstOrNull : null;
    var used = 0;
    if (member != null && nz(body['redeem']) > 0) {
      used = min(nz(body['redeem']).floor(), nz(member['points']).floor());
      if (used < nz(rules!['min_redeem'])) used = 0;
    }
    final m = saleMoney(
      lines: items,
      discount: nz(body['discount']),
      promo: promo.discount,
      points: used * nz(rules?['point_value']),
      currency: currency,
      rate: rate,
      method: js(body['method']),
      paidUsd: nz(body['paid_usd']),
      paidKhr: nz(body['paid_khr']),
      khrRound: khrRound,
    );
    if (m.short > 0) throw ApiError(400, 'Short', code: 'short', body: {'short': m.short});
    final cid = js(body['client_id']);
    final id = 'local-$cid';
    final sale = <String, dynamic>{
      '_id': id,
      'client_id': cid,
      'no': 'OFF-${cid.substring(0, 5).toUpperCase()}',
      'items': m.items,
      'subtotal': m.subtotal,
      'discount': m.discount,
      'promo_discount': m.promoDiscount,
      'promos': [
        for (final x in promo.applied) {'id': x['id'], 'name': x['name'], 'amount': x['amount']},
      ],
      'coupon': promo.coupon == 'ok' ? js(body['coupon']) : '',
      'member_phone': rules != null && phone.isNotEmpty ? phone : '',
      'member_name': member != null ? js(member['name']) : js(body['member_name']),
      'points_used': m.pointsValue > 0 ? used : 0,
      'points_value': m.pointsValue,
      'points_earned': rules != null && phone.isNotEmpty ? (m.total / (nz(rules['earn_per']) == 0 ? 1 : nz(rules['earn_per'])) + 1e-9).floor() : 0,
      'total': m.total,
      'currency': currency,
      'khr_rate': rate,
      'method': body['method'],
      'paid_usd': body['method'] == 'cash' ? nz(body['paid_usd']) : 0,
      'paid_khr': body['method'] == 'cash' ? nz(body['paid_khr']) : 0,
      'change': m.change,
      'change_khr': m.changeKhr,
      'status': 'paid',
      'at': body['at'],
      'by': js(_who['name']),
      'offline': true,
      'pending': true,
    };
    if (body['method'] == 'debt') {
      final ds = jlist(boot['debtors']);
      final i = ds.indexWhere((x) => js(x['_id']) == js(body['debtor_id']));
      sale['debtor_name'] = i >= 0 ? js(ds[i]['name']) : js(jmap(body['new_debtor'])['name']);
      if (i >= 0) {
        ds[i] = {...ds[i], 'balance': ((nz(ds[i]['balance']) + m.total) * 100).round() / 100};
        cache!['boot'] = {...boot, 'debtors': ds};
      }
    }
    _enqueue({'kind': 'sale', 'sid': id, 'body': body, 'label': sale['no']});
    _putSale(sale);
    _moveStock(jlist(sale['items']), -1);
    _memberPoints(sale);
    return (sale, true);
  }

  Future<J> voidSale(String sid, String reason) async {
    final local = sid.startsWith('local-');
    if (!local && online && queue.isEmpty && !_needLogin) {
      try {
        final was = jlist(cache?['sales']).where((x) => js(x['_id']) == sid).firstOrNull;
        final r = await _call('POST', '/sales/$sid/void', body: {'reason': reason});
        final d = jmap(r['data']);
        if (was?['status'] == 'paid' && r['already'] != true) _moveStock(jlist(d['items']), 1);
        return _putSale(d);
      } on ApiError catch (e) {
        if (!e.network) rethrow;
        _setOnline(false);
      }
    }
    if (_who['role'] == 'cashier') throw const ApiError(403, 'Manager only', code: 'manager_only');
    final s = jlist(cache?['sales']).where((x) => js(x['_id']) == sid).firstOrNull;
    if (s == null) throw const ApiError(404, 'Not found', code: 'not_found');
    _enqueue({'kind': 'void', 'sid': sid, 'reason': reason, 'label': s['no']});
    if (s['status'] == 'paid') _moveStock(jlist(s['items']), 1);
    return _putSale({...s, 'status': 'void', 'void_by': js(_who['name']), 'void_reason': reason, 'pending': true});
  }

  // today's receipts (all devices when online, this device's copy when not)
  Future<({List<J> rows, J totals, bool offline})> sales([String? day]) async {
    try {
      final r = await _tryServer(() async => jmap((await _call('GET', '/sales${day == null ? '' : '?day=$day'}'))['data']), () => <String, dynamic>{});
      if (r.isNotEmpty) return (rows: jlist(r['rows']), totals: jmap(r['totals']), offline: false);
    } on ApiError catch (e) {
      if (!e.network) rethrow;
    }
    final d = day ?? today;
    final rows = jlist(cache?['sales']).where((x) => _localDay(DateTime.tryParse(js(x['at']))) == d).toList()..sort((a, b) => js(b['at']).compareTo(js(a['at'])));
    return (rows: rows, totals: _totalsOf(rows), offline: true);
  }

  J _totalsOf(List<J> rows) {
    final r = roundOf(currency);
    final paid = rows.where((x) => x['status'] == 'paid').toList();
    final by = <String, double>{};
    for (final x in paid) {
      by[js(x['method'])] = r((by[js(x['method'])] ?? 0) + nz(x['total']));
    }
    final sales = r(paid.fold<double>(0, (a, x) => a + nz(x['total'])));
    return {'sales': sales, 'count': paid.length, 'voids': rows.length - paid.length, 'avg': paid.isEmpty ? 0 : r(sales / paid.length), 'by_method': by};
  }

  // loyalty: the customer's phone → their points (online first, the copy here when offline)
  Future<J?> lookupMember(String phone) async {
    try {
      return await _tryServer(
        () async {
          final r = await _call('GET', '/loyalty/lookup?phone=${Uri.encodeQueryComponent(phone)}');
          return r['data'] == null ? null : jmap(r['data']);
        },
        () {
          final k = phone.replaceAll(RegExp(r'\D'), '');
          return jlist(boot['members']).where((x) => x['phone'] == k || x['phone'] == '0${k.replaceFirst(RegExp(r'^855'), '')}').firstOrNull;
        },
      );
    } on ApiError {
      return null;
    }
  }

  // ---------- shifts (need the internet, like the web) ----------
  Future<J> shifts() async => jmap((await _call('GET', '/shifts'))['data']);
  Future<void> openShift(double usd, double khr) async {
    await _call('POST', '/shifts/open', body: {'float_usd': usd, 'float_khr': khr});
    await loadBoot();
  }

  Future<void> shiftCash(String sid, String kind, double usd, double khr, String note) => _call('POST', '/shifts/$sid/cash', body: {'kind': kind, 'amount_usd': usd, 'amount_khr': khr, 'note': note});
  Future<J> closeShift(String sid, double usd, double khr, String note) async =>
      jmap((await _call('POST', '/shifts/$sid/close', body: {'counted_usd': usd, 'counted_khr': khr, 'note': note}))['data']);

  // ---------- stock, debt book, online orders (the screens call the API through here) ----------
  Future<J> api(String method, String path, [Object? body]) async {
    try {
      final r = await _call(method, path, body: body);
      _setOnline(true);
      return r;
    } on ApiError catch (e) {
      if (e.network) _setOnline(false);
      rethrow;
    }
  }

  // the debt book: online, or the copy on this device (search by name / phone)
  Future<J> debtors(String q) async {
    try {
      return await _tryServer(() async => jmap((await _call('GET', '/debtors${q.isEmpty ? '' : '?q=${Uri.encodeQueryComponent(q)}'}'))['data']), () {
        final t = q.toLowerCase();
        final rows = jlist(boot['debtors']).where((d) => t.isEmpty || js(d['name']).toLowerCase().contains(t) || js(d['phone']).contains(t)).toList();
        return {
          'rows': rows,
          'totals': {'owed': rows.fold<double>(0, (a, d) => a + max(0, nz(d['balance']))), 'people': rows.where((d) => nz(d['balance']) > 0).length},
          'offline': true,
        };
      });
    } on ApiError {
      rethrow;
    }
  }

  // online orders (website shop): how many new ones wait — the POS rings until it is 0
  int newOrders = 0;
  String orderSound = '';
  int _muteUntil = 0;
  Timer? _orderPoll, _orderRing;
  bool get ringMuted => DateTime.now().millisecondsSinceEpoch < _muteUntil;

  void watchOrders(bool on) {
    _orderPoll?.cancel();
    _orderPoll = null;
    if (!on) {
      _setRing(false);
      return;
    }
    checkOrders();
    _orderPoll = Timer.periodic(const Duration(seconds: 15), (_) => checkOrders());
  }

  Future<void> checkOrders() async {
    if (session.isEmpty) return;
    try {
      final d = jmap((await _call('GET', '/orders/count'))['data']);
      newOrders = nz(d['pending']).toInt();
      orderSound = js(d['sound']);
      _setRing(newOrders > 0);
      _set();
    } catch (_) {}
  }

  void muteOrders() {
    _muteUntil = DateTime.now().millisecondsSinceEpoch + 120000;
    _set();
  }

  void _setRing(bool on) {
    if (!on) {
      _orderRing?.cancel();
      _orderRing = null;
      return;
    }
    if (_orderRing != null) return;
    void ding() {
      if (ringMuted || newOrders == 0) return;
      SystemSound.play(SystemSoundType.alert);
      HapticFeedback.heavyImpact();
    }

    ding();
    _orderRing = Timer.periodic(const Duration(seconds: 5), (_) => ding());
  }

  // ---------- the cart (kept on this device, like the web) ----------
  J cart = {'lines': <J>[]};
  List<J> heldCarts = [];
  void saveCart(J c) {
    cart = c;
    _write('cart', cart);
    _set();
  }

  void saveHeld(List<J> list) {
    heldCarts = list;
    _write('held', heldCarts);
    _set();
  }
}
