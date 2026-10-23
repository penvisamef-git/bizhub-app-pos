import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../core/api.dart';
import '../../core/format.dart' show fmt;
import '../../core/theme.dart';
import '../../widgets/qr_scan.dart';
import '../../widgets/ui.dart';
import 'sc_card.dart';
import 'sc_common.dart';

// The stamp desk's screens — the owner app's counter, customers, history and stats (sc_counter.dart), as the desk sees them.

// a sheet from the bottom (the owner app's mart_kit)
Future<R?> showSheet<R>(BuildContext context, WidgetBuilder builder) => showModalBottomSheet<R>(context: context, isScrollControlled: true, useSafeArea: true, showDragHandle: true, builder: builder);

class MSheet extends StatelessWidget {
  final String title;
  final List<Widget> children;
  final List<Widget> footer;
  const MSheet({super.key, required this.title, required this.children, this.footer = const []});
  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
            child: Text(title, style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
          ),
          Flexible(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: children),
            ),
          ),
          if (footer.isNotEmpty)
            Container(
              padding: const EdgeInsets.fromLTRB(20, 10, 20, 14),
              decoration: BoxDecoration(
                border: Border(top: BorderSide(color: c.line)),
              ),
              child: Row(children: footer),
            ),
        ],
      ),
    );
  }
}

// Find a card (scan / card no. / phone / name), add stamps, give rewards, add a new customer (DeskCore.jsx).
class ScCounter extends StatefulWidget {
  final ScCtx ctx;
  final bool owner, canReset;
  final void Function(Json m)? onOpen;
  final VoidCallback? onChanged;
  final ValueChanged<Json?>? onMember; // the open customer changed (null = none)
  final (int, String)? pick; // a customer chosen in a list: (seq, card no.) → opened here
  const ScCounter({super.key, required this.ctx, this.owner = true, this.canReset = false, this.onOpen, this.onChanged, this.onMember, this.pick});
  @override
  State<ScCounter> createState() => _ScCounterState();
}

class _ScCounterState extends State<ScCounter> {
  ScCtx get ctx => widget.ctx;
  final _q = TextEditingController();
  String _busy = '';
  List<Json>? _found;
  Json? _m;
  int _pop = -1;
  (bool, String)? _msg; // ok, text
  bool _sure = false;
  Timer? _sureTimer;

  @override
  void initState() {
    super.initState();
    if (widget.pick != null) WidgetsBinding.instance.addPostFrameCallback((_) => _search(widget.pick!.$2));
  }

  @override
  void didUpdateWidget(ScCounter old) {
    super.didUpdateWidget(old);
    if (widget.pick != null && widget.pick!.$1 != old.pick?.$1) _search(widget.pick!.$2);
  }

  @override
  void setState(VoidCallback fn) {
    final before = _m?['_id'];
    super.setState(fn);
    if (before != _m?['_id']) widget.onMember?.call(_m);
  }

  @override
  void dispose() {
    _q.dispose();
    _sureTimer?.cancel();
    super.dispose();
  }

  void _reset() => setState(() {
    _m = null;
    _found = null;
    _q.clear();
    _msg = null;
    _pop = -1;
  });

