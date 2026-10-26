import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:image_picker/image_picker.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/app_state.dart';
import '../../core/i18n.dart';
import '../../core/theme.dart';
import '../../widgets/ui.dart';
import 'att_api.dart';
import '../../widgets/qr_scan.dart';
import 'att_link.dart';
import 'att_month.dart';
import 'att_more.dart';
import '../updates/updates_page.dart';

// What every staff screen needs: the API with this phone's token, the words, "me", the owner's colour.
class AttCtx {
  final AttApi api;
  final T t;
  final String lang;
  final Json me;
  final Color accent;
  final VoidCallback authLost; // the token stopped working (401)
  final Future<void> Function() refresh;
  const AttCtx({required this.api, required this.t, required this.lang, required this.me, required this.accent, required this.authLost, required this.refresh});
  String err(Object e) => attErr(t, e);
  Json get features => obj(me['features']);
  bool on(String f) => features[f] == true;
  // a failed call: 401 → log in again, otherwise the words to show
  String fail(Object e) {
    if (e is ApiError && e.status == 401) authLost();
    return err(e);
  }
}

// The staff phone (like the web's /a/<code>): Today (clock in / out) + my month, leave, news, pay, team.
class AttStaffRoot extends StatefulWidget {
  const AttStaffRoot({super.key});
  @override
  State<AttStaffRoot> createState() => _AttStaffRootState();
}

class _AttStaffRootState extends State<AttStaffRoot> with WidgetsBindingObserver {
  Json? _me;
  String _error = '';
  bool _out = false; // logged out by the server (PIN changed, phone moved…)
  String _tab = 'today';
  Timer? _timer;

