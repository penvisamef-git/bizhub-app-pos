import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/api.dart';
import '../../widgets/ui.dart' show netImage;
import 'sc_common.dart';
import 'sc_data.dart';

// The card itself (StampCard.jsx): shop, stamps (filled / empty), small rewards on the way, the last reward.
// member = { name, no, stamps, claimed } — null = a preview with 60% stamps.
class ScCardView extends StatelessWidget {
  final ScShop shop;
  final Json? member;
  final String lang;
  final bool compact;
  final int pop; // the slot that just got a stamp (-1 = none)
  const ScCardView({super.key, required this.shop, this.member, required this.lang, this.compact = false, this.pop = -1});

  static const _tilt = [-12, 8, -4, 14, -9, 5, -15, 10, -6, 12];

  @override
  Widget build(BuildContext context) {
    final t = scThemeOf(shop.theme);
    final accent = scHex(shop.color) ?? t.accent;
    final icon = scIconOf(shop.icon);
    final goal = shop.goal.clamp(3, 20);
    final levels = shop.levels.isNotEmpty
        ? shop.levels
        : [
            {'at': goal, 'en': 'Reward', 'km': 'រង្វាន់'},
          ];
    final last = levels.last;
    final stamps = member == null ? (goal * .6).round() : n(member!['stamps']).toInt();
    final have = math.min(stamps, goal);
    final extra = math.max(0, stamps - goal);
    final cols = goal <= 5
        ? goal
        : goal <= 10
        ? 5
        : goal <= 12
        ? 6
        : 5;
    final ready = member != null && stamps >= n(last['at']);
    final claimed = (member?['claimed'] as List? ?? const []).map((e) => n(e).toInt()).toSet();
    final pad = compact ? 14.0 : 20.0;
    final km = lang == 'km';
    TextStyle s(double size, Color col, {FontWeight w = FontWeight.w400}) => TextStyle(fontSize: size, color: col, fontWeight: w, height: 1.25);

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 440),
        child: DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(compact ? 18 : 24),
            boxShadow: [BoxShadow(color: const Color(0xFF16171B).withValues(alpha: .22), blurRadius: 30, offset: const Offset(0, 14), spreadRadius: -12)],
          ),
          child: ClipPath(
            clipper: _Notches(top: compact ? 52 : 62, radius: compact ? 18 : 24),
            child: Container(
              decoration: BoxDecoration(gradient: scGradient(t.bg, t.angle)),
              child: CustomPaint(
                painter: t.pat.isEmpty ? null : _Pattern(t.pat, t.dark),
                child: Padding(
                  padding: EdgeInsets.fromLTRB(pad, pad, pad, compact ? 12 : 16),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          Container(
                            width: compact ? 34 : 42,
                            height: compact ? 34 : 42,
                            clipBehavior: Clip.antiAlias,
                            decoration: BoxDecoration(color: t.slot, borderRadius: BorderRadius.circular(compact ? 10 : 13)),
                            child: shop.logo.isNotEmpty
                                ? Image(
                                    image: netImage(shop.logo),
                                    fit: BoxFit.cover,
                                    errorBuilder: (_, _, _) => Icon(icon, size: 20, color: accent),
                                  )
                                : Icon(icon, size: 20, color: accent),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  shop.name.isEmpty ? '—' : shop.name,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: s(compact ? 15 : 16, t.ink, w: FontWeight.w800),
                                ),
                                Text(
                                  member != null
                                      ? '${str(member!['name'])}${member!['no'] != null ? ' · #${member!['no']}' : ''}'
                                      : km
                                      ? 'កាតប្រមូលត្រា'
                                      : 'Stamp card',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: s(12.5, t.muted),
                                ),
                              ],
                            ),
                          ),
                          Text.rich(
                            TextSpan(
                              text: '$stamps',
                              style: s(compact ? 18 : 24, t.ink, w: FontWeight.w800),
                              children: [TextSpan(text: '/$goal', style: s(13, t.muted))],
                            ),
                          ),
                        ],
                      ),
                      Padding(
                        padding: EdgeInsets.symmetric(vertical: compact ? 10 : 14),
                        child: CustomPaint(size: const Size(double.infinity, 1.5), painter: _Dash(t.line)),
                      ),
                      LayoutBuilder(
                        builder: (context, box) {
                          const gap = 10.0;
                          final size = (box.maxWidth - gap * (cols - 1)) / cols;
                          return Wrap(
                            spacing: gap,
                            runSpacing: gap + 4,
                            children: [
                              for (var i = 0; i < goal; i++)
                                () {
                                  final at = i + 1;
                                  final filled = at <= have;
                                  final level = levels.where((l) => n(l['at']).toInt() == at).firstOrNull;
                                  final given = level != null && claimed.contains(at);
                                  final slot = Container(
                                    width: size,
                                    height: size,
                                    alignment: Alignment.center,
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      color: filled ? Color.alphaBlend(accent.withValues(alpha: .14), t.slot) : t.slot,
                                      border: Border.all(
                                        color: filled
                                            ? accent
                                            : level != null
                                            ? accent.withValues(alpha: .55)
                                            : t.line,
                                        width: filled ? 2 : 1.5,
                                      ),
                                    ),
                                    child: filled
                                        ? Transform.rotate(
                                            angle: _tilt[i % 10] * math.pi / 180,
                                            child: Icon(icon, size: compact ? 15 : 19, color: accent),
                                          )
                                        : level != null
                                        ? Icon(LucideIcons.gift, size: compact ? 13 : 16, color: accent)
                                        : Text('$at', style: s(12, t.muted.withValues(alpha: .6), w: FontWeight.w700)),
                                  );
                                  return SizedBox(
                                    width: size,
                                    height: size,
                                    child: Stack(
                                      clipBehavior: Clip.none,
                                      children: [
                                        i == pop ? _Pop(child: slot) : slot,
                                        if (level != null && n(level['at']).toInt() != goal)
                                          Positioned(
                                            left: -size * .3,
                                            right: -size * .3,
                                            bottom: -7,
                                            child: Center(
                                              child: Container(
                                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                                                decoration: BoxDecoration(
                                                  color: accent.withValues(alpha: given ? .45 : 1),
                                                  borderRadius: BorderRadius.circular(99),
                                                ),
                                                child: Text(
                                                  levelName(level, lang),
                                                  maxLines: 1,
                                                  overflow: TextOverflow.ellipsis,
                                                  style: TextStyle(
                                                    fontSize: 9,
                                                    fontWeight: FontWeight.w800,
                                                    color: t.dark ? const Color(0xFF111111) : t.bg.first,
                                                    decoration: given ? TextDecoration.lineThrough : null,
                                                  ),
                                                ),
                                              ),
                                            ),
                                          ),
                                      ],
                                    ),
                                  );
                                }(),
                            ],
                          );
                        },
                      ),
                      SizedBox(height: compact ? 12 : 16),
                      Row(
                        children: [
                          Icon(LucideIcons.gift, size: 15, color: accent),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              ready
                                  ? (km ? '🎉 ${levelName(last, lang)} រួចរាល់!' : '🎉 ${levelName(last, lang)} is ready!')
                                  : km
                                  ? '$goal ត្រា = ${levelName(last, lang)}'
                                  : '$goal stamps = ${levelName(last, lang)}',
                              style: s(13.5, ready ? t.ink : t.muted, w: FontWeight.w700),
                            ),
                          ),
                          if (extra > 0)
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                              decoration: BoxDecoration(color: t.slot, borderRadius: BorderRadius.circular(99)),
                              child: Text('+$extra', style: s(11, t.ink, w: FontWeight.w700)),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// the stamp lands: big → small, like a rubber stamp
