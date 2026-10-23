import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../../core/format.dart' show money;
import '../../core/printing/printing.dart' show renderWidget;
import '../../core/theme.dart';
import '../../widgets/ui.dart';
import 'att_api.dart';
import 'att_month.dart';
import 'att_staff.dart';

// ---------------------------------------------------------------- LEAVE (att_leave)
class AttLeave extends StatefulWidget {
  final AttCtx ctx;
  const AttLeave({super.key, required this.ctx});
  @override
  State<AttLeave> createState() => _AttLeaveState();
}

class _AttLeaveState extends State<AttLeave> {
  Json? _data;
  String _error = '', _note = '';
  AttCtx get ctx => widget.ctx;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final d = obj(await ctx.api.get('/leave'));
      if (mounted) setState(() => (_data = d, _error = ''));
    } catch (e) {
      if (mounted) setState(() => _error = ctx.fail(e));
    }
  }

  Future<void> _ask() async {
    final t = ctx.t;
    var type = 'annual', from = khDay(), to = khDay();
    final reason = TextEditingController();
    final done = await formSheet(
      context,
      title: t('att.askLeave'),
      send: t('att.send'),
      cancel: t('att.cancel'),
      fields: (set) => [
        Seg(
          accent: ctx.accent,
          options: [
            for (final k in ['annual', 'sick', 'personal', 'unpaid']) (k, t('att.types.$k')),
          ],
          value: type,
          onChange: (v) => set(() => type = v),
        ),
        const SizedBox(height: 14),
        Row(
          children: [
            Expanded(
              child: PickBox(
                label: t('att.from'),
                value: dayLabel(from, ctx.lang, withMonth: true),
                icon: LucideIcons.calendarDays,
                onTap: () async {
                  final v = await pickDate(context, from);
                  if (v != null) set(() => (from = v, to = to.compareTo(v) < 0 ? v : to));
                },
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: PickBox(
                label: t('att.to'),
                value: dayLabel(to, ctx.lang, withMonth: true),
                icon: LucideIcons.calendarDays,
                onTap: () async {
                  final v = await pickDate(context, to, first: from);
                  if (v != null) set(() => to = v);
                },
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),
        Field(label: t('att.reason'), controller: reason, hint: t('att.reasonPh'), maxLength: 300),
      ],
      onSend: () async {
        try {
          await ctx.api.post('/leave', {'type': type, 'from': from, 'to': to, 'reason': reason.text.trim()});
          return null;
        } catch (e) {
          return ctx.fail(e);
        }
      },
    );
    if (done && mounted) {
      setState(() => _note = t('att.leaveSent'));
      _load();
    }
  }

  Future<void> _cancel(Json l) async {
    try {
      await ctx.api.del('/leave/${l['_id']}');
      _load();
    } catch (e) {
      if (mounted) setState(() => _error = ctx.fail(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = ctx.t;
    final c = context.c;
    final d = _data;
    final bal = obj(d?['balance']);
    final rows = objs(d?['rows']);
    String day(String x) => dayLabel(x, ctx.lang, withMonth: true);
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 28),
        children: [
          Row(
            children: [
              Expanded(
                child: Text(t('att.leaveTitle'), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 18)),
              ),
              Btn(t('att.askLeave'), icon: LucideIcons.plus, small: true, onTap: _ask),
            ],
          ),
          const SizedBox(height: 14),
          if (d != null)
            Panel(
              color: ctx.accent.withValues(alpha: .1),
              padding: const EdgeInsets.all(18),
              child: Column(
                children: [
                  Text(t('att.leaveLeft'), style: TextStyle(color: c.muted)),
                  Text(
                    '${bal['left']}',
                    style: TextStyle(fontWeight: FontWeight.w800, fontSize: 40, color: ctx.accent),
                  ),
                  Text(t('att.leaveOf', {'left': bal['left'], 'allowed': bal['allowed'], 'year': bal['year']}), style: TextStyle(color: c.muted, fontSize: 13)),
                ],
              ),
            ),
          const SizedBox(height: 14),
          if (_note.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Alert(_note, tone: Tone.good),
            ),
          if (_error.isNotEmpty) Padding(padding: const EdgeInsets.only(bottom: 12), child: Alert(_error)),
          if (d == null && _error.isEmpty) const SkelList(rows: 3),
          if (d != null && rows.isEmpty) Muted(t('att.noLeaveYet'), align: TextAlign.center),
          if (rows.isNotEmpty)
            Panel(
              padding: const EdgeInsets.fromLTRB(12, 4, 4, 4),
              child: Column(
                children: [
                  for (final l in rows)
                    ReqRow(
                      title: '${day(str(l['from']))}${str(l['to']) != str(l['from']) ? ' → ${day(str(l['to']))}' : ''}',
                      sub: '${t('att.types.${str(l['type'])}')} · ${t('att.days', {'n': l['days']})}${str(l['reason']).isNotEmpty ? ' · “${str(l['reason'])}”' : ''}',
                      note: str(l['note']),
                      chip: Chip2(t.or('att.lstatus.${str(l['status'])}', str(l['status'])), tone: reqTone(str(l['status']))),
                      onCancel: str(l['status']) == 'pending' ? () => _cancel(l) : null,
                      cancelTip: t('att.cancelReq'),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------- NEWS (att_news)
class AttNews extends StatefulWidget {
  final AttCtx ctx;
  const AttNews({super.key, required this.ctx});
  @override
  State<AttNews> createState() => _AttNewsState();
}

class _AttNewsState extends State<AttNews> {
  Json? _data;
  String _error = '';
  String? _open;
  AttCtx get ctx => widget.ctx;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final d = obj(await ctx.api.get('/news'));
      if (mounted) setState(() => (_data = d, _error = ''));
    } catch (e) {
      if (mounted) setState(() => _error = ctx.fail(e));
    }
  }

  Future<void> _tap(Json x) async {
    setState(() => _open = _open == str(x['_id']) ? null : str(x['_id']));
    if (x['read'] == true) return;
    try {
      final d = obj(await ctx.api.post('/news/${x['_id']}/read'));
      if (mounted) setState(() => _data = d);
      ctx.refresh(); // the red number on the tab
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final t = ctx.t;
    final c = context.c;
    final rows = objs(_data?['rows']);
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 28),
        children: [
          if (_error.isNotEmpty) Padding(padding: const EdgeInsets.only(bottom: 12), child: Alert(_error)),
          if (_data == null && _error.isEmpty) const SkelList(rows: 3),
          if (_data != null && rows.isEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 30),
              child: Muted(t('atte.noNews'), align: TextAlign.center),
            ),
          for (final x in rows)
            Panel(
              margin: const EdgeInsets.only(bottom: 10),
              padding: const EdgeInsets.all(16),
              color: x['read'] == true ? null : ctx.accent.withValues(alpha: .08),
              onTap: () => _tap(x),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      if (x['pinned'] == true) ...[Icon(LucideIcons.pin, size: 14, color: ctx.accent), const SizedBox(width: 6)],
                      Expanded(
                        child: Text(str(x['title']), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                      ),
                      if (x['read'] != true) Chip2(t('atte.new'), tone: Tone.brand),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(fmtWhen(x['created_date'], ctx.lang), style: TextStyle(color: c.muted, fontSize: 12.5)),
                  if (str(x['body']).isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Text(str(x['body']), maxLines: _open == str(x['_id']) ? null : 2, overflow: _open == str(x['_id']) ? null : TextOverflow.ellipsis, style: const TextStyle(height: 1.5)),
                  ],
                ],
              ),
            ),
        ],
      ),
    );
  }
}

// "19 Oct, 14:24"
String fmtWhen(Object? v, String lang) {
  final d = DateTime.tryParse(str(v))?.toUtc().add(const Duration(hours: 7));
  if (d == null) return '';
  const en = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
  const km = ['មករា', 'កុម្ភៈ', 'មីនា', 'មេសា', 'ឧសភា', 'មិថុនា', 'កក្កដា', 'សីហា', 'កញ្ញា', 'តុលា', 'វិច្ឆិកា', 'ធ្នូ'];
  return '${d.day} ${(lang == 'km' ? km : en)[d.month - 1]}, ${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
}

// ---------------------------------------------------------------- MY PAY (att_payroll)
class AttPay extends StatefulWidget {
  final AttCtx ctx;
  const AttPay({super.key, required this.ctx});
  @override
  State<AttPay> createState() => _AttPayState();
}

class _AttPayState extends State<AttPay> {
  String _month = khMonth();
  Json? _data;
  String _error = '';
  Timer? _timer;
  bool _printing = false;
  AttCtx get ctx => widget.ctx;

  @override
  void initState() {
    super.initState();
    _load();
    // live: the numbers move as you clock in and out
    _timer = Timer.periodic(const Duration(seconds: 60), (_) => _load(quiet: true));
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _load({bool quiet = false}) async {
    if (!quiet) setState(() => (_data = null, _error = ''));
    final m = _month;
    try {
      final d = obj(await ctx.api.get('/pay?month=$m'));
      if (mounted && m == _month) setState(() => (_data = d, _error = ''));
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e is ApiError && e.code == 'pay_hidden' ? ctx.t('att.pay.hidden') : ctx.fail(e));
    }
  }

  // the pay lines like the web's "My pay": (label, sub, amount, sign)
  List<(String, String, num, int)> _lines(Json d) {
    final t = ctx.t;
    String m(Object? v) => money(v, str(d['currency']));
    final kh = obj(d['kh']);
    final type = str(d['pay_type']);
    return [
      if (type == 'hourly')
        (t('att.pay.hours', {'t': dur(d['worked_min'])}), t('att.pay.perHour', {'r': m(d['salary'])}), n(d['base']), 0)
      else if (type == 'daily')
        (t('att.pay.daysWorked', {'n': n(d['present']) - n(d['holiday_worked'])}), t('att.pay.perDay', {'r': m(d['salary'])}), n(d['base']), 0)
      else
        (t('att.pay.base'), n(d['base']) != n(d['salary']) ? t('att.pay.ofSalary', {'s': m(d['salary'])}) : '', n(d['base']), 0),
      if (n(d['paid_leave_pay']) > 0) (t('att.pay.paidLeavePay', {'n': d['paid_leave_days']}), '', n(d['paid_leave_pay']), 1),
      if (n(d['absent_ded']) > 0) (t('att.pay.absent', {'n': d['absent_days']}), '', n(d['absent_ded']), -1),
      if (n(d['late_ded']) > 0) (t('att.pay.late', {'t': dur(d['late_min'])}), '', n(d['late_ded']), -1),
      if (n(d['unpaid_ded']) > 0) (t('att.pay.unpaid', {'n': d['unpaid_days']}), '', n(d['unpaid_ded']), -1),
      if (n(d['ot_pay']) > 0) (t('att.pay.ot', {'t': dur(d['ot_min'])}), t('att.pay.otRate', {'r': d['ot_rate']}), n(d['ot_pay']), 1),
      if (n(d['extra_pay']) > 0) (t('att.pay.extra', {'n': d['extra_days']}), '', n(d['extra_pay']), 1),
      for (final a in objs(d['adjustments']))
        (
          str(a['label']).isNotEmpty ? str(a['label']) : (n(a['amount']) < 0 ? t('att.pay.deduct') : t('att.pay.bonus')),
          n(a['amount']) < 0 ? t('att.pay.deduct') : t('att.pay.bonus'),
          n(a['amount']).abs(),
          n(a['amount']) < 0 ? -1 : 1,
        ),
      if (n(d['reward']) > 0) (ctx.lang == 'km' ? '🏆 ប្រាក់រង្វាន់ខែល្អឥតខ្ចោះ' : '🏆 Perfect month bonus', '', n(d['reward']), 1),
      if (n(kh['seniority']) > 0) (t('att.pay.seniority'), t('att.pay.seniorityNote'), n(kh['seniority']), 1),
      if (n(kh['pension_ee']) > 0) (t('att.pay.nssf'), t('att.pay.nssfNote'), n(kh['pension_ee']), -1),
      if (n(kh['tax']) > 0) (t('att.pay.tax'), n(kh['dependents']) > 0 ? t('att.pay.taxDeps', {'n': kh['dependents']}) : t('att.pay.taxNote'), n(kh['tax']), -1),
    ];
  }

  // the payslip as a PDF (print / save / share), drawn by Flutter so Khmer shows right
  Future<void> _slip(Json d, List<(String, String, num, int)> lines) async {
    setState(() => _printing = true);
    try {
      final t = ctx.t;
      String m(Object? v) => money(v, str(d['currency']));
      final staff = obj(ctx.me['staff']);
      final title = monthTitle(_month, ctx.lang);
      final page = Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(str(obj(ctx.me['business'])['name']), style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800)),
            Text('${t('att.pay.slip')} · $title', style: const TextStyle(color: Color(0xFF666666))),
            const SizedBox(height: 12),
            Text('${str(staff['name'])}${str(staff['position']).isNotEmpty ? ' · ${str(staff['position'])}' : ''}', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
            const SizedBox(height: 14),
            for (final l in lines)
              Container(
                padding: const EdgeInsets.symmetric(vertical: 8),
                decoration: const BoxDecoration(
                  border: Border(bottom: BorderSide(color: Color(0xFFE5E5E5))),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(l.$1),
                          if (l.$2.isNotEmpty) Text(l.$2, style: const TextStyle(color: Color(0xFF666666), fontSize: 11)),
                        ],
                      ),
                    ),
                    Text('${l.$4 < 0 ? '−' : (l.$4 > 0 ? '+' : '')}${m(l.$3)}', style: TextStyle(color: l.$4 < 0 ? const Color(0xFFB91C1C) : Colors.black)),
                  ],
                ),
              ),
            Container(
              padding: const EdgeInsets.only(top: 10),
              decoration: const BoxDecoration(border: Border(top: BorderSide(width: 2))),
              child: Row(
                children: [
                  Expanded(
                    child: Text(t('att.pay.net'), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 17)),
                  ),
                  Text(m(d['net']), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 17)),
                ],
              ),
            ),
          ],
        ),
      );
      final ui.Image img = await renderWidget(page, width: 560, dots: 1680);
      final png = (await img.toByteData(format: ui.ImageByteFormat.png))!.buffer.asUint8List();
      final doc = pw.Document(title: '${t('att.pay.slip')} $title');
      doc.addPage(
        pw.Page(
          pageFormat: PdfPageFormat.a4,
          margin: const pw.EdgeInsets.all(24),
          build: (_) => pw.Align(
            alignment: pw.Alignment.topCenter,
            child: pw.Image(pw.MemoryImage(png), fit: pw.BoxFit.fitWidth),
          ),
        ),
      );
      await Printing.layoutPdf(name: 'payslip-$_month', onLayout: (_) async => doc.save());
    } catch (e) {
      if (mounted) toast(context, '$e');
    } finally {
      if (mounted) setState(() => _printing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = ctx.t;
    final c = context.c;
    final d = _data;
    final isNow = _month == khMonth();
    final lines = d == null ? <(String, String, num, int)>[] : _lines(d);
    final minus = lines.where((l) => l.$4 < 0).fold<num>(0, (a, l) => a + l.$3);
    final plus = lines.where((l) => l.$4 > 0).fold<num>(0, (a, l) => a + l.$3);
    String m(Object? v) => money(v, str(d?['currency']));
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 28),
        children: [
          MonthBar(
            month: _month,
            lang: ctx.lang,
            onChange: (v) {
              setState(() => _month = v);
              _load();
            },
          ),
          if (_error.isNotEmpty) Alert(_error),
          if (d == null && _error.isEmpty) const SkelList(rows: 4),
          if (d != null) ...[
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [ctx.accent, Color.lerp(ctx.accent, Colors.black, .3)!]),
                borderRadius: BorderRadius.circular(24),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(isNow ? t('att.pay.soFar') : t('att.pay.net'), style: const TextStyle(color: Colors.white70)),
                  Text(
                    m(d['net']),
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 36),
                  ),
                  if (isNow) Text('● ${t('att.pay.live')}', style: const TextStyle(color: Colors.white70, fontSize: 12.5)),
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      for (final (label, v, col) in [
                        (t('att.pay.salary'), m(d['salary']), Colors.white),
                        (t('att.pay.minus'), '−${m(minus)}', const Color(0xFFFFD1D1)),
                        (t('att.pay.plus'), '+${m(plus)}', const Color(0xFFC8F7DC)),
                      ])
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(label, style: const TextStyle(color: Colors.white70, fontSize: 12)),
                              Text(
                                v,
                                style: TextStyle(color: col, fontWeight: FontWeight.w800),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            ),
            if (n(d['salary']) == 0)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Muted(t('att.pay.noSalary'), align: TextAlign.center),
              ),
            const SizedBox(height: 14),
            Panel(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              child: Column(
                children: [
                  for (final l in lines)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 9),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(l.$1, style: const TextStyle(fontWeight: FontWeight.w600)),
                                if (l.$2.isNotEmpty) Text(l.$2, style: TextStyle(color: c.muted, fontSize: 12.5)),
                              ],
                            ),
                          ),
                          Text(
                            '${l.$4 < 0 ? '−' : (l.$4 > 0 ? '+' : '')}${m(l.$3)}',
                            style: TextStyle(fontWeight: FontWeight.w700, color: l.$4 < 0 ? c.danger : (l.$4 > 0 ? c.good : c.ink)),
                          ),
                        ],
                      ),
                    ),
                  const Divider(),
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(t('att.pay.net'), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                        ),
                        Text(m(d['net']), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                Chip2(t('att.pay.days', {'n': d['present'], 'm': d['work_days']})),
                if (n(d['paid_leave_days']) > 0) Chip2(t('att.pay.paidLeave', {'n': d['paid_leave_days']})),
                Chip2(t('att.pay.rate', {'d': m(d['daily_rate']), 'h': m(d['hourly_rate'])})),
              ],
            ),
            const SizedBox(height: 10),
            Muted(isNow ? t('att.pay.noteNow') : t('att.pay.noteDone')),
            const SizedBox(height: 14),
            Btn(t('att.pay.slip'), icon: LucideIcons.fileText, kind: BtnKind.ghost, busy: _printing, onTap: _printing ? null : () => _slip(d, lines)),
          ],
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------- TEAM (att_manager: managers only)
class AttTeam extends StatefulWidget {
  final AttCtx ctx;
  const AttTeam({super.key, required this.ctx});
  @override
  State<AttTeam> createState() => _AttTeamState();
}

