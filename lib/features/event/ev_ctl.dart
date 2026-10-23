import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/app_state.dart';
import '../../core/format.dart';
import 'ev_api.dart';

// the door phone's words (web: pos/event/doorText.js → evd.*)
String ev(String k, [Map<String, Object?> vars = const {}]) => AppState.i.t('evd.$k', vars);

// "in 3 h" / "now" / "2 days ago" (the web's soonText)
String evSoon(Object? at) {
  final d = DateTime.tryParse('${at ?? ''}');
  if (d == null) return '';
  final ms = d.difference(DateTime.now()).inMilliseconds;
  final m = (ms.abs() / 60000).round();
  if (m < 30) return ev('now');
  final txt = m < 60 ? ev('mins', {'n': m}) : (m < 48 * 60 ? ev('hoursOnly', {'h': (m / 60).round()}) : ev('days', {'n': (m / 1440).round()}));
  return ms > 0 ? ev('startsIn', {'t': txt}) : ev('startedAgo', {'t': txt});
}

// "in 2 h 15 min" / "35 min ago" (Live)
String evSpan(Object? at, DateTime now) {
  final d = DateTime.tryParse('${at ?? ''}');
  if (d == null) return '';
  final ms = d.difference(now).inMilliseconds;
  final m = (ms.abs() / 60000).round();
  final txt = m < 60 ? ev('mins', {'n': m}) : (m < 48 * 60 ? ev('hoursMins', {'h': m ~/ 60, 'm': m % 60}) : ev('days', {'n': (m / 1440).round()}));
  return ms > 0 ? ev('startsIn', {'t': txt}) : ev('startedAgo', {'t': txt});
}

String evWhen(Object? v) => fmtDate(v, time: true, lang: AppState.i.lang);

// what one scan showed: ok | used | cancelled | other_event | other_show | not_found | error
class ScanResult {
  final String kind, code, msg;
  final Json? ticket, other;
  final bool offline;
  const ScanResult(this.kind, {this.code = '', this.msg = '', this.ticket, this.other, this.offline = false});
  bool get ok => kind == 'ok';
}

// One event open on the door phone: the counts, every ticket code (for offline), the scans waiting to be sent.
// Every 20 s it sends the waiting scans, or refreshes the counts.
class EvCtl extends ChangeNotifier {
  final Json boot;
  final Json event;
  final VoidCallback onLogout;
  Json? info;
  Map<String, Json> codes = {};
  List<Json> queue = [];
  bool online = true;
  DateTime? lastSync;
  String show = '';
  Timer? _timer;
  bool _dead = false;

  EvCtl({required this.boot, required this.event, required this.onLogout}) {
    codes = EvStore.map(_codesKey).map((k, v) => MapEntry(k, obj(v)));
    queue = EvStore.list(_queueKey);
    final shows = objs(event['shows']);
    if (shows.isNotEmpty) {
      // the next showtime, or the one going on
      final now = DateTime.now().subtract(const Duration(hours: 3));
      show = str(shows.firstWhere((s) => (DateTime.tryParse(str(s['starts_at'])) ?? DateTime(0)).isAfter(now), orElse: () => shows.last)['key']);
    }
    refresh();
    _timer = Timer.periodic(const Duration(seconds: 20), (_) => queue.isNotEmpty ? syncQueue() : refresh());
  }

  String get eid => str(event['_id']);
  Json get member => obj(boot['member']);
  String get me => str(member['name']);
  String get role => str(member['role']);
  bool get manager => role == 'manager';
  String get _codesKey => 'codes.$eid';
  String get _queueKey => 'queue.$eid';
  String get _histKey => 'hist.$eid';

  List<String> get tabs => [
    'scan',
    'live',
    if (['crew', 'cashier', 'manager'].contains(role)) 'guests',
    if (['cashier', 'manager'].contains(role) && boot['cashier'] == true) 'sell',
    if (manager) 'orders',
  ];

  int get used => info == null ? codes.values.where((c) => c['status'] == 'used').length : n(obj(info!['counts'])['used']).toInt();
  int get total => info == null ? codes.values.where((c) => c['status'] != 'cancelled').length : n(obj(info!['counts'])['tickets']).toInt();

  void setShow(String k) {
    show = k;
    notifyListeners();
  }

  void _set() {
    if (!_dead) notifyListeners();
  }

