import 'dart:async';

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../../core/app_state.dart';
import '../../core/config.dart';
import '../../core/theme.dart';
import '../../widgets/ui.dart';
import 'att_api.dart';

// The door tablet (att_kiosk, like the web's /k/<token>): a QR that changes every 20 s.
// Staff scan it with their phone → …/a/<code>?k=… → clocked in at this branch, no GPS needed.
class AttKioskRoot extends StatefulWidget {
  const AttKioskRoot({super.key});
  @override
  State<AttKioskRoot> createState() => _AttKioskRootState();
}

class _AttKioskRootState extends State<AttKioskRoot> {
  Json? _d;
  String _err = ''; // off | net
  int _offset = 0; // server clock − tablet clock (ms)
  DateTime _nextAt = DateTime.now();
  Timer? _load, _tick;

  String get _token => AppState.i.token;

  @override
  void initState() {
    super.initState();
    WakelockPlus.enable().catchError((_) {});
    _fetch();
    _tick = Timer.periodic(const Duration(milliseconds: 250), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _load?.cancel();
    _tick?.cancel();
    WakelockPlus.disable().catchError((_) {});
    super.dispose();
  }

  Future<void> _fetch() async {
    _load?.cancel();
    try {
      final d = obj(await AttApi().get('/kiosk/$_token'));
      if (!mounted) return;
      final left = (n(d['seconds_left']) > 0 ? n(d['seconds_left']) : 20).toInt();
      setState(() {
        _offset = (DateTime.tryParse(str(d['server_time']))?.millisecondsSinceEpoch ?? DateTime.now().millisecondsSinceEpoch) - DateTime.now().millisecondsSinceEpoch;
        _nextAt = DateTime.now().add(Duration(seconds: left));
        _d = d;
        _err = '';
      });
      // right after the code changes, and every 5 s for the "just now" list
      _load = Timer(Duration(milliseconds: (left * 1000 + 300).clamp(300, 5000)), _fetch);
    } on ApiError catch (e) {
      if (!mounted) return;
      setState(() => _err = e.network ? 'net' : 'off');
      _load = Timer(Duration(seconds: e.network ? 5 : 30), _fetch);
    }
  }

  void _menu() {
    final app = AppState.i;
    final t = app.t;
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheet) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(str(app.link?['shop']), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 17)),
              const SizedBox(height: 4),
              Muted(t('att.keepAwake')),
              const SizedBox(height: 8),
              ListTile(
                leading: const Icon(LucideIcons.refreshCw),
                title: Text(t('att.refresh')),
                onTap: () {
                  Navigator.pop(sheet);
                  _fetch();
                },
              ),
              ListTile(
                leading: const Icon(LucideIcons.languages),
                title: Text(app.lang == 'km' ? 'English' : 'ខ្មែរ'),
                onTap: () {
                  Navigator.pop(sheet);
                  app.setLang(app.lang == 'km' ? 'en' : 'km');
                },
              ),
              ListTile(
                leading: const Icon(LucideIcons.sunMoon),
                title: Text(t('app.theme')),
                onTap: () {
                  Navigator.pop(sheet);
                  pickTheme(context);
                },
              ),
              ListTile(
                leading: Icon(LucideIcons.unplug, color: context.c.danger),
                title: Text(t('att.unlink'), style: TextStyle(color: context.c.danger)),
                onTap: () async {
                  Navigator.pop(sheet);
                  final ok = await showDialog<bool>(
                    context: context,
                    builder: (d) => AlertDialog(
                      content: Text(t('att.unlinkSure')),
                      actions: [
                        TextButton(onPressed: () => Navigator.pop(d, false), child: Text(t('att.cancel'))),
                        TextButton(onPressed: () => Navigator.pop(d, true), child: Text(t('att.unlink'))),
                      ],
                    ),
                  );
                  if (ok == true) app.unlink();
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final t = app.t;
    final c = context.c;
    final d = _d;
    if (d == null) {
      return Scaffold(
        backgroundColor: c.appBg,
        body: SafeArea(
          child: Stack(
            children: [
              Center(
                child: _err == 'off'
                    ? Padding(
                        padding: const EdgeInsets.all(28),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(LucideIcons.triangleAlert, size: 46, color: c.warn),
                            const SizedBox(height: 14),
                            Text(
                              t('attkp.off'),
                              textAlign: TextAlign.center,
                              style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600, height: 1.45),
                            ),
                          ],
                        ),
                      )
                    : _err == 'net'
                    ? Muted(t('attkp.net'))
                    : const CircularProgressIndicator(),
              ),
              Positioned(
                top: 8,
                right: 8,
                child: RoundBtn(LucideIcons.ellipsisVertical, onTap: _menu, tip: t('att.more')),
              ),
            ],
          ),
        ),
      );
    }
    final accent = hexColor(d['color'], const Color(0xFF0F766E));
    final now = khNow(_offset);
    final left = (_nextAt.difference(DateTime.now()).inMilliseconds / 1000).clamp(0, 999).toDouble();
    final frac = (left / (n(d['seconds']) > 0 ? n(d['seconds']) : 20)).clamp(0.0, 1.0);
    final link = '${Config.siteUrl}/a/${str(d['code'])}?k=${Uri.encodeComponent(str(d['k']))}';
    final recent = objs(d['recent']);
    final b = obj(d['business']);
    final logo = str(b['logo_url']);
    final hm = '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';
    final sec = now.second.toString().padLeft(2, '0');

    Widget brand(Color fg) => Row(
      children: [
        Container(
          width: 52,
          height: 52,
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16)),
          child: logo.isNotEmpty ? Image(image: netImage(logo), fit: BoxFit.cover) : Icon(LucideIcons.fingerprintPattern, color: accent, size: 28),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                str(b['name']),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: fg, fontWeight: FontWeight.w800, fontSize: 19),
              ),
              Text(
                str(obj(d['branch'])['name']),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: fg.withValues(alpha: .8), fontSize: 14),
              ),
            ],
          ),
        ),
      ],
    );
    Widget clock(Color fg, double size) => Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Text(
              hm,
              style: TextStyle(color: fg, fontSize: size, fontWeight: FontWeight.w800, height: 1, fontFeatures: const [FontFeature.tabularFigures()]),
            ),
            const SizedBox(width: 6),
            Text(
              sec,
              style: TextStyle(color: fg.withValues(alpha: .7), fontSize: size * .36, fontWeight: FontWeight.w700, fontFeatures: const [FontFeature.tabularFigures()]),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Text(longDate(now, app.lang), style: TextStyle(color: fg.withValues(alpha: .85), fontSize: 16)),
      ],
    );
    Widget count(Color fg) => Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(color: fg.withValues(alpha: .14), borderRadius: BorderRadius.circular(999)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(LucideIcons.users, size: 16, color: fg),
          const SizedBox(width: 6),
          Text(
            '${t('attk.came')} · ${n(d['today_in'])}${n(d['staff_total']) > 0 ? ' / ${n(d['staff_total'])}' : ''}',
            style: TextStyle(color: fg, fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );
    Widget recentList(Color fg, int max) => Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          t('attk.recent'),
          style: TextStyle(color: fg.withValues(alpha: .75), fontWeight: FontWeight.w700, fontSize: 13),
        ),
        const SizedBox(height: 8),
        if (recent.isEmpty) Text(t('attk.none'), style: TextStyle(color: fg.withValues(alpha: .8))),
        for (final r in recent.take(max))
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 5),
            child: Row(
              children: [
                Icon(str(r['kind']) == 'in' ? LucideIcons.logIn : LucideIcons.logOut, size: 17, color: fg),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    str(r['name']),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: fg, fontWeight: FontWeight.w700, fontSize: 16),
                  ),
                ),
                Text(t('attk.${str(r['kind'])}'), style: TextStyle(color: fg.withValues(alpha: .75))),
                const SizedBox(width: 10),
                Text(
                  hhmm(r['at']),
                  style: TextStyle(color: fg, fontWeight: FontWeight.w700),
                ),
              ],
            ),
          ),
      ],
    );
    Widget qrCard(double size) => Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(28),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: .12), blurRadius: 30, offset: const Offset(0, 12))],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Semantics(
            label: 'QR',
            child: QrImageView(data: link, size: size, padding: EdgeInsets.zero, backgroundColor: Colors.white, errorCorrectionLevel: QrErrorCorrectLevel.M),
          ),
          const SizedBox(height: 14),
          ClipRRect(
            borderRadius: BorderRadius.circular(99),
            child: LinearProgressIndicator(value: frac, minHeight: 6, color: accent, backgroundColor: accent.withValues(alpha: .15)),
          ),
          const SizedBox(height: 8),
          Text(
            t('attk.next', {'s': left.ceil()}),
            style: const TextStyle(color: Color(0xFF475569), fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
    final how = Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          t('attk.scan'),
          textAlign: TextAlign.center,
          style: TextStyle(color: c.ink, fontWeight: FontWeight.w800, fontSize: 26),
        ),
        const SizedBox(height: 6),
        Text(
          t('attk.how'),
          textAlign: TextAlign.center,
          style: TextStyle(color: c.muted, fontSize: 15.5, height: 1.4),
        ),
        if (_err == 'net') ...[const SizedBox(height: 10), Alert(t('attkp.net'), tone: Tone.warn)],
      ],
    );

    return Scaffold(
      backgroundColor: c.appBg,
      body: LayoutBuilder(
        builder: (context, box) {
          final wide = box.maxWidth >= 820 && box.maxWidth > box.maxHeight * 1.05;
          final menuBtn = RoundBtn(LucideIcons.ellipsisVertical, onTap: _menu, tip: t('att.more'), size: 40, bg: Colors.white.withValues(alpha: .18), fg: wide ? Colors.white : c.muted);
          if (wide) {
            final qr = (box.maxHeight * .52).clamp(220.0, 460.0);
            return Row(
              children: [
                Container(
                  width: box.maxWidth * .4,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [accent, Color.lerp(accent, Colors.black, .35)!]),
                  ),
                  child: SafeArea(
                    right: false,
                    child: Padding(
                      padding: const EdgeInsets.all(28),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(child: brand(Colors.white)),
                              menuBtn,
                            ],
                          ),
                          const Spacer(),
                          clock(Colors.white, 84),
                          const SizedBox(height: 16),
                          count(Colors.white),
                          const SizedBox(height: 24),
                          recentList(Colors.white, 6),
                        ],
                      ),
                    ),
                  ),
                ),
                Expanded(
                  child: SafeArea(
                    left: false,
                    child: Center(
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.all(24),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            qrCard(qr),
                            const SizedBox(height: 22),
                            ConstrainedBox(constraints: const BoxConstraints(maxWidth: 460), child: how),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            );
          }
          // phone / tablet standing up
          final qr = (box.maxWidth * .62).clamp(200.0, 420.0);
          return ListView(
            padding: EdgeInsets.zero,
            children: [
              Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [accent, Color.lerp(accent, Colors.black, .35)!]),
                  borderRadius: const BorderRadius.vertical(bottom: Radius.circular(32)),
                ),
                child: SafeArea(
                  bottom: false,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 14, 20, 26),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(child: brand(Colors.white)),
                            RoundBtn(LucideIcons.ellipsisVertical, onTap: _menu, tip: t('att.more'), size: 40, bg: Colors.white.withValues(alpha: .18), fg: Colors.white),
                          ],
                        ),
                        const SizedBox(height: 18),
                        clock(Colors.white, 60),
                        const SizedBox(height: 12),
                        count(Colors.white),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 22),
              Center(child: qrCard(qr)),
              const SizedBox(height: 18),
              Padding(padding: const EdgeInsets.symmetric(horizontal: 24), child: how),
              const SizedBox(height: 18),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                child: Panel(padding: const EdgeInsets.all(16), child: recentList(c.ink, 6)),
              ),
            ],
          );
        },
      ),
    );
  }
}
