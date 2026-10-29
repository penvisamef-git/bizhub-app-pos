import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/app_state.dart';
import '../../core/theme.dart';
import '../../widgets/ui.dart';
import 'engine/calc.dart';
import 'engine/rest_pos.dart';
import 'pos_ui.dart';
import '../../core/powered_by.dart';

// The screens before selling: loading, no menu yet, unlinked, staff PIN, open shift.

class _StartCard extends StatelessWidget {
  final List<Widget> children;
  final double maxWidth;
  const _StartCard({required this.children, this.maxWidth = 420});
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.c.appBg,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: maxWidth),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: children),
            ),
          ),
        ),
      ),
    );
  }
}

class _BigIcon extends StatelessWidget {
  final IconData icon;
  final Color? color, bg;
  const _BigIcon(this.icon, {this.color, this.bg});
  @override
  Widget build(BuildContext context) => Center(
    child: Container(
      width: 72,
      height: 72,
      decoration: BoxDecoration(color: bg ?? context.c.active, borderRadius: BorderRadius.circular(24)),
      child: Icon(icon, size: 32, color: color ?? context.c.brand),
    ),
  );
}

// a small link-style button
class _LinkBtn extends StatelessWidget {
  final String label;
  final IconData icon;
  final VoidCallback? onTap;
  const _LinkBtn(this.label, this.icon, this.onTap);
  @override
  Widget build(BuildContext context) => Center(
    child: TextButton.icon(
      style: TextButton.styleFrom(foregroundColor: context.c.muted),
      onPressed: onTap,
      icon: Icon(icon, size: 16),
      label: Text(label),
    ),
  );
}

class RestSplash extends StatelessWidget {
  const RestSplash({super.key});
  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: context.c.appBg,
    body: Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          CircularProgressIndicator(color: context.c.brand),
          const SizedBox(height: 16),
          Muted(tr(context)('rpos.loading')),
        ],
      ),
    ),
  );
}

// the menu was never downloaded: needs the internet once
class RestNoSetup extends StatefulWidget {
  const RestNoSetup({super.key});
  @override
  State<RestNoSetup> createState() => _RestNoSetupState();
}

class _RestNoSetupState extends State<RestNoSetup> {
  bool _busy = false;
  @override
  Widget build(BuildContext context) {
    final t = tr(context);
    final pos = RestPos.i;
    return _StartCard(
      children: [
        _BigIcon(LucideIcons.wifiOff, color: context.c.warn, bg: context.c.warnBg),
        const SizedBox(height: 18),
        Text(
          t('rpos.noSetup'),
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700, height: 1.45),
        ),
        if (pos.error.isNotEmpty) ...[const SizedBox(height: 12), Alert(pos.error)],
        const SizedBox(height: 20),
        Btn(
          t('rpos.retry'),
          icon: LucideIcons.refreshCw,
          busy: _busy,
          expand: true,
          onTap: () async {
            setState(() => _busy = true);
            await pos.retry();
            if (mounted) setState(() => _busy = false);
          },
        ),
        const SizedBox(height: 8),
        _LinkBtn(t('rpos.unlink'), LucideIcons.unplug, () => showUnlink(context)),
        const PoweredBy(),
      ],
    );
  }
}

// the owner removed this device in the dashboard
class RestUnlinked extends StatelessWidget {
  const RestUnlinked({super.key});
  @override
  Widget build(BuildContext context) {
    final t = tr(context);
    return _StartCard(
      children: [
        _BigIcon(LucideIcons.unplug, color: context.c.danger, bg: context.c.dangerBg),
        const SizedBox(height: 18),
        Text(
          t('rpos.unlinked'),
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700, height: 1.45),
        ),
        const SizedBox(height: 20),
        Btn(t('rp.relink'), icon: LucideIcons.link, expand: true, onTap: () => AppState.i.unlink()),
      ],
    );
  }
}

// staff PIN (works offline)
class RestPinLock extends StatefulWidget {
  const RestPinLock({super.key});
  @override
  State<RestPinLock> createState() => _RestPinLockState();
}

class _RestPinLockState extends State<RestPinLock> {
  String _pin = '';
  bool _error = false, _busy = false;

