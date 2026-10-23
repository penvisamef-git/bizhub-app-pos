import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/theme.dart';
import '../../widgets/ui.dart';
import 'att_api.dart';
import 'att_staff.dart';

// ---------------------------------------------------------------- small shared pieces
Tone dayTone(String status) => switch (status) {
  'present' || 'working' || 'extra' => Tone.good,
  'absent' || 'missing_out' => Tone.danger,
  'not_yet' => Tone.warn,
  'leave' || 'holiday' => Tone.brand,
  _ => Tone.muted,
};

Tone reqTone(String status) => switch (status) {
  'approved' => Tone.good,
  'rejected' => Tone.danger,
  'pending' => Tone.warn,
  _ => Tone.muted,
};

// ‹ October 2026 ›
class MonthBar extends StatelessWidget {
  final String month;
  final String lang;
  final ValueChanged<String> onChange;
  const MonthBar({super.key, required this.month, required this.lang, required this.onChange});
  @override
  Widget build(BuildContext context) => Row(
    children: [
      IconButton(onPressed: () => onChange(shiftMonth(month, -1)), icon: const Icon(LucideIcons.chevronLeft), tooltip: '-1'),
      Expanded(
        child: Text(
          monthTitle(month, lang),
          textAlign: TextAlign.center,
          style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 17),
        ),
      ),
      IconButton(onPressed: month.compareTo(khMonth()) >= 0 ? null : () => onChange(shiftMonth(month, 1)), icon: const Icon(LucideIcons.chevronRight), tooltip: '+1'),
    ],
  );
}

class StatBox extends StatelessWidget {
  final String value, label;
  final Color? color;
  const StatBox(this.value, this.label, {super.key, this.color});
  @override
  Widget build(BuildContext context) => Expanded(
    child: Container(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 6),
      decoration: BoxDecoration(color: context.c.card, borderRadius: BorderRadius.circular(16), boxShadow: context.c.cardShadow),
      child: Column(
        children: [
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              value,
              maxLines: 1,
              style: TextStyle(fontWeight: FontWeight.w800, fontSize: 19, color: color),
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(color: context.c.muted, fontSize: 12.5),
          ),
        ],
      ),
    ),
  );
}

// a list row: day · details · status chip · (cancel)
class ReqRow extends StatelessWidget {
  final String title, sub;
  final String? note;
  final Widget chip;
  final VoidCallback? onCancel;
  final String? cancelTip;
  final VoidCallback? onTap;
  const ReqRow({super.key, required this.title, required this.sub, this.note, required this.chip, this.onCancel, this.cancelTip, this.onTap});
  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
                  if (sub.isNotEmpty) Text(sub, style: TextStyle(color: c.muted, fontSize: 13)),
                  if (note != null && note!.isNotEmpty)
                    Text(
                      '↳ $note',
                      style: TextStyle(color: c.muted, fontSize: 13, fontStyle: FontStyle.italic),
                    ),
                ],
              ),
            ),
            chip,
            if (onCancel != null) IconButton(onPressed: onCancel, icon: const Icon(LucideIcons.x, size: 16), tooltip: cancelTip, visualDensity: VisualDensity.compact),
          ],
        ),
      ),
    );
  }
}

// segmented choice (leave type, in / out)
class Seg extends StatelessWidget {
  final List<(String, String)> options;
  final String value;
  final ValueChanged<String> onChange;
  final Color accent;
  const Seg({super.key, required this.options, required this.value, required this.onChange, required this.accent});
  @override
  Widget build(BuildContext context) => Wrap(
    spacing: 8,
    runSpacing: 8,
    children: [for (final o in options) ChoiceChip(label: Text(o.$2), selected: value == o.$1, selectedColor: accent.withValues(alpha: .16), onSelected: (_) => onChange(o.$1))],
  );
}

String _p2(int x) => x.toString().padLeft(2, '0');
Future<String?> pickTime(BuildContext context, String hm) async {
  final parts = hm.split(':');
  final r = await showTimePicker(
    context: context,
    initialTime: TimeOfDay(hour: int.tryParse(parts.first) ?? 8, minute: int.tryParse(parts.length > 1 ? parts[1] : '0') ?? 0),
    builder: (ctx, child) => MediaQuery(data: MediaQuery.of(ctx).copyWith(alwaysUse24HourFormat: true), child: child!),
  );
  return r == null ? null : '${_p2(r.hour)}:${_p2(r.minute)}';
}

