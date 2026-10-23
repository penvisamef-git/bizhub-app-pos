import 'dart:async';

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../core/config.dart';
import '../../core/format.dart' as f;
import '../../core/pos_api.dart' show ApiError;
import '../../core/theme.dart';
import '../../widgets/ui.dart';
import 'engine/calc.dart';
import 'engine/rest_pos.dart';
import 'pos_ui.dart';

// Reward points on a bill: find or add the member (name or phone), then spend points on rewards or use their coupons.
// ensureOrder() makes the bill first when the ticket is still empty. Needs the internet (points can't be spent twice).
Future<void> showMemberSheet(BuildContext context, {required String? Function() orderId, required Future<String> Function() ensureOrder}) => posSheet(
  context,
  title: tr(context)('rpos.member'),
  maxWidth: 620,
  body: (_) => _Member(orderId: orderId, ensureOrder: ensureOrder),
);

class _Member extends StatefulWidget {
  final String? Function() orderId;
  final Future<String> Function() ensureOrder;
  const _Member({required this.orderId, required this.ensureOrder});
  @override
  State<_Member> createState() => _MemberState();
}

class _MemberState extends State<_Member> {
  final pos = RestPos.i;
  final _q = TextEditingController();
  final _phone = TextEditingController(), _name = TextEditingController(), _birthday = TextEditingController();
  List<J>? _results;
  bool _creating = false, _showInfo = false, _qr = false;
  String? _viewing;
  String _busy = '', _error = '';
  Timer? _debounce;

  J? get order => widget.orderId() == null ? null : pos.orders[widget.orderId()];
  String get memberId => js(jmap(order?['member'])['id']);

  @override
  void initState() {
    super.initState();
    if (memberId.isNotEmpty) _run('refresh', () => pos.refreshMember(memberId));
  }

  @override
  void dispose() {
    _debounce?.cancel();
    for (final c in [_q, _phone, _name, _birthday]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<T?> _run<T>(String key, Future<T> Function() fn) async {
    setState(() {
      _busy = key;
      _error = '';
    });
    try {
      return await fn();
    } on ApiError catch (e) {
      if (mounted) setState(() => _error = e.network ? tr(context)('rpos.memberOffline') : e.message);
    } finally {
      if (mounted) setState(() => _busy = '');
    }
    return null;
  }

  void _typed(String v) {
    _debounce?.cancel();
    final text = v.trim();
    if (text.length < 2) return setState(() => _results = null);
    _debounce = Timer(const Duration(milliseconds: 350), () async {
      final r = await _run('find', () => pos.searchMembers(text));
      if (r != null && mounted) setState(() => _results = r);
    });
  }

  String _phoneOf(String text) => RegExp(r'^[\d\s+()-]{8,}$').hasMatch(text.trim()) ? text.trim() : '';

  void _startCreate() {
    final p = _phoneOf(_q.text);
    _phone.text = p;
    _name.text = p.isEmpty ? _q.text.trim() : '';
    _birthday.clear();
    setState(() => _creating = true);
  }

  Future<void> _attach(J m) => _run('attach', () async {
    final id = await widget.ensureOrder();
    await pos.attachMember(id, m);
    await pos.refreshMember(js(m['_id']));
    setState(() {
      _viewing = null;
      _results = null;
      _q.clear();
    });
  });

  Future<void> _create() => _run('create', () async {
    final data = await pos.createMember(phone: _phone.text.trim(), name: _name.text.trim(), birthday: _birthday.text.trim());
    final id = await widget.ensureOrder();
    await pos.attachMember(id, jmap(data['member']));
    setState(() => _creating = false);
  });

  @override
  Widget build(BuildContext context) {
    final t = tr(context);
    return ListenableBuilder(
      listenable: pos,
      builder: (context, _) {
        final c = context.c;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (memberId.isEmpty) (_viewing != null ? _detail(context, _viewing!) : (_creating ? _createForm(context) : _find(context))) else _onBill(context),
            if (!pos.online) ...[const SizedBox(height: 10), Alert(t('rpos.memberOffline'), tone: Tone.warn)],
            if (_error.isNotEmpty) ...[
              const SizedBox(height: 10),
              Text(
                _error,
                style: TextStyle(color: c.danger, fontWeight: FontWeight.w600),
              ),
            ],
          ],
        );
      },
    );
  }

