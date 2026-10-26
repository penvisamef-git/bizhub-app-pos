import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/app_state.dart';
import '../../core/format.dart';
import '../../core/theme.dart';
import '../../widgets/ui.dart';
import 'ts_api.dart';

// Telegram Store staff screen — one order card (the web's dashboard OrderCard / the owner app's TsOrderCard, same words)
// and the order sound.

String tsMoney(Object? v, [String cur = 'USD']) => money(v, cur.isEmpty ? 'USD' : cur);

String tsAgo(Object? v) {
  final d = DateTime.tryParse('${v ?? ''}');
  if (d == null) return '';
  final s = DateTime.now().difference(d).inSeconds;
  if (s < 60) return tsm('justNow');
  if (s < 3600) return tsm('minAgo', {'n': s ~/ 60});
  if (s < 86400) return tsm('hAgo', {'n': s ~/ 3600});
  return tsm('dAgo', {'n': s ~/ 86400});
}

Future<void> tsOpen(String url) async {
  final u = Uri.tryParse(url);
  if (u != null) await launchUrl(u, mode: LaunchMode.externalApplication);
}

const tsModeIcons = <String, IconData>{'delivery': LucideIcons.bike, 'pickup': LucideIcons.shoppingBag, 'dine_in': LucideIcons.utensilsCrossed};

Tone tsStatusTone(String s) => switch (s) {
  'new' => Tone.brand,
  'accepted' => Tone.warn,
  'ready' || 'on_way' => Tone.lime,
  'done' => Tone.good,
  'cancelled' => Tone.danger,
  _ => Tone.muted,
};

// the two-note chime (assets/sounds/ts_chime.wav, the same notes as the web) + a buzz
class TsSound {
  static bool off = false; // tests
  static AudioPlayer? _p;
  static Future<void> chime() async {
    if (off) return;
    HapticFeedback.heavyImpact();
    try {
      final p = _p ??= AudioPlayer()..setReleaseMode(ReleaseMode.stop);
      await p.stop();
      await p.play(AssetSource('sounds/ts_chime.wav'), volume: 1);
    } catch (_) {
      // no sound on this device: the buzz and the banner still tell the staff
    }
  }
}

// act(order, status, extra) — status 'paid' marks it paid, 'riders' sends it to the riders' group
typedef TsAct = Future<void> Function(Json o, String status, [Json extra]);

class TsOrderCard extends StatelessWidget {
  final Json o;
  final bool readOnly, ridersOn, busy;
  final TsAct act;
  final Widget? extra; // Print
  const TsOrderCard({super.key, required this.o, required this.act, this.readOnly = false, this.ridersOn = false, this.busy = false, this.extra});

