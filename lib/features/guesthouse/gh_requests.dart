import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/theme.dart';
import '../../widgets/ui.dart';
import '../restaurant/engine/calc.dart' show J, jmap, jlist, js, nz;
import '../restaurant/pos_ui.dart';
import 'engine/gh_pos.dart';
import 'gh_ui.dart';

// Website booking requests (customer accounts) — the web's GhRequests.jsx: the ringing band + the list (accept → a room, or decline)

class GhRequestAlert extends StatelessWidget {
  final VoidCallback onOpen;
  const GhRequestAlert({super.key, required this.onOpen});
  @override
  Widget build(BuildContext context) {
    final pos = GhPos.i;
    if (pos.newRequests == 0) return const SizedBox.shrink();
    final t = tr(context);
    final c = context.c;
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 0, 12, 8),
      padding: const EdgeInsets.fromLTRB(14, 6, 6, 6),
      decoration: BoxDecoration(
        color: c.warnBg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: c.warn),
      ),
      child: Row(
        children: [
          Icon(LucideIcons.bellRing, color: c.warn),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              pos.newRequests == 1 ? t('gc.alertOne') : t('gc.alertMany', {'n': pos.newRequests}),
              style: TextStyle(color: c.warn, fontWeight: FontWeight.w800),
            ),
          ),
          if (!pos.ringMuted) TextButton(onPressed: pos.muteRequests, child: Text(t('gc.alertMute'))),
          Btn(t('gc.alertOpen'), small: true, onTap: onOpen),
        ],
      ),
    );
  }
}

Future<void> openRequests(BuildContext context) => posSheet<void>(context, title: tr(context)('gc.sheetTitle'), maxWidth: 720, body: (_) => const _RequestList());

class _RequestList extends StatefulWidget {
  const _RequestList();
  @override
  State<_RequestList> createState() => _RequestListState();
}

class _RequestListState extends State<_RequestList> {
  final pos = GhPos.i;
  String _status = 'pending';
  List<J>? _rows;
  int _page = 1, _pages = 1;
  String _error = '';

  @override
  void initState() {
    super.initState();
    _load(1);
  }

  Future<void> _load(int p) async {
    if (p == 1) setState(() => _rows = null);
    try {
      final r = await pos.api('GET', '/cust-requests?status=${_status == 'all' ? '' : _status}&page=$p');
      if (!mounted) return;
      setState(() {
        _rows = p == 1 ? jlist(r['data']) : [...?_rows, ...jlist(r['data'])];
        _page = p;
        _pages = nz(jmap(r['pagination'])['totalPages']).toInt();
        _error = '';
      });
    } catch (e) {
      if (mounted) setState(() => _error = ghErr(context, e));
    }
  }

  void _changed() {
    _load(1);
    pos.checkRequests();
    pos.syncNow();
  }