  Future<void> _search(String code) async {
    final v = code.trim();
    if (v.isEmpty) return;
    setState(() {
      _busy = 'find';
      _msg = null;
    });
    try {
      final r = await ctx.api.post('${ctx.base}/lookup', {'code': v});
      final rows = objs(r['data']);
      if (mounted) {
        setState(() {
          _found = rows;
          _m = rows.length == 1 ? rows.first : null;
          _pop = -1;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _msg = (false, e is ApiError ? e.message : '$e'));
    }
    if (mounted) setState(() => _busy = '');
  }

  Future<void> _scan() async {
    final v = await scanQr(context, title: ctx.m('scan'));
    if (v != null && v.isNotEmpty) {
      _q.clear();
      _search(v);
    }
  }

  Future<void> _stamp(int count, {bool force = false}) async {
    final m = _m;
    if (m == null) return;
    setState(() {
      _busy = 's$count';
      _msg = null;
    });
    try {
      final r = await ctx.api.post('${ctx.base}/members/${m['_id']}/stamp', {'n': count, 'force': force});
      final d = obj(r['data']);
      final after = obj(d['member']);
      final goal = ctx.goal;
      final ready = (after['ready'] as List? ?? const []).map((e) => n(e).toInt()).toSet();
      final top = ctx.levels.where((l) => ready.contains(n(l['at']).toInt())).lastOrNull;
      HapticFeedback.mediumImpact();
      if (mounted) {
        setState(() {
          _pop = (n(after['stamps']).toInt().clamp(1, goal)) - 1;
          _m = {...m, ...after};
          _msg = (
            true,
            top != null
                ? ctx.m('rewardReady', {'name': levelName(top, ctx.lang)})
                : d['full'] == true && n(d['added']) == 0
                ? ctx.m('cardFull')
                : ctx.m('stampedOk', {'n': d['added'] ?? count, 'now': after['stamps'], 'goal': goal}),
          );
        });
      }
      widget.onChanged?.call();
    } catch (e) {
      if (mounted) setState(() => _msg = (false, e is ApiError ? e.message : '$e'));
    }
    if (mounted) setState(() => _busy = '');
  }

  Future<void> _reward(Json l) async {
    final m = _m!;
    final at = n(l['at']).toInt();
    setState(() {
      _busy = 'r$at';
      _msg = null;
    });
    try {
      final r = await ctx.api.post('${ctx.base}/members/${m['_id']}/reward', {'at': at});
      final d = obj(r['data']);
      if (mounted) {
        setState(() {
          _m = {...m, ...obj(d['member'])};
          _pop = -1;
          _msg = (true, '🎁 ${ctx.m('rewardOk', {'name': levelName(obj(d['reward']).isNotEmpty ? obj(d['reward']) : l, ctx.lang)})}');
        });
      }
      widget.onChanged?.call();
    } catch (e) {
      if (mounted) setState(() => _msg = (false, e is ApiError ? e.message : '$e'));
    }
    if (mounted) setState(() => _busy = '');
  }

  Future<void> _resetCard() async {
    if (!_sure) {
      setState(() => _sure = true);
      _sureTimer?.cancel();
      _sureTimer = Timer(const Duration(seconds: 4), () {
        if (mounted) setState(() => _sure = false);
      });
      return;
    }
    _sureTimer?.cancel();
    final m = _m!;
    setState(() {
      _sure = false;
      _busy = 'reset';
      _msg = null;
    });
    try {
      final r = await ctx.api.post('${ctx.base}/members/${m['_id']}/reset');
      if (mounted) {
        setState(() {
          _m = {...m, ...obj(obj(r['data'])['member'])};
          _pop = -1;
          _msg = (true, ctx.m('resetDone'));
        });
      }
      widget.onChanged?.call();
    } catch (e) {
      if (mounted) setState(() => _msg = (false, e is ApiError ? e.message : '$e'));
    }
    if (mounted) setState(() => _busy = '');
  }

  Future<void> _addNew() async {
    final r = await showSheet<Json>(context, (_) => _NewCustomerSheet(ctx: ctx, paper: false));
    if (r == null || !mounted) return;
    setState(() {
      _found = [r];
      _m = r;
      _pop = -1;
    });
    widget.onChanged?.call();
    if (mounted) showCardQr(context, ctx, r);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final m = _m;
    final ro = ctx.readOnly;
    final maxPer = n(ctx.program['max_per_visit']).toInt();
    final steps = [2, 3, 5].where((s) => widget.owner || s <= (maxPer == 0 ? 5 : maxPer)).toList();
    final readyAt = m == null ? <int>{} : (m['ready'] as List? ?? const []).map((e) => n(e).toInt()).toSet();
    final ready = ctx.levels.where((l) => readyAt.contains(n(l['at']).toInt())).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Field(controller: _q, hint: ctx.m('find'), icon: LucideIcons.search, keyboard: TextInputType.text, onSubmit: _search),
            ),
            const SizedBox(width: 8),
            RoundBtn(LucideIcons.search, size: 50, onTap: _busy == 'find' ? null : () => _search(_q.text)),
          ],
        ),
        const SizedBox(height: 10),
        Btn(ctx.m('scan'), icon: LucideIcons.camera, expand: true, onTap: _scan),
        const SizedBox(height: 8),
        Btn(ctx.m('addNew'), icon: LucideIcons.userPlus, kind: BtnKind.ghost, expand: true, onTap: ro ? null : _addNew),
        if (_busy == 'find')
          const Padding(
            padding: EdgeInsets.only(top: 14),
            child: Center(child: CircularProgressIndicator()),
          ),
        if (_msg != null && m == null)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: _Msg(ok: _msg!.$1, text: _msg!.$2),
          ),
        if (_found != null && _found!.isEmpty) Padding(padding: const EdgeInsets.only(top: 12), child: Muted(ctx.m('noMatch'))),
        if (_found != null && _found!.length > 1 && m == null) ...[
          const SizedBox(height: 12),
          Text(ctx.m('pickOne'), style: const TextStyle(fontWeight: FontWeight.w800)),
          const SizedBox(height: 4),
          for (final r in _found!) ScMemberRow(ctx: ctx, m: r, onTap: () => setState(() => _m = r)),
        ],
        if (m != null) ...[
          const SizedBox(height: 16),
          ScCardView(shop: ctx.shop(), member: m, lang: ctx.lang, pop: _pop, key: ValueKey('${m['_id']}${m['stamps']}')),
          const SizedBox(height: 14),
          Text(str(m['name']), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 18)),
          Text('${ctx.m('cardNo', {'n': m['no']})}${str(m['phone']).isNotEmpty ? ' · ${prettyPhone(m['phone'])}' : ''}', style: TextStyle(color: c.ink.withValues(alpha: .8))),
          Muted(m['last_visit_at'] != null ? ctx.m('lastVisit', {'ago': scAgo(m['last_visit_at'], ctx)}) : ctx.m('neverVisit')),
          if (_msg != null)
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: _Msg(ok: _msg!.$1, text: _msg!.$2),
            ),
          const SizedBox(height: 10),
          for (final l in ready)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: _BigButton(
                label: ctx.m('giveReward', {'name': levelName(l, ctx.lang)}),
                icon: LucideIcons.gift,
                color: const Color(0xFF16A34A),
                busy: _busy == 'r${l['at']}',
                onTap: _busy.isNotEmpty || ro ? null : () => _reward(l),
              ),
            ),
          _BigButton(
            label: ctx.m('addStamp'),
            icon: LucideIcons.plus,
            color: scHex(str(ctx.program['color'])) ?? c.brand,
            big: true,
            busy: _busy == 's1',
            onTap: _busy.isNotEmpty || ro ? null : () => _stamp(1),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              for (final s in steps) ...[
                Expanded(
                  child: Btn(ctx.m('addN', {'n': s}), kind: BtnKind.ghost, small: true, busy: _busy == 's$s', onTap: _busy.isNotEmpty || ro ? null : () => _stamp(s)),
                ),
                if (s != steps.last) const SizedBox(width: 8),
              ],
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 4,
            runSpacing: 0,
            children: [
              if (str(m['token']).isNotEmpty) TextButton.icon(onPressed: () => showCardQr(context, ctx, m), icon: const Icon(LucideIcons.qrCode, size: 15), label: Text(ctx.m('showCard'))),
              if (widget.owner && widget.onOpen != null) TextButton.icon(onPressed: () => widget.onOpen!(m), icon: const Icon(LucideIcons.user, size: 15), label: Text(ctx.m('seeCustomer'))),
              if (widget.canReset && (n(m['stamps']) > 0 || (m['claimed'] as List? ?? const []).isNotEmpty))
                TextButton.icon(
                  onPressed: _busy.isNotEmpty || ro ? null : _resetCard,
                  style: TextButton.styleFrom(foregroundColor: _sure ? c.danger : c.muted),
                  icon: const Icon(LucideIcons.eraser, size: 15),
                  label: Text(_sure ? ctx.m('resetSure') : ctx.m('resetCard'), style: TextStyle(fontWeight: _sure ? FontWeight.w800 : FontWeight.w600)),
                ),
              TextButton.icon(onPressed: _reset, icon: const Icon(LucideIcons.rotateCcw, size: 15), label: Text(ctx.m('newSearch'))),
            ],
          ),
          Muted('${fmt(n(m['total_stamps']))} ${ctx.m('totalStamps').toLowerCase()} · ${fmt(n(m['rewards']))} ${ctx.m('rewardsGot').toLowerCase()}'),
        ],
      ],
    );
  }
}

