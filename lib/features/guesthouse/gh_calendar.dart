import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/theme.dart';
import '../../widgets/ui.dart';
import '../restaurant/engine/calc.dart' show J, jmap, js, nz;
import '../restaurant/pos_ui.dart';
import 'engine/gh_pos.dart';
import 'gh_book.dart';
import 'gh_stay.dart';
import 'gh_ui.dart';

// Room calendar (the web's CalendarTab): 14 days × every room; a bar per booking; tap an empty day to book it
class GhCalendar extends StatefulWidget {
  const GhCalendar({super.key});
  @override
  State<GhCalendar> createState() => _GhCalendarState();
}

class _GhCalendarState extends State<GhCalendar> {
  static const days = 14;
  static const cell = 58.0, roomW = 92.0, rowH = 50.0;
  final pos = GhPos.i;
  late String _start = GhPos.addDays(pos.today, -1);
  List<J>? _stays;
  String _error = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final r = await pos.stays(from: _start, to: GhPos.addDays(_start, days));
      if (mounted) {
        setState(() {
          _stays = r;
          _error = '';
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = ghErr(context, e));
    }
  }

  void _move(int n) {
    setState(() {
      _start = n == 0 ? GhPos.addDays(pos.today, -1) : GhPos.addDays(_start, n);
      _stays = null;
    });
    _load();
  }

  int _idx(String day) => GhPos.nightsOf(_start, day);

  @override
  Widget build(BuildContext context) {
    final t = tr(context);
    final c = context.c;
    final today = pos.today;
    final list = List.generate(days, (i) => GhPos.addDays(_start, i));
    final rooms = pos.rooms.where((r) => r['active'] == true).toList();
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
                    Text(t('gh.calTitle'), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 18)),
                    Text(t('gh.calSub'), maxLines: 2, style: TextStyle(color: c.muted, fontSize: 12.5)),
                  ],
                ),
              ),
              IconButton(onPressed: () => _move(-7), icon: const Icon(LucideIcons.chevronLeft)),
              TextButton(onPressed: () => _move(0), child: Text(t('gh.thisWeek'))),
              IconButton(onPressed: () => _move(7), icon: const Icon(LucideIcons.chevronRight)),
            ],
          ),
          const SizedBox(height: 8),
          if (_error.isNotEmpty) Alert(_error, tone: Tone.warn),
          if (_stays == null && _error.isEmpty)
            const Padding(
              padding: EdgeInsets.all(40),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (rooms.isEmpty)
            Panel(
              padding: const EdgeInsets.all(20),
              child: Muted(t('gh.noRooms'), align: TextAlign.center),
            )
          else if (_stays != null)
            Panel(
              padding: const EdgeInsets.all(8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: SizedBox(
                      width: roomW + cell * days,
                      child: Column(
                        children: [
                          // day header
                          Row(
                            children: [
                              const SizedBox(width: roomW),
                              for (final d in list)
                                Container(
                                  width: cell,
                                  padding: const EdgeInsets.symmetric(vertical: 6),
                                  decoration: BoxDecoration(color: d == today ? c.active : null, borderRadius: BorderRadius.circular(10)),
                                  child: Column(
                                    children: [
                                      Text(
                                        ghWeekday(d),
                                        style: TextStyle(fontSize: 10.5, color: c.muted, fontWeight: FontWeight.w600),
                                      ),
                                      Text(
                                        '${int.parse(d.substring(8))}',
                                        style: TextStyle(fontWeight: FontWeight.w800, color: d == today ? c.brandInk : c.ink),
                                      ),
                                    ],
                                  ),
                                ),
                            ],
                          ),
                          for (final r in rooms) _row(context, r, list, today),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 14,
                    runSpacing: 6,
                    children: [
                      for (final k in ['booked', 'in', 'out'])
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              width: 14,
                              height: 10,
                              decoration: BoxDecoration(color: _barColor(context, k).$2, borderRadius: BorderRadius.circular(3)),
                            ),
                            const SizedBox(width: 5),
                            Text(t('gh.status.$k'), style: const TextStyle(fontSize: 12)),
                          ],
                        ),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          CircleAvatar(radius: 4, backgroundColor: c.danger),
                          const SizedBox(width: 5),
                          Text(t('gh.balance'), style: const TextStyle(fontSize: 12)),
                        ],
                      ),
                    ],
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  (Color, Color) _barColor(BuildContext context, String s) {
    final c = context.c;
    return switch (s) {
      'in' => (Colors.white, const Color(0xFF2563EB)),
      'out' => (c.muted, c.chip),
      _ => (c.brandInk, c.active),
    };
  }

  Widget _row(BuildContext context, J r, List<String> list, String today) {
    final c = context.c;
    final ty = pos.typeOf(r['type_id']);
    final mine = _stays!.where((s) => js(s['room_id']) == js(r['_id'])).toList();
    return SizedBox(
      height: rowH,
      child: Stack(
        children: [
          Row(
            children: [
              Container(
                width: roomW,
                padding: const EdgeInsets.only(left: 8),
                decoration: BoxDecoration(
                  border: Border(left: BorderSide(color: ghColor(js(ty?['color'])), width: 4)),
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      js(r['name']),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                    Text(
                      js(ty?['name']),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: c.muted, fontSize: 11),
                    ),
                  ],
                ),
              ),
              for (final d in list)
                InkWell(
                  onTap: pos.readOnly || d.compareTo(GhPos.addDays(today, -1)) < 0
                      ? null
                      : () async {
                          final s = await openBook(context, {'from': d, 'to': GhPos.addDays(d, 1), 'room_id': r['_id']});
                          await _load();
                          if (s != null && context.mounted) {
                            await openStay(context, s['_id']);
                            _load();
                          }
                        },
                  child: Container(
                    width: cell,
                    height: rowH,
                    decoration: BoxDecoration(
                      color: d == today ? c.active.withValues(alpha: .45) : null,
                      border: Border(
                        top: BorderSide(color: c.line.withValues(alpha: .6)),
                        left: BorderSide(color: c.line.withValues(alpha: .6)),
                      ),
                    ),
                  ),
                ),
            ],
          ),
          for (final s in mine)
            () {
              final a = _idx(js(s['from'])).clamp(0, days);
              final z = _idx(js(s['to'])).clamp(0, days);
              if (z <= a) return const SizedBox.shrink();
              final (fg, bg) = _barColor(context, js(s['status']));
              final owes = nz(jmap(s['bill'])['balance']) > 0;
              return Positioned(
                left: roomW + a * cell + 2,
                width: (z - a) * cell - 4,
                top: 8,
                height: rowH - 16,
                child: Material(
                  color: bg,
                  borderRadius: BorderRadius.circular(9),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(9),
                    onTap: () async {
                      await openStay(context, s['_id']);
                      _load();
                    },
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              js(jmap(s['guest'])['name']),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(color: fg, fontWeight: FontWeight.w700, fontSize: 12.5),
                            ),
                          ),
                          if (owes) CircleAvatar(radius: 4, backgroundColor: c.danger),
                        ],
                      ),
                    ),
                  ),
                ),
              );
            }(),
        ],
      ),
    );
  }
}
