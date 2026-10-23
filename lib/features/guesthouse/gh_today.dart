import 'dart:async';

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/theme.dart';
import '../../widgets/ui.dart';
import '../restaurant/engine/calc.dart' show J, jmap, jlist, js, nz;
import '../restaurant/pos_ui.dart';
import 'engine/gh_pos.dart';
import 'gh_book.dart';
import 'gh_stay.dart';
import 'gh_ui.dart';

// Today (the web's TodayTab): the numbers, every room as a card (free / arriving / in / leaving),
// arrivals + departures with one-tap check-in / check-out, who is in the house.
class GhToday extends StatefulWidget {
  const GhToday({super.key});
  @override
  State<GhToday> createState() => _GhTodayState();
}

class _GhTodayState extends State<GhToday> {
  final pos = GhPos.i;
  J? _d;
  String _error = '';
  bool _busy = false;
  String _filter = '';
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _load();
    _timer = Timer.periodic(const Duration(seconds: 60), (_) => _load());
    pos.addListener(_onPos);
  }

  int _pending = 0;
  void _onPos() {
    // the queue was sent: the board changes
    if (pos.pending != _pending) {
      _pending = pos.pending;
      _load();
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    pos.removeListener(_onPos);
    super.dispose();
  }

  Future<void> _load() async {
    if (!mounted) return;
    setState(() => _busy = true);
    try {
      final d = await pos.todayBoard();
      if (mounted) {
        setState(() {
          _d = d;
          _error = '';
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = ghErr(context, e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _stay(Object? id) async {
    await openStay(context, id);
    _load();
  }

  Future<void> _book([J init = const {}]) async {
    final s = await openBook(context, init);
    await _load();
    if (s != null && mounted) _stay(s['_id']);
  }

  Future<void> _quick(J s, String action) async {
    final t = tr(context);
    try {
      await pos.action(s['_id'], action);
      if (mounted) ghToast(context, action == 'check-in' ? t('gh.checkedIn') : t('gh.checkedOut'));
      _load();
    } catch (_) {
      _stay(s['_id']); // money left to settle etc. → open the booking
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = tr(context);
    final c = context.c;
    final d = _d;
    final cur = pos.currency;
    final ready = pos.types.isNotEmpty && pos.rooms.any((r) => r['active'] == true);
    final counts = jmap(d?['counts']);
    final money = jmap(d?['money']);
    final byMethod = jmap(money['by_method']);
    final big = wide(context);
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(12, 4, 12, 24),
        children: [
          Row(
            children: [
              Expanded(
                child: Text(ghDay(pos.today, long: true), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 18)),
              ),
              IconButton(onPressed: _busy ? null : _load, icon: const Icon(LucideIcons.refreshCw, size: 18), tooltip: t('ghp.syncNow')),
              if (big) ...[
                OutlinedButton.icon(onPressed: pos.readOnly || !ready ? null : () => _book({'walkIn': true}), icon: const Icon(LucideIcons.userPlus, size: 16), label: Text(t('gh.walkIn'))),
                const SizedBox(width: 8),
              ],
              Btn(t('gh.newBooking'), icon: LucideIcons.calendarPlus, small: true, onTap: pos.readOnly || !ready ? null : () => _book()),
            ],
          ),
          if (!big)
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(onPressed: pos.readOnly || !ready ? null : () => _book({'walkIn': true}), icon: const Icon(LucideIcons.userPlus, size: 16), label: Text(t('gh.walkIn'))),
            ),
          const SizedBox(height: 6),
          if (_error.isNotEmpty)
            Alert(
              _error,
              tone: Tone.warn,
              action: TextButton(onPressed: _load, child: Text(t('rpos.retry'))),
            ),
          if (!ready && d != null)
            Panel(
              padding: const EdgeInsets.all(16),
              margin: const EdgeInsets.only(bottom: 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(t('gh.setupTitle'), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                  const SizedBox(height: 4),
                  Muted(t('gh.setupSub')),
                ],
              ),
            ),
          if (d == null && _error.isEmpty)
            const Padding(
              padding: EdgeInsets.all(40),
              child: Center(child: CircularProgressIndicator()),
            ),
          if (d != null) ...[
            LayoutBuilder(
              builder: (_, box) {
                final per = box.maxWidth > 900 ? 5 : (box.maxWidth > 560 ? 3 : 2);
                final w = (box.maxWidth - 8 * (per - 1)) / per;
                final tiles = [
                  _Tile('${nz(counts['occupied']).toInt()}/${nz(counts['rooms']).toInt()}', t('gh.occupied'), const Color(0xFF1D4ED8)),
                  _Tile('${nz(counts['free']).toInt()}', t('gh.free'), c.good),
                  _Tile('${nz(counts['arrivals']).toInt()}', t('gh.arrivals'), c.warn),
                  _Tile('${nz(counts['departures']).toInt()}', t('gh.departures'), c.muted),
                  _Tile(
                    ghMoney(money['total'], cur),
                    '${t('gh.moneyToday')}${byMethod.isEmpty ? '' : ' · ${byMethod.entries.map((e) => '${t('gh.methods.${e.key}')} ${ghMoney(e.value, cur)}').join(' · ')}'}',
                    c.brandInk,
                    main: true,
                  ),
                ];
                return Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [for (var i = 0; i < tiles.length; i++) SizedBox(width: (!big && i == tiles.length - 1) ? box.maxWidth : w, child: tiles[i])],
                );
              },
            ),
            const SizedBox(height: 12),
            if (jlist(d['rooms']).isNotEmpty) _board(context, jlist(d['rooms'])),
            const SizedBox(height: 4),
            LayoutBuilder(
              builder: (_, box) {
                final arr = _list(
                  context,
                  t('gh.arrivals'),
                  jlist(d['arrivals']),
                  t('gh.noArrivals'),
                  js(d['day']),
                  (s) => js(s['from']).compareTo(js(d['day'])) <= 0 ? ('check-in', t('gh.checkIn'), LucideIcons.logIn) : null,
                );
                final dep = _list(context, t('gh.departures'), jlist(d['departures']), t('gh.noDepartures'), js(d['day']), (_) => ('check-out', t('gh.checkOut'), LucideIcons.logOut));
                return box.maxWidth > 760
                    ? Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(child: arr),
                          const SizedBox(width: 10),
                          Expanded(child: dep),
                        ],
                      )
                    : Column(children: [arr, dep]);
              },
            ),
            if (jlist(d['in_house']).isNotEmpty) _list(context, '${t('gh.inHouse')} (${jlist(d['in_house']).length})', jlist(d['in_house']), '', js(d['day']), null),
          ],
        ],
      ),
    );
  }

  Widget _board(BuildContext context, List<J> rooms) {
    final t = tr(context);
    final c = context.c;
    const states = ['free', 'arriving', 'occupied', 'due_out'];
    final floors = <String>[];
    for (final r in rooms) {
      if (!floors.contains(js(r['floor']))) floors.add(js(r['floor']));
    }
    final shown = rooms.where((r) => _filter.isEmpty || r['state'] == _filter).toList();
    return Panel(
      padding: const EdgeInsets.all(12),
      margin: const EdgeInsets.only(bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                ChoiceChip(label: Text('${t('gh.filterAll')} ${rooms.length}'), selected: _filter.isEmpty, showCheckmark: false, onSelected: (_) => setState(() => _filter = '')),
                for (final k in states) ...[
                  const SizedBox(width: 6),
                  ChoiceChip(
                    avatar: CircleAvatar(radius: 5, backgroundColor: ghStatusColors(context, k).$1),
                    label: Text('${t('gh.states.$k')} ${rooms.where((r) => r['state'] == k).length}'),
                    selected: _filter == k,
                    showCheckmark: false,
                    onSelected: (_) => setState(() => _filter = _filter == k ? '' : k),
                  ),
                ],
              ],
            ),
          ),
          for (final fl in floors)
            if (shown.any((r) => js(r['floor']) == fl)) ...[
              if (floors.length > 1)
                Padding(
                  padding: const EdgeInsets.only(top: 12, bottom: 2),
                  child: Text(
                    fl.isEmpty ? '—' : '${t('gh.floor')} $fl',
                    style: TextStyle(color: c.muted, fontWeight: FontWeight.w700, fontSize: 12.5),
                  ),
                ),
              const SizedBox(height: 8),
              LayoutBuilder(
                builder: (_, box) {
                  final per = (box.maxWidth / 170).floor().clamp(2, 8);
                  final w = (box.maxWidth - 8 * (per - 1)) / per;
                  return Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final r in shown.where((r) => js(r['floor']) == fl))
                        SizedBox(
                          width: w,
                          child: _RoomCard(r: r, onTap: () => r['stay'] != null ? _stay(jmap(r['stay'])['_id']) : (pos.readOnly ? null : _book({'walkIn': true, 'room_id': r['_id']}))),
                        ),
                    ],
                  );
                },
              ),
            ],
        ],
      ),
    );
  }

  Widget _list(BuildContext context, String title, List<J> rows, String empty, String day, (String, String, IconData)? Function(J)? action) {
    final t = tr(context);
    final c = context.c;
    final cur = pos.currency;
    return Panel(
      padding: const EdgeInsets.fromLTRB(14, 12, 10, 8),
      margin: const EdgeInsets.only(bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(title, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
          if (rows.isEmpty && empty.isNotEmpty) Padding(padding: const EdgeInsets.symmetric(vertical: 10), child: Muted(empty)),
          for (final s in rows)
            () {
              final act = action?.call(s);
              final b = jmap(s['bill']);
              final late = s['status'] == 'booked' && js(s['from']).compareTo(day) < 0;
              return InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: () => _stay(s['_id']),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 7),
                  child: Row(
                    children: [
                      Container(
                        width: 48,
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        decoration: BoxDecoration(color: c.chip, borderRadius: BorderRadius.circular(10)),
                        child: Text(
                          js(s['room_name']),
                          textAlign: TextAlign.center,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontWeight: FontWeight.w800),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Flexible(
                                  child: Text(
                                    js(jmap(s['guest'])['name']),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(fontWeight: FontWeight.w700),
                                  ),
                                ),
                                if (late) ...[const SizedBox(width: 6), GhPill(t('gh.late'), fg: c.danger, bg: c.dangerBg)],
                              ],
                            ),
                            Text.rich(
                              TextSpan(
                                style: TextStyle(color: c.muted, fontSize: 12),
                                children: [
                                  TextSpan(text: '${ghDay(js(s['from']))} → ${ghDay(js(s['to']))} · ${t('gh.nights', {'n': nz(b['nights']).toInt()})}'),
                                  if (nz(b['balance']) > 0)
                                    TextSpan(
                                      text: ' · ${t('gh.balance')} ${ghMoney(b['balance'], cur)}',
                                      style: TextStyle(color: c.danger, fontWeight: FontWeight.w700),
                                    ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (act != null && !pos.readOnly) Btn(act.$2, icon: act.$3, small: true, onTap: () => _quick(s, act.$1)),
                    ],
                  ),
                ),
              );
            }(),
        ],
      ),
    );
  }
}