class _Pop extends StatelessWidget {
  final Widget child;
  const _Pop({required this.child});
  @override
  Widget build(BuildContext context) => TweenAnimationBuilder<double>(
    tween: Tween(begin: 0, end: 1),
    duration: const Duration(milliseconds: 600),
    curve: Curves.elasticOut,
    builder: (_, v, c) => Opacity(
      opacity: v.clamp(0, 1).toDouble(),
      child: Transform.scale(scale: 1.8 - .8 * v, child: c),
    ),
    child: child,
  );
}

// a punched notch on each side, like a paper loyalty card
class _Notches extends CustomClipper<Path> {
  final double top, radius;
  const _Notches({required this.top, required this.radius});
  @override
  Path getClip(Size size) {
    final card = Path()..addRRect(RRect.fromRectAndRadius(Offset.zero & size, Radius.circular(radius)));
    final holes = Path()
      ..addOval(Rect.fromCircle(center: Offset(0, top + 9), radius: 9))
      ..addOval(Rect.fromCircle(center: Offset(size.width, top + 9), radius: 9));
    return Path.combine(PathOperation.difference, card, holes);
  }

  @override
  bool shouldReclip(_Notches old) => old.top != top || old.radius != radius;
}

class _Dash extends CustomPainter {
  final Color color;
  const _Dash(this.color);
  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()
      ..color = color
      ..strokeWidth = 1.5;
    for (double x = 0; x < size.width; x += 9) {
      canvas.drawLine(Offset(x, 0), Offset(math.min(x + 5, size.width), 0), p);
    }
  }

  @override
  bool shouldRepaint(_Dash old) => old.color != color;
}

