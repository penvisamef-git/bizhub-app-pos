import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/app_state.dart';
import '../../core/theme.dart';
import 'bizi_face.dart';
import 'pos_bizi_find.dart';
import 'pos_bizi_help.dart';

// Bizi in the POS (v3.0.0, free, no AI): the same helper as the website and the BizHub app, for the counter.
//   • a small bubble over the POS (hold and drag it anywhere; it stays there on this device)
//   • tap → the cashier's questions for this POS ("printer doesn't print", "close the shift", "void an item")
//     with the steps, typed in English or Khmer — plus dark mode / language
//   • worried + a red dot when something waits at this counter (new Telegram orders waiting too long…):
//     a POS screen tells it through posBiziWaiting
class PosWaiting {
  final String key; // what waits: tg_new
  final int n;
  final DateTime? oldest;
  const PosWaiting(this.key, this.n, {this.oldest});
}

// a POS screen says what waits here (null = nothing)
final posBiziWaiting = ValueNotifier<PosWaiting?>(null);

const _size = 56.0;
const _edge = 8.0;
const _posKey = 'pos.bizi_pos';

class PosBizi extends StatefulWidget {
  final String kind; // restaurant | mart | guest_house | stamp_card | event | tg_store | attendance
  final Widget child;
  const PosBizi({super.key, required this.kind, required this.child});
  @override
  State<PosBizi> createState() => _PosBiziState();
}

class _PosBiziState extends State<PosBizi> {
  Offset? _pos; // parts of the screen (0–1); null = the corner
  Offset? _dragAt;
  bool _dragging = false;
  bool _open = false;

  @override
  void initState() {
    super.initState();
    try {
      final v = jsonDecode(AppState.i.pref(_posKey) ?? 'null');
      if (v is Map && v['x'] is num && v['y'] is num) _pos = Offset((v['x'] as num).toDouble(), (v['y'] as num).toDouble());
    } catch (_) {}
  }