class _Msg extends StatelessWidget {
  final bool ok;
  final String text;
  const _Msg({required this.ok, required this.text});
  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(color: ok ? c.goodBg : c.dangerBg, borderRadius: BorderRadius.circular(12)),
      child: Text(
        text,
        style: TextStyle(fontWeight: FontWeight.w700, color: ok ? c.good : c.danger),
      ),
    );
  }
}

class _BigButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color color;
  final bool big, busy;
  final VoidCallback? onTap;
  const _BigButton({required this.label, required this.icon, required this.color, this.big = false, this.busy = false, this.onTap});
  @override
  Widget build(BuildContext context) => SizedBox(
    height: big ? 62 : 52,
    child: FilledButton.icon(
      style: FilledButton.styleFrom(
        backgroundColor: color,
        foregroundColor: Colors.white,
        disabledBackgroundColor: color.withValues(alpha: .45),
        disabledForegroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        textStyle: TextStyle(fontSize: big ? 20 : 16, fontWeight: FontWeight.w800),
      ),
      onPressed: onTap,
      icon: busy ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2.4, color: Colors.white)) : Icon(icon, size: big ? 24 : 19),
      label: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
    ),
  );
}

// the customer's card QR, big, for them to scan with their own phone
void showCardQr(BuildContext context, ScCtx ctx, Json m) {
  final url = cardUrl(m['token']);
  showSheet<void>(
    context,
    (s) => MSheet(
      title: '${m['name']} · #${m['no']}',
      footer: [
        Expanded(
          child: Btn(ctx.m('copyLink'), icon: LucideIcons.copy, kind: BtnKind.ghost, small: true, onTap: () => scCopy(ctx, url)),
        ),
      ],
      children: [
        Center(
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(18)),
            child: QrImageView(data: url, size: 240, padding: EdgeInsets.zero, backgroundColor: Colors.white),
          ),
        ),
        const SizedBox(height: 10),
        Muted(ctx.m('showCardSub'), align: TextAlign.center),
        const SizedBox(height: 4),
        SelectableText(
          url,
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 12, color: s.c.muted),
        ),
      ],
    ),
  );
}