// the light patterns some designs have (stamp.css .sc-pat)
class _Pattern extends CustomPainter {
  final String kind;
  final bool dark;
  const _Pattern(this.kind, this.dark);
  @override
  void paint(Canvas canvas, Size size) {
    final col = dark ? Colors.white.withValues(alpha: kind == 'stars' ? .45 : .08) : Colors.black.withValues(alpha: .06);
    final p = Paint()..color = col;
    final line = Paint()
      ..color = col
      ..style = PaintingStyle.stroke;
    canvas.save();
    canvas.clipRect(Offset.zero & size);
    switch (kind) {
      case 'dots':
        for (double y = 8; y < size.height; y += 16) {
          for (double x = 8; x < size.width; x += 16) {
            canvas.drawCircle(Offset(x, y), 1.6, p);
          }
        }
      case 'stripes':
        line.strokeWidth = 8;
        for (double d = -size.height; d < size.width + size.height; d += 20) {
          canvas.drawLine(Offset(d, 0), Offset(d + size.height, size.height), line);
        }
      case 'grid':
        line.strokeWidth = 1;
        for (double x = 0; x < size.width; x += 18) {
          canvas.drawLine(Offset(x, 0), Offset(x, size.height), line);
        }
        for (double y = 0; y < size.height; y += 18) {
          canvas.drawLine(Offset(0, y), Offset(size.width, y), line);
        }
      case 'waves':
        line.strokeWidth = 2;
        for (double y = 0; y < size.height + 22; y += 22) {
          for (double x = 0; x < size.width + 36; x += 36) {
            canvas.drawArc(Rect.fromCircle(center: Offset(x + 18, y + 26), radius: 16), math.pi * 1.2, math.pi * .6, false, line);
          }
        }
      case 'flowers':
        for (double y = 0; y < size.height + 34; y += 34) {
          for (double x = 0; x < size.width + 34; x += 34) {
            canvas.drawCircle(Offset(x, y), 3, p);
            canvas.drawCircle(Offset(x + 17, y + 17), 2, p);
          }
        }
      case 'clouds':
        for (double y = 0; y < size.height; y += 80) {
          for (double x = 0; x < size.width; x += 120) {
            canvas.drawOval(Rect.fromCenter(center: Offset(x + 36, y + 24), width: 44, height: 20), p);
            canvas.drawOval(Rect.fromCenter(center: Offset(x + 90, y + 60), width: 60, height: 24), p);
          }
        }
      case 'bubbles':
        line.strokeWidth = 1.5;
        for (double y = 0; y < size.height; y += 60) {
          for (double x = 0; x < size.width; x += 60) {
            canvas.drawCircle(Offset(x + 12, y + 18), 8, line);
            canvas.drawCircle(Offset(x + 42, y + 42), 5, line);
          }
        }
      case 'stars':
        for (double y = 0; y < size.height; y += 70) {
          for (double x = 0; x < size.width; x += 70) {
            canvas.drawCircle(Offset(x + 14, y + 21), 1.4, p);
            canvas.drawCircle(Offset(x + 49, y + 42), 1.8, p);
            canvas.drawCircle(Offset(x + 28, y + 56), 1, p);
          }
        }
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_Pattern old) => old.kind != kind || old.dark != dark;
}

// a small swatch of a card design (the design picker)
class ScThemeSwatch extends StatelessWidget {
  final ScTheme theme;
  final String icon;
  const ScThemeSwatch({super.key, required this.theme, required this.icon});
  @override
  Widget build(BuildContext context) {
    final i = scIconOf(icon);
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: Container(
        height: 64,
        decoration: BoxDecoration(gradient: scGradient(theme.bg, theme.angle)),
        child: CustomPaint(
          painter: theme.pat.isEmpty ? null : _Pattern(theme.pat, theme.dark),
          child: Center(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (var k = 0; k < 3; k++)
                  Container(
                    width: 22,
                    height: 22,
                    margin: const EdgeInsets.symmetric(horizontal: 2),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: k < 2 ? theme.accent : theme.slot,
                      border: Border.all(color: k < 2 ? theme.accent : theme.line, width: 1.5),
                    ),
                    child: k < 2 ? Icon(i, size: 12, color: theme.dark ? const Color(0xFF111111) : Colors.white) : null,
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