  AttApi get _api => AttApi(AppState.i.token);
  String get _code => str(AppState.i.link?['code']);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _refresh();
    // pick up changes from the owner (new add-on, new shift times…)
    _timer = Timer.periodic(const Duration(seconds: 60), (_) => _refresh());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _timer?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState s) {
    if (s == AppLifecycleState.resumed) _refresh();
  }

  Future<void> _refresh() async {
    try {
      final me = obj(await _api.get('/me'));
      if (mounted) {
        setState(() {
          _me = me;
          _error = '';
        });
      }
    } on ApiError catch (e) {
      if (!mounted) return;
      if (e.status == 401) return setState(() => _out = true);
      setState(() => _error = attErr(AppState.i.t, e));
    }
  }

  Future<void> _logout() async {
    final t = AppState.i.t;
    final ok = await showDialog<bool>(
      context: context,
      builder: (d) => AlertDialog(
        title: Text(t('att.logout')),
        content: Text(t('att.logoutSure')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(d, false), child: Text(t('att.cancel'))),
          TextButton(onPressed: () => Navigator.pop(d, true), child: Text(t('att.logout'))),
        ],
      ),
    );
    if (ok == true) AppState.i.unlink();
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final t = app.t;
    final c = context.c;
    if (_out) {
      return Scaffold(
        backgroundColor: c.appBg,
        body: SafeArea(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(28),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(LucideIcons.lock, size: 40, color: c.muted),
                  const SizedBox(height: 12),
                  Text(
                    t('att.err.logged_out'),
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 17),
                  ),
                  const SizedBox(height: 18),
                  Btn(
                    t('att.next'),
                    icon: LucideIcons.logIn,
                    onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => StaffLoginPage(code: _code))),
                  ),
                  const SizedBox(height: 8),
                  TextButton(onPressed: () => AppState.i.unlink(), child: Text(t('link.changeType'))),
                ],
              ),
            ),
          ),
        ),
      );
    }
    final me = _me;
    if (me == null) {
      return Scaffold(
        backgroundColor: c.appBg,
        body: Center(
          child: _error.isEmpty
              ? const CircularProgressIndicator()
              : Padding(
                  padding: const EdgeInsets.all(24),
                  child: LoadError(text: _error, retry: t('att.refresh'), onRetry: _refresh),
                ),
        ),
      );
    }
    final ctx = AttCtx(api: _api, t: t, lang: app.lang, me: me, accent: hexColor(me['color'], const Color(0xFF4F46E5)), authLost: () => setState(() => _out = true), refresh: _refresh);
    // the tabs this staff member has (add-ons the owner bought)
    final tabs = <(String, IconData, String)>[
      ('today', LucideIcons.sun, t('att.today')),
      ('history', LucideIcons.calendarDays, t('att.history')),
      if (ctx.on('leave')) ('leave', LucideIcons.palmtree, t('att.leave')),
      if (ctx.on('news')) ('news', LucideIcons.megaphone, t('atte.news')),
      if (ctx.on('pay')) ('pay', LucideIcons.wallet, t('att.pay.tab')),
      if (ctx.on('team')) ('team', LucideIcons.usersRound, t('attt.tab')),
    ];
    if (!tabs.any((x) => x.$1 == _tab)) _tab = 'today';
    final many = tabs.length > 4;
    final shown = many ? tabs.take(3).toList() : tabs;
    final rest = many ? tabs.skip(3).toList() : <(String, IconData, String)>[];
    final inRest = rest.any((x) => x.$1 == _tab);
    final unread = (n(me['news_unread'])).toInt();

    Widget icon(String key, IconData i) => key == 'news' && unread > 0 ? Badge(label: Text(unread > 9 ? '9+' : '$unread'), child: Icon(i)) : Icon(i);

    final body = switch (_tab) {
      'history' => AttMonth(ctx: ctx),
      'leave' => AttLeave(ctx: ctx),
      'news' => AttNews(ctx: ctx),
      'pay' => AttPay(ctx: ctx),
      'team' => AttTeam(ctx: ctx),
      _ => AttToday(ctx: ctx),
    };
    final logo = str(obj(me['business'])['logo_url']);
    return Scaffold(
      backgroundColor: c.appBg,
      appBar: AppBar(
        backgroundColor: c.appBg,
        surfaceTintColor: Colors.transparent,
        titleSpacing: 16,
        title: Row(
          children: [
            Container(
              width: 34,
              height: 34,
              clipBehavior: Clip.antiAlias,
              decoration: BoxDecoration(color: ctx.accent.withValues(alpha: .12), borderRadius: BorderRadius.circular(11)),
              child: logo.isNotEmpty ? Image(image: netImage(logo), fit: BoxFit.cover) : Icon(LucideIcons.fingerprintPattern, size: 19, color: ctx.accent),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                str(obj(me['business'])['name']),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 17),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => app.setLang(app.lang == 'km' ? 'en' : 'km'),
            child: Text(app.lang == 'km' ? 'EN' : 'ខ្មែរ', style: const TextStyle(fontWeight: FontWeight.w700)),
          ),
          const ThemeBtn(),
          IconButton(onPressed: () => openUpdates(context), icon: const Icon(LucideIcons.history), tooltip: updatesText(app.lang, 'title')),
          IconButton(onPressed: _logout, icon: const Icon(LucideIcons.power), tooltip: t('att.logout')),
          const SizedBox(width: 4),
        ],
      ),
      body: Center(
        child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 640), child: body),
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: inRest ? shown.length : shown.indexWhere((x) => x.$1 == _tab).clamp(0, shown.length),
        indicatorColor: ctx.accent.withValues(alpha: .16),
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        onDestinationSelected: (i) {
          if (i < shown.length) return setState(() => _tab = shown[i].$1);
          showModalBottomSheet<void>(
            context: context,
            showDragHandle: true,
            builder: (sheet) => SafeArea(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (final x in rest)
                    ListTile(
                      leading: icon(x.$1, x.$2),
                      title: Text(x.$3),
                      selected: _tab == x.$1,
                      onTap: () {
                        Navigator.pop(sheet);
                        setState(() => _tab = x.$1);
                      },
                    ),
                  const SizedBox(height: 8),
                ],
              ),
            ),
          );
        },
        destinations: [
          for (final x in shown) NavigationDestination(icon: icon(x.$1, x.$2), label: x.$3),
          if (many)
            NavigationDestination(
              icon: rest.any((x) => x.$1 == 'news') && unread > 0 ? Badge(smallSize: 8, child: const Icon(LucideIcons.ellipsis)) : const Icon(LucideIcons.ellipsis),
              label: t('att.more'),
            ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------- TODAY: the clock and the big button
class AttToday extends StatefulWidget {
  final AttCtx ctx;
  const AttToday({super.key, required this.ctx});
  @override
  State<AttToday> createState() => _AttTodayState();
}

class _AttTodayState extends State<AttToday> {
  late int _offset; // server clock − phone clock (the phone's clock may be wrong)
  Timer? _tick, _back;
  String _step = 'idle'; // idle | camera | locating | sending | nogps | done
  String _kiosk = ''; // the scanned door QR (<branch>.<code>)
  Json? _pos; // { lat, lng, accuracy }
  Uint8List? _photo;
  Json? _result;
  String _error = '';

  AttCtx get ctx => widget.ctx;
  T get t => ctx.t;
  Json get me => ctx.me;

  @override
  void initState() {
    super.initState();
    _offset = (DateTime.tryParse(str(me['server_time']))?.millisecondsSinceEpoch ?? DateTime.now().millisecondsSinceEpoch) - DateTime.now().millisecondsSinceEpoch;
    _tick = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    _back?.cancel();
    super.dispose();
  }

  int get _nowMs => DateTime.now().millisecondsSinceEpoch + _offset;
  int? _ms(Object? v) => DateTime.tryParse(str(v))?.millisecondsSinceEpoch;

  // where is the phone? → { lat, lng, accuracy, mocked } or { error }
  Future<Json> _locate() async {
    try {
      if (!await Geolocator.isLocationServiceEnabled()) return {'error': 'off'};
      var p = await Geolocator.checkPermission();
      if (p == LocationPermission.denied) p = await Geolocator.requestPermission();
      if (p == LocationPermission.denied || p == LocationPermission.deniedForever) return {'error': 'denied'};
      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(accuracy: LocationAccuracy.high, timeLimit: Duration(seconds: 15)),
      );
      return {'lat': pos.latitude, 'lng': pos.longitude, 'accuracy': pos.accuracy.round(), 'mocked': !kIsWeb && pos.isMocked};
    } catch (e) {
      debugPrint('att locate: $e');
      return {'error': 'failed'};
    }
  }

  Future<void> _send(Json? where) async {
    setState(() {
      _step = 'sending';
      _error = '';
    });
    try {
      final d = await ctx.api.punch({
        'kind': str(me['next']),
        if (where?['lat'] != null) ...{'lat': where!['lat'], 'lng': where['lng'], 'accuracy': where['accuracy'], if (where['mocked'] == true) 'mocked': true},
        if (_kiosk.isNotEmpty) 'kiosk': _kiosk,
      }, photo: _photo);
      _kiosk = '';
      _photo = null;
      if (!mounted) return;
      setState(() {
        _result = obj(d['punch']);
        _step = 'done';
      });
      await ctx.refresh();
      _back?.cancel();
      _back = Timer(const Duration(seconds: 12), () {
        if (mounted) setState(() => _step = 'idle');
      });
    } on ApiError catch (e) {
      if (!mounted) return;
      setState(() {
        _error = ctx.fail(e);
        _step = 'idle';
        if (e.code == 'kiosk_old') _kiosk = '';
      });
      if (e.code == 'already_in' || e.code == 'not_in') ctx.refresh();
    }
  }

  Future<void> _press() async {
    setState(() => _error = '');
    // selfie add-on: the front camera first
    if (ctx.on('selfie')) {
      setState(() => _step = 'camera');
      try {
        final shot = await ImagePicker().pickImage(source: ImageSource.camera, preferredCameraDevice: CameraDevice.front, maxWidth: 640, imageQuality: 80);
        if (shot == null) return setState(() => _step = 'idle');
        _photo = await shot.readAsBytes();
      } catch (_) {
        return setState(() {
          _step = 'idle';
          _error = t('att.cameraNo');
        });
      }
    }
    if (_kiosk.isNotEmpty) return _send(null); // the door QR proves the place
    setState(() => _step = 'locating');
    final where = await _locate();
    if (!mounted) return;
    if (where['error'] != null) {
      return setState(() {
        _pos = null;
        _step = 'nogps';
        _error = where['error'] == 'denied' ? t('att.gpsDenied') : (where['error'] == 'off' ? t('att.gpsOff') : t('att.gpsFailed'));
      });
    }
    setState(() => _pos = where);
    _send(where);
  }

  Future<void> _scanDoor() async {
    final v = await scanQr(context, title: t('att.scanDoor'));
    if (v == null || !mounted) return;
    final p = parseStaffLink(v);
    if (p == null || p.k.isEmpty || p.code.toLowerCase() != str(AppState.i.link?['code']).toLowerCase()) return setState(() => _error = t('att.notDoor'));
    _kiosk = p.k;
    _press();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final today = obj(me['today']);
    final shift = me['shift'] == null ? null : obj(me['shift']);
    final now = khNow(_offset);
    final nowMs = _nowMs;
    final isIn = str(me['next']) == 'out';
    final busy = _step == 'locating' || _step == 'sending' || _step == 'camera';
    final win = me['window'] == null ? null : obj(me['window']);
    final winFrom = _ms(win?['from']), winTo = _ms(win?['to']);
    final early = winFrom != null && nowMs < winFrom;
    final late = winTo != null && nowMs > winTo;
    final closed = early || late;
    final stopped = me['stopped'] == true;
    final label = _step == 'locating'
        ? t('att.locating')
        : _step == 'sending'
        ? t('att.sending')
        : early
        ? t('att.opensAt', {'t': hhmm(win!['from'])})
        : late
        ? t('att.closedAt', {'t': hhmm(win!['to'])})
        : isIn
        ? t('att.clockOut')
        : t('att.clockIn');
    final btnColor = isIn ? const Color(0xFFE11D48) : ctx.accent;
    final endMs = _ms(today['end']);
    final branches = objs(me['branches']);
    // the nearest branch to where the phone was found
    Json? nearB;
    int nearD = 0;
    if (_pos?['lat'] != null) {
      for (final b in branches.where((b) => b['lat'] is num && b['lng'] is num)) {
        final d = distanceM((_pos!['lat'] as num).toDouble(), (_pos!['lng'] as num).toDouble(), (b['lat'] as num).toDouble(), (b['lng'] as num).toDouble());
        if (nearB == null || d - n(b['radius_m']) < nearD - n(nearB['radius_m'])) {
          nearB = b;
          nearD = d;
        }
      }
    }
    final hms = '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}:${now.second.toString().padLeft(2, '0')}';
    final name = str(obj(me['staff'])['name']);

    Widget tag(String text, Tone tone) => Chip2(text, tone: tone);
    final status = str(today['status']);
    final statusTone = switch (status) {
      'present' || 'working' => Tone.good,
      'absent' || 'missing_out' => Tone.danger,
      'not_yet' => Tone.warn,
      _ => Tone.muted,
    };

    final result = _result;
    final pressArea = _step == 'done' && result != null
        ? Panel(
            color: str(result['review']) == 'ok' ? c.goodBg : c.warnBg,
            child: Column(
              children: [
                Icon(str(result['review']) == 'ok' ? LucideIcons.circleCheck : LucideIcons.triangleAlert, size: 48, color: str(result['review']) == 'ok' ? c.good : c.warn),
                const SizedBox(height: 8),
                Text(str(result['kind']) == 'in' ? t('att.inDone') : t('att.outDone'), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 20)),
                Text(hhmm(result['at']), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 34)),
                if (str(result['branch_name']).isNotEmpty) Text('${str(result['branch_name'])}${result['distance_m'] != null ? ' · ${result['distance_m']} m' : ''}', style: TextStyle(color: c.muted)),
                if (str(result['review']) != 'ok') ...[
                  const SizedBox(height: 8),
                  Text(
                    '${t('att.needsCheck')} ${[for (final f in (result['flags'] as List? ?? const [])) t('att.flags.$f')].join(', ')}',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: c.warn, fontWeight: FontWeight.w600),
                  ),
                ],
                const SizedBox(height: 12),
                Btn(t('att.ok'), kind: BtnKind.ghost, small: true, onTap: () => setState(() => _step = 'idle')),
              ],
            ),
          )
        : Column(
            children: [
              Semantics(
                button: true,
                enabled: !(stopped || busy || closed),
                label: label,
                excludeSemantics: true, // one label, not the inner text again
                child: GestureDetector(
                  onTap: stopped || busy || closed ? null : _press,
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 250),
                    width: 210,
                    height: 210,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: closed || stopped ? c.chip : btnColor,
                      boxShadow: closed || stopped ? null : [BoxShadow(color: btnColor.withValues(alpha: .35), blurRadius: 34, offset: const Offset(0, 14))],
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        if (busy)
                          const SizedBox(width: 44, height: 44, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 3.5))
                        else
                          Icon(closed ? LucideIcons.clock : (isIn ? LucideIcons.logOut : LucideIcons.logIn), size: 48, color: closed || stopped ? c.muted : Colors.white),
                        const SizedBox(height: 10),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 18),
                          child: Text(
                            label,
                            textAlign: TextAlign.center,
                            style: TextStyle(color: closed || stopped ? c.muted : Colors.white, fontWeight: FontWeight.w800, fontSize: 19),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              if (win != null)
                Text(
                  t(isIn ? 'att.outAllowed' : 'att.inAllowed', {'from': winFrom != null ? hhmm(win['from']) : '…', 'to': winTo != null ? hhmm(win['to']) : '…'}),
                  style: TextStyle(color: closed ? c.warn : c.muted, fontSize: 13),
                ),
              if (ctx.on('selfie') && _step == 'idle')
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Muted(t('att.selfieNote'), align: TextAlign.center),
                ),
              if (nearB != null && _step != 'nogps')
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(LucideIcons.mapPin, size: 14, color: nearD <= n(nearB['radius_m']) ? c.good : c.warn),
                      const SizedBox(width: 4),
                      Flexible(
                        child: Text(
                          t(nearD <= n(nearB['radius_m']) ? 'att.atBranch' : 'att.awayFrom', {'m': nearD, 'name': str(nearB['name'])}),
                          style: TextStyle(color: nearD <= n(nearB['radius_m']) ? c.good : c.warn, fontSize: 13, fontWeight: FontWeight.w600),
                        ),
                      ),
                    ],
                  ),
                ),
              if (_error.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 12), child: Alert(_error)),
              if (_step == 'nogps')
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Panel(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      children: [
                        Text(
                          t('att.noGpsAsk'),
                          textAlign: TextAlign.center,
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                        const SizedBox(height: 12),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Btn(t('att.cancel'), kind: BtnKind.ghost, small: true, onTap: () => setState(() => (_step = 'idle', _photo = null))),
                            const SizedBox(width: 10),
                            Btn(t('att.sendAnyway'), small: true, onTap: () => _send(null)),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              if (ctx.on('kiosk') && _step == 'idle' && !stopped && !closed) ...[
                const SizedBox(height: 14),
                Btn(t('att.scanDoor'), icon: LucideIcons.scanLine, kind: BtnKind.ghost, small: true, onTap: _scanDoor),
                const SizedBox(height: 4),
                Muted(t('att.scanDoorSub'), align: TextAlign.center),
              ],
            ],
          );

    String stat(String k) => switch (k) {
      'in' => hhmm(today['first_in']),
      'out' => status == 'missing_out' ? '?' : hhmm(today['last_out']),
      _ => n(today['worked_min']) > 0 ? dur(today['worked_min']) : '—',
    };

    return RefreshIndicator(
      onRefresh: ctx.refresh,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 28),
        children: [
          if (isIn && endMs != null && nowMs > endMs + 15 * 60000)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Alert(t('att.remind', {'time': hhmm(today['end'])}), tone: Tone.warn),
            ),
          Row(
            children: [
              CircleAvatar(
                radius: 22,
                backgroundColor: ctx.accent.withValues(alpha: .14),
                child: Text(
                  name.trim().isEmpty ? '?' : name.trim().characters.first.toUpperCase(),
                  style: TextStyle(color: ctx.accent, fontWeight: FontWeight.w800, fontSize: 18),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(t('att.hello'), style: TextStyle(color: c.muted, fontSize: 13)),
                    Text(
                      name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 18),
                    ),
                  ],
                ),
              ),
              Chip2(isIn ? t('att.onDuty') : t('att.offDuty'), tone: isIn ? Tone.good : Tone.muted),
            ],
          ),
          const SizedBox(height: 18),
          Center(
            child: Text(
              hms,
              style: const TextStyle(fontSize: 46, fontWeight: FontWeight.w800, height: 1.05, fontFeatures: [FontFeature.tabularFigures()]),
            ),
          ),
          Center(
            child: Text(longDate(now, ctx.lang), style: TextStyle(color: c.muted, fontSize: 15)),
          ),
          if (shift != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Center(
                child: Chip2('${str(shift['name'])} · ${str(shift['start'])}–${str(shift['end'])}', icon: LucideIcons.clock, tone: Tone.brand),
              ),
            ),
          if (stopped) Padding(padding: const EdgeInsets.only(top: 14), child: Alert(t('att.err.stopped'))),
          const SizedBox(height: 22),
          pressArea,
          const SizedBox(height: 22),
          Panel(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    for (final k in ['in', 'out', 'worked'])
                      Expanded(
                        child: Column(
                          children: [
                            Text(t('att.$k'), style: TextStyle(color: c.muted, fontSize: 13)),
                            const SizedBox(height: 2),
                            Text(stat(k), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 20)),
                          ],
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    if (status.isNotEmpty) tag(t.or('att.status.$status', status), statusTone),
                    if (n(today['late_min']) > 0) tag(t('att.late', {'m': dur(today['late_min'])}), Tone.warn),
                    if (n(today['early_min']) > 0) tag(t('att.early', {'m': dur(today['early_min'])}), Tone.warn),
                    if (n(today['ot_min']) > 0) tag(t('att.ot', {'m': dur(today['ot_min'])}), Tone.brand),
                    if (n(today['pending']) > 0) tag(t('att.pending'), Tone.warn),
                  ],
                ),
                for (final p in objs(today['punches'])) ...[
                  const Divider(height: 18),
                  Row(
                    children: [
                      Icon(str(p['kind']) == 'in' ? LucideIcons.logIn : LucideIcons.logOut, size: 16, color: c.muted),
                      const SizedBox(width: 8),
                      Text(hhmm(p['at']), style: const TextStyle(fontWeight: FontWeight.w800)),
                      const SizedBox(width: 8),
                      Expanded(child: Text(str(p['kind']) == 'in' ? t('att.clockIn') : t('att.clockOut'))),
                      if (str(p['review']) != 'ok') Chip2(t('att.review.${str(p['review'])}'), tone: str(p['review']) == 'rejected' ? Tone.danger : Tone.warn),
                    ],
                  ),
                ],
              ],
            ),
          ),
          if (branches.isEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Muted(t('att.noBranch'), align: TextAlign.center),
            ),
        ],
      ),
    );
  }
}
