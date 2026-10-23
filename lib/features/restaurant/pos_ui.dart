import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/app_state.dart';
import '../../core/format.dart' as f;
import '../../core/i18n.dart';
import '../../core/theme.dart';
import 'engine/calc.dart';

// Small pieces the restaurant POS screens share.

T tr(BuildContext context) => AppScope.of(context).t;
String m$(Object? v, String currency) => f.money(v, currency);
String other(String c) => c == 'USD' ? 'KHR' : 'USD';
String nameOf(J? x, String lang) {
  if (x == null) return '';
  final km = js(x['name_km']), en = js(x['name_en']);
  final n = lang == 'km' ? (km.isNotEmpty ? km : en) : (en.isNotEmpty ? en : km);
  return n.isNotEmpty ? n : js(x['name']);
}

// a phone (one column) or a tablet / desktop (side by side)
bool wide(BuildContext context) => MediaQuery.sizeOf(context).width >= 860;

// Big touch keypad. value = digits typed; dot → allow "."; enter → extra wide key under it
class Keypad extends StatelessWidget {
  final String value;
  final ValueChanged<String> onChanged;
  final int max;
  final bool dot;
  final bool disabled;
  final String? enterLabel;
  final VoidCallback? onEnter;
  final double keyHeight;
  const Keypad({super.key, required this.value, required this.onChanged, this.max = 12, this.dot = false, this.disabled = false, this.enterLabel, this.onEnter, this.keyHeight = 58});

  void _press(String k) {
    if (disabled) return;
    HapticFeedback.selectionClick();
    if (k == 'back') return onChanged(value.isEmpty ? '' : value.substring(0, value.length - 1));
    if (k == '.' && (!dot || value.contains('.'))) return;
    if (value.length >= max) return;
    if (k == '.' && value.isEmpty) return onChanged('0.');
    onChanged(value + k);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final keys = ['1', '2', '3', '4', '5', '6', '7', '8', '9', dot ? '.' : '00', '0', 'back'];
    Widget key(String k) => Material(
      color: c.card,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: disabled ? null : () => _press(k),
        child: SizedBox(
          height: keyHeight,
          child: Center(
            child: k == 'back'
                ? Icon(LucideIcons.delete, color: c.ink, semanticLabel: 'Delete')
                : Text(
                    k,
                    style: TextStyle(fontSize: 24, fontWeight: FontWeight.w700, color: disabled ? c.muted : c.ink),
                  ),
          ),
        ),
      ),
    );
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var r = 0; r < 4; r++)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              children: [
                for (var i = 0; i < 3; i++) ...[if (i > 0) const SizedBox(width: 8), Expanded(child: key(keys[r * 3 + i]))],
              ],
            ),
          ),
        if (onEnter != null)
          SizedBox(
            width: double.infinity,
            height: keyHeight - 4,
            child: FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: c.solid,
                foregroundColor: c.onSolid,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              ),
              onPressed: disabled ? null : onEnter,
              child: Text(enterLabel ?? '', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
            ),
          ),
      ],
    );
  }
}

// four dots for a PIN (red + shake when wrong)
class PinDots extends StatelessWidget {
  final int length;
  final bool error;
  const PinDots(this.length, {super.key, this.error = false});
  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return TweenAnimationBuilder<double>(
      key: ValueKey(error),
      tween: Tween(begin: 0, end: error ? 1 : 0),
      duration: const Duration(milliseconds: 380),
      builder: (_, v, child) => Transform.translate(offset: Offset(error ? sin(v * pi * 6) * 9 * (1 - v) : 0, 0), child: child),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          for (var i = 0; i < 4; i++)
            AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              width: 16,
              height: 16,
              margin: const EdgeInsets.symmetric(horizontal: 9),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: error ? c.danger : (i < length ? c.brand : Colors.transparent),
                border: Border.all(color: error ? c.danger : (i < length ? c.brand : c.lineStrong), width: 2),
              ),
            ),
        ],
      ),
    );
  }
}

