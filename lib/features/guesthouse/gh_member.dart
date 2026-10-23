import 'dart:async';

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/theme.dart';
import '../../widgets/ui.dart';
import '../restaurant/engine/calc.dart' show J, jmap, jlist, js, jsRound, nz;
import '../restaurant/pos_ui.dart';
import 'engine/gh_pos.dart';
import 'gh_ui.dart';

// Loyalty points on a booking (gh_loyalty) — the web's MemberBox: link a member, use points, give them back
class GhMemberBox extends StatefulWidget {
  final J stay;
  final ValueChanged<J> onStay;
  const GhMemberBox({super.key, required this.stay, required this.onStay});
  @override
  State<GhMemberBox> createState() => _GhMemberBoxState();
}

class _GhMemberBoxState extends State<GhMemberBox> {
  final pos = GhPos.i;
  J? _m;
  String? _find; // null = not searching
  final _q = TextEditingController();
  final _use = TextEditingController();
  List<J> _hits = [];
  bool _working = false;
  Timer? _deb;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(GhMemberBox old) {
    super.didUpdateWidget(old);
    final a = old.stay, b = widget.stay;
    if (a['customer_id'] != b['customer_id'] || a['points_used'] != b['points_used'] || a['status'] != b['status']) _load();
  }

  @override
  void dispose() {
    _deb?.cancel();
    _q.dispose();
    _use.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    if (js(widget.stay['_id']).startsWith('local-') || pos.boot['loyalty'] != true) return;
    try {
      final r = await pos.api('GET', '/stays/${widget.stay['_id']}/member');
      if (mounted) setState(() => _m = jmap(r['data']));
    } catch (_) {
      if (mounted) setState(() => _m = null);
    }
  }

  Future<void> _run(Future<J> Function() fn) async {
    setState(() => _working = true);
    try {
      final r = await fn();
      if (r['data'] is Map) widget.onStay(jmap(r['data']));
      await _load();
    } catch (e) {
      if (mounted) ghToast(context, ghErr(context, e));
    } finally {
      if (mounted) {
        setState(() {
          _working = false;
          _find = null;
          _use.clear();
        });
      }
    }
  }