  @override
  Widget build(BuildContext context) {
    AppScope.of(context);
    final c = context.c;
    final cur = str(o['currency']);
    final status = str(o['status']);
    final mode = str(o['mode']);
    final pay = obj(o['pay']);
    final payName = pay['method'] == 'custom' ? str(obj(pay['custom'])['name']) : tsm('payMethods.${pay['method']}');
    final open = !['done', 'cancelled'].contains(status);
    final who = obj(o['customer']);
    final zone = o['zone'] is Map ? obj(o['zone']) : null;
    final rider = o['rider'] is Map ? obj(o['rider']) : null;
    final off = readOnly || busy;
    Widget b(String key, String label, VoidCallback fn, {bool primary = false, IconData? icon}) =>
        Btn(label, icon: icon, small: true, kind: primary ? BtnKind.primary : BtnKind.ghost, onTap: off ? null : fn, key: ValueKey('ts-o${o['no']}-$key'));
    Future<void> reject() async {
      final why = await _askReason(context);
      if (why != null) await act(o, 'cancelled', {'reason': why});
    }

    final body = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          spacing: 6,
          runSpacing: 6,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text('#${o['no']}', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 20)),
            Chip2(tsm('statuses.$status'), tone: tsStatusTone(status)),
            Chip2('${tsm('modes.$mode')}${mode == 'dine_in' && str(o['table']).isNotEmpty ? ' ${o['table']}' : ''}', icon: tsModeIcons[mode]),
            Chip2(
              '$payName · ${tsm('payStates.${pay['status']}')}',
              icon: LucideIcons.circleDollarSign,
              tone: pay['status'] == 'paid' ? Tone.good : (pay['status'] == 'proof' ? Tone.warn : Tone.muted),
            ),
            if (o['from_remind'] == true) Chip2(tsm('wonBack'), icon: LucideIcons.shoppingCart, tone: Tone.warn),
            Text('${fmtTime(o['created_date'])} · ${tsAgo(o['created_date'])}', style: TextStyle(fontSize: 12, color: c.muted)),
          ],
        ),
        const SizedBox(height: 10),
        for (final l in objs(o['items']))
          Padding(
            padding: const EdgeInsets.only(bottom: 5),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Text.rich(
                    TextSpan(
                      style: const TextStyle(fontSize: 15),
                      children: [
                        TextSpan(
                          text: '${fmt(n(l['qty']))} × ',
                          style: const TextStyle(fontWeight: FontWeight.w800),
                        ),
                        TextSpan(
                          text: str(l['name']),
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                        if (objs(l['options']).isNotEmpty)
                          TextSpan(
                            text: ' · ${objs(l['options']).map((x) => str(x['choice'])).join(', ')}',
                            style: TextStyle(color: c.muted, fontSize: 13),
                          ),
                        if (str(l['note']).isNotEmpty)
                          TextSpan(
                            text: ' — ${l['note']}',
                            style: TextStyle(color: c.muted, fontStyle: FontStyle.italic, fontSize: 13),
                          ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Text(tsMoney(l['total'], cur)),
              ],
            ),
          ),
        if (n(o['discount']) > 0) _sum(context, '🏷 ${tsm('discount', {'code': o['promo']})}', '−${tsMoney(o['discount'], cur)}', muted: true),
        if (n(o['fee']) > 0) _sum(context, tsm('deliveryFee'), tsMoney(o['fee'], cur), muted: true),
        Divider(height: 14, color: c.line),
        _sum(context, tsm('total'), tsMoney(o['total'], cur), bold: true),
        const SizedBox(height: 6),
        Wrap(
          spacing: 12,
          runSpacing: 4,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            if (str(who['name']).isNotEmpty) Text(str(who['name']), style: const TextStyle(fontWeight: FontWeight.w800)),
            if (str(who['phone']).isNotEmpty)
              InkWell(
                onTap: () => tsOpen('tel:${who['phone']}'),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(LucideIcons.phone, size: 13, color: c.brand),
                    const SizedBox(width: 4),
                    Text(str(who['phone']), style: TextStyle(color: c.brand)),
                  ],
                ),
              ),
            if (str(who['username']).isNotEmpty)
              InkWell(
                onTap: () => tsOpen('https://t.me/${who['username']}'),
                child: Text('@${who['username']}', style: TextStyle(color: c.brand)),
              ),
            Text(o['via'] == 'telegram' ? tsm('viaTelegram') : tsm('viaWeb'), style: TextStyle(color: c.muted, fontSize: 12.5)),
          ],
        ),
        if (mode == 'delivery' && str(o['address']).isNotEmpty) _Line(LucideIcons.mapPin, str(o['address'])),
        if (mode == 'delivery' && zone != null)
          _Line(
            LucideIcons.map,
            [if (str(zone['name']).isNotEmpty && !str(zone['name']).endsWith(' km')) str(zone['name']), if (zone['km'] != null) '${zone['km']} km'].join(' · '),
            trailing: zone['lat'] == null
                ? null
                : InkWell(
                    onTap: () => tsOpen('https://maps.google.com/?q=${zone['lat']},${zone['lng']}'),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(LucideIcons.externalLink, size: 12, color: c.brand),
                        const SizedBox(width: 3),
                        Text(
                          tsm('openMap'),
                          style: TextStyle(color: c.brand, fontWeight: FontWeight.w700, fontSize: 13),
                        ),
                      ],
                    ),
                  ),
          ),
        if (rider != null)
          _Line(
            LucideIcons.bike,
            '${rider['name']}${str(rider['username']).isNotEmpty ? ' @${rider['username']}' : ''} · ${rider['delivered_at'] != null ? tsm('riderDone') : (rider['picked_at'] != null ? tsm('riderPicked') : tsm('riderTook'))} · ${fmtTime(rider['delivered_at'] ?? rider['picked_at'] ?? rider['taken_at'])}',
          ),
        if (mode == 'delivery' && rider == null && o['riders_sent'] == true && open) _Line(LucideIcons.bike, tsm('ridersWaiting'), color: c.muted),
        if (str(o['note']).isNotEmpty) _Line(LucideIcons.messageSquareText, str(o['note']), color: c.warn),
        if (status == 'accepted' && n(o['eta_min']) > 0) _Line(LucideIcons.clock, tsm('eta', {'n': o['eta_min']})),
        if (status == 'cancelled' && str(o['reason']).isNotEmpty) _Line(LucideIcons.x, str(o['reason']), color: c.danger),
        if (open || str(pay['proof']).isNotEmpty || pay['status'] != 'paid' || extra != null) ...[
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              if (status == 'new') ...[
                b('accept', tsm('accept'), () => act(o, 'accepted'), primary: true, icon: LucideIcons.check),
                b('eta15', tsm('min', {'n': 15}), () => act(o, 'accepted', {'eta': 15}), icon: LucideIcons.clock),
                b('eta30', tsm('min', {'n': 30}), () => act(o, 'accepted', {'eta': 30}), icon: LucideIcons.clock),
                b('reject', tsm('reject'), reject, icon: LucideIcons.x),
              ],
              if (status == 'accepted' && mode != 'delivery') b('ready', tsm('ready'), () => act(o, 'ready'), primary: true),
              if (status == 'accepted' && mode == 'delivery') b('on_way', tsm('onWay'), () => act(o, 'on_way'), primary: true, icon: LucideIcons.bike),
              if (['accepted', 'ready', 'on_way'].contains(status)) b('done', tsm('doneBtn'), () => act(o, 'done'), primary: status != 'accepted', icon: LucideIcons.check),
              if (pay['status'] != 'paid' && status != 'cancelled') b('paid', tsm('markPaid'), () => act(o, 'paid'), icon: LucideIcons.circleDollarSign),
              if (mode == 'delivery' && ['accepted', 'ready'].contains(status) && o['riders_sent'] != true && ridersOn) b('riders', tsm('toRiders'), () => act(o, 'riders'), icon: LucideIcons.send),
              if (str(pay['proof']).isNotEmpty) Btn(tsm('seeProof'), icon: LucideIcons.image, small: true, kind: BtnKind.ghost, onTap: () => _proof(context, str(pay['proof']))),
              ?extra,
            ],
          ),
        ],
      ],
    );
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: c.card,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: status == 'new' ? c.brand : c.line, width: status == 'new' ? 2 : 1),
        boxShadow: status == 'new' ? c.cardShadow : null,
      ),
      child: busy
          ? Stack(
              children: [
                body,
                const Positioned.fill(child: Center(child: CircularProgressIndicator())),
              ],
            )
          : body,
    );
  }

  Widget _sum(BuildContext context, String a, String b, {bool bold = false, bool muted = false}) {
    final c = context.c;
    final st = TextStyle(fontWeight: bold ? FontWeight.w800 : FontWeight.w500, color: muted ? c.muted : c.ink, fontSize: bold ? 15.5 : 14);
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: Row(
        children: [
          Expanded(child: Text(a, style: st)),
          Text(b, style: st),
        ],
      ),
    );
  }

  Future<String?> _askReason(BuildContext context) {
    final ctl = TextEditingController();
    final t = AppState.i.t;
    return showDialog<String>(
      context: context,
      builder: (d) => AlertDialog(
        title: Text(tsm('rejectAsk')),
        content: TextField(
          controller: ctl,
          autofocus: true,
          maxLength: 200,
          maxLines: 2,
          decoration: InputDecoration(hintText: tsm('rejectPh')),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(d), child: Text(t('app.cancel'))),
          TextButton(
            onPressed: () => Navigator.pop(d, ctl.text.trim()),
            child: Text(tsm('reject'), style: TextStyle(color: d.c.danger)),
          ),
        ],
      ),
    ).whenComplete(ctl.dispose);
  }

  void _proof(BuildContext context, String url) => showDialog<void>(
    context: context,
    builder: (d) => Dialog(
      backgroundColor: Colors.black,
      insetPadding: const EdgeInsets.all(12),
      child: GestureDetector(
        onTap: () => Navigator.pop(d),
        child: InteractiveViewer(child: Image(image: netImage(url))),
      ),
    ),
  );
}

class _Line extends StatelessWidget {
  final IconData icon;
  final String text;
  final Color? color;
  final Widget? trailing;
  const _Line(this.icon, this.text, {this.color, this.trailing});
  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Icon(icon, size: 14, color: color ?? c.muted),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(text, style: TextStyle(fontSize: 13.5, color: color ?? c.ink)),
          ),
          ?trailing,
        ],
      ),
    );
  }
}