class _AttTeamState extends State<AttTeam> {
  Json? _data;
  String _error = '', _msg = '', _busy = '';
  final Map<String, TextEditingController> _notes = {};
  Timer? _timer;
  AttCtx get ctx => widget.ctx;

  @override
  void initState() {
    super.initState();
    _load();
    _timer = Timer.periodic(const Duration(seconds: 60), (_) => _load());
  }

  @override
  void dispose() {
    _timer?.cancel();
    for (final c in _notes.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final d = obj(await ctx.api.get('/team'));
      if (mounted) setState(() => (_data = d, _error = ''));
    } catch (e) {
      if (mounted) setState(() => _error = ctx.fail(e));
    }
  }

  Future<void> _decide(String kind, Json r, bool approve) async {
    final id = str(r['_id']);
    setState(() => (_busy = '$kind:$id', _msg = ''));
    try {
      await ctx.api.post('/team/$kind/$id/decide', {'approve': approve, 'note': _notes[id]?.text.trim() ?? ''});
      if (mounted) setState(() => _msg = ctx.t('attt.done'));
    } catch (e) {
      if (mounted) setState(() => _error = ctx.fail(e));
    }
    await _load();
    if (mounted) setState(() => _busy = '');
  }

  static const _icons = {'leave': LucideIcons.palmtree, 'fix': LucideIcons.fileText, 'overtime': LucideIcons.clock, 'punch': LucideIcons.mapPin};

