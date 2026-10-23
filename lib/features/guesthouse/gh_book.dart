import 'dart:async';

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/i18n.dart';
import '../../core/theme.dart';
import '../../widgets/ui.dart';
import '../mart/mart_kit.dart' show DayField;
import '../restaurant/engine/calc.dart' show J, jmap, js, nz;
import '../restaurant/pos_ui.dart';
import 'engine/gh_pos.dart';
import 'gh_ui.dart';

String _dayShow(String d) => ghDay(d, weekday: true);

// New booking / walk-in (the web's BookModal): dates → a free room → the guest → pay now (deposit)
// init: { walkIn, room_id, from, to }   returns the new stay
Future<J?> openBook(BuildContext context, [J init = const {}]) {
  final t = tr(context);
  final walk = init['walkIn'] == true;
  return posSheet<J>(
    context,
    title: walk ? t('gh.walkIn') : t('gh.bookTitle'),
    maxWidth: 820,
    body: (ctx) => _BookForm(init: init),
  );
}

// the rooms booked (or in use) between from → to (the departure day is free)
Future<Set<String>> busyRooms(String from, String to, [String except = '']) async {
  if (from.isEmpty || to.compareTo(from) <= 0) return {};
  try {
    final list = await GhPos.i.stays(from: from, to: to);
    return {
      for (final s in list)
        if (GhPos.live.contains(s['status']) && js(s['_id']) != except) js(s['room_id']),
    };
  } catch (_) {
    return {};
  }
}

// a − value + stepper
class GhStepper extends StatelessWidget {
  final int value, min, max;
  final ValueChanged<int> onChanged;
  const GhStepper({super.key, required this.value, this.min = 0, this.max = 99, required this.onChanged});
  @override
  Widget build(BuildContext context) {
    final c = context.c;
    Widget b(IconData i, bool on, VoidCallback f) => Material(
      color: c.card,
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: on ? f : null,
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Icon(i, size: 18, color: on ? c.ink : c.muted.withValues(alpha: .4)),
        ),
      ),
    );
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        b(LucideIcons.minus, value > min, () => onChanged(value - 1)),
        SizedBox(
          width: 40,
          child: Text(
            '$value',
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
          ),
        ),
        b(LucideIcons.plus, value < max, () => onChanged(value + 1)),
      ],
    );
  }
}

// free rooms for the chosen dates, grouped by type
class GhRoomPicker extends StatelessWidget {
  final String value;
  final Set<String>? busy;
  final void Function(J room, J? type) onPick;
  const GhRoomPicker({super.key, required this.value, required this.busy, required this.onPick});
  @override
  Widget build(BuildContext context) {
    final t = tr(context);
    final c = context.c;
    final pos = GhPos.i;
    if (busy == null) {
      return const Padding(
        padding: EdgeInsets.all(16),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    final free = pos.rooms.where((r) => r['active'] == true && r['usable'] != false && (!busy!.contains(js(r['_id'])) || js(r['_id']) == value)).toList();
    if (free.isEmpty) {
      return Padding(padding: const EdgeInsets.all(12), child: Muted(t('gh.noFree')));
    }
    final order = {for (var i = 0; i < pos.types.length; i++) js(pos.types[i]['_id']): i};
    free.sort((a, b) => (order[js(a['type_id'])] ?? 99).compareTo(order[js(b['type_id'])] ?? 99));
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final r in free)
          () {
            final ty = pos.typeOf(r['type_id']);
            final on = js(r['_id']) == value;
            final col = ghColor(js(ty?['color']));
            return Material(
              color: on ? col.withValues(alpha: .14) : c.card,
              borderRadius: BorderRadius.circular(14),
              child: InkWell(
                borderRadius: BorderRadius.circular(14),
                onTap: () => onPick(r, ty),
                child: Container(
                  width: 128,
                  padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: on ? col : c.line, width: on ? 2 : 1),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(js(r['name']), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                          ),
                          if (on) Icon(LucideIcons.check, size: 16, color: col),
                        ],
                      ),
                      Text(
                        js(ty?['name']),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: col, fontSize: 12, fontWeight: FontWeight.w700),
                      ),
                      Text('${ghMoney(ty?['price'], pos.currency)} ${t('gh.perNight')}', style: TextStyle(color: c.muted, fontSize: 12)),
                    ],
                  ),
                ),
              ),
            );
          }(),
      ],
    );
  }
}