// add a customer (the counter: name + phone · the Customers tab: + note + paper stamps)
class _NewCustomerSheet extends StatefulWidget {
  final ScCtx ctx;
  final bool paper;
  const _NewCustomerSheet({required this.ctx, required this.paper});
  @override
  State<_NewCustomerSheet> createState() => _NewCustomerSheetState();
}

class _NewCustomerSheetState extends State<_NewCustomerSheet> {
  ScCtx get ctx => widget.ctx;
  final _name = TextEditingController(), _phone = TextEditingController(), _note = TextEditingController(), _stamps = TextEditingController();
  bool _busy = false;
  String _error = '';

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    _note.dispose();
    _stamps.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_name.text.trim().isEmpty) return;
    setState(() {
      _busy = true;
      _error = '';
    });
    try {
      final r = await ctx.api.post('${ctx.base}/members', {
        'name': _name.text.trim(),
        'phone': _phone.text.trim(),
        if (widget.paper) 'note': _note.text.trim(),
        if (widget.paper) 'stamps': int.tryParse(_stamps.text.trim()) ?? 0,
      });
      ctx.notify(ctx.m('added'));
      if (mounted) Navigator.pop(context, obj(r['data']));
    } catch (e) {
      if (mounted) setState(() => _error = e is ApiError ? e.message : '$e');
    }
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) => MSheet(
    title: widget.paper ? ctx.m('add') : ctx.m('addNew'),
    footer: [
      Expanded(
        child: Btn(ctx.m('cancel'), kind: BtnKind.ghost, onTap: () => Navigator.pop(context)),
      ),
      const SizedBox(width: 8),
      Expanded(
        child: Btn(ctx.m('add'), icon: LucideIcons.userPlus, busy: _busy, onTap: _save),
      ),
    ],
    children: [
      Field(label: ctx.m('name'), controller: _name, autofocus: true, maxLength: 80),
      const SizedBox(height: 12),
      Field(label: ctx.m('phone'), controller: _phone, hint: '012 345 678', keyboard: TextInputType.phone, maxLength: 20),
      if (widget.paper) ...[
        const SizedBox(height: 12),
        Field(label: ctx.m('note'), controller: _note, hint: ctx.m('notePh'), maxLength: 300),
        const SizedBox(height: 12),
        Field(label: ctx.m('paperStamps'), controller: _stamps, keyboard: TextInputType.number, maxLength: 2),
        const SizedBox(height: 4),
        Muted(ctx.m('paperHint')),
      ],
      if (_error.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 10), child: Alert(_error)),
    ],
  );
}

