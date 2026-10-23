import 'dart:async';

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

// Bookings (the web's BookingsTab): search by name / phone / number / ID, filter by status
class GhBookings extends StatefulWidget {
  const GhBookings({super.key});
  @override
  State<GhBookings> createState() => _GhBookingsState();
}

class _GhBookingsState extends State<GhBookings> {
  final pos = GhPos.i;
  final _q = TextEditingController();
  String _status = '';
  List<J>? _rows;
  String _error = '';
  Timer? _deb;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _deb?.cancel();
    _q.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final r = await pos.stays(q: _q.text.trim(), status: _status);
      if (mounted) {
        setState(() {
          _rows = r;
          _error = '';
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = ghErr(context, e));
    }
  }

  Future<void> _open(Object? id) async {
    await openStay(context, id);
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final t = tr(context);
    final c = context.c;
    final cur = pos.currency;
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(12, 4, 12, 24),
        children: [
          Row(
            children: [
              Expanded(
                child: Field(
                  controller: _q,
                  hint: t('gh.search'),
                  icon: LucideIcons.search,
                  onChanged: (_) {
                    _deb?.cancel();
                    _deb = Timer(const Duration(milliseconds: 300), _load);
                  },
                ),
              ),
              const SizedBox(width: 8),
              Btn(
                t('gh.newBooking'),
                icon: LucideIcons.calendarPlus,
                small: true,
                onTap: pos.readOnly || !pos.rooms.any((r) => r['active'] == true)
                    ? null
                    : () async {
                        final s = await openBook(context);
                        await _load();
                        if (s != null) _open(s['_id']);
                      },
              ),
            ],
          ),
          const SizedBox(height: 8),
          PosChips<String>(
            scroll: true,
            value: _status,
            onTap: (v) {
              setState(() {
                _status = v;
                _rows = null;
              });
              _load();
            },
            options: [
              for (final k in ['', 'booked', 'in', 'out', 'cancelled', 'no_show']) (k, k.isEmpty ? t('gh.all') : t('gh.status.$k')),
            ],
          ),
          const SizedBox(height: 8),
          if (_error.isNotEmpty) Alert(_error, tone: Tone.warn),
          if (_rows == null && _error.isEmpty)
            const Padding(
              padding: EdgeInsets.all(40),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (_rows != null && _rows!.isEmpty)
            Padding(
              padding: const EdgeInsets.all(24),
              child: Muted(t('gh.noBookings'), align: TextAlign.center),
            )
          else if (_rows != null)
            for (final s in _rows!)
              () {
                final b = jmap(s['bill']);
                final st = js(s['status']);
                final (fg, bg) = ghStatusColors(context, st);
                return Card(
                  margin: const EdgeInsets.only(bottom: 6),
                  elevation: 0,
                  color: c.card,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  child: ListTile(
                    onTap: () => _open(s['_id']),
                    leading: Container(
                      width: 50,
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
                    title: Text.rich(
                      TextSpan(
                        children: [
                          TextSpan(
                            text: js(jmap(s['guest'])['name']),
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                          TextSpan(
                            text: '  ${js(s['no'])}',
                            style: TextStyle(color: c.muted, fontSize: 12),
                          ),
                        ],
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    subtitle: Text.rich(
                      TextSpan(
                        children: [
                          TextSpan(text: '${ghDay(js(s['from']))} → ${ghDay(js(s['to']))} · ${t('gh.nights', {'n': nz(b['nights']).toInt()})} · ${ghMoney(b['total'], cur)}'),
                          if (nz(b['balance']) > 0 && ['booked', 'in', 'out'].contains(st))
                            TextSpan(
                              text: ' · ${t('gh.balance')} ${ghMoney(b['balance'], cur)}',
                              style: TextStyle(color: c.danger, fontWeight: FontWeight.w700),
                            ),
                        ],
                      ),
                    ),
                    trailing: GhPill(t('gh.status.$st'), fg: fg, bg: bg),
                  ),
                );
              }(),
        ],
      ),
    );
  }
}