// chips for one choice
Widget ghChips(BuildContext context, List<(String, String)> opts, String value, ValueChanged<String> onTap) => Wrap(
  spacing: 6,
  runSpacing: 6,
  children: [for (final (k, label) in opts) ChoiceChip(label: Text(label), selected: value == k, showCheckmark: false, onSelected: (_) => onTap(k))],
);

// the guest: name, phone (+ past guests to pick), people, ID / nationality (+ passport details with gh_police)
class GhGuestFields extends StatefulWidget {
  final J f; // the form: { guest: {...}, adults, children }
  final VoidCallback onChanged;
  final bool lookup;
  const GhGuestFields({super.key, required this.f, required this.onChanged, this.lookup = true});
  @override
  State<GhGuestFields> createState() => _GhGuestFieldsState();
}

class _GhGuestFieldsState extends State<GhGuestFields> {
  late final J g = jmap(widget.f['guest']);
  late final _name = TextEditingController(text: js(g['name']));
  late final _phone = TextEditingController(text: js(g['phone']));
  late final _idn = TextEditingController(text: js(g['id_number']));
  late final _nat = TextEditingController(text: js(g['nationality']));
  late final _visa = TextEditingController(text: js(g['visa_type']));
  late bool _more = js(g['id_number']).isNotEmpty || js(g['nationality']).isNotEmpty;
  List<J> _hits = [];
  Timer? _deb;

  @override
  void dispose() {
    _deb?.cancel();
    for (final c in [_name, _phone, _idn, _nat, _visa]) {
      c.dispose();
    }
    super.dispose();
  }

  void _put(String k, Object? v) {
    widget.f['guest'] = {...jmap(widget.f['guest']), k: v};
    widget.onChanged();
  }

  void _look() {
    if (!widget.lookup) return;
    _deb?.cancel();
    final q = _name.text.trim().length >= 2 ? _name.text.trim() : (_phone.text.trim().length >= 3 ? _phone.text.trim() : '');
    if (q.isEmpty) {
      setState(() => _hits = []);
      return;
    }
    _deb = Timer(const Duration(milliseconds: 300), () async {
      final r = await GhPos.i.guests(q).catchError((_) => <J>[]);
      if (mounted) setState(() => _hits = r);
    });
  }

  void _pick(J h) {
    final gg = {
      'name': js(h['name']),
      'phone': js(h['phone']),
      'id_type': js(h['id_type']).isEmpty ? 'id_card' : js(h['id_type']),
      'id_number': js(h['id_number']),
      'nationality': js(h['nationality']),
      'gender': js(h['gender']),
      'dob': js(h['dob']),
      'visa_type': js(h['visa_type']),
      'visa_until': js(h['visa_until']),
    };
    widget.f['guest'] = gg;
    _name.text = gg['name']!;
    _phone.text = gg['phone']!;
    _idn.text = gg['id_number']!;
    _nat.text = gg['nationality']!;
    _visa.text = gg['visa_type']!;
    setState(() {
      _hits = [];
      _more = _more || gg['id_number']!.isNotEmpty || gg['nationality']!.isNotEmpty;
    });
    widget.onChanged();
  }