  Widget _find(BuildContext context) {
    final t = tr(context);
    final c = context.c;
    final r = _results;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Field(
          controller: _q,
          hint: t('rpos.memberSearch'),
          icon: LucideIcons.search,
          autofocus: true,
          onChanged: _typed,
          suffix: _busy == 'find'
              ? Padding(
                  padding: const EdgeInsets.all(14),
                  child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: c.brand)),
                )
              : null,
        ),
        const SizedBox(height: 10),
        if (r != null && r.isNotEmpty)
          for (final m in r)
            _MemberCard(
              m,
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    onPressed: _busy.isNotEmpty
                        ? null
                        : () => _run('detail', () async {
                            await pos.refreshMember(js(m['_id']));
                            setState(() => _viewing = js(m['_id']));
                          }),
                    icon: const Icon(LucideIcons.eye, size: 18),
                    tooltip: t('rpos.details'),
                  ),
                  Btn(t('rpos.addToBill'), small: true, onTap: _busy.isNotEmpty ? null : () => _attach(m)),
                ],
              ),
            ),
        if (r != null && r.isEmpty && _q.text.trim().length >= 2 && _busy != 'find') Padding(padding: const EdgeInsets.only(bottom: 8), child: Muted(t('rpos.noMemberFound'))),
        Btn(
          _phoneOf(_q.text).isNotEmpty ? t('rpos.memberAddPhone', {'p': _q.text.trim()}) : t('rpos.memberAddNew'),
          icon: LucideIcons.userPlus,
          kind: BtnKind.ghost,
          expand: true,
          onTap: _busy.isNotEmpty ? null : _startCreate,
        ),
      ],
    );
  }

  Widget _createForm(BuildContext context) {
    final t = tr(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Field(controller: _phone, hint: t('rpos.memberPhone'), keyboard: TextInputType.phone, autofocus: _phone.text.isEmpty, onChanged: (_) => setState(() {})),
        const SizedBox(height: 10),
        Field(controller: _name, hint: t('rpos.memberName'), maxLength: 60),
        const SizedBox(height: 10),
        Field(controller: _birthday, hint: t('rpos.memberBirthday'), maxLength: 10),
        const SizedBox(height: 14),
        Row(
          children: [
            Expanded(
              child: Btn(t('rpos.back'), kind: BtnKind.ghost, onTap: _busy.isNotEmpty ? null : () => setState(() => _creating = false)),
            ),
            const SizedBox(width: 8),
            Expanded(
              flex: 2,
              child: Btn(t('rpos.memberCreate'), icon: LucideIcons.userPlus, busy: _busy == 'create', onTap: _busy.isNotEmpty || _phone.text.trim().isEmpty ? null : _create),
            ),
          ],
        ),
      ],
    );
  }

  Widget _detail(BuildContext context, String id) {
    final t = tr(context);
    final info = pos.members[id];
    if (info == null) return const SizedBox.shrink();
    final m = jmap(info['member']);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _MemberCard(m, on: true),
        _MemberStats(info),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: Btn(t('rpos.back'), icon: LucideIcons.arrowLeft, kind: BtnKind.ghost, onTap: () => setState(() => _viewing = null)),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Btn(t('rpos.addToBill'), busy: _busy == 'attach', onTap: _busy.isNotEmpty ? null : () => _attach(m)),
            ),
          ],
        ),
      ],
    );
  }

  Widget _onBill(BuildContext context) {
    final t = tr(context);
    final c = context.c;
    final o = order!;
    final oid = js(o['_id']);
    final info = pos.members[memberId];
    final mem = jmap(o['member']);
    final earn = pos.pointsFor(o);
    final open = o['status'] == 'open';
    final used = jlist(o['redemptions']);
    final cur = pos.currency;
    final token = js(jmap(info?['member'])['token']);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _MemberCard(
          {...mem, if (info != null) 'points': jmap(info['member'])['points']},
          on: true,
          extra: earn > 0 ? t('rpos.earnThisBill', {'n': earn}) : '',
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (info != null)
                IconButton(
                  onPressed: () => setState(() => _showInfo = !_showInfo),
                  icon: Icon(LucideIcons.eye, color: _showInfo ? c.brand : null),
                  tooltip: t('rpos.details'),
                ),
              if (token.isNotEmpty)
                IconButton(
                  onPressed: () => setState(() => _qr = !_qr),
                  icon: Icon(LucideIcons.qrCode, color: _qr ? c.brand : null),
                  tooltip: t('rpos.memberQr'),
                ),
              if (open && used.isEmpty) IconButton(onPressed: () => pos.attachMember(oid, null), icon: const Icon(LucideIcons.x), tooltip: t('rpos.memberRemove')),
            ],
          ),
        ),
        if (_showInfo && info != null) _MemberStats(info),
        if (_qr && token.isNotEmpty)
          Center(
            child: Column(
              children: [
                const SizedBox(height: 8),
                Container(
                  color: Colors.white,
                  padding: const EdgeInsets.all(10),
                  child: QrImageView(data: '${Config.siteUrl}/public/member/$token', size: 200),
                ),
                const SizedBox(height: 6),
                Muted(t('rpos.memberQrHint'), align: TextAlign.center),
              ],
            ),
          ),
        if (used.isNotEmpty) ...[
          _head(t('rpos.usedOnBill')),
          for (final r in used)
            _Row(
              title: '${js(r['name'])}${js(r['code']).isNotEmpty ? ' · ${js(r['code'])}' : ''}',
              sub: js(r['code']).isNotEmpty ? t('rpos.coupon') : t('rpos.points', {'n': '−${nz(r['points']).toInt()}'}),
              action: open
                  ? Btn(
                      t('rpos.undo'),
                      icon: LucideIcons.undo2,
                      small: true,
                      kind: BtnKind.ghost,
                      busy: _busy == 'undo:${r['id']}',
                      onTap: _busy.isNotEmpty ? null : () => _run('undo:${r['id']}', () => pos.undoRedemption(oid, js(r['id']))),
                    )
                  : null,
            ),
        ],
        if (open && info != null && jlist(info['coupons']).isNotEmpty) ...[
          _head(t('rpos.coupons')),
          for (final cp in jlist(info['coupons']))
            () {
              final moneyOff = cp['kind'] == 'amount' || cp['kind'] == 'percent';
              final blocked = moneyOff && pos.billRewardTaken(oid);
              return _Row(
                icon: LucideIcons.ticket,
                title: '${js(cp['name'])} · ${js(cp['code'])}',
                sub: blocked ? t('rpos.oneMoneyOff') : '',
                action: Btn(
                  t('rpos.use'),
                  small: true,
                  busy: _busy == 'cp:${cp['id']}',
                  onTap: _busy.isNotEmpty || blocked ? null : () => _run('cp:${cp['id']}', () => pos.useCoupon(oid, js(cp['id']))),
                ),
              );
            }(),
        ],
        if (open && info != null) ...[
          _head(t('rpos.rewards')),
          if (jlist(info['rewards']).isEmpty) Muted(t('rpos.noRewards')),
          for (final r in jlist(info['rewards']))
            () {
              final short = nz(jmap(info['member'])['points']) < nz(r['points']);
              final moneyOff = r['kind'] == 'amount' || r['kind'] == 'percent';
              final blocked = moneyOff && pos.billRewardTaken(oid);
              final what = switch (js(r['kind'])) {
                'amount' => '−${m$(r['value'], cur)}',
                'percent' => '−${_n(r['value'])}%',
                'coupon' => t('rpos.couponLater'),
                'gift' => t('rpos.gift'),
                _ => t('rpos.freeItem'),
              };
              return Opacity(
                opacity: short ? .5 : 1,
                child: _Row(
                  icon: moneyOff || r['kind'] == 'coupon' ? LucideIcons.ticket : LucideIcons.gift,
                  title: '${js(r['name'])} · $what',
                  sub: blocked ? t('rpos.oneMoneyOff') : t('rpos.points', {'n': nz(r['points']).toInt()}),
                  action: Btn(
                    t('rpos.use'),
                    small: true,
                    busy: _busy == 'rw:${r['_id']}',
                    onTap: _busy.isNotEmpty || short || blocked ? null : () => _run('rw:${r['_id']}', () => pos.redeemReward(oid, js(r['_id']))),
                  ),
                ),
              );
            }(),
        ],
      ],
    );
  }

  Widget _head(String text) => Padding(
    padding: const EdgeInsets.only(top: 14, bottom: 6),
    child: Text(text, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
  );
}