  Future<void> _typed(String v) async {
    setState(() => _pin = v);
    if (v.length != 4) return;
    setState(() => _busy = true);
    final s = await RestPos.i.loginPin(v);
    if (!mounted) return;
    setState(() => _busy = false);
    if (s == null) {
      setState(() => _error = true);
      await Future.delayed(const Duration(milliseconds: 650));
      if (mounted) {
        setState(() {
          _error = false;
          _pin = '';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final t = app.t;
    final c = context.c;
    final pos = RestPos.i;
    final logo = js(pos.restaurant['logo']);
    return _StartCard(
      maxWidth: 380,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                js(pos.device['name']),
                style: TextStyle(color: c.muted, fontWeight: FontWeight.w600),
              ),
            ),
            const ThemeBtn(),
            TextButton(onPressed: () => app.setLang(app.lang == 'km' ? 'en' : 'km'), child: Text(t('home.lang'))),
          ],
        ),
        const SizedBox(height: 8),
        Center(
          child: Container(
            width: 84,
            height: 84,
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(color: c.active, borderRadius: BorderRadius.circular(26)),
            child: logo.isNotEmpty
                ? Image(
                    image: netImage(logo),
                    fit: BoxFit.cover,
                    errorBuilder: (_, _, _) => Icon(LucideIcons.chefHat, color: c.brand, size: 36),
                  )
                : Icon(LucideIcons.chefHat, color: c.brand, size: 36),
          ),
        ),
        const SizedBox(height: 14),
        Text(
          nameOf(pos.restaurant, app.lang),
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 6),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(LucideIcons.lock, size: 14, color: _error ? c.danger : c.muted),
            const SizedBox(width: 6),
            Text(
              _busy ? t('rpos.checking') : (_error ? t('rpos.wrongPin') : t('rpos.enterPin')),
              style: TextStyle(color: _error ? c.danger : c.muted, fontWeight: FontWeight.w600),
            ),
          ],
        ),
        const DemoPinHint(),
        const SizedBox(height: 20),
        PinDots(_pin.length, error: _error),
        const SizedBox(height: 24),
        Keypad(value: _pin, onChanged: _typed, max: 4, disabled: _busy || _error, keyHeight: 64),
        const SizedBox(height: 8),
        _LinkBtn(t('rpos.unlink'), LucideIcons.unplug, () => showUnlink(context)),
        const PoweredBy(),
      ],
    );
  }
}

// count the drawer, start the shift
class RestOpenShift extends StatefulWidget {
  const RestOpenShift({super.key});
  @override
  State<RestOpenShift> createState() => _RestOpenShiftState();
}

class _RestOpenShiftState extends State<RestOpenShift> {
  String _usd = '', _khr = '', _field = 'usd';
  bool _busy = false;
  @override
  Widget build(BuildContext context) {
    final t = tr(context);
    final pos = RestPos.i;
    return _StartCard(
      maxWidth: 400,
      children: [
        Text(
          t('rpos.openShift'),
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 6),
        Muted('${js(pos.staff?['name'])} · ${t('rpos.openShiftSub')}', align: TextAlign.center),
        const SizedBox(height: 20),
        Row(
          children: [
            Expanded(
              child: AmountBox(label: t('rpos.cashUsd'), value: m$(nz(_usd), 'USD'), on: _field == 'usd', onTap: () => setState(() => _field = 'usd')),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: AmountBox(label: t('rpos.cashKhr'), value: m$(nz(_khr), 'KHR'), on: _field == 'khr', onTap: () => setState(() => _field = 'khr')),
            ),
          ],
        ),
        const SizedBox(height: 16),
        Keypad(value: _field == 'usd' ? _usd : _khr, onChanged: (v) => setState(() => _field == 'usd' ? _usd = v : _khr = v), dot: _field == 'usd', max: _field == 'usd' ? 9 : 10),
        const SizedBox(height: 10),
        Btn(
          t('rpos.start'),
          icon: LucideIcons.play,
          busy: _busy,
          expand: true,
          onTap: () async {
            setState(() => _busy = true);
            await pos.startShift(nz(_usd), nz(_khr));
          },
        ),
        const SizedBox(height: 10),
        Center(child: Muted('1 USD = ${m$(nz(pos.moneyS['khr_rate']) == 0 ? 4100 : nz(pos.moneyS['khr_rate']), 'KHR')}')),
        _LinkBtn(t('rpos.notYou', {'name': js(pos.staff?['name'])}), LucideIcons.logOut, _busy ? null : pos.lock),
      ],
    );
  }
}