  @override
  Widget build(BuildContext context) {
    final t = tr(context);
    final c = context.c;
    final pos = GhPos.i;
    final gg = jmap(widget.f['guest']);
    final police = pos.boot['police'] == true;
    final shown = _hits.where((h) => !(js(h['name']) == _name.text && js(h['phone']) == _phone.text)).take(4).toList();
    final two = wide(context);
    Widget pair(Widget a, Widget b) => two
        ? Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: a),
              const SizedBox(width: 10),
              Expanded(child: b),
            ],
          )
        : Column(children: [a, const SizedBox(height: 10), b]);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        pair(
          Field(
            controller: _name,
            label: '${t('gh.guestName')} *',
            hint: 'Sok Dara',
            maxLength: 80,
            onChanged: (v) {
              _put('name', v);
              _look();
            },
          ),
          Field(
            controller: _phone,
            label: t('gh.phone'),
            hint: '012 345 678',
            keyboard: TextInputType.phone,
            maxLength: 30,
            onChanged: (v) {
              _put('phone', v);
              _look();
            },
          ),
        ),
        if (shown.isNotEmpty) ...[
          const SizedBox(height: 6),
          Muted(t('gh.past')),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final h in shown)
                ActionChip(avatar: const Icon(LucideIcons.userRound, size: 15), label: Text('${js(h['name'])}${js(h['phone']).isNotEmpty ? ' · ${js(h['phone'])}' : ''}'), onPressed: () => _pick(h)),
            ],
          ),
        ],
        const SizedBox(height: 10),
        Wrap(
          spacing: 14,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(t('gh.adults'), style: const TextStyle(fontWeight: FontWeight.w700)),
                const SizedBox(width: 6),
                GhStepper(
                  value: nz(widget.f['adults']).toInt(),
                  min: 1,
                  max: 20,
                  onChanged: (v) {
                    widget.f['adults'] = v;
                    widget.onChanged();
                  },
                ),
              ],
            ),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(t('gh.children'), style: const TextStyle(fontWeight: FontWeight.w700)),
                const SizedBox(width: 6),
                GhStepper(
                  value: nz(widget.f['children']).toInt(),
                  max: 20,
                  onChanged: (v) {
                    widget.f['children'] = v;
                    widget.onChanged();
                  },
                ),
              ],
            ),
            TextButton(onPressed: () => setState(() => _more = !_more), child: Text('${_more ? '−' : '+'} ${t('gh.idType')} / ${t('gh.nationality')}')),
          ],
        ),
        if (_more) ...[
          const SizedBox(height: 6),
          ghChips(context, [for (final k in pos.list('id_types')) (k, t('gh.idTypes.$k'))], js(gg['id_type']).isEmpty ? 'id_card' : js(gg['id_type']), (k) => setState(() => _put('id_type', k))),
          const SizedBox(height: 10),
          pair(
            Field(controller: _idn, label: t('gh.idNumber'), maxLength: 40, onChanged: (v) => _put('id_number', v)),
            Field(controller: _nat, label: t('gh.nationality'), hint: 'Cambodia', maxLength: 40, onChanged: (v) => _put('nationality', v)),
          ),
          if (police) ...[
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: c.card, borderRadius: BorderRadius.circular(14)),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Muted(t('gh.passportBox')),
                  const SizedBox(height: 8),
                  Text(t('gh.gender'), style: const TextStyle(fontWeight: FontWeight.w700)),
                  const SizedBox(height: 4),
                  ghChips(context, [('m', t('gh.genders.m')), ('f', t('gh.genders.f'))], js(gg['gender']), (k) => setState(() => _put('gender', js(gg['gender']) == k ? '' : k))),
                  const SizedBox(height: 10),
                  pair(
                    DayField(show: _dayShow, label: t('gh.dob'), value: js(gg['dob']), onPick: (v) => setState(() => _put('dob', v))),
                    DayField(show: _dayShow, label: t('gh.visaUntil'), value: js(gg['visa_until']), onPick: (v) => setState(() => _put('visa_until', v))),
                  ),
                  const SizedBox(height: 10),
                  Field(controller: _visa, label: t('gh.visaType'), hint: 'T · E · K', maxLength: 30, onChanged: (v) => _put('visa_type', v)),
                ],
              ),
            ),
          ],
        ],
      ],
    );
  }
}

class _BookForm extends StatefulWidget {
  final J init;
  const _BookForm({required this.init});
  @override
  State<_BookForm> createState() => _BookFormState();
}

class _BookFormState extends State<_BookForm> {
  final pos = GhPos.i;
  late final bool walk = widget.init['walkIn'] == true;
  late J f;
  Set<String>? _busy;
  bool _saving = false;
  String _error = '';
  final _rate = TextEditingController();
  final _deposit = TextEditingController();
  final _note = TextEditingController();

  @override
  void initState() {
    super.initState();
    final room = pos.roomOf(widget.init['room_id']);
    final type = room == null ? null : pos.typeOf(room['type_id']);
    final from = walk ? pos.today : (js(widget.init['from']).isEmpty ? pos.today : js(widget.init['from']));
    f = {
      'from': from,
      'to': js(widget.init['to']).isEmpty ? GhPos.addDays(from, 1) : js(widget.init['to']),
      'room_id': js(widget.init['room_id']),
      'guest': {'name': '', 'phone': '', 'id_type': 'id_card', 'id_number': '', 'nationality': '', 'gender': '', 'dob': '', 'visa_type': '', 'visa_until': ''},
      'adults': 1,
      'children': 0,
      'source': walk ? 'walk_in' : 'phone',
      'method': pos.methods.first,
    };
    if (type != null) _rate.text = _num(type['price']);
    _loadBusy();
  }