  Offset _px(Size s, EdgeInsets pad) {
    final maxX = s.width - _size - _edge;
    final maxY = s.height - _size - _edge - pad.bottom;
    // first time: on the left, above the bottom bars (a mini mart's cart bar too), away from the pay buttons on the
    // right; the event door keeps the code field under the camera free, so higher there
    if (_pos == null) return Offset(_edge + 8 + pad.left, widget.kind == 'event' ? s.height * .3 : maxY - 150);
    return Offset((_pos!.dx * s.width).clamp(_edge, maxX), (_pos!.dy * s.height).clamp(_edge + pad.top, maxY));
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final app = AppScope.of(context);
    final mq = MediaQuery.of(context);
    final at = _dragAt ?? _px(mq.size, mq.padding);
    return Stack(
      children: [
        widget.child,
        if (_open)
          Positioned.fill(
            child: PosBiziPanel(kind: widget.kind, lang: app.lang, onClose: () => setState(() => _open = false)),
          ),
        if (!_open)
          Positioned(
            left: at.dx,
            top: at.dy,
            child: ValueListenableBuilder<PosWaiting?>(
              valueListenable: posBiziWaiting,
              builder: (_, waiting, _) {
                final warn = waiting != null && waiting.n > 0;
                return Semantics(
                  button: true,
                  label: app.lang == 'km' ? 'បើក Bizi ជំនួយការ' : 'Open Bizi, the helper',
                  child: GestureDetector(
                    key: const ValueKey('pos-bizi'),
                    onTap: () => setState(() => _open = true),
                    onPanStart: (_) => setState(() {
                      _dragging = true;
                      _dragAt = at;
                    }),
                    onPanUpdate: (d) => setState(() {
                      final p = (_dragAt ?? at) + d.delta;
                      _dragAt = Offset(p.dx.clamp(_edge, mq.size.width - _size - _edge), p.dy.clamp(_edge + mq.padding.top, mq.size.height - _size - _edge - mq.padding.bottom));
                    }),
                    onPanEnd: (_) => setState(() {
                      final p = _dragAt ?? at;
                      _pos = Offset(p.dx / mq.size.width, p.dy / mq.size.height);
                      _dragAt = null;
                      _dragging = false;
                      AppState.i.setPref(_posKey, jsonEncode({'x': _pos!.dx, 'y': _pos!.dy}));
                    }),
                    child: Material(
                      type: MaterialType.transparency,
                      child: Stack(
                        clipBehavior: Clip.none,
                        children: [
                          AnimatedContainer(
                            duration: const Duration(milliseconds: 120),
                            width: _size,
                            height: _size,
                            decoration: BoxDecoration(color: c.card, shape: BoxShape.circle, boxShadow: c.popShadow),
                            alignment: Alignment.center,
                            child: BiziFace(mood: _dragging ? BiziMood.happy : (warn ? BiziMood.worried : BiziMood.idle), size: _size - 12),
                          ),
                          if (warn)
                            Positioned(
                              top: -4,
                              right: -4,
                              child: Container(
                                key: const ValueKey('pos-bizi-dot'),
                                constraints: const BoxConstraints(minWidth: 22),
                                height: 22,
                                padding: const EdgeInsets.symmetric(horizontal: 6),
                                alignment: Alignment.center,
                                decoration: BoxDecoration(
                                  color: const Color(0xFFB42318),
                                  borderRadius: BorderRadius.circular(999),
                                  border: Border.all(color: c.card, width: 2),
                                ),
                                child: Text(
                                  waiting.n > 9 ? '9+' : '${waiting.n}',
                                  style: const TextStyle(color: Colors.white, fontSize: 11.5, fontWeight: FontWeight.w800),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
      ],
    );
  }
}

// the panel: search the questions, what waits, quick settings
class PosBiziPanel extends StatefulWidget {
  final String kind, lang;
  final VoidCallback onClose;
  const PosBiziPanel({super.key, required this.kind, required this.lang, required this.onClose});
  @override
  State<PosBiziPanel> createState() => _PosBiziPanelState();
}

class _PosBiziPanelState extends State<PosBiziPanel> {
  final _q = TextEditingController();
  String _openId = '';
  String? _openQ;
  Timer? _tick;

  @override
  void initState() {
    super.initState();
    _q.addListener(() => setState(() {}));
    // "waiting 12 min" moves on
    _tick = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    _q.dispose();
    super.dispose();
  }

  String x(String k, [Map<String, Object?> v = const {}]) {
    var s = (posBiziText[widget.lang] ?? posBiziText['en']!)[k] ?? posBiziText['en']![k] ?? k;
    v.forEach((key, val) => s = s.replaceAll('{$key}', '$val'));
    return s;
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final app = AppScope.of(context);
    final lang = widget.lang;
    final list = posHelpFor(widget.kind);
    final term = _q.text.trim();
    final asked = isQuestion(term);
    final hits = term.isEmpty ? <HelpHit>[] : findHelp(term, list, max: 4);
    final shown = term.isEmpty ? list.where((a) => a['popular'] == true).map((a) => HelpHit(a, 0)).toList() : hits;
    final openId = _openQ == term ? _openId : (asked && hits.isNotEmpty ? hits.first.id : '');
    final dark = Theme.of(context).brightness == Brightness.dark;
    final waiting = posBiziWaiting.value;
    final mood = term.isEmpty ? (waiting != null && waiting.n > 0 ? BiziMood.worried : BiziMood.idle) : (hits.isNotEmpty ? BiziMood.happy : BiziMood.thinking);
    final actions = [
      (dark ? x('light') : x('dark'), dark ? LucideIcons.sun : LucideIcons.moon, 'dark light mode night theme ងងឹត ភ្លឺ', () => app.setTheme(dark ? 'light' : 'dark')),
      (lang == 'km' ? 'English' : 'ភាសាខ្មែរ', LucideIcons.languages, 'language khmer english ភាសា ខ្មែរ អង់គ្លេស', () => app.setLang(lang == 'km' ? 'en' : 'km')),
    ];
    final ws = words(term);
    final acts = term.isEmpty ? actions : actions.where((a) => ws.every((w) => hit(w, '${a.$1} ${a.$3}'.toLowerCase()) > 0)).toList();

    return Material(
      color: Colors.black.withValues(alpha: .35),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onClose,
        child: SafeArea(
          child: Center(
            child: GestureDetector(
              onTap: () {}, // taps inside stay inside
              child: Container(
                key: const ValueKey('pos-bizi-panel'),
                constraints: const BoxConstraints(maxWidth: 560, maxHeight: 640),
                margin: const EdgeInsets.all(16),
                decoration: BoxDecoration(color: c.appBg, borderRadius: BorderRadius.circular(22), boxShadow: c.popShadow),
                clipBehavior: Clip.antiAlias,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
                      child: Row(
                        children: [
                          Container(
                            width: 44,
                            height: 44,
                            decoration: BoxDecoration(color: c.card, shape: BoxShape.circle),
                            alignment: Alignment.center,
                            child: BiziFace(mood: mood, size: 36),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Container(
                              height: 48,
                              padding: const EdgeInsets.symmetric(horizontal: 12),
                              decoration: BoxDecoration(
                                color: c.card,
                                borderRadius: BorderRadius.circular(14),
                                border: Border.all(color: c.brand, width: 1.5),
                              ),
                              child: Row(
                                children: [
                                  Icon(LucideIcons.search, size: 18, color: c.muted),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: TextField(
                                      key: const ValueKey('pos-bizi-input'),
                                      controller: _q,
                                      autofocus: true,
                                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: c.ink),
                                      decoration: InputDecoration(
                                        isCollapsed: true,
                                        border: InputBorder.none,
                                        hintText: x('ph'),
                                        hintStyle: TextStyle(color: c.muted),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          IconButton(
                            key: const ValueKey('pos-bizi-close'),
                            onPressed: widget.onClose,
                            icon: Icon(LucideIcons.x, color: c.ink),
                            tooltip: x('close'),
                          ),
                        ],
                      ),
                    ),
                    Flexible(
                      child: ListView(
                        shrinkWrap: true,
                        padding: const EdgeInsets.fromLTRB(12, 0, 12, 16),
                        children: [
                          if (term.isEmpty && waiting != null && waiting.n > 0) ...[
                            _head(x('says'), c, hot: true),
                            _tile(
                              c,
                              icon: LucideIcons.bellRing,
                              warn: true,
                              title: x(waiting.n == 1 ? '${waiting.key}1' : waiting.key, {'n': waiting.n}),
                              sub: waiting.oldest == null ? '' : x('waited', {'min': DateTime.now().difference(waiting.oldest!).inMinutes}),
                              onTap: widget.onClose,
                            ),
                          ],
                          if (shown.isNotEmpty) _head(term.isEmpty ? x('questions') : x('howTo'), c, hot: true),
                          for (final h in shown) ...[
                            _tile(
                              c,
                              key: ValueKey('pos-bizi-q-${h.id}'),
                              icon: LucideIcons.lifeBuoy,
                              help: true,
                              title: h.q(lang),
                              sub: x('tapSteps'),
                              open: openId == h.id,
                              onTap: () => setState(() {
                                _openQ = term;
                                _openId = openId == h.id ? '' : h.id;
                              }),
                            ),
                            if (openId == h.id) _steps(c, h.steps(lang)),
                          ],
                          if (acts.isNotEmpty) ...[_head(x('quick'), c), for (final a in acts) _tile(c, icon: a.$2, title: a.$1, sub: x('doIt'), onTap: a.$4)],
                          if (term.isNotEmpty && hits.isEmpty && acts.isEmpty)
                            Padding(
                              key: const ValueKey('pos-bizi-none'),
                              padding: const EdgeInsets.all(20),
                              child: Text(
                                x('none'),
                                textAlign: TextAlign.center,
                                style: TextStyle(color: c.muted, height: 1.45),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _head(String text, C c, {bool hot = false}) => Padding(
    padding: const EdgeInsets.fromLTRB(4, 12, 4, 6),
    child: Text(
      text.toUpperCase(),
      style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w800, letterSpacing: .6, color: hot ? c.brandInk : c.muted),
    ),
  );

  Widget _tile(C c, {Key? key, required IconData icon, required String title, String sub = '', bool warn = false, bool help = false, bool open = false, required VoidCallback onTap}) {
    final (bg, fg) = warn
        ? (c.dangerBg, c.danger)
        : help
        ? (c.dark ? const Color(0x2E3B82F6) : const Color(0xFFE8F1FF), c.dark ? const Color(0xFF93C5FD) : const Color(0xFF1D4ED8))
        : (c.active, c.brandInk);
    return Material(
      color: open ? c.active : Colors.transparent,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        key: key,
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 9),
          child: Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(11)),
                child: Icon(icon, size: 18, color: fg),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
                    if (sub.isNotEmpty) Text(sub, style: TextStyle(color: c.muted, fontSize: 12.5)),
                  ],
                ),
              ),
              if (help) Icon(open ? LucideIcons.chevronUp : LucideIcons.chevronDown, size: 18, color: c.muted),
            ],
          ),
        ),
      ),
    );
  }

  Widget _steps(C c, List<String> steps) => Container(
    key: const ValueKey('pos-bizi-steps'),
    margin: const EdgeInsets.fromLTRB(8, 4, 8, 10),
    padding: const EdgeInsets.fromLTRB(14, 12, 14, 6),
    decoration: BoxDecoration(
      color: c.card,
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: c.line),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final (i, s) in steps.indexed)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 22,
                  height: 22,
                  margin: const EdgeInsets.only(right: 10, top: 1),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(color: c.active, shape: BoxShape.circle),
                  child: Text(
                    '${i + 1}',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: c.brandInk),
                  ),
                ),
                Expanded(child: Text(s, style: const TextStyle(fontSize: 14.5, height: 1.45))),
              ],
            ),
          ),
      ],
    ),
  );
}