// Unlink this device from the shop: a manager types their PIN (any staff PIN when the shop has no manager).
// Sales not sent yet must go first; offline, the staff has to accept losing them.
Future<void> showUnlink(BuildContext context) => posSheet(context, title: tr(context)('rpos.unlink'), body: (_) => const _Unlink());

class _Unlink extends StatefulWidget {
  const _Unlink();
  @override
  State<_Unlink> createState() => _UnlinkState();
}

class _UnlinkState extends State<_Unlink> {
  String _pin = '', _error = '';
  bool _busy = false, _lose = false;

  Future<void> _go(String p) async {
    final t = tr(context);
    setState(() {
      _busy = true;
      _error = '';
    });
    try {
      await RestPos.i.unlink(p);
      if (!mounted) return;
      Navigator.of(context).popUntil((r) => r.isFirst);
      AppState.i.unlink();
    } catch (e) {
      setState(() {
        _error = e == 'manager' ? t('rpos.unlinkNeedManager') : t('rpos.wrongPin');
        _busy = false;
      });
      await Future.delayed(const Duration(milliseconds: 650));
      if (mounted) setState(() => _pin = '');
    }
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final t = app.t;
    final c = context.c;
    return ListenableBuilder(
      listenable: RestPos.i,
      builder: (context, _) {
        final pos = RestPos.i;
        final waiting = pos.pending;
        final blocked = waiting > 0 && (pos.online ? true : !_lose);
        final needPin = pos.setup != null;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _BigIcon(LucideIcons.unplug, color: c.danger, bg: c.dangerBg),
            const SizedBox(height: 14),
            Text(
              t('rpos.unlinkWhat', {
                'shop': nameOf(pos.restaurant, app.lang).isEmpty ? '—' : nameOf(pos.restaurant, app.lang),
                'device': js(pos.device['name']).isEmpty ? 'POS' : js(pos.device['name']),
              }),
              textAlign: TextAlign.center,
              style: const TextStyle(height: 1.45),
            ),
            if (pos.setup != null && pos.openShift != null) ...[const SizedBox(height: 10), Alert(t('rpos.unlinkShiftOpen'), tone: Tone.warn)],
            if (waiting > 0 && pos.online) ...[
              const SizedBox(height: 10),
              Alert(
                t('rpos.unlinkWaiting', {'n': waiting}),
                tone: Tone.warn,
                action: Btn(t('rpos.syncNow'), icon: LucideIcons.refreshCw, small: true, busy: pos.syncing, onTap: pos.syncNow),
              ),
            ],
            if (waiting > 0 && !pos.online) ...[
              const SizedBox(height: 10),
              Alert(
                t('rpos.unlinkOfflineLose', {'n': waiting}),
                action: CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  value: _lose,
                  onChanged: (v) => setState(() => _lose = v == true),
                  title: Text(t('rpos.unlinkLoseOk')),
                  controlAffinity: ListTileControlAffinity.leading,
                ),
              ),
            ],
            if (!pos.online && waiting == 0) ...[const SizedBox(height: 10), Muted(t('rpos.unlinkOffline'), align: TextAlign.center)],
            const SizedBox(height: 16),
            if (needPin) ...[
              Text(
                _error.isNotEmpty ? _error : (pos.hasManager ? t('rpos.unlinkPinManager') : t('rpos.unlinkPinAny')),
                textAlign: TextAlign.center,
                style: TextStyle(color: _error.isNotEmpty ? c.danger : c.muted, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 14),
              PinDots(_pin.length, error: _error.isNotEmpty),
              const SizedBox(height: 18),
              Keypad(
                value: _pin,
                max: 4,
                disabled: _busy || blocked,
                onChanged: (v) {
                  setState(() => _pin = v);
                  if (v.length == 4 && !blocked && !_busy) _go(v);
                },
              ),
            ] else
              Btn(t('rpos.unlink'), icon: LucideIcons.unplug, kind: BtnKind.danger, busy: _busy, expand: true, onTap: () => _go('')),
          ],
        );
      },
    );
  }
}