  @override
  void dispose() {
    _rate.dispose();
    _deposit.dispose();
    _note.dispose();
    super.dispose();
  }

  static String _num(Object? v) {
    final x = nz(v);
    return x == x.roundToDouble() ? x.toInt().toString() : x.toString();
  }

  int get _nights => js(f['to']).compareTo(js(f['from'])) > 0 ? GhPos.nightsOf(js(f['from']), js(f['to'])) : 0;

  Future<void> _loadBusy() async {
    setState(() => _busy = null);
    final b = await busyRooms(js(f['from']), js(f['to']));
    if (!mounted) return;
    setState(() {
      _busy = b;
      if (b.contains(js(f['room_id']))) f['room_id'] = '';
    });
  }

  void _dates(String from, String to) {
    f['from'] = from;
    f['to'] = to;
    _loadBusy();
  }

  Future<void> _submit(T t) async {
    setState(() {
      _saving = true;
      _error = '';
    });
    try {
      final s = await pos.book({
        ...f,
        'rate': nz(_rate.text),
        'note': _note.text.trim(),
        'deposit': nz(_deposit.text),
        'check_in_now': walk,
        'guest': {...jmap(f['guest']), 'name': js(jmap(f['guest'])['name']).trim()},
      });
      if (!mounted) return;
      ghToast(context, walk ? t('gh.checkedIn') : t('gh.booked', {'no': js(s['no'])}));
      Navigator.pop(context, s);
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = ghErr(context, e);
          _saving = false;
        });
      }
    }
  }

  Widget _step(int n, String title, bool done) {
    final c = context.c;
    return Padding(
      padding: const EdgeInsets.only(top: 14, bottom: 8),
      child: Row(
        children: [
          CircleAvatar(
            radius: 12,
            backgroundColor: done ? c.good : c.chip,
            child: done
                ? const Icon(LucideIcons.check, size: 14, color: Colors.white)
                : Text(
                    '$n',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: c.ink),
                  ),
          ),
          const SizedBox(width: 8),
          Text(title, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = tr(context);
    final c = context.c;
    final cur = pos.currency;
    final nights = _nights;
    final total = nights * nz(_rate.text);
    final dep = nz(_deposit.text);
    final guestOk = js(jmap(f['guest'])['name']).trim().isNotEmpty;
    final can = js(f['room_id']).isNotEmpty && nights > 0 && guestOk && _rate.text.trim().isNotEmpty && !_saving;
    final room = pos.roomOf(f['room_id']);
    final big = wide(context);

    final main = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _step(1, t('gh.stayDates'), nights > 0),
        () {
          final arrive = walk
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(t('gh.arrive'), style: const TextStyle(fontWeight: FontWeight.w700)),
                    const SizedBox(height: 6),
                    Text(ghDay(js(f['from']), weekday: true), style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                  ],
                )
              : DayField(show: _dayShow, label: t('gh.arrive'), value: js(f['from']), onPick: (v) => setState(() => _dates(v, GhPos.addDays(v, nights < 1 ? 1 : nights))));
          final leave = DayField(
            show: _dayShow,
            label: t('gh.leave'),
            value: js(f['to']),
            onPick: (v) {
              if (v.compareTo(js(f['from'])) > 0) setState(() => _dates(js(f['from']), v));
            },
          );
          final stepper = Column(
            children: [
              Text(
                t('gh.nightsLabel'),
                style: TextStyle(color: c.muted, fontSize: 12, fontWeight: FontWeight.w700),
              ),
              GhStepper(value: nights, min: 1, max: 366, onChanged: (n) => setState(() => _dates(js(f['from']), GhPos.addDays(js(f['from']), n)))),
            ],
          );
          return big
              ? Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Expanded(child: arrive),
                    const SizedBox(width: 8),
                    stepper,
                    const SizedBox(width: 8),
                    Expanded(child: leave),
                  ],
                )
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Expanded(child: arrive),
                        const SizedBox(width: 8),
                        Expanded(child: leave),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Align(alignment: Alignment.center, child: stepper),
                  ],
                );
        }(),
        _step(2, t('gh.room'), js(f['room_id']).isNotEmpty),
        GhRoomPicker(
          value: js(f['room_id']),
          busy: _busy,
          onPick: (r, ty) => setState(() {
            final sameType = room != null && js(room['type_id']) == js(r['type_id']);
            f['room_id'] = js(r['_id']);
            if (!sameType && ty != null) _rate.text = _num(ty['price']);
          }),
        ),
        _step(3, t('gh.guest'), guestOk),
        GhGuestFields(f: f, onChanged: () => setState(() {})),
        if (!walk) ...[
          const SizedBox(height: 12),
          Text(t('gh.source'), style: const TextStyle(fontWeight: FontWeight.w700)),
          const SizedBox(height: 6),
          ghChips(
            context,
            [
              for (final k in pos.list('sources'))
                if (k != 'walk_in') (k, t('gh.sources.$k')),
            ],
            js(f['source']),
            (k) => setState(() => f['source'] = k),
          ),
        ],
        const SizedBox(height: 12),
        Field(controller: _note, label: t('gh.note'), maxLength: 500),
      ],
    );

    final side = Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: c.card, borderRadius: BorderRadius.circular(18)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 12,
                backgroundColor: dep > 0 ? c.good : c.chip,
                child: dep > 0
                    ? const Icon(LucideIcons.check, size: 14, color: Colors.white)
                    : Text(
                        '4',
                        style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: c.ink),
                      ),
              ),
              const SizedBox(width: 8),
              Text(t('gh.payNow'), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
            ],
          ),
          const SizedBox(height: 10),
          SumRow(room != null ? '${t('gh.room')} ${js(room['name'])}' : t('gh.pickRoom'), '${ghDay(js(f['from']))} → ${ghDay(js(f['to']))}'),
          const SizedBox(height: 6),
          Field(controller: _rate, label: '${t('gh.rate')} ($cur)', keyboard: const TextInputType.numberWithOptions(decimal: true), onChanged: (_) => setState(() {})),
          const SizedBox(height: 6),
          SumRow(t('gh.nights', {'n': nights}), ghMoney(total, cur), big: true),
          const SizedBox(height: 10),
          Field(controller: _deposit, label: t('gh.deposit'), hint: '0', keyboard: const TextInputType.numberWithOptions(decimal: true), onChanged: (_) => setState(() {})),
          const SizedBox(height: 6),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              ChoiceChip(label: const Text('0'), selected: dep == 0, showCheckmark: false, onSelected: (_) => setState(() => _deposit.text = '')),
              if (nz(_rate.text) > 0 && nights > 1)
                ChoiceChip(
                  label: Text('${t('gh.oneNight')} · ${ghMoney(_rate.text, cur)}'),
                  selected: dep == nz(_rate.text),
                  showCheckmark: false,
                  onSelected: (_) => setState(() => _deposit.text = _num(_rate.text)),
                ),
              if (total > 0)
                ChoiceChip(label: Text('${t('gh.payAll')} · ${ghMoney(total, cur)}'), selected: dep == total, showCheckmark: false, onSelected: (_) => setState(() => _deposit.text = _num(total))),
            ],
          ),
          if (dep > 0) ...[
            const SizedBox(height: 8),
            ghChips(context, [for (final k in pos.methods) (k, t('gh.methods.$k'))], js(f['method']), (k) => setState(() => f['method'] = k)),
          ],
          const SizedBox(height: 10),
          SumRow(t('gh.balance'), ghMoney((total - dep) < 0 ? 0 : total - dep, cur), color: c.danger),
          if (_error.isNotEmpty) ...[const SizedBox(height: 8), Alert(_error)],
          const SizedBox(height: 12),
          Btn(
            _saving ? t('gh.saving') : (walk ? t('gh.checkInNow') : t('gh.book')),
            icon: walk ? LucideIcons.logIn : LucideIcons.calendarRange,
            busy: _saving,
            expand: true,
            onTap: can ? () => _submit(t) : null,
          ),
        ],
      ),
    );

    return big
        ? Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(flex: 3, child: main),
              const SizedBox(width: 16),
              Expanded(flex: 2, child: side),
            ],
          )
        : Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [main, const SizedBox(height: 16), side]);
  }
}