// a sheet from the bottom (phone) or a dialog in the middle (tablet)
Future<R?> posSheet<R>(BuildContext context, {required String title, required WidgetBuilder body, WidgetBuilder? footer, double maxWidth = 560}) {
  final big = wide(context);
  Widget frame(BuildContext ctx) {
    final c = ctx.c;
    final content = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 14, 8, 6),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              IconButton(
                onPressed: () => Navigator.pop(ctx),
                icon: Icon(LucideIcons.x, color: c.muted),
                tooltip: MaterialLocalizations.of(ctx).closeButtonLabel,
              ),
            ],
          ),
        ),
        Flexible(
          child: SingleChildScrollView(padding: const EdgeInsets.fromLTRB(20, 4, 20, 16), child: body(ctx)),
        ),
        if (footer != null)
          Container(
            padding: EdgeInsets.fromLTRB(20, 12, 20, 12 + MediaQuery.paddingOf(ctx).bottom),
            decoration: BoxDecoration(
              border: Border(top: BorderSide(color: c.line)),
            ),
            child: footer(ctx),
          ),
      ],
    );
    return AnimatedPadding(
      duration: const Duration(milliseconds: 120),
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(ctx).bottom),
      child: content,
    );
  }

  if (big) {
    return showDialog<R>(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: ctx.c.appBg,
        insetPadding: const EdgeInsets.all(24),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(26)),
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: maxWidth, maxHeight: MediaQuery.sizeOf(ctx).height * .9),
          child: frame(ctx),
        ),
      ),
    );
  }
  return showModalBottomSheet<R>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: context.c.appBg,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(26))),
    builder: (ctx) => ConstrainedBox(
      constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(ctx).height * .92),
      child: frame(ctx),
    ),
  );
}

// a row of chips; one is "on"
class PosChips<V> extends StatelessWidget {
  final List<(V, String)> options;
  final V? value;
  final ValueChanged<V> onTap;
  final bool scroll;
  final bool Function(V)? enabled;
  const PosChips({super.key, required this.options, required this.value, required this.onTap, this.scroll = false, this.enabled});
  @override
  Widget build(BuildContext context) {
    final c = context.c;
    Widget chip(V v, String label) {
      final on = v == value;
      final ok = enabled?.call(v) ?? true;
      return Opacity(
        opacity: ok ? 1 : .45,
        child: Material(
          color: on ? c.solid : c.card,
          borderRadius: BorderRadius.circular(999),
          child: InkWell(
            borderRadius: BorderRadius.circular(999),
            onTap: ok ? () => onTap(v) : null,
            child: Container(
              constraints: const BoxConstraints(minHeight: 42),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(999),
                border: Border.all(color: on ? c.solid : c.line),
              ),
              child: Text(
                label,
                style: TextStyle(color: on ? c.onSolid : c.ink, fontWeight: FontWeight.w700, fontSize: 14),
              ),
            ),
          ),
        ),
      );
    }

    final list = [for (final (v, l) in options) chip(v, l)];
    if (scroll) {
      return SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [for (final w in list) Padding(padding: const EdgeInsets.only(right: 8), child: w)],
        ),
      );
    }
    return Wrap(spacing: 8, runSpacing: 8, children: list);
  }
}

// a total line: label … amount
class SumRow extends StatelessWidget {
  final String label, value;
  final bool big;
  final Color? color;
  const SumRow(this.label, this.value, {super.key, this.big = false, this.color});
  @override
  Widget build(BuildContext context) {
    final st = TextStyle(fontSize: big ? 20 : 14.5, fontWeight: big ? FontWeight.w800 : FontWeight.w600, color: color ?? (big ? context.c.ink : context.c.muted));
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Expanded(child: Text(label, style: st)),
          Text(value, style: st.copyWith(color: color ?? context.c.ink)),
        ],
      ),
    );
  }
}

// USD / riel amount box the keypad types into
class AmountBox extends StatelessWidget {
  final String label, value;
  final bool on;
  final VoidCallback onTap;
  const AmountBox({super.key, required this.label, required this.value, required this.on, required this.onTap});
  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Material(
      color: on ? c.active : c.card,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: on ? c.brand : c.line, width: on ? 2 : 1),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: TextStyle(color: c.muted, fontSize: 12.5, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 2),
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(value, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