  @override
  Widget build(BuildContext context) {
    final t = ctx.t;
    final c = context.c;
    final d = _data;
    final inbox = obj(d?['inbox']);
    final items = [
      for (final k in ['leave', 'fix', 'overtime', 'punch'])
        for (final r in objs(inbox[k])) (k, r),
    ];
    final team = objs(d?['team']);
    final came = team.where((m) => m['first_in'] != null).length;
    final late = team.where((m) => n(m['late_min']) > 0).length;
    final notIn = team.where((m) => str(m['status']) == 'not_yet' || str(m['status']) == 'absent').length;
    String day(Object? x) => dayLabel(str(x), ctx.lang, withMonth: true);
    String line(String k, Json r) => switch (k) {
      'leave' => '${t.or('att.types.${str(r['type'])}', str(r['type']))} · ${day(r['from'])}${str(r['to']) != str(r['from']) ? ' → ${day(r['to'])}' : ''} · ${t('attt.days', {'n': r['days']})}',
      'fix' => '${day(r['day'])} · ${t(str(r['kind']) == 'in' ? 'attt.fixIn' : 'attt.fixOut', {'time': r['time']})}',
      'overtime' => '${day(r['day'])} · ${t('attt.until', {'time': r['until']})}',
      _ =>
        '${day(r['day'])} · ${str(r['kind']) == 'in' ? t('att.in') : t('att.out')} ${hhmm(r['at'])} · ${[for (final f in (r['flags'] as List? ?? const [])) t.or('att.flags.$f', '$f')].join(', ')}${n(r['distance_m']) > 0 ? ' (${r['distance_m']} m)' : ''}',
    };
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 28),
        children: [
          if (_error.isNotEmpty) Padding(padding: const EdgeInsets.only(bottom: 10), child: Alert(_error)),
          if (_msg.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Alert(_msg, tone: Tone.good),
            ),
          Row(
            children: [
              Expanded(
                child: Text(t('attt.inbox'), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 17)),
              ),
              IconButton(onPressed: _load, icon: const Icon(LucideIcons.refreshCw, size: 18), tooltip: t('att.refresh')),
            ],
          ),
          if (d == null && _error.isEmpty) const SkelList(rows: 2),
          if (d != null && items.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 14),
              child: Muted(t('attt.empty'), align: TextAlign.center),
            ),
          for (final (k, r) in items)
            Panel(
              margin: const EdgeInsets.only(bottom: 10),
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 34,
                        height: 34,
                        decoration: BoxDecoration(color: ctx.accent.withValues(alpha: .12), borderRadius: BorderRadius.circular(11)),
                        child: Icon(_icons[k], size: 17, color: ctx.accent),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(str(r['staff_name']), style: const TextStyle(fontWeight: FontWeight.w800)),
                            Text(t('attt.$k'), style: TextStyle(color: c.muted, fontSize: 12.5)),
                          ],
                        ),
                      ),
                      if (str(r['photo_url']).isNotEmpty)
                        ClipRRect(
                          borderRadius: BorderRadius.circular(10),
                          child: Image(image: netImage(str(r['photo_url'])), width: 44, height: 44, fit: BoxFit.cover),
                        ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(line(k, r), style: const TextStyle(fontWeight: FontWeight.w600)),
                  if (str(r['reason']).isNotEmpty)
                    Text(
                      '“${str(r['reason'])}”',
                      style: TextStyle(color: c.muted, fontStyle: FontStyle.italic),
                    ),
                  const SizedBox(height: 10),
                  Field(controller: _notes.putIfAbsent(str(r['_id']), TextEditingController.new), hint: t('attt.note'), maxLength: 300),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: Btn(t('attt.reject'), icon: LucideIcons.x, kind: BtnKind.ghost, small: true, expand: true, onTap: _busy.isNotEmpty ? null : () => _decide(k, r, false)),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Btn(
                          k == 'punch' ? t('attt.accept') : t('attt.approve'),
                          icon: LucideIcons.check,
                          small: true,
                          expand: true,
                          busy: _busy == '$k:${r['_id']}',
                          onTap: _busy.isNotEmpty ? null : () => _decide(k, r, true),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          const SizedBox(height: 10),
          Text(t('attt.today'), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 17)),
          if (d != null) Text(t('attt.counts', {'in': came, 'late': late, 'out': notIn}), style: TextStyle(color: c.muted, fontSize: 13)),
          const SizedBox(height: 8),
          if (team.isNotEmpty)
            Panel(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              child: Column(
                children: [
                  for (final m in team)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: Row(
                        children: [
                          CircleAvatar(
                            radius: 17,
                            backgroundColor: ctx.accent.withValues(alpha: .12),
                            child: Text(
                              str(m['name']).trim().isEmpty ? '?' : str(m['name']).trim().characters.first.toUpperCase(),
                              style: TextStyle(color: ctx.accent, fontWeight: FontWeight.w800),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  '${str(m['name'])}${m['me'] == true ? ' (${t('attt.me')})' : ''}${str(m['position']).isNotEmpty ? ' · ${str(m['position'])}' : ''}',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(fontWeight: FontWeight.w700),
                                ),
                                Text(
                                  [
                                    if (m['first_in'] != null) '↘ ${hhmm(m['first_in'])}',
                                    if (m['last_out'] != null) '↗ ${hhmm(m['last_out'])}',
                                    if (n(m['late_min']) > 0) t('att.late', {'m': dur(m['late_min'])}),
                                  ].join('  '),
                                  style: TextStyle(color: n(m['late_min']) > 0 ? c.warn : c.muted, fontSize: 12.5),
                                ),
                              ],
                            ),
                          ),
                          Chip2(t.or('att.status.${str(m['status'])}', str(m['status'])), tone: dayTone(str(m['status']))),
                        ],
                      ),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