class _Tile extends StatelessWidget {
  final String value, label;
  final Color fg;
  final bool main;
  const _Tile(this.value, this.label, this.fg, {this.main = false});
  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(gradient: main ? c.gradient : null, color: main ? null : c.card, borderRadius: BorderRadius.circular(16)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              value,
              style: TextStyle(fontWeight: FontWeight.w800, fontSize: 22, color: main ? Colors.white : fg),
            ),
          ),
          Text(
            label,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(color: main ? Colors.white.withValues(alpha: .9) : c.muted, fontSize: 12.5, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }
}

// one room on the board: colour = what is happening in it now
class _RoomCard extends StatelessWidget {
  final J r;
  final VoidCallback? onTap;
  const _RoomCard({required this.r, required this.onTap});
  @override
  Widget build(BuildContext context) {
    final t = tr(context);
    final c = context.c;
    final state = js(r['state']);
    final (fg, bg) = ghStatusColors(context, state);
    final st = r['stay'] == null ? null : jmap(r['stay']);
    final b = jmap(st?['bill']);
    final hk = js(r['hk']);
    return Material(
      color: state == 'free' ? c.card : bg,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Container(
          constraints: const BoxConstraints(minHeight: 124),
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border(left: BorderSide(color: ghColor(js(r['color'])), width: 5)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      js(r['name']),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 17),
                    ),
                  ),
                  Text(
                    t('gh.states.$state'),
                    style: TextStyle(color: fg, fontWeight: FontWeight.w800, fontSize: 11.5),
                  ),
                ],
              ),
              Text(
                js(r['type']),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: c.muted, fontSize: 12),
              ),
              const SizedBox(height: 8),
              if (st != null) ...[
                Text(
                  js(jmap(st['guest'])['name']),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                Text('${ghDay(js(st['from']))} → ${ghDay(js(st['to']))}', maxLines: 1, style: TextStyle(color: c.muted, fontSize: 11.5)),
                if (nz(b['balance']) > 0)
                  Text(
                    ghMoney(b['balance'], GhPos.i.currency),
                    style: TextStyle(color: c.danger, fontWeight: FontWeight.w800, fontSize: 12.5),
                  ),
              ] else ...[
                Icon(LucideIcons.doorOpen, size: 22, color: c.good),
                Text(r['next'] != null ? t('gh.nextBooking', {'date': ghDay(js(jmap(r['next'])['from']))}) : ' ', maxLines: 1, style: TextStyle(color: c.muted, fontSize: 11.5)),
              ],
              if (hk.isNotEmpty && hk != 'ready')
                Text(
                  '🧹 ${t.or('gh.hkStates.$hk', hk)}',
                  style: TextStyle(color: c.warn, fontSize: 11, fontWeight: FontWeight.w700),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
