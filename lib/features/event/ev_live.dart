import 'dart:async';

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/app_state.dart';
import '../../core/format.dart';
import '../../core/theme.dart';
import '../../widgets/ui.dart';
import 'ev_api.dart';
import 'ev_ctl.dart';

// Live (web: LiveTab.jsx): the clock, how full it is, how fast people come in, by ticket type, money (manager),
// what this phone did today, online / waiting scans
class EvLiveTab extends StatefulWidget {
  final EvCtl ctl;
  final ValueChanged<String> onGo;
  const EvLiveTab({super.key, required this.ctl, required this.onGo});
  @override
  State<EvLiveTab> createState() => _EvLiveTabState();
}

class _EvLiveTabState extends State<EvLiveTab> {
  Timer? _tick;
  DateTime _now = DateTime.now();

  @override
  void initState() {
    super.initState();
    _tick = Timer.periodic(const Duration(seconds: 1), (_) => setState(() => _now = DateTime.now()));
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final ctl = widget.ctl;
    final lang = AppState.i.lang;
    final e = ctl.event;
    final info = ctl.info;
    final hist = ctl.hist;
    final used = ctl.used, total = ctl.total;
    final left = (total - used).clamp(0, 1 << 30);
    final pct = total == 0 ? 0 : (used * 100 / total).round();
    final show = objs(e['shows']).where((s) => s['key'] == ctl.show).firstOrNull;
    final start = show?['starts_at'] ?? e['starts_at'];
    final nowMs = _now.millisecondsSinceEpoch;
    bool today(Json h) {
      final d = DateTime.fromMillisecondsSinceEpoch(n(h['at']).toInt());
      return d.year == _now.year && d.month == _now.month && d.day == _now.day;
    }

    final ok15 = hist.where((h) => h['kind'] == 'ok' && nowMs - n(h['at']) < 15 * 60000).length;
    final mineOk = hist.where((h) => h['kind'] == 'ok' && today(h)).length;
    final refused = hist.where((h) => h['kind'] != 'ok' && today(h)).length;
    final perHour = ok15 * 4;
    final eta = perHour > 0 && left > 0 ? (left / perHour * 60).round() : 0;
    final counts = obj(info?['counts']);
    final byType = objs(info?['by_type']);
    String two(int x) => x.toString().padLeft(2, '0');

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
      children: [
        Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 640),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _Card(
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '${two(_now.hour)}:${two(_now.minute)}:${two(_now.second)}',
                              style: const TextStyle(fontSize: 30, fontWeight: FontWeight.w800, height: 1.1, fontFeatures: [FontFeature.tabularFigures()]),
                            ),
                            Text(fmtToday(lang), style: TextStyle(color: c.muted, fontSize: 13)),
                          ],
                        ),
                      ),
                      Flexible(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [_IconText(LucideIcons.clock, '${fmtTime(start)} · ${evSpan(start, _now)}'), if (str(e['venue']).isNotEmpty) _IconText(LucideIcons.mapPin, str(e['venue']))],
                        ),
                      ),
                    ],
                  ),
                ),
                _Card(
                  child: Row(
                    children: [
                      SizedBox(
                        width: 128,
                        height: 128,
                        child: Stack(
                          fit: StackFit.expand,
                          children: [
                            CircularProgressIndicator(value: pct / 100, strokeWidth: 12, backgroundColor: c.chip, color: c.good, strokeCap: StrokeCap.round),
                            Center(
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text('$pct%', style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w800, height: 1.1)),
                                  Text(ev('inside'), style: TextStyle(color: c.muted, fontSize: 12)),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 18),
                      Expanded(child: Column(children: [_Num(ev('inside'), '$used'), _Num(ev('notYet'), '$left'), _Num(ev('soldN'), '$total')])),
                    ],
                  ),
                ),
                _Card(
                  title: ev('pace'),
                  icon: LucideIcons.trendingUp,
                  child: Row(children: [_Stat('$ok15', ev('last15')), _Stat('$perHour', ev('perHour')), _Stat(eta == 0 ? '—' : (eta < 60 ? '$eta′' : '${eta ~/ 60} h ${two(eta % 60)}'), ev('eta'))]),
                ),
                if (byType.isNotEmpty)
                  _Card(
                    title: ev('byType'),
                    icon: LucideIcons.ticket,
                    child: Column(
                      children: [
                        for (final ty in byType)
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 5),
                            child: Row(
                              children: [
                                SizedBox(
                                  width: 110,
                                  child: Text(
                                    str(ty['name']),
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(fontWeight: FontWeight.w600),
                                  ),
                                ),
                                Expanded(
                                  child: ClipRRect(
                                    borderRadius: BorderRadius.circular(9),
                                    child: LinearProgressIndicator(
                                      value: n(ty['sold']) == 0 ? 0 : n(ty['used']) / n(ty['sold']),
                                      minHeight: 8,
                                      backgroundColor: c.chip,
                                      color: _hex(str(ty['color'])) ?? c.brand,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Text('${n(ty['used']).toInt()}/${n(ty['sold']).toInt()}', style: const TextStyle(fontWeight: FontWeight.w800)),
                              ],
                            ),
                          ),
                      ],
                    ),
                  ),
                if (ctl.manager && info != null)
                  _Card(
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(ev('money'), style: TextStyle(color: c.muted, fontSize: 13)),
                              Text(usd(counts['money']), style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800)),
                            ],
                          ),
                        ),
                        Btn(
                          ev('toCheck', {'n': n(counts['review']).toInt()}),
                          icon: LucideIcons.receiptText,
                          small: true,
                          kind: n(counts['review']) > 0 ? BtnKind.primary : BtnKind.ghost,
                          onTap: () => widget.onGo('orders'),
                        ),
                      ],
                    ),
                  ),
                _Card(
                  title: ev('thisPhone'),
                  icon: LucideIcons.users,
                  child: Column(
                    children: [
                      Row(
                        children: [
                          _Stat('$mineOk', ev('letIn'), color: c.good),
                          _Stat('$refused', ev('refused'), color: c.danger),
                          _Stat('${ctl.codes.length}', ev('offlineReady')),
                        ],
                      ),
                      const SizedBox(height: 10),
                      if (hist.isEmpty)
                        Align(alignment: Alignment.centerLeft, child: Muted(ev('noScansYet')))
                      else
                        for (final h in hist.take(12))
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 6),
                            child: Row(
                              children: [
                                Icon(h['kind'] == 'ok' ? LucideIcons.circleCheck : LucideIcons.circleX, size: 18, color: h['kind'] == 'ok' ? c.good : c.danger),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        str(h['holder']).isNotEmpty ? str(h['holder']) : (str(h['code']).isNotEmpty ? str(h['code']) : '—'),
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(fontWeight: FontWeight.w700),
                                      ),
                                      Text(
                                        [str(h['type']), str(h['seat']), if (h['kind'] != 'ok') AppState.i.t.or('evd.kinds.${h['kind']}', str(h['kind']))].where((x) => x.isNotEmpty).join(' · '),
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(color: c.muted, fontSize: 12.5),
                                      ),
                                    ],
                                  ),
                                ),
                                Text(fmtTime(DateTime.fromMillisecondsSinceEpoch(n(h['at']).toInt()).toUtc().toIso8601String()), style: TextStyle(color: c.muted, fontSize: 12.5)),
                              ],
                            ),
                          ),
                    ],
                  ),
                ),
                _Card(
                  child: Wrap(
                    spacing: 16,
                    runSpacing: 8,
                    children: [
                      _IconText(ctl.online ? LucideIcons.wifi : LucideIcons.cloudOff, ctl.online ? ev('online') : ev('offline'), color: ctl.online ? c.good : c.danger),
                      _IconText(LucideIcons.shieldCheck, ctl.queue.isNotEmpty ? ev('queued', {'n': ctl.queue.length}) : ev('allSent')),
                      if (ctl.lastSync != null) _IconText(LucideIcons.clock, ev('updatedAt', {'t': fmtTime(ctl.lastSync!.toUtc().toIso8601String())})),
                      _IconText(LucideIcons.smartphone, '${str(obj(ctl.boot['device'])['name']).isEmpty ? '—' : str(obj(ctl.boot['device'])['name'])} · ${ctl.me}'),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

Color? _hex(String s) {
  final m = RegExp(r'^#?([0-9a-fA-F]{6})$').firstMatch(s);
  return m == null ? null : Color(int.parse('FF${m[1]}', radix: 16));
}

class _Card extends StatelessWidget {
  final Widget child;
  final String? title;
  final IconData? icon;
  const _Card({required this.child, this.title, this.icon});
  @override
  Widget build(BuildContext context) => Panel(
    margin: const EdgeInsets.only(bottom: 12),
    padding: const EdgeInsets.all(16),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (title != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Row(
              children: [
                Icon(icon, size: 16, color: context.c.brandInk),
                const SizedBox(width: 8),
                Text(title!, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
              ],
            ),
          ),
        child,
      ],
    ),
  );
}

class _Num extends StatelessWidget {
  final String label, value;
  const _Num(this.label, this.value);
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 5),
    child: Row(
      children: [
        Expanded(
          child: Text(label, style: TextStyle(color: context.c.muted)),
        ),
        Text(value, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 18)),
      ],
    ),
  );
}

class _Stat extends StatelessWidget {
  final String value, label;
  final Color? color;
  const _Stat(this.value, this.label, {this.color});
  @override
  Widget build(BuildContext context) => Expanded(
    child: Column(
      children: [
        Text(
          value,
          style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: color),
        ),
        Text(
          label,
          textAlign: TextAlign.center,
          style: TextStyle(color: context.c.muted, fontSize: 12, height: 1.3),
        ),
      ],
    ),
  );
}

class _IconText extends StatelessWidget {
  final IconData icon;
  final String text;
  final Color? color;
  const _IconText(this.icon, this.text, {this.color});
  @override
  Widget build(BuildContext context) {
    final col = color ?? context.c.muted;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: col),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              text,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: col, fontSize: 13, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }
}