String _n(Object? v) {
  final x = nz(v);
  return x == x.roundToDouble() ? x.toInt().toString() : x.toString();
}

class _MemberCard extends StatelessWidget {
  final J m;
  final bool on;
  final String extra;
  final Widget? trailing;
  const _MemberCard(this.m, {this.on = false, this.extra = '', this.trailing});
  @override
  Widget build(BuildContext context) {
    final t = tr(context);
    final c = context.c;
    final bits = [
      js(m['phone']),
      if (m['points'] != null) t('rpos.points', {'n': nz(m['points']).toInt()}),
      if (m['visits'] != null) t('rpos.visitsN', {'n': nz(m['visits']).toInt()}),
    ].where((x) => x.isNotEmpty).join(' · ');
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.fromLTRB(14, 10, 6, 10),
      decoration: BoxDecoration(
        color: on ? c.active : c.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: on ? c.brand : c.line),
      ),
      child: Row(
        children: [
          Icon(LucideIcons.star, color: c.brand, size: on ? 22 : 18),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(js(m['name']).isEmpty ? '—' : js(m['name']), style: const TextStyle(fontWeight: FontWeight.w800)),
                Text(bits, style: TextStyle(color: c.muted, fontSize: 12.5)),
                if (extra.isNotEmpty)
                  Text(
                    extra,
                    style: TextStyle(color: c.good, fontWeight: FontWeight.w700, fontSize: 12.5),
                  ),
              ],
            ),
          ),
          ?trailing,
        ],
      ),
    );
  }
}