  void _search(String v) {
    _deb?.cancel();
    if (v.trim().length < 2) {
      setState(() => _hits = []);
      return;
    }
    _deb = Timer(const Duration(milliseconds: 300), () async {
      try {
        final r = await pos.api('GET', '/members?q=${Uri.encodeQueryComponent(v.trim())}');
        if (mounted) setState(() => _hits = jlist(r['data']));
      } catch (_) {
        if (mounted) setState(() => _hits = []);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final m = _m;
    if (m == null || m['on'] != true) return const SizedBox.shrink();
    final t = tr(context);
    final c = context.c;
    final cur = pos.currency;
    final s = widget.stay;
    final live = GhPos.live.contains(s['status']);
    final member = m['member'] == null ? null : jmap(m['member']);
    final rules = jmap(m['rules']);
    final bill = jmap(s['bill']);
    double worth(num p) {
      final v = p / (nz(rules['redeem_points']) == 0 ? 1 : nz(rules['redeem_points'])) * nz(rules['redeem_value']);
      return cur == 'KHR' ? jsRound(v) : jsRound(v * 100) / 100;
    }

    final maxUse = member == null
        ? 0
        : [
            nz(member['points']).toInt(),
            ((nz(bill['balance']) < 0 ? 0 : nz(bill['balance'])) / (nz(rules['redeem_value']) == 0 ? 1 : nz(rules['redeem_value'])) * nz(rules['redeem_points'])).ceil(),
          ].reduce((a, b) => a < b ? a : b);
    final n = [nz(_use.text).toInt(), maxUse].reduce((a, b) => a < b ? a : b);
    return Container(
      margin: const EdgeInsets.only(top: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: c.active, borderRadius: BorderRadius.circular(16)),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(LucideIcons.gift, color: c.brandInk, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: member != null
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(js(member['name']), style: const TextStyle(fontWeight: FontWeight.w800)),
                          ),
                          const SizedBox(width: 8),
                          GhPill(t('gx.lyPoints', {'n': nz(member['points']).toInt()}), fg: c.good, bg: c.goodBg),
                          if (live && nz(m['used']) == 0 && !pos.readOnly)
                            IconButton(
                              visualDensity: VisualDensity.compact,
                              tooltip: t('gx.lyUnlink'),
                              onPressed: _working ? null : () => _run(() => pos.api('PUT', '/stays/${s['_id']}/customer', {'customer_id': null})),
                              icon: const Icon(LucideIcons.x, size: 15),
                            ),
                        ],
                      ),
                      if (nz(m['used']) > 0)
                        Row(
                          children: [
                            Flexible(child: Text(t('gx.lyUsed2', {'p': nz(m['used']).toInt(), 'v': ghMoney(m['value'], cur)}), style: const TextStyle(fontSize: 12.5))),
                            if (live && !pos.desk && !pos.readOnly)
                              TextButton.icon(
                                onPressed: _working ? null : () => _run(() => pos.api('DELETE', '/stays/${s['_id']}/points')),
                                icon: const Icon(LucideIcons.undo2, size: 14),
                                label: Text(t('gx.lyUndo')),
                              ),
                          ],
                        ),
                      if (nz(m['given']) > 0) Muted(t('gx.lyGiven', {'p': nz(m['given']).toInt()})),
                      if (live && nz(m['given']) == 0 && nz(bill['total']) > 0)
                        Muted(t('gx.lyWillEarn', {'p': (nz(bill['total']) / (nz(rules['unit']) == 0 ? 1 : nz(rules['unit'])) * nz(rules['earn'])).floor()})),
                      if (live && !pos.readOnly && maxUse > 0) ...[
                        const SizedBox(height: 6),
                        Row(
                          children: [
                            SizedBox(
                              width: 90,
                              child: Field(controller: _use, hint: '$maxUse', keyboard: TextInputType.number, onChanged: (_) => setState(() {})),
                            ),
                            const SizedBox(width: 8),
                            Flexible(
                              child: Btn(
                                n > 0 ? t('gx.lyUseBtn', {'p': n, 'v': ghMoney(worth(n), cur)}) : t('gx.lyUse'),
                                small: true,
                                busy: _working,
                                onTap: _working || n <= 0 ? null : () => _run(() => pos.api('POST', '/stays/${s['_id']}/points', {'points': n})),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ],
                  )
                : _find != null
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Field(controller: _q, hint: t('gx.lyFind'), icon: LucideIcons.search, autofocus: true, onChanged: _search),
                          ),
                          IconButton(onPressed: () => setState(() => _find = null), icon: const Icon(LucideIcons.x, size: 16)),
                        ],
                      ),
                      for (final h in _hits)
                        ListTile(
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          leading: const Icon(LucideIcons.userRound, size: 18),
                          title: Text(js(h['name']), style: const TextStyle(fontWeight: FontWeight.w700)),
                          subtitle: Text([js(h['phone']), js(h['email'])].where((x) => x.isNotEmpty).join(' · ')),
                          trailing: Text(t('gx.lyPoints', {'n': nz(h['points']).toInt()})),
                          onTap: _working ? null : () => _run(() => pos.api('PUT', '/stays/${s['_id']}/customer', {'customer_id': h['_id']})),
                        ),
                    ],
                  )
                : Row(
                    children: [
                      Expanded(child: Muted(t('gx.lyMember'))),
                      if (live && !pos.readOnly)
                        TextButton.icon(
                          onPressed: () {
                            final ph = js(jmap(s['guest'])['phone']);
                            _q.text = ph;
                            setState(() => _find = ph);
                            _search(ph);
                          },
                          icon: const Icon(LucideIcons.link2, size: 15),
                          label: Text(t('gx.lyLink')),
                        ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}