Future<String?> pickDate(BuildContext context, String day, {String? first}) async {
  final init = DateTime.tryParse(day) ?? DateTime.now();
  final f = DateTime.tryParse(first ?? '') ?? DateTime(init.year - 1);
  final r = await showDatePicker(context: context, initialDate: init.isBefore(f) ? f : init, firstDate: f, lastDate: DateTime(init.year + 2));
  return r == null ? null : '${r.year}-${_p2(r.month)}-${_p2(r.day)}';
}

// a box that opens a picker
class PickBox extends StatelessWidget {
  final String label, value;
  final IconData icon;
  final VoidCallback onTap;
  const PickBox({super.key, required this.label, required this.value, required this.icon, required this.onTap});
  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(color: c.muted, fontSize: 13, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 6),
        Material(
          color: c.bg2,
          borderRadius: BorderRadius.circular(14),
          child: InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
              child: Row(
                children: [
                  Icon(icon, size: 17, color: c.muted),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(value, style: const TextStyle(fontWeight: FontWeight.w700)),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

// a form in a bottom sheet; onSend returns an error text (null = done)
Future<bool> formSheet(
  BuildContext context, {
  required String title,
  String? sub,
  required List<Widget> Function(void Function(VoidCallback) set) fields,
  required String send,
  required String cancel,
  required Future<String?> Function() onSend,
}) async {
  final ok = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (sheet) {
      var busy = false;
      var error = '';
      return StatefulBuilder(
        builder: (ctx, set) => Padding(
          padding: EdgeInsets.fromLTRB(20, 0, 20, 20 + MediaQuery.viewInsetsOf(ctx).bottom),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(title, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 18)),
                if (sub != null) ...[const SizedBox(height: 4), Muted(sub)],
                const SizedBox(height: 16),
                ...fields(set),
                if (error.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 12), child: Alert(error)),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: Btn(cancel, kind: BtnKind.ghost, expand: true, onTap: busy ? null : () => Navigator.pop(sheet, false)),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Btn(
                        send,
                        expand: true,
                        busy: busy,
                        onTap: busy
                            ? null
                            : () async {
                                set(() => (busy = true, error = ''));
                                final e = await onSend();
                                if (!sheet.mounted) return;
                                if (e == null) return Navigator.pop(sheet, true);
                                set(() => (busy = false, error = e));
                              },
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      );
    },
  );
  return ok == true;
}

// ---------------------------------------------------------------- MY MONTH
class AttMonth extends StatefulWidget {
  final AttCtx ctx;
  const AttMonth({super.key, required this.ctx});
  @override
  State<AttMonth> createState() => _AttMonthState();
}

class _AttMonthState extends State<AttMonth> {
  String _month = khMonth();
  Json? _data;
  List<Json> _fixes = [], _ots = [];
  String _error = '', _note = '';

  AttCtx get ctx => widget.ctx;

  @override
  void initState() {
    super.initState();
    _load();
    _loadReqs();
  }

  Future<void> _load() async {
    setState(() {
      _data = null;
      _error = '';
    });
    final m = _month;
    try {
      final d = obj(await ctx.api.get('/history?month=$m'));
      if (mounted && m == _month) setState(() => _data = d);
    } catch (e) {
      if (mounted) setState(() => _error = ctx.fail(e));
    }
  }

  Future<void> _loadReqs() async {
    try {
      final f = objs(await ctx.api.get('/fixes'));
      final o = ctx.on('overtime') ? objs(await ctx.api.get('/overtime')) : <Json>[];
      if (mounted) {
        setState(() {
          _fixes = f;
          _ots = o;
        });
      }
    } catch (_) {}
  }

  Future<void> _fix(Json d) async {
    final t = ctx.t;
    final shift = ctx.me['shift'] == null ? <String, dynamic>{} : obj(ctx.me['shift']);
    var kind = d['first_in'] != null && (str(d['status']) == 'missing_out' || d['last_out'] == null) ? 'out' : 'in';
    String timeOf(String k) => str(shift[k == 'in' ? 'start' : 'end']).isNotEmpty ? str(shift[k == 'in' ? 'start' : 'end']) : (k == 'in' ? '08:00' : '17:00');
    var time = timeOf(kind);
    final reason = TextEditingController();
    final done = await formSheet(
      context,
      title: t('att.fix.title', {'day': dayLabel(str(d['day']), ctx.lang)}),
      sub: t('att.fix.sub'),
      send: t('att.fix.send'),
      cancel: t('att.cancel'),
      fields: (set) => [
        Seg(accent: ctx.accent, options: [('in', t('att.fix.kindIn')), ('out', t('att.fix.kindOut'))], value: kind, onChange: (v) => set(() => (kind = v, time = timeOf(v)))),
        const SizedBox(height: 14),
        PickBox(
          label: t('att.fix.time'),
          value: time,
          icon: LucideIcons.clock,
          onTap: () async {
            final v = await pickTime(context, time);
            if (v != null) set(() => time = v);
          },
        ),
        const SizedBox(height: 14),
        Field(label: t('att.fix.reason'), controller: reason, hint: t('att.fix.reasonPh'), maxLength: 300),
      ],
      onSend: () async {
        if (reason.text.trim().isEmpty) return t('att.fix.reason');
        try {
          await ctx.api.post('/fixes', {'day': d['day'], 'kind': kind, 'time': time, 'reason': reason.text.trim()});
          return null;
        } catch (e) {
          return ctx.fail(e);
        }
      },
    );
    if (done && mounted) {
      setState(() => _note = t('att.fix.sent'));
      _loadReqs();
    }
  }

  Future<void> _askOt() async {
    final t = ctx.t;
    final shift = ctx.me['shift'] == null ? <String, dynamic>{} : obj(ctx.me['shift']);
    final end = str(shift['end']);
    var day = khDay();
    var until = end.length == 5 ? '${((int.parse(end.substring(0, 2)) + 2) % 24).toString().padLeft(2, '0')}:${end.substring(3)}' : '19:00';
    final reason = TextEditingController();
    final done = await formSheet(
      context,
      title: t('att.ot.title'),
      sub: t('att.ot.sub'),
      send: t('att.fix.send'),
      cancel: t('att.cancel'),
      fields: (set) => [
        Row(
          children: [
            Expanded(
              child: PickBox(
                label: t('att.ot.day'),
                value: dayLabel(day, ctx.lang, withMonth: true),
                icon: LucideIcons.calendarDays,
                onTap: () async {
                  final v = await pickDate(context, day, first: khDay());
                  if (v != null) set(() => day = v);
                },
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: PickBox(
                label: t('att.ot.until'),
                value: until,
                icon: LucideIcons.clock,
                onTap: () async {
                  final v = await pickTime(context, until);
                  if (v != null) set(() => until = v);
                },
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),
        Field(label: t('att.fix.reason'), controller: reason, hint: t('att.ot.reasonPh'), maxLength: 300),
      ],
      onSend: () async {
        if (reason.text.trim().isEmpty) return t('att.fix.reason');
        try {
          await ctx.api.post('/overtime', {'day': day, 'until': until, 'reason': reason.text.trim()});
          return null;
        } catch (e) {
          return ctx.fail(e);
        }
      },
    );
    if (done && mounted) {
      setState(() => _note = t('att.ot.sent'));
      _loadReqs();
    }
  }

  Future<void> _cancelFix(Json f) async {
    try {
      await ctx.api.del('/fixes/${f['_id']}');
      _loadReqs();
    } catch (e) {
      if (mounted) setState(() => _error = ctx.fail(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = ctx.t;
    final c = context.c;
    final d = _data;
    final today = khDay();
    final totals = obj(d?['totals']);
    final schedule = ctx.me['schedule'] is List ? objs(ctx.me['schedule']) : null;
    final fixes = _fixes.where((f) => str(f['status']) != 'cancelled').take(6).toList();
    final ots = _ots.where((o) => str(o['status']) != 'cancelled').take(5).toList();
    final days = d == null ? <Json>[] : objs(d['days']).where((x) => str(x['day']).compareTo(today) <= 0 && str(x['status']) != 'upcoming' && str(x['status']) != 'before').toList().reversed.toList();
    return RefreshIndicator(
      onRefresh: () async {
        await Future.wait([_load(), _loadReqs()]);
      },
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 28),
        children: [
          if (ctx.on('rewards')) RewardsCard(ctx: ctx),
          MonthBar(
            month: _month,
            lang: ctx.lang,
            onChange: (m) {
              setState(() => _month = m);
              _load();
            },
          ),
          if (_error.isNotEmpty) Padding(padding: const EdgeInsets.only(bottom: 10), child: Alert(_error)),
          if (d == null && _error.isEmpty) const Padding(padding: EdgeInsets.all(12), child: SkelList(rows: 4)),
          if (d != null) ...[
            Row(
              children: [
                StatBox('${n(totals['present']).toInt()}', t('att.sum.present')),
                const SizedBox(width: 8),
                StatBox('${n(totals['late']).toInt()}', t('att.sum.late'), color: c.warn),
                const SizedBox(width: 8),
                StatBox('${n(totals['absent']).toInt()}', t('att.sum.absent'), color: c.danger),
                const SizedBox(width: 8),
                StatBox(dur(totals['worked_min']), t('att.sum.worked')),
              ],
            ),
            const SizedBox(height: 14),
            if (schedule != null && _month == khMonth())
              Panel(
                padding: const EdgeInsets.all(16),
                margin: const EdgeInsets.only(bottom: 14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      t('att.sched.title'),
                      style: TextStyle(color: c.muted, fontWeight: FontWeight.w700, fontSize: 13),
                    ),
                    const SizedBox(height: 6),
                    for (final s in schedule)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 5),
                        child: Row(
                          children: [
                            Container(
                              width: 4,
                              height: 22,
                              decoration: BoxDecoration(color: s['off'] == true ? c.line : hexColor(s['color'], ctx.accent), borderRadius: BorderRadius.circular(4)),
                            ),
                            const SizedBox(width: 10),
                            SizedBox(
                              width: 92,
                              child: Text(str(s['day']) == today ? t('att.sched.today') : dayLabel(str(s['day']), ctx.lang), style: const TextStyle(fontWeight: FontWeight.w700)),
                            ),
                            Expanded(
                              child: Text(
                                s['off'] == true ? t('att.sched.off') : '${str(s['name'])} · ${str(s['start'])}–${str(s['end'])}',
                                style: TextStyle(color: s['off'] == true ? c.muted : c.ink),
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
            if (_note.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Alert(_note, tone: Tone.good),
              ),
            if (fixes.isNotEmpty)
              Panel(
                padding: const EdgeInsets.fromLTRB(14, 12, 6, 6),
                margin: const EdgeInsets.only(bottom: 14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      t('att.fix.mine'),
                      style: TextStyle(color: c.muted, fontWeight: FontWeight.w700, fontSize: 13),
                    ),
                    for (final f in fixes)
                      ReqRow(
                        title: dayLabel(str(f['day']), ctx.lang),
                        sub: '${str(f['kind']) == 'in' ? t('att.fix.kindIn') : t('att.fix.kindOut')} · ${str(f['time'])}',
                        note: str(f['note']),
                        chip: Chip2(t.or('att.fix.status.${str(f['status'])}', str(f['status'])), tone: reqTone(str(f['status']))),
                        onCancel: str(f['status']) == 'pending' ? () => _cancelFix(f) : null,
                        cancelTip: t('att.fix.cancel'),
                      ),
                  ],
                ),
              ),
            if (ctx.on('overtime')) ...[
              Align(
                alignment: Alignment.centerLeft,
                child: Btn(t('att.ot.ask'), icon: LucideIcons.clock, kind: BtnKind.ghost, small: true, onTap: _askOt),
              ),
              const SizedBox(height: 12),
            ],
            if (ots.isNotEmpty)
              Panel(
                padding: const EdgeInsets.fromLTRB(14, 12, 14, 6),
                margin: const EdgeInsets.only(bottom: 14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      t('att.ot.mine'),
                      style: TextStyle(color: c.muted, fontWeight: FontWeight.w700, fontSize: 13),
                    ),
                    for (final o in ots)
                      ReqRow(
                        title: dayLabel(str(o['day']), ctx.lang),
                        sub: t('att.ot.untilT', {'t': str(o['until'])}),
                        note: str(o['note']),
                        chip: Chip2(t.or('att.lstatus.${str(o['status'])}', str(o['status'])), tone: reqTone(str(o['status']))),
                      ),
                  ],
                ),
              ),
            Padding(
              padding: const EdgeInsets.only(left: 4, bottom: 6),
              child: Text(t('att.fix.tap'), style: TextStyle(color: c.muted, fontSize: 13)),
            ),
            Panel(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              child: Column(
                children: [
                  for (final x in days)
                    Opacity(
                      opacity: str(x['status']) == 'off' || str(x['status']) == 'holiday' ? .6 : 1,
                      child: ReqRow(
                        onTap: () => _fix(x),
                        title: dayLabel(str(x['day']), ctx.lang),
                        sub: x['first_in'] != null
                            ? '${hhmm(x['first_in'])} – ${str(x['status']) == 'missing_out' ? '?' : hhmm(x['last_out'])}${n(x['late_min']) > 0 ? ' · ${t('att.late', {'m': dur(x['late_min'])})}' : ''}'
                            : (str(x['status']) == 'holiday' ? str(x['holiday']) : ''),
                        chip: Chip2(t.or('att.status.${str(x['status'])}', str(x['status'])), tone: dayTone(str(x['status']))),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------- on-time rewards (att_rewards)
class RewardsCard extends StatefulWidget {
  final AttCtx ctx;
  const RewardsCard({super.key, required this.ctx});
  @override
  State<RewardsCard> createState() => _RewardsCardState();
}

class _RewardsCardState extends State<RewardsCard> {
  Json? _d;
  @override
  void initState() {
    super.initState();
    widget.ctx.api
        .get('/rewards')
        .then(
          (v) {
            if (mounted) setState(() => _d = obj(v));
          },
          onError: (Object e) {
            widget.ctx.fail(e);
          },
        );
  }

  static const _icons = {
    'streak_5': LucideIcons.flame,
    'streak_10': LucideIcons.flame,
    'streak_20': LucideIcons.flame,
    'perfect_month': LucideIcons.star,
    'last_perfect': LucideIcons.calendarCheck,
    'top': LucideIcons.crown,
  };

  @override
  Widget build(BuildContext context) {
    final d = _d;
    if (d == null) return const SizedBox.shrink();
    final t = widget.ctx.t;
    final c = context.c;
    final accent = widget.ctx.accent;
    final m = obj(d['month']);
    final cur = str(d['currency']);
    final bonus = n(d['bonus']);
    return Panel(
      padding: const EdgeInsets.all(16),
      margin: const EdgeInsets.only(bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(LucideIcons.award, size: 18, color: accent),
              const SizedBox(width: 8),
              Expanded(
                child: Text(t('atte.rewards'), style: const TextStyle(fontWeight: FontWeight.w800)),
              ),
              if (d['rank'] != null) Text(t('atte.rank', {'n': d['rank'], 'm': d['team_size']}), style: TextStyle(color: c.muted, fontSize: 13)),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: Row(
                  children: [
                    const Icon(LucideIcons.flame, size: 28, color: Color(0xFFF97316)),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(t('atte.days', {'n': d['streak']}), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 18)),
                          Text(t('atte.streak'), style: TextStyle(color: c.muted, fontSize: 12.5)),
                          Text(t('atte.best', {'n': d['best']}), style: TextStyle(color: c.muted, fontSize: 12.5)),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(t('atte.month'), style: TextStyle(color: c.muted, fontSize: 12.5)),
                    Text(
                      '${m['rate']}%',
                      style: TextStyle(fontWeight: FontWeight.w800, fontSize: 22, color: accent),
                    ),
                    Text(
                      t('atte.onTime', {'a': m['on_time'], 'b': m['work']}),
                      textAlign: TextAlign.end,
                      style: TextStyle(color: c.muted, fontSize: 12.5),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (m['perfect'] == true)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text('⭐ ${t('atte.perfectSoFar')}', style: const TextStyle(fontWeight: FontWeight.w600)),
            ),
          if (bonus > 0)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                '🏆 ${t('atte.bonus', {'amt': cur == 'KHR' ? '${bonus.round()}៛' : '\$${bonus.toStringAsFixed(bonus % 1 == 0 ? 0 : 2)}'})}',
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              if ((d['badges'] as List? ?? const []).isEmpty) Text(t('atte.noBadges'), style: TextStyle(color: c.muted, fontSize: 13)),
              for (final k in (d['badges'] as List? ?? const [])) Chip2(t.or('atte.badges.$k', '$k'), icon: _icons['$k'] ?? LucideIcons.star, tone: Tone.brand),
            ],
          ),
          if (objs(d['board']).isNotEmpty) ...[
            const SizedBox(height: 12),
            Text(
              t('atte.top'),
              style: TextStyle(color: c.muted, fontWeight: FontWeight.w700, fontSize: 13),
            ),
            for (final r in objs(d['board']))
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  children: [
                    SizedBox(
                      width: 24,
                      child: n(r['rank']) == 1 ? const Icon(LucideIcons.trophy, size: 15, color: Color(0xFFEAB308)) : Text('${r['rank']}', style: TextStyle(color: c.muted)),
                    ),
                    Expanded(
                      child: Text('${str(r['name'])}${r['me'] == true ? ' (${t('atte.you')})' : ''}', style: TextStyle(fontWeight: r['me'] == true ? FontWeight.w800 : FontWeight.w500)),
                    ),
                    Text('${r['rate']}%', style: const TextStyle(fontWeight: FontWeight.w700)),
                  ],
                ),
              ),
          ],
        ],
      ),
    );
  }
}