  @override
  Widget build(BuildContext context) {
    final t = tr(context);
    final c = context.c;
    final cur = pos.currency;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        PosChips<String>(
          value: _status,
          onTap: (v) {
            _status = v;
            _load(1);
          },
          options: [('pending', t('gc.pending')), ('all', t('gc.all'))],
        ),
        const SizedBox(height: 10),
        if (_error.isNotEmpty) Alert(_error, tone: Tone.warn),
        if (_rows == null && _error.isEmpty)
          const Padding(
            padding: EdgeInsets.all(30),
            child: Center(child: CircularProgressIndicator()),
          )
        else if (_rows != null && _rows!.isEmpty)
          Padding(
            padding: const EdgeInsets.all(24),
            child: Muted(t('gc.none'), align: TextAlign.center),
          )
        else if (_rows != null) ...[
          for (final r in _rows!)
            () {
              final st = js(r['status']);
              final cu = jmap(r['customer']);
              final (fg, bg) = switch (st) {
                'pending' => (c.warn, c.warnBg),
                'accepted' => (c.good, c.goodBg),
                _ => (c.danger, c.dangerBg),
              };
              final proof = js(jmap(r['pay_proof'])['url']).isNotEmpty ? js(jmap(r['pay_proof'])['url']) : js(r['proof']);
              return Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: c.card,
                  borderRadius: BorderRadius.circular(16),
                  border: st == 'pending' ? Border.all(color: c.warn) : null,
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 74,
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(color: c.active, borderRadius: BorderRadius.circular(12)),
                      child: Column(
                        children: [
                          Text(
                            ghDay(js(r['from'])),
                            style: TextStyle(fontWeight: FontWeight.w800, color: c.brandInk),
                          ),
                          Text('→ ${ghDay(js(r['to']))}', style: TextStyle(fontSize: 11.5, color: c.brandInk)),
                          Text(t('gc.nights', {'n': nz(r['nights']).toInt()}), style: TextStyle(fontSize: 11, color: c.muted)),
                        ],
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(js(cu['name']).isEmpty ? '—' : js(cu['name']), style: const TextStyle(fontWeight: FontWeight.w800)),
                              ),
                              GhPill(t('gc.states.$st'), fg: fg, bg: bg),
                            ],
                          ),
                          Text(
                            '${js(r['type_name'])}${js(jmap(r['stay'])['room']).isNotEmpty ? ' · ${t('gc.room', {'r': js(jmap(r['stay'])['room'])})}' : ''} · ${t('gc.guests', {
                              'a': nz(r['adults']).toInt(),
                              'c': nz(r['children']) > 0 ? t('gc.kids', {'n': nz(r['children']).toInt()}) : '',
                            })}',
                            style: const TextStyle(fontSize: 13),
                          ),
                          if (js(cu['phone']).isNotEmpty)
                            InkWell(
                              onTap: () => launchUrl(Uri.parse('tel:${js(cu['phone']).replaceAll(RegExp(r'[^\d+]'), '')}')),
                              child: Text('📞 ${js(cu['phone'])}${js(cu['email']).isNotEmpty ? '  ✉ ${js(cu['email'])}' : ''}', style: TextStyle(color: c.brandInk, fontSize: 12.5)),
                            ),
                          const SizedBox(height: 4),
                          Row(
                            children: [
                              GhPill(
                                r['pay_method'] == 'qr' ? '${t('gc.paidQr')}${nz(r['estimate']) > 0 ? ' · ${ghMoney(r['estimate'], cur)}' : ''}' : t('gc.payCash'),
                                fg: r['pay_method'] == 'qr' ? c.good : c.muted,
                                bg: r['pay_method'] == 'qr' ? c.goodBg : c.chip,
                              ),
                              if (proof.isNotEmpty) ...[
                                const SizedBox(width: 6),
                                InkWell(
                                  onTap: () => launchUrl(Uri.parse(proof), mode: LaunchMode.externalApplication),
                                  child: ClipRRect(
                                    borderRadius: BorderRadius.circular(6),
                                    child: Image(image: netImage(proof), width: 34, height: 34, fit: BoxFit.cover, errorBuilder: (_, _, _) => const Icon(LucideIcons.image)),
                                  ),
                                ),
                              ],
                            ],
                          ),
                          if (js(r['note']).isNotEmpty)
                            Padding(
                              padding: const EdgeInsets.only(top: 4),
                              child: Text('“${js(r['note'])}”', style: const TextStyle(fontStyle: FontStyle.italic)),
                            ),
                          Text(
                            [
                              if (nz(r['estimate']) > 0) t('gc.estimate', {'v': ghMoney(r['estimate'], cur)}),
                              ghTime(r['created_date']),
                              if (js(r['decided_by']).isNotEmpty) t('gc.by', {'name': js(r['decided_by'])}),
                              js(r['reason']),
                            ].where((s) => s.isNotEmpty).join(' · '),
                            style: TextStyle(color: c.muted, fontSize: 11.5),
                          ),
                          if (st == 'pending' && !pos.readOnly) ...[
                            const SizedBox(height: 8),
                            Row(
                              children: [
                                Btn(t('gc.accept'), icon: LucideIcons.check, small: true, onTap: () => _accept(context, r)),
                                const SizedBox(width: 8),
                                TextButton.icon(
                                  style: TextButton.styleFrom(foregroundColor: c.danger),
                                  onPressed: () => _decline(context, r),
                                  icon: const Icon(LucideIcons.x, size: 16),
                                  label: Text(t('gc.decline')),
                                ),
                              ],
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
              );
            }(),
          if (_page < _pages) OutlinedButton(onPressed: () => _load(_page + 1), child: Text(t('gc.more'))),
        ],
      ],
    );
  }

  Future<void> _accept(BuildContext context, J row) async {
    final t = tr(context);
    final cur = pos.currency;
    List<J> rooms = [];
    var asked = false, loaded = false;
    String pick = '';
    var record = true;
    var busy = false;
    var error = '';
    final ok = await posSheet<bool>(
      context,
      title: '${t('gc.accept')} · ${js(jmap(row['customer'])['name'])}',
      maxWidth: 520,
      body: (ctx) => StatefulBuilder(
        builder: (ctx, set) {
          if (!asked) {
            asked = true;
            pos.api('GET', '/cust-requests/${row['_id']}/rooms').then((r) {
              set(() {
                rooms = jlist(r['data']);
                loaded = true;
                pick = rooms.isEmpty ? '' : js(rooms.first['_id']);
              });
            }, onError: (e) => set(() => error = ghErr(ctx, e)));
          }
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                '${js(row['type_name'])} · ${ghDay(js(row['from']))} → ${ghDay(js(row['to']))} · ${t('gc.nights', {'n': nz(row['nights']).toInt()})}',
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 10),
              Muted(t('gc.pickRoom')),
              const SizedBox(height: 6),
              if (!loaded && error.isEmpty) const LinearProgressIndicator(),
              if (loaded && rooms.isEmpty) Muted(t('gc.noFree')),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final r in rooms)
                    ChoiceChip(
                      avatar: const Icon(LucideIcons.bedDouble, size: 16),
                      label: Text('${js(r['name'])}${js(r['floor']).isNotEmpty ? ' · ${js(r['floor'])}' : ''}'),
                      selected: pick == js(r['_id']),
                      showCheckmark: false,
                      onSelected: (_) => set(() => pick = js(r['_id'])),
                    ),
                ],
              ),
              if (row['pay_method'] == 'qr') ...[
                const SizedBox(height: 10),
                Muted(t('gc.checkProof')),
                if (nz(row['estimate']) > 0)
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    value: record,
                    onChanged: (v) => set(() => record = v ?? false),
                    title: Text(t('gc.recordPay', {'v': ghMoney(row['estimate'], cur)})),
                  ),
              ],
              if (error.isNotEmpty) ...[const SizedBox(height: 8), Alert(error)],
              const SizedBox(height: 12),
              Btn(
                t('gc.accept'),
                icon: LucideIcons.check,
                busy: busy,
                expand: true,
                onTap: busy || pick.isEmpty
                    ? null
                    : () async {
                        set(() => busy = true);
                        try {
                          await pos.api('POST', '/cust-requests/${row['_id']}/accept', {'room_id': pick, 'record_payment': record});
                          if (ctx.mounted) Navigator.pop(ctx, true);
                        } catch (e) {
                          set(() {
                            busy = false;
                            error = ghErr(ctx, e);
                          });
                        }
                      },
              ),
            ],
          );
        },
      ),
    );
    if (ok == true) {
      if (context.mounted) ghToast(context, t('gc.states.accepted'));
      _changed();
    }
  }

  Future<void> _decline(BuildContext context, J row) async {
    final t = tr(context);
    final reason = TextEditingController();
    var busy = false;
    var error = '';
    final ok = await posSheet<bool>(
      context,
      title: '${t('gc.decline')} · ${js(jmap(row['customer'])['name'])}',
      maxWidth: 460,
      body: (ctx) => StatefulBuilder(
        builder: (ctx, set) => Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Field(controller: reason, label: t('gc.reason'), hint: t('gc.reasonPh'), maxLength: 200, autofocus: true),
            if (error.isNotEmpty) ...[const SizedBox(height: 8), Alert(error)],
            const SizedBox(height: 12),
            Btn(
              t('gc.decline'),
              kind: BtnKind.danger,
              busy: busy,
              expand: true,
              onTap: busy
                  ? null
                  : () async {
                      set(() => busy = true);
                      try {
                        await pos.api('POST', '/cust-requests/${row['_id']}/decline', {'reason': reason.text.trim()});
                        if (ctx.mounted) Navigator.pop(ctx, true);
                      } catch (e) {
                        set(() {
                          busy = false;
                          error = ghErr(ctx, e);
                        });
                      }
                    },
            ),
          ],
        ),
      ),
    );
    if (ok == true) {
      if (context.mounted) ghToast(context, t('gc.states.declined'));
      _changed();
    }
  }
}