class _EventRow extends StatelessWidget {
  final ScCtx ctx;
  final Json e;
  final bool showName;
  const _EventRow({required this.ctx, required this.e}) : showName = true;
  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final k = str(e['kind']);
    final color = switch (k) {
      'stamp' => c.brand,
      'reward' => c.good,
      'adjust' => c.warn,
      'expire' => c.danger,
      _ => c.muted,
    };
    final icon = switch (k) {
      'stamp' => LucideIcons.stamp,
      'reward' => LucideIcons.gift,
      'adjust' => LucideIcons.wrench,
      'expire' => LucideIcons.hourglass,
      _ => LucideIcons.userPlus,
    };
    final mem = obj(e['member']);
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 9),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: c.line)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 30,
            height: 30,
            decoration: BoxDecoration(color: color.withValues(alpha: .12), shape: BoxShape.circle),
            child: Icon(icon, size: 15, color: color),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text.rich(
                  TextSpan(
                    children: [
                      if (showName) ...[
                        TextSpan(
                          text: str(mem['name']),
                          style: const TextStyle(fontWeight: FontWeight.w800),
                        ),
                        TextSpan(
                          text: ' #${mem['no'] ?? ''} · ',
                          style: TextStyle(color: c.muted),
                        ),
                      ],
                      TextSpan(text: scEvent(e, ctx)),
                      if (str(e['note']).isNotEmpty)
                        TextSpan(
                          text: ' · ${e['note']}',
                          style: TextStyle(color: c.muted, fontSize: 12.5),
                        ),
                    ],
                  ),
                ),
                Text('${scTime(e['at'], ctx.lang)} · ${scBy(e, ctx)}', style: TextStyle(color: c.muted, fontSize: 12)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ------------------------------------------------------------------------------------------------ CUSTOMERS
class CustomersTab extends StatefulWidget {
  final ScCtx ctx;
  final ValueChanged<Json> onPick;
  const CustomersTab({super.key, required this.ctx, required this.onPick});
  @override
  State<CustomersTab> createState() => _CustomersTabState();
}

class _CustomersTabState extends State<CustomersTab> {
  ScCtx get ctx => widget.ctx;
  final _q = TextEditingController();
  String _filter = 'all', _sort = 'recent', _query = '';
  List<Json>? _rows;
  int _page = 1, _pages = 1, _total = 0;
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    _load(1);
  }

  @override
  void dispose() {
    _q.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  Future<void> _load(int p) async {
    try {
      final r = await ctx.api.get('${ctx.base}/members', {'filter': _filter, 'sort': _sort, 'q': _query, 'page': '$p'});
      if (!mounted) return;
      final pg = obj(r['pagination']);
      setState(() {
        _rows = p == 1 ? objs(r['data']) : [...?_rows, ...objs(r['data'])];
        _page = p;
        _pages = n(pg['totalPages']).toInt().clamp(1, 9999);
        _total = n(pg['total']).toInt();
      });
    } catch (e) {
      ctx.fail(e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final rows = _rows;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
      children: [
        scHead(context, LucideIcons.users, ctx.m('customersTitle'), ctx.p('tapToOpen')),
        scGap,
        scPanel(padding: const EdgeInsets.fromLTRB(12, 12, 12, 8), [
          Field(
            controller: _q,
            hint: ctx.m('search'),
            icon: LucideIcons.search,
            onChanged: (v) {
              _debounce?.cancel();
              _debounce = Timer(const Duration(milliseconds: 300), () {
                _query = v.trim();
                _load(1);
              });
            },
          ),
          const SizedBox(height: 10),
          SizedBox(
            height: 36,
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: [
                for (final k in ['all', 'ready', 'sleeping'])
                  Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: ChoiceChip(
                      label: Text(ctx.m('filters.$k')),
                      selected: _filter == k,
                      onSelected: (_) {
                        setState(() {
                          _filter = k;
                          _rows = null;
                        });
                        _load(1);
                      },
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Expanded(child: Muted(rows == null ? '' : fmt(_total))),
              DropdownButton<String>(
                value: _sort,
                underline: const SizedBox.shrink(),
                items: [
                  for (final k in ['recent', 'stamps', 'best', 'new', 'name']) DropdownMenuItem(value: k, child: Text(ctx.m('sort.$k'))),
                ],
                onChanged: (v) {
                  if (v == null) return;
                  setState(() {
                    _sort = v;
                    _rows = null;
                  });
                  _load(1);
                },
              ),
            ],
          ),
          if (rows == null)
            const SkelList(rows: 4)
          else if (rows.isEmpty)
            Padding(padding: const EdgeInsets.all(6), child: Muted(_query.isNotEmpty || _filter != 'all' ? ctx.m('noResults') : ctx.m('noCustomers')))
          else
            for (final m in rows) ScMemberRow(ctx: ctx, m: m, onTap: () => widget.onPick(m)),
          if (_page < _pages)
            Padding(
              padding: const EdgeInsets.all(8),
              child: Btn(ctx.m('more'), kind: BtnKind.ghost, small: true, onTap: () => _load(_page + 1)),
            ),
        ]),
      ],
    );
  }
}

// ------------------------------------------------------------------------------------------------ HISTORY
class HistoryTab extends StatefulWidget {
  final ScCtx ctx;
  final ValueChanged<Json> onPick;
  const HistoryTab({super.key, required this.ctx, required this.onPick});
  @override
  State<HistoryTab> createState() => _HistoryTabState();
}

class _HistoryTabState extends State<HistoryTab> {
  ScCtx get ctx => widget.ctx;
  String _kind = '';
  List<Json>? _rows;
  int _page = 1, _pages = 1;

  @override
  void initState() {
    super.initState();
    _load(1);
  }

  Future<void> _load(int p) async {
    try {
      final r = await ctx.api.get('${ctx.base}/history', {'kind': _kind, 'page': '$p'});
      if (!mounted) return;
      setState(() {
        _rows = p == 1 ? objs(r['data']) : [...?_rows, ...objs(r['data'])];
        _page = p;
        _pages = n(obj(r['pagination'])['totalPages']).toInt().clamp(1, 9999);
      });
    } catch (e) {
      ctx.fail(e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final rows = _rows;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
      children: [
        scHead(context, LucideIcons.history, ctx.m('historyTitle'), ctx.m('historySub')),
        scGap,
        scPanel(padding: const EdgeInsets.fromLTRB(12, 12, 12, 8), [
          SizedBox(
            height: 36,
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: [
                for (final k in ['', 'join', 'stamp', 'reward', 'adjust', 'expire'])
                  Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: ChoiceChip(
                      label: Text(ctx.t.or('sc.kinds.$k', k.isEmpty ? ctx.m('filters.all') : k)),
                      selected: _kind == k,
                      onSelected: (_) {
                        setState(() {
                          _kind = k;
                          _rows = null;
                        });
                        _load(1);
                      },
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 6),
          if (rows == null)
            const SkelList(rows: 4)
          else if (rows.isEmpty)
            Padding(padding: const EdgeInsets.all(6), child: Muted(ctx.m('noHistory')))
          else
            for (final e in rows)
              InkWell(
                onTap: obj(e['member'])['no'] == null ? null : () => widget.onPick(obj(e['member'])),
                child: _EventRow(ctx: ctx, e: e),
              ),
          if (_page < _pages)
            Padding(
              padding: const EdgeInsets.all(8),
              child: Btn(ctx.m('more'), kind: BtnKind.ghost, small: true, onTap: () => _load(_page + 1)),
            ),
        ]),
      ],
    );
  }
}

// ------------------------------------------------------------------------------------------------ STATS
class StatsTab extends StatefulWidget {
  final ScCtx ctx;
  final ValueChanged<Json> onPick;
  const StatsTab({super.key, required this.ctx, required this.onPick});
  @override
  State<StatsTab> createState() => _StatsTabState();
}

class _StatsTabState extends State<StatsTab> {
  ScCtx get ctx => widget.ctx;
  int _days = 30;
  Json? _d;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _d = null);
    try {
      final r = await ctx.api.get('${ctx.base}/stats', {'days': '$_days'});
      if (mounted) setState(() => _d = obj(r['data']));
    } catch (e) {
      ctx.fail(e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final d = _d;
    final accent = scHex(str(ctx.program['color'])) ?? c.brand;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
      children: [
        scHead(context, LucideIcons.chartColumn, ctx.m('statsTitle'), ctx.m('statsSub')),
        const SizedBox(height: 10),
        Row(
          children: [
            for (final dd in [7, 30, 90])
              Padding(
                padding: const EdgeInsets.only(right: 6),
                child: ChoiceChip(
                  label: Text(ctx.m('days$dd')),
                  selected: _days == dd,
                  onSelected: (_) {
                    _days = dd;
                    _load();
                  },
                ),
              ),
          ],
        ),
        scGap,
        if (d == null)
          const SkelList(rows: 4)
        else ...[
          GridView.count(
            crossAxisCount: 2,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 10,
            crossAxisSpacing: 10,
            childAspectRatio: 2.4,
            children: [
              for (final (k, v) in [
                (ctx.m('visits'), obj(d['totals'])['visits']),
                (ctx.m('stamps'), obj(d['totals'])['stamps']),
                (ctx.m('rewards'), obj(d['totals'])['rewards']),
                (ctx.m('newCustomers'), d['joined']),
              ])
                Panel(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        k,
                        style: TextStyle(color: c.muted, fontSize: 12.5, fontWeight: FontWeight.w600),
                      ),
                      Text(fmt(n(v)), style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
                    ],
                  ),
                ),
            ],
          ),
          scGap,
          scPanel([
            scTitle(context, ctx.m('perDay')),
            if (n(obj(d['totals'])['visits']) == 0)
              Muted(ctx.m('noData'))
            else ...[
              _Bars(values: objs(d['days']).map((r) => n(r['visits'])).toList(), color: accent),
              const SizedBox(height: 6),
              Row(children: [Muted(scDay(str(objs(d['days']).first['day']), ctx.lang)), const Spacer(), Muted(scDay(str(objs(d['days']).last['day']), ctx.lang))]),
            ],
          ]),
          scGap,
          scPanel([
            scTitle(context, ctx.m('busyHours')),
            _Bars(values: (d['hours'] as List? ?? const []).map((e) => n(e)).toList(), color: accent),
            const SizedBox(height: 6),
            Row(children: [Muted('0:00'), const Spacer(), Muted('12:00'), const Spacer(), Muted('23:00')]),
          ]),
          scGap,
          scPanel([
            scTitle(context, ctx.m('best')),
            if (objs(d['best']).isEmpty) Muted(ctx.m('noData')),
            for (final (i, b) in objs(d['best']).indexed)
              InkWell(
                onTap: () => widget.onPick(b),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Row(
                    children: [
                      SizedBox(
                        width: 26,
                        child: Text(
                          '${i + 1}.',
                          style: TextStyle(color: c.muted, fontWeight: FontWeight.w700),
                        ),
                      ),
                      Expanded(
                        child: Text.rich(
                          TextSpan(
                            text: str(b['name']),
                            style: const TextStyle(fontWeight: FontWeight.w800),
                            children: [
                              TextSpan(
                                text: '  #${b['no']}',
                                style: TextStyle(color: c.muted, fontWeight: FontWeight.w500),
                              ),
                            ],
                          ),
                        ),
                      ),
                      Text('${fmt(n(b['visits']))} ${ctx.m('visits').toLowerCase()} · ${fmt(n(b['period_stamps']))} ★', style: TextStyle(color: c.muted, fontSize: 12.5)),
                    ],
                  ),
                ),
              ),
          ]),
        ],
      ],
    );
  }
}

class _Bars extends StatelessWidget {
  final List<num> values;
  final Color color;
  const _Bars({required this.values, required this.color});
  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final max = values.fold<num>(1, (a, b) => b > a ? b : a);
    return SizedBox(
      height: 120,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          for (final v in values)
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 1.2),
                child: Tooltip(
                  message: '$v',
                  child: Container(
                    height: v == 0 ? 3 : (v / max * 120).toDouble().clamp(4, 120),
                    decoration: BoxDecoration(color: v == 0 ? c.line : color, borderRadius: BorderRadius.circular(3)),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
