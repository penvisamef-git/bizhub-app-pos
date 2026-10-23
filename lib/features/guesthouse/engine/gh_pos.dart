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
import '../../restaurant/engine/calc.dart' show J, jmap, jlist, js, jsRound, nz;

// The Guest House desk engine (the web's pos/guesthouse/ghApi.js + offline.js, in Dart).
// - a linked device (x-gh-device) + a staff PIN session (x-gh-session)
// - rooms, settings, staff PIN checks and the bookings that matter are kept on the device
// - with no internet, bookings / check-in / check-out / extras / payments are saved here and queued;
//   each carries a client_id, so sending it twice adds nothing
class GhPos extends ChangeNotifier {
  GhPos._();
  static final GhPos i = GhPos._();
  static const _k = 'gh.'; // keys on this device
  static const live = ['booked', 'in'];

  late LocalPrefs _p;
  String device = '';
  String session = '';
  String stage = 'loading'; // loading | pin | boot | nocache | main | unlinked
  J? cache; // { boot, stays, staff, at, offline_staff, idmap }
  List<J> queue = [];
  bool online = true, syncing = false;
  List<J> failed = [];
  String _heldPin = '';
  Timer? _timer;
  bool _started = false;

  void _set() => notifyListeners();

  // ---------- what the screens read ----------
  J get boot => jmap(cache?['boot']);
  J get settings => jmap(boot['settings']);
  String get currency => js(settings['currency']).isEmpty ? 'USD' : js(settings['currency']);
  J get staff => jmap(boot['staff']);
  String get role => js(staff['role']);
  bool get manager => role == 'manager';
  bool get desk => role == 'desk';
  bool get isHousekeeper => role == 'housekeeper'; // desk staff: no removing lines, no discounts
  J get business => jmap(boot['business']);
  List<J> get types => jlist(boot['types']);
  List<J> get rooms => jlist(boot['rooms']);
  List<String> get methods {
    final m = settings['methods'] is List ? (settings['methods'] as List).map((e) => '$e').toList() : <String>[];
    return m.isEmpty ? const ['cash'] : m;
  }