  Future<void> refresh() async {
    try {
      final d = obj((await EvDoor.event(eid, codes: true))['data']);
      final map = <String, Json>{};
      for (final row in (d['codes'] is List ? d['codes'] as List : const [])) {
        if (row is! List || row.isEmpty) continue;
        Object? at(int i) => i < row.length ? row[i] : null;
        map[str(at(0))] = {'status': str(at(1)), 'type': str(at(2)), 'holder': str(at(3)), 'used_at': at(4), 'used_by': str(at(5)), 'show': str(at(6)), 'seat_label': str(at(7))};
      }
      // scans still waiting to be sent stay "used" here
      for (final q in EvStore.list(_queueKey)) {
        final c = map[str(q['code'])];
        if (c != null && c['status'] == 'valid') map[str(q['code'])] = {...c, 'status': 'used', 'used_at': q['at'], 'used_by': me};
      }
      codes = map;
      EvStore.set(_codesKey, map);
      info = d;
      online = true;
      lastSync = DateTime.now();
      _set();
    } on ApiError catch (e) {
      if (e.network) {
        online = false;
        _set();
      } else if (e.status == 401) {
        onLogout();
      }
    }
  }

  Future<void> syncQueue() async {
    final q = EvStore.list(_queueKey);
    if (q.isEmpty) return;
    try {
      await EvDoor.sync(eid, q, show);
      // keep scans made while this was sending
      final sent = q.map((x) => '${x['code']}|${x['at']}').toSet();
      final rest = EvStore.list(_queueKey).where((x) => !sent.contains('${x['code']}|${x['at']}')).toList();
      EvStore.set(_queueKey, rest);
      queue = rest;
      online = true;
      _set();
      await refresh();
    } on ApiError catch (e) {
      if (e.network) {
        online = false;
        _set();
      }
    }
  }

  // a scan, checked by the server (or by this phone when there is no internet)
  Future<ScanResult> scan(String raw) async {
    final code = evCodeOf(raw);
    ScanResult r;
    try {
      final d = obj((await EvDoor.scan(eid, code, show))['data']);
      final tk = d['ticket'] == null ? null : obj(d['ticket']);
      final kind = str(d['result']);
      // only this event's tickets go in the offline list (a ticket for another event must not pass later offline)
      if (tk != null && ['ok', 'used', 'cancelled', 'other_show'].contains(kind)) {
        codes[str(tk['code'])] = {
          'status': str(tk['status']),
          'type': str(tk['type_name']),
          'holder': str(tk['holder']),
          'used_at': tk['used_at'],
          'used_by': str(tk['used_by']),
          'show': str(tk['show']),
          'seat_label': str(tk['seat_label']),
        };
        EvStore.set(_codesKey, codes);
      }
      if (info != null) {
        info = {
          ...info!,
          'counts': {...obj(info!['counts']), 'used': d['used']},
        };
      }
      online = true;
      r = ScanResult(kind, code: code, ticket: tk == null ? null : {...tk, 'type': tk['type_name']}, other: d['other'] == null ? null : obj(d['other']));
    } on ApiError catch (e) {
      if (e.network) {
        online = false;
        r = _offline(code);
      } else if (e.status == 401) {
        onLogout();
        r = ScanResult('error', msg: e.message);
      } else {
        r = ScanResult('error', msg: e.message);
      }
    }
    _remember(r);
    _set();
    return r;
  }

  // no internet: the phone checks the codes it downloaded and keeps the scan to send later
  ScanResult _offline(String code) {
    final c = codes[code];
    if (c == null) return ScanResult('not_found', code: code, offline: true);
    final tk = {...c, 'code': code};
    if (c['status'] == 'cancelled') return ScanResult('cancelled', code: code, ticket: tk, offline: true);
    if (c['status'] == 'used') return ScanResult('used', code: code, ticket: tk, offline: true);
    if (show.isNotEmpty && str(c['show']).isNotEmpty && c['show'] != show) return ScanResult('other_show', code: code, ticket: tk, offline: true);
    final at = DateTime.now().toUtc().toIso8601String();
    codes[code] = {...c, 'status': 'used', 'used_at': at, 'used_by': me};
    EvStore.set(_codesKey, codes);
    queue = [
      ...EvStore.list(_queueKey),
      {'code': code, 'at': at, 'show': show},
    ];
    EvStore.set(_queueKey, queue);
    return ScanResult('ok', code: code, ticket: tk, offline: true);
  }

  // every scan on this phone (Live)
  List<Json> get hist => EvStore.list(_histKey);
  void _remember(ScanResult r) {
    final list = hist;
    list.insert(0, {
      'at': DateTime.now().millisecondsSinceEpoch,
      'kind': r.kind,
      'holder': str(r.ticket?['holder']),
      'type': str(r.ticket?['type'] ?? r.ticket?['type_name']),
      'seat': str(r.ticket?['seat_label']),
      'code': r.code.isNotEmpty ? r.code : str(r.ticket?['code']),
    });
    EvStore.set(_histKey, list.take(300).toList());
  }

  @override
  void dispose() {
    _dead = true;
    _timer?.cancel();
    super.dispose();
  }
}