class _Row extends StatelessWidget {
  final String title, sub;
  final IconData? icon;
  final Widget? action;
  const _Row({required this.title, this.sub = '', this.icon, this.action});
  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          if (icon != null) ...[Icon(icon, size: 16, color: c.brand), const SizedBox(width: 8)],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
                if (sub.isNotEmpty) Text(sub, style: TextStyle(color: c.muted, fontSize: 12)),
              ],
            ),
          ),
          ?action,
        ],
      ),
    );
  }
}

// what the cashier may see about a member (read only: points can only be changed by the owner)
class _MemberStats extends StatelessWidget {
  final J info;
  const _MemberStats(this.info);
  @override
  Widget build(BuildContext context) {
    final t = tr(context);
    final c = context.c;
    final m = jmap(info['member']);
    final pos = RestPos.i;
    Widget cell(String label, String value) => Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: c.card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: c.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: TextStyle(color: c.muted, fontSize: 12)),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(value, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
          ),
        ],
      ),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        GridView.count(
          crossAxisCount: 2,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: 8,
          crossAxisSpacing: 8,
          childAspectRatio: 2.6,
          children: [
            cell(t('rpos.pointsLabel'), '${nz(m['points']).toInt()}'),
            cell(t('rpos.visitsLabel'), '${nz(m['visits']).toInt()}'),
            cell(t('rpos.spentLabel'), m$(m['total_spent'], pos.currency)),
            cell(t('rpos.lastVisit'), m['last_visit'] == null ? '—' : f.fmtDate(m['last_visit'])),
            if (js(m['birthday']).isNotEmpty) cell(t('rpos.birthdayLabel'), js(m['birthday'])),
          ],
        ),
        if (jlist(info['moves']).isNotEmpty) ...[
          Padding(
            padding: const EdgeInsets.only(top: 12, bottom: 4),
            child: Text(t('rpos.history'), style: const TextStyle(fontWeight: FontWeight.w800)),
          ),
          for (final x in jlist(info['moves']))
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      '${t.or('rpos.moveKinds.${x['kind']}', js(x['kind']))}${js(x['reward_name']).isNotEmpty ? ' · ${js(x['reward_name'])}' : ''}${js(x['order_number']).isNotEmpty ? ' · #${js(x['order_number'])}' : ''} · ${f.fmtDate(x['at'])}',
                      style: const TextStyle(fontSize: 13),
                    ),
                  ),
                  Text(
                    '${nz(x['points']) > 0 ? '+' : ''}${nz(x['points']).toInt()}',
                    style: TextStyle(fontWeight: FontWeight.w800, color: nz(x['points']) > 0 ? c.good : c.danger),
                  ),
                ],
              ),
            ),
        ],
        const SizedBox(height: 6),
        Muted(t('rpos.ownerOnly')),
      ],
    );
  }
}