  List<String> list(String k) => jmap(boot['lists'])[k] is List ? (jmap(boot['lists'])[k] as List).map((e) => '$e').toList() : const [];
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
      await _clearAll();
      await _p.setString('${_k}device', deviceToken);
    }
    device = deviceToken;
    session = _p.getString('${_k}session') ?? '';
    cache = _read('cache') is Map ? jmap(_read('cache')) : null;
    queue = jlist(_read('queue'));
    final offlineStaff = _p.getString('${_k}offline_staff') ?? '';
    stage = session.isNotEmpty || offlineStaff.isNotEmpty ? 'boot' : 'pin';
    _set();
    if (stage == 'boot') await loadBoot();
  }

  Future<void> _clearAll() async {
    for (final k in _p.getKeys().where((k) => k.startsWith(_k)).toList()) {
      await _p.remove(k);
    }
    cache = null;
    queue = [];
    session = '';
  }

  void stop() {
    watchRequests(false);
    _timer?.cancel();
    _timer = null;
    _started = false;
  }

  // ---------- talking to Biz Hub ----------
  static final Dio _dio = makeDio(BaseOptions(baseUrl: Config.apiHost, connectTimeout: const Duration(seconds: 12), receiveTimeout: const Duration(seconds: 40), validateStatus: (_) => true));

  // sess: null = the current session (a 401 sends the person back to the PIN screen); '' = none
  Future<J> _call(String method, String path, {Object? body, String? sess}) async {
    final s = sess ?? session;
    Response<dynamic> r;
    try {
      r = await _dio.request<dynamic>(
        '/api/ghpos$path',
        data: method == 'GET' ? null : (body ?? const {}),
        options: Options(method: method, headers: {'x-api-key': Config.apiKey, if (device.isNotEmpty) 'x-gh-device': device, if (s.isNotEmpty) 'x-gh-session': s}),
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
      _clearAll();
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
        '/api/ghpos/pair',
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

  // online: the server checks the PIN; no internet: the PIN check saved on this device (never the PIN)
  Future<bool> login(String pin) async {
    try {
      final r = jmap((await _call('POST', '/login', body: {'pin': pin}, sess: ''))['data']);
      session = js(r['session']);
      await _p.setString('${_k}session', session);
      await _p.remove('${_k}offline_staff');
      final sid = js(jmap(r['staff'])['_id']);
      if (sid.isNotEmpty) _rememberSession(sid, session);
      _setOnline(true);
      stage = 'boot';
      _set();
      await loadBoot();
      unawaited(pull().then((_) {}, onError: (_) {}));
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
    watchRequests(false);
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

  Future<void> unlinkHere() async {
    await _clearAll();
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
        cache = {...?cache, 'boot': x, 'stays': cache?['stays'] ?? <J>[], 'staff': cache?['staff'] ?? <J>[], 'at': cache?['at'] ?? 0};
        _saveCache();
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

  // fresh copy from the server (rooms, settings, PIN checks, bookings)
  Future<void> pull() async {
    final res = await Future.wait([_call('GET', '/boot'), _call('GET', '/sync')]);
    if (queue.isNotEmpty) return; // local changes still waiting: don't overwrite them
    final s = jmap(res[1]['data']);
    cache = {...?cache, 'boot': jmap(res[0]['data']), 'stays': jlist(s['stays']), 'staff': s['staff'], 'at': DateTime.now().millisecondsSinceEpoch, 'offline_staff': null};
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

  // ---------- local maths (the same rules as the server) ----------
  static final _rnd = Random.secure();
  static String uid() => List.generate(24, (_) => '0123456789abcdef'[_rnd.nextInt(16)]).join();
  static String localDay([DateTime? t]) {
    final d = (t ?? DateTime.now()).toUtc().add(const Duration(hours: 7));
    return '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
  }

  static String addDays(String day, int n) {
    final p = day.split('-').map(int.parse).toList();
    final d = DateTime.utc(p[0], p[1], p[2] + n);
    return '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
  }

  static int nightsOf(String a, String b) {
    final x = DateTime.tryParse('${a}T00:00:00Z'), y = DateTime.tryParse('${b}T00:00:00Z');
    if (x == null || y == null) return 0;
    return (y.difference(x).inHours / 24).round();
  }

  String get today => localDay();

  static J billOf(J s, String currency) {
    double r(double v) => currency == 'KHR' ? jsRound(v) : jsRound(v * 100) / 100;
    final nights = max(0, nightsOf(js(s['from']), js(s['to'])));
    final room = r(nights * nz(s['rate']));
    final extras = r(jlist(s['charges']).fold<double>(0, (a, c) => a + nz(c['amount']) * (nz(c['qty']) == 0 ? 1 : nz(c['qty']))));
    final total = r(max(0, room + extras - nz(s['discount'])));
    final paid = r(jlist(s['payments']).fold<double>(0, (a, p) => a + nz(p['amount'])));
    return {'nights': nights, 'room': room, 'extras': extras, 'discount': nz(s['discount']), 'total': total, 'paid': paid, 'balance': r(total - paid)};
  }

  J? roomOf(Object? id) => rooms.where((r) => js(r['_id']) == js(id)).firstOrNull;
  J? typeOf(Object? id) => types.where((t) => js(t['_id']) == js(id)).firstOrNull;

  J dress(J s) {
    final room = roomOf(s['room_id']);
    return {...s, 'room_name': room?['name'] ?? s['room_name'] ?? '?', 'type_id': room?['type_id'] ?? s['type_id'], 'bill': billOf(s, currency)};
  }

  List<J> get _stays => jlist(cache?['stays']);

  J _putStay(J s) {
    if (cache == null) return s;
    final d = dress(s);
    final list = _stays;
    final i = list.indexWhere((x) => js(x['_id']) == js(s['_id']) || (js(s['client_id']).isNotEmpty && x['client_id'] == s['client_id']));
    if (i >= 0) {
      list[i] = d;
    } else {
      list.insert(0, d);
    }
    cache!['stays'] = list;
    _saveCache();
    return d;
  }

  J? cachedStay(Object? sid) => _findStay(sid);
  J? _findStay(Object? sid) => _stays.where((x) => js(x['_id']) == js(sid)).firstOrNull;
  static ApiError _bad(String message, String code, [J extra = const {}]) => ApiError(409, message, code: code, body: {'code': code, 'message': message, ...extra});
  bool _takenLocal(Object? roomId, String from, String to, [Object? except]) =>
      _stays.any((x) => js(x['room_id']) == js(roomId) && live.contains(x['status']) && js(x['from']).compareTo(to) < 0 && js(x['to']).compareTo(from) > 0 && js(x['_id']) != js(except));
  String get _who => js(jmap(cache?['offline_staff'])['name']).isNotEmpty ? js(jmap(cache!['offline_staff'])['name']) : (js(staff['name']).isEmpty ? 'desk' : js(staff['name']));
  String get _now => DateTime.now().toUtc().toIso8601String();

  J _todayLocal() {
    final t = today;
    final active = rooms.where((r) => r['active'] == true).toList();
    final stays = _stays.where((s) => live.contains(s['status'])).toList();
    int byFrom(J a, J b) => js(a['from']).compareTo(js(b['from']));
    final arrivals = stays.where((s) => s['status'] == 'booked' && js(s['from']).compareTo(t) <= 0).toList()..sort(byFrom);
    final inHouse = stays.where((s) => s['status'] == 'in').toList();
    final departures = inHouse.where((s) => js(s['to']).compareTo(t) <= 0).toList();
    final board = [
      for (final r in active)
        () {
          final here = inHouse.where((s) => js(s['room_id']) == js(r['_id'])).firstOrNull;
          final nexts = stays.where((s) => s['status'] == 'booked' && js(s['room_id']) == js(r['_id'])).toList()..sort(byFrom);
          final next = nexts.firstOrNull;
          final arriving = next != null && js(next['from']).compareTo(t) <= 0;
          final state = here != null ? (js(here['to']).compareTo(t) <= 0 ? 'due_out' : 'occupied') : (arriving ? 'arriving' : 'free');
          final ty = typeOf(r['type_id']);
          return <String, dynamic>{
            '_id': r['_id'],
            'name': r['name'],
            'floor': r['floor'],
            'type': ty?['name'] ?? '',
            'color': ty?['color'] ?? '',
            'hk': r['hk'],
            'state': state,
            'stay': here != null ? dress(here) : (arriving ? dress(next) : null),
            'next': here == null && next != null && !arriving ? {'_id': next['_id'], 'from': next['from'], 'to': next['to'], 'guest': jmap(next['guest'])['name']} : null,
          };
        }(),
    ];
    final dayStart = DateTime.parse('${t}T00:00:00Z').subtract(const Duration(hours: 7));
    final money = <String, double>{};
    var total = 0.0;
    for (final s in _stays) {
      for (final p in jlist(s['payments'])) {
        final at = DateTime.tryParse(js(p['at']));
        if (at != null && !at.isBefore(dayStart)) {
          money[js(p['method'])] = (money[js(p['method'])] ?? 0) + nz(p['amount']);
          total += nz(p['amount']);
        }
      }
    }
    return {
      'day': t,
      'rooms': board,
      'arrivals': arrivals.map(dress).toList(),
      'departures': departures.map(dress).toList(),
      'in_house': inHouse.map(dress).toList(),
      'counts': {'rooms': active.length, 'occupied': inHouse.length, 'free': board.where((x) => x['state'] == 'free').length, 'arrivals': arrivals.length, 'departures': departures.length},
      'money': {'total': total, 'by_method': money},
      'currency': currency,
      'offline': true,
    };
  }

  List<J> _staysLocal({String from = '', String to = '', String status = '', String q = ''}) {
    var list = _stays;
    if (from.isNotEmpty && to.isNotEmpty) list = list.where((s) => js(s['from']).compareTo(to) < 0 && js(s['to']).compareTo(from) > 0 && ['booked', 'in', 'out'].contains(s['status'])).toList();
    if (status.isNotEmpty) list = list.where((s) => s['status'] == status).toList();
    if (q.isNotEmpty) {
      final t = q.toLowerCase();
      list = list.where((s) => [jmap(s['guest'])['name'], jmap(s['guest'])['phone'], s['no'], jmap(s['guest'])['id_number']].any((v) => js(v).toLowerCase().contains(t))).toList();
    }
    return list.map(dress).toList();
  }

  // ---------- the queue ----------
  void _enqueue(J op) {
    queue.add({
      'id': uid(),
      'at': DateTime.now().millisecondsSinceEpoch,
      'staff': js(jmap(cache?['offline_staff'])['_id']).isNotEmpty ? js(jmap(cache!['offline_staff'])['_id']) : js(staff['_id']),
      ...op,
    });
    _saveQueue();
  }

  J _applyLocal(String kind, Object? sid, J body) {
    final s = _findStay(sid);
    if (s == null) throw _bad('Not found', 'not_found');
    final t = today;
    final st = {...s};
    if (kind == 'check-in') {
      if (st['status'] != 'booked') throw _bad('Not booked', 'not_booked');
      if (js(st['from']).compareTo(t) > 0) throw _bad('Too early', 'too_early');
      if (js(st['from']).compareTo(t) < 0 && t.compareTo(js(st['to'])) < 0) st['from'] = t;
      st['status'] = 'in';
      st['checked_in_at'] = _now;
    } else if (kind == 'check-out') {
      if (st['status'] != 'in') throw _bad('Not in', 'not_in');
      if (js(st['to']).compareTo(t) > 0) st['to'] = t.compareTo(js(st['from'])) > 0 ? t : addDays(js(st['from']), 1);
      final b = billOf(st, currency);
      if (nz(b['balance']) != 0 && body['force'] != true) {
        throw _bad(nz(b['balance']) > 0 ? 'Unpaid' : 'Refund', nz(b['balance']) > 0 ? 'unpaid' : 'refund', {'balance': b['balance'], 'nights': b['nights'], 'total': b['total'], 'to': st['to']});
      }
      st['status'] = 'out';
      st['checked_out_at'] = _now;
    } else if (kind == 'cancel' || kind == 'no-show') {
      if (st['status'] != 'booked') throw _bad('Not booked', 'not_booked');
      st['status'] = kind == 'cancel' ? 'cancelled' : 'no_show';
    }
    return _putStay(st);
  }

  // send the queue in order; a local booking's id becomes the server's
  Future<void> flush() async {
    if (syncing || queue.isEmpty) return;
    syncing = true;
    _set();
    final sessions = jmap(_read('sessions'));
    try {
      while (queue.isNotEmpty) {
        final op = queue.first;
        final sess = js(sessions[op['staff']]).isNotEmpty ? js(sessions[op['staff']]) : session;
        if (sess.isEmpty) break; // someone must log in with the internet on
        final ids = jmap(cache?['idmap']);
        final sid = ids[op['sid']] != null ? js(ids[op['sid']]) : js(op['sid']);
        final kind = js(op['kind']);
        final body = jmap(op['body']);
        try {
          final r = await switch (kind) {
            'book' => _call('POST', '/stays', body: body, sess: sess),
            'update' => _call('PUT', '/stays/$sid', body: body, sess: sess),
            'charge' => _call('POST', '/stays/$sid/charges', body: body, sess: sess),
            'payment' => _call('POST', '/stays/$sid/payments', body: body, sess: sess),
            'remove-charge' => _call('DELETE', '/stays/$sid/charges/${op['lid']}', sess: sess),
            'remove-payment' => _call('DELETE', '/stays/$sid/payments/${op['lid']}', sess: sess),
            'discount' => _call('PUT', '/stays/$sid/discount', body: body, sess: sess),
            _ => _call('POST', '/stays/$sid/$kind', body: body, sess: sess),
          };
          final data = r['data'];
          if (data is Map && cache != null) {
            if (kind == 'book' && js(op['sid']).isNotEmpty) {
              cache!['idmap'] = {...jmap(cache!['idmap']), js(op['sid']): js(data['_id'])};
              cache!['stays'] = _stays.where((x) => js(x['_id']) != js(op['sid'])).toList();
            }
            _putStay(jmap(data));
          }
          _setOnline(true);
        } on ApiError catch (e) {
          if (e.network) {
            _setOnline(false);
            break;
          }
          if (e.status == 401) {
            // that staff session ended: forget it and try with whoever is logged in now
            sessions.remove(op['staff']);
            _write('sessions', sessions);
            if (session.isNotEmpty && session != sess) continue;
            break;
          }
          // the server said no (room taken meanwhile, already checked in…): keep a note, move on
          final already = e.status == 409 && ['not_booked', 'not_in'].contains(e.code);
          if (!already) {
            failed = [
              ...failed,
              {'kind': kind, 'guest': js(op['label']), 'message': e.message, 'at': DateTime.now().millisecondsSinceEpoch},
            ];
            if (failed.length > 20) failed = failed.sublist(failed.length - 20);
          }
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
          _heldPin = ''; // the PIN changed meanwhile: the PIN screen will ask
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

  Future<void> syncNow() async {
    if (queue.isNotEmpty) return flush();
    try {
      await pull();
    } catch (_) {}
  }

  // ---------- website booking requests: the desk rings while some wait ----------
  int newRequests = 0;
  bool requestsOn = false;
  int _muteUntil = 0;
  Timer? _reqPoll, _reqRing;
  bool get ringMuted => DateTime.now().millisecondsSinceEpoch < _muteUntil;

  void watchRequests(bool on) {
    _reqPoll?.cancel();
    _reqPoll = null;
    if (!on) {
      _setRing(false);
      return;
    }
    checkRequests();
    _reqPoll = Timer.periodic(const Duration(seconds: 15), (_) => checkRequests());
  }

  Future<void> checkRequests() async {
    if (session.isEmpty) return;
    try {
      final d = jmap((await _call('GET', '/cust-requests/count'))['data']);
      newRequests = nz(d['pending']).toInt();
      requestsOn = d['on'] == true;
      _setRing(newRequests > 0);
      _set();
    } catch (_) {}
  }

  void muteRequests() {
    _muteUntil = DateTime.now().millisecondsSinceEpoch + 120000;
    _set();
  }

  void _setRing(bool on) {
    if (!on) {
      _reqRing?.cancel();
      _reqRing = null;
      return;
    }
    if (_reqRing != null) return;
    void ding() {
      if (ringMuted || newRequests == 0) return;
      SystemSound.play(SystemSoundType.alert);
      HapticFeedback.heavyImpact();
    }

    ding();
    _reqRing = Timer.periodic(const Duration(seconds: 4), (_) => ding());
  }

  // ---------- what the screens call (online first, the copy here with no internet) ----------
  // online only (reports, housekeeping, expenses…)
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

  Future<J> todayBoard() => _tryServer(() async => jmap((await _call('GET', '/today'))['data']), _todayLocal);

  Future<List<J>> stays({String from = '', String to = '', String status = '', String q = ''}) {
    final qs = {'from': from, 'to': to, 'status': status, 'q': q}.entries.where((e) => e.value.isNotEmpty).map((e) => '${e.key}=${Uri.encodeQueryComponent(e.value)}').join('&');
    return _tryServer(() async => jlist((await _call('GET', '/stays${qs.isEmpty ? '' : '?$qs'}'))['data']), () => _staysLocal(from: from, to: to, status: status, q: q));
  }

  Future<J> stay(Object? sid) => _tryServer(
    () async {
      if (js(sid).startsWith('local-')) return dress(_findStay(sid) ?? (throw _bad('Not found', 'not_found')));
      final r = jmap((await _call('GET', '/stays/$sid'))['data']);
      return _putStay(r);
    },
    () {
      final s = _findStay(sid);
      if (s == null) throw _bad('Not found', 'not_found');
      return dress(s);
    },
  );

  // past guests (name / phone / ID number) to fill the form again
  Future<List<J>> guests(String q) => _tryServer(() async => jlist((await _call('GET', '/guests?q=${Uri.encodeQueryComponent(q)}'))['data']), () {
    final t = q.toLowerCase();
    final seen = <String, J>{};
    for (final s in _stays) {
      final g = jmap(s['guest']);
      if (![g['name'], g['phone'], g['id_number']].any((v) => js(v).toLowerCase().contains(t))) continue;
      final k = '${js(g['name']).toLowerCase()}|${js(g['phone'])}';
      seen.putIfAbsent(k, () => {...g, 'last': s['from'], 'stays': 0});
      seen[k]!['stays'] = nz(seen[k]!['stays']).toInt() + 1;
    }
    return seen.values.take(10).toList();
  });

  // a write: online when possible (the answer replaces the copy here), else here + queued
  Future<J> _write1(Future<J> Function() server, J Function() local) async {
    if (online && queue.isEmpty && !_needLogin) {
      try {
        final r = await server();
        final d = jmap(r['data']);
        _setOnline(true);
        return js(d['_id']).isNotEmpty ? _putStay(d) : d;
      } on ApiError catch (e) {
        if (!e.network) rethrow;
        _setOnline(false);
      }
    }
    if (!hasCache) throw const ApiError(0, 'network');
    final d = local();
    _set();
    return {...d, 'offline': true};
  }

  Future<J> book(J data) {
    final body = {...data, 'client_id': js(data['client_id']).isEmpty ? uid() : data['client_id']};
    return _write1(() => _call('POST', '/stays', body: body), () {
      final t = today;
      if (body['check_in_now'] == true && body['from'] != t) throw _bad('Walk-in must start today', 'walk_in_today');
      if (_takenLocal(body['room_id'], js(body['from']), js(body['to']))) throw _bad('Room taken', 'taken');
      final cid = js(body['client_id']);
      final id = 'local-$cid';
      final walk = body['check_in_now'] == true;
      final s = <String, dynamic>{
        '_id': id,
        'client_id': cid,
        'no': 'OFF-${cid.substring(0, 4).toUpperCase()}',
        'room_id': body['room_id'],
        'status': walk ? 'in' : 'booked',
        'from': body['from'],
        'to': body['to'],
        'rate': nz(body['rate']),
        'guest': {'name': '', 'phone': '', 'id_type': 'id_card', 'id_number': '', 'nationality': '', ...jmap(body['guest'])},
        'adults': body['adults'] ?? 1,
        'children': body['children'] ?? 0,
        'source': js(body['source']).isNotEmpty ? body['source'] : (walk ? 'walk_in' : 'phone'),
        'note': body['note'] ?? '',
        'charges': <J>[],
        'discount': 0,
        'payments': nz(body['deposit']) > 0
            ? [
                {'_id': 'local-${uid()}', 'method': js(body['method']).isEmpty ? 'cash' : body['method'], 'amount': nz(body['deposit']), 'note': walk ? '' : 'deposit', 'at': _now, 'by': _who},
              ]
            : <J>[],
        'checked_in_at': walk ? _now : null,
        'by': _who,
        'created_date': _now,
        'offline': true,
      };
      _enqueue({'kind': 'book', 'sid': id, 'body': body, 'label': jmap(s['guest'])['name']});
      return _putStay(s);
    });
  }

  Future<J> updateStay(Object? sid, J data) => _write1(() => _call('PUT', '/stays/$sid', body: data), () {
    final s = _findStay(sid);
    if (s == null) throw _bad('Not found', 'not_found');
    final next = {
      ...s,
      ...data,
      'guest': {...jmap(s['guest']), ...jmap(data['guest'])},
    };
    if (_takenLocal(next['room_id'], js(next['from']), js(next['to']), sid)) throw _bad('Room taken', 'taken');
    _enqueue({'kind': 'update', 'sid': sid, 'body': data, 'label': jmap(s['guest'])['name']});
    return _putStay(next);
  });

  // check-in | check-out | cancel | no-show
  Future<J> action(Object? sid, String action, [J body = const {}]) => _write1(() => _call('POST', '/stays/$sid/$action', body: body), () {
    final s = _applyLocal(action, sid, body);
    _enqueue({'kind': action, 'sid': sid, 'body': body, 'label': jmap(s['guest'])['name']});
    return s;
  });

  Future<J> addCharge(Object? sid, J data) {
    final body = {...data, 'client_id': uid()};
    return _write1(() => _call('POST', '/stays/$sid/charges', body: body), () {
      final s = _findStay(sid);
      if (s == null) throw _bad('Not found', 'not_found');
      _enqueue({'kind': 'charge', 'sid': sid, 'body': body, 'label': jmap(s['guest'])['name']});
      return _putStay({
        ...s,
        'charges': [
          ...jlist(s['charges']),
          {
            '_id': 'local-${body['client_id']}',
            'label': body['label'],
            'amount': nz(body['amount']),
            'qty': nz(body['qty']) == 0 ? 1 : nz(body['qty']),
            'at': _now,
            'by': _who,
            'client_id': body['client_id'],
          },
        ],
      });
    });
  }

  Future<J> addPayment(Object? sid, J data) {
    final body = {...data, 'client_id': uid()};
    return _write1(() => _call('POST', '/stays/$sid/payments', body: body), () {
      final s = _findStay(sid);
      if (s == null) throw _bad('Not found', 'not_found');
      _enqueue({'kind': 'payment', 'sid': sid, 'body': body, 'label': jmap(s['guest'])['name']});
      return _putStay({
        ...s,
        'payments': [
          ...jlist(s['payments']),
          {
            '_id': 'local-${body['client_id']}',
            'method': js(body['method']).isEmpty ? 'cash' : body['method'],
            'amount': nz(body['amount']),
            'note': body['note'] ?? '',
            'at': _now,
            'by': _who,
            'client_id': body['client_id'],
          },
        ],
      });
    });
  }

  Future<J> removeCharge(Object? sid, String cid) => _write1(() => _call('DELETE', '/stays/$sid/charges/$cid'), () {
    final s = _findStay(sid) ?? (throw _bad('Not found', 'not_found'));
    if (cid.startsWith('local-')) {
      queue = queue.where((q) => !(q['kind'] == 'charge' && 'local-${jmap(q['body'])['client_id']}' == cid)).toList();
    } else {
      _enqueue({'kind': 'remove-charge', 'sid': sid, 'lid': cid, 'label': jmap(s['guest'])['name']});
    }
    _saveQueue();
    return _putStay({...s, 'charges': jlist(s['charges']).where((c) => c['_id'] != cid).toList()});
  });

  Future<J> removePayment(Object? sid, String pid) => _write1(() => _call('DELETE', '/stays/$sid/payments/$pid'), () {
    final s = _findStay(sid) ?? (throw _bad('Not found', 'not_found'));
    if (pid.startsWith('local-')) {
      queue = queue.where((q) => !(q['kind'] == 'payment' && 'local-${jmap(q['body'])['client_id']}' == pid)).toList();
    } else {
      _enqueue({'kind': 'remove-payment', 'sid': sid, 'lid': pid, 'label': jmap(s['guest'])['name']});
    }
    _saveQueue();
    return _putStay({...s, 'payments': jlist(s['payments']).where((p) => p['_id'] != pid).toList()});
  });

  Future<J> discount(Object? sid, double amount) => _write1(() => _call('PUT', '/stays/$sid/discount', body: {'discount': amount}), () {
    final s = _findStay(sid) ?? (throw _bad('Not found', 'not_found'));
    _enqueue({
      'kind': 'discount',
      'sid': sid,
      'body': {'discount': amount},
      'label': jmap(s['guest'])['name'],
    });
    return _putStay({...s, 'discount': amount});
  });
}
