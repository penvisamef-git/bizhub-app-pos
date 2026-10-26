import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../core/app_state.dart';
import '../core/format.dart';
import '../core/theme.dart';

// ---------------------------------------------------------------- brand
class Logo extends StatelessWidget {
  final double height;
  final bool white;
  final bool iconOnly;
  const Logo({super.key, this.height = 30, this.white = false, this.iconOnly = false});
  @override
  Widget build(BuildContext context) =>
      SvgPicture.asset(iconOnly ? 'assets/brand/bizhub-icon.svg' : (white ? 'assets/brand/bizhub-logo-white.svg' : 'assets/brand/bizhub-logo.svg'), height: height, semanticsLabel: 'BizHub');
}

// the gold "B" coin (components/CoinIcon.jsx)
class CoinIcon extends StatelessWidget {
  final double size;
  const CoinIcon({super.key, this.size = 22});
  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        children: [
          Positioned(
            left: size * .06,
            right: size * .06,
            top: size * .12,
            bottom: 0,
            child: const DecoratedBox(
              decoration: BoxDecoration(shape: BoxShape.circle, color: Color(0xFFC97A10)),
            ),
          ),
          Positioned(
            left: size * .06,
            right: size * .06,
            top: size * .03,
            bottom: size * .09,
            child: Container(
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Color(0xFFFFD25E), Color(0xFFF0A020)]),
              ),
              alignment: Alignment.center,
              child: Container(
                margin: EdgeInsets.all(size * .1),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: const Color(0xD9FFF3C4), width: size * .05),
                ),
                alignment: Alignment.center,
                child: Text(
                  'B',
                  style: TextStyle(fontSize: size * .4, fontWeight: FontWeight.w800, color: const Color(0xFF9A5400), height: 1, fontFamily: 'PlusJakartaSans'),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------- business types
const typeIcons = <String, IconData>{
  'namecard': LucideIcons.idCard,
  'menu_qr': LucideIcons.qrCode,
  'flipbook': LucideIcons.bookOpen,
  'qr_gen': LucideIcons.scanLine,
  'website': LucideIcons.globe,
  'debt_book': LucideIcons.notebookPen,
  'stamp_card': LucideIcons.stamp,
  'restaurant': LucideIcons.utensilsCrossed,
  'attendance': LucideIcons.fingerprint,
  'guest_house': LucideIcons.bedDouble,
  'mart': LucideIcons.shoppingBasket,
  'event': LucideIcons.ticket,
  'tg_store': LucideIcons.send,
};
// the small icons in "My businesses" rows (DashboardPage.jsx BizRow)
const rowIcons = <String, IconData>{
  'restaurant': LucideIcons.chefHat,
  'namecard': LucideIcons.contact,
  'attendance': LucideIcons.fingerprint,
  'guest_house': LucideIcons.bedDouble,
  'mart': LucideIcons.shoppingBasket,
  'menu_qr': LucideIcons.qrCode,
  'flipbook': LucideIcons.bookOpen,
  'qr_gen': LucideIcons.scanLine,
  'website': LucideIcons.globe,
  'debt_book': LucideIcons.notebookPen,
  'stamp_card': LucideIcons.stamp,
};

// coloured square icon, same gradient as the homepage service icons
class TypeIcon extends StatelessWidget {
  final String type;
  final double size;
  const TypeIcon(this.type, {super.key, this.size = 44});
  @override
  Widget build(BuildContext context) {
    final g = Brand.typeGrad[type] ?? context.c.grad;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(size * .32),
        gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: g),
      ),
      child: Icon(typeIcons[type] ?? LucideIcons.sparkles, color: Colors.white, size: size * .48),
    );
  }
}

// ---------------------------------------------------------------- surfaces
class Panel extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final EdgeInsetsGeometry margin;
  final VoidCallback? onTap;
  final Color? color;
  const Panel({super.key, required this.child, this.padding = const EdgeInsets.all(20), this.margin = EdgeInsets.zero, this.onTap, this.color});
  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final box = Container(
      margin: margin,
      decoration: BoxDecoration(color: color ?? c.card, borderRadius: BorderRadius.circular(22), boxShadow: c.cardShadow),
      child: Material(
        type: MaterialType.transparency,
        borderRadius: BorderRadius.circular(22),
        clipBehavior: Clip.antiAlias,
        child: onTap == null
            ? Padding(padding: padding, child: child)
            : InkWell(
                onTap: onTap,
                child: Padding(padding: padding, child: child),
              ),
      ),
    );
    return box;
  }
}

class SecHead extends StatelessWidget {
  final String title;
  final String? sub;
  final Widget? trailing;
  const SecHead(this.title, {super.key, this.sub, this.trailing});
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: Theme.of(context).textTheme.titleMedium),
                if (sub != null && sub!.isNotEmpty) Text(sub!, style: Theme.of(context).textTheme.bodySmall),
              ],
            ),
          ),
          ?trailing,
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------- buttons (md-btn)
enum BtnKind { primary, ghost, solid, danger, white }

class Btn extends StatelessWidget {
  final String label;
  final IconData? icon;
  final VoidCallback? onTap;
  final BtnKind kind;
  final bool busy;
  final bool small;
  final bool expand;
  final Widget? lead;
  const Btn(this.label, {super.key, this.icon, this.onTap, this.kind = BtnKind.primary, this.busy = false, this.small = false, this.expand = false, this.lead});

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final off = onTap == null || busy;
    final h = small ? 40.0 : 50.0;
    final (bg, fg, border, shadow) = switch (kind) {
      BtnKind.primary => (null, Colors.white, null, c.orangeShadow),
      BtnKind.ghost => (c.card, c.ink, c.line, c.cardShadow),
      BtnKind.solid => (c.solid, c.onSolid, null, const <BoxShadow>[]),
      BtnKind.danger => (c.dangerBg, c.danger, null, const <BoxShadow>[]),
      BtnKind.white => (Colors.white, const Color(0xFF9E380A), null, const <BoxShadow>[]),
    };
    final content = Row(
      mainAxisSize: expand ? MainAxisSize.max : MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (busy)
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2.2, color: fg)),
          )
        else if (lead != null)
          Padding(padding: const EdgeInsets.only(right: 8), child: lead)
        else if (icon != null)
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: Icon(icon, size: small ? 16 : 18, color: fg),
          ),
        Flexible(
          child: Text(
            label,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(color: fg, fontWeight: FontWeight.w700, fontSize: small ? 13.5 : 15.5),
          ),
        ),
      ],
    );
    return Semantics(
      container: true, // its own node: a screen reader (and tests) find the button by its words
      button: true,
      enabled: !off,
      child: Opacity(
        opacity: off && !busy ? .5 : 1,
        child: Container(
          height: h,
          decoration: BoxDecoration(
            color: bg,
            gradient: kind == BtnKind.primary ? c.gradient : null,
            borderRadius: BorderRadius.circular(999),
            border: border == null ? null : Border.all(color: border),
            boxShadow: off ? null : shadow,
          ),
          child: Material(
            type: MaterialType.transparency,
            borderRadius: BorderRadius.circular(999),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: off ? null : onTap,
              child: Padding(
                padding: EdgeInsets.symmetric(horizontal: small ? 12 : 22),
                child: content,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// round icon button (theme / refresh / close)
class RoundBtn extends StatelessWidget {
  final IconData icon;
  final VoidCallback? onTap;
  final String? tip;
  final double size;
  final Color? bg, fg;
  const RoundBtn(this.icon, {super.key, this.onTap, this.tip, this.size = 44, this.bg, this.fg});
  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final b = Material(
      color: bg ?? c.card,
      shape: const CircleBorder(),
      elevation: 0,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: SizedBox(
          width: size,
          height: size,
          child: Icon(icon, size: size * .45, color: fg ?? c.ink),
        ),
      ),
    );
    return Container(
      decoration: BoxDecoration(shape: BoxShape.circle, boxShadow: bg == null ? c.cardShadow : null),
      child: tip == null ? b : Tooltip(message: tip!, child: b),
    );
  }
}

// ---------------------------------------------------------------- chips (status, tx type)
enum Tone { good, warn, danger, brand, muted, lime }

class Chip2 extends StatelessWidget {
  final String text;
  final Tone tone;
  final IconData? icon;
  const Chip2(this.text, {super.key, this.tone = Tone.muted, this.icon});
  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final (bg, fg) = switch (tone) {
      Tone.good => (c.goodBg, c.good),
      Tone.warn => (c.warnBg, c.warn),
      Tone.danger => (c.dangerBg, c.danger),
      Tone.brand => (c.active, c.brandInk),
      Tone.lime => (c.limeBg, c.limeInk),
      Tone.muted => (c.chip, c.muted),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(999)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[Icon(icon, size: 12, color: fg), const SizedBox(width: 4)],
          Text(
            text,
            style: TextStyle(color: fg, fontSize: 12, fontWeight: FontWeight.w700, height: 1.3),
          ),
        ],
      ),
    );
  }
}

// a picture from the internet, kept on the phone after the first time (faster, less mobile data)
ImageProvider netImage(String url) => kIsWeb ? NetworkImage(url) : CachedNetworkImageProvider(url);

// a photo field from the API: "https://…" or { url, public_id }
String photoUrl(Object? v) => v is Map ? '${v['url'] ?? ''}' : (v is String ? v : '');

class Avatar extends StatelessWidget {
  final String name;
  final String photo;
  final double size;
  final bool brand;
  const Avatar({super.key, required this.name, this.photo = '', this.size = 40, this.brand = false});
  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: brand ? c.gradient : null,
        color: brand ? null : c.active,
        boxShadow: brand ? c.orangeShadow : null,
        image: photo.isNotEmpty ? DecorationImage(image: netImage(photo), fit: BoxFit.cover) : null,
      ),
      alignment: Alignment.center,
      child: photo.isNotEmpty
          ? null
          : Text(
              initialOf(name),
              style: TextStyle(color: brand ? Colors.white : c.brandInk, fontWeight: FontWeight.w800, fontSize: size * .4),
            ),
    );
  }
}

// ---------------------------------------------------------------- inputs (auth-form .field / md-field)
class Field extends StatefulWidget {
  final String? label;
  final Widget? labelTrailing;
  final String? hint;
  final IconData? icon;
  final TextEditingController controller;
  final bool password;
  final TextInputType? keyboard;
  final bool invalid;
  final bool enabled;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmit;
  final Iterable<String>? autofill;
  final int? maxLength;
  final Widget? prefix;
  final Widget? suffix;
  final TextAlign align;
  final TextStyle? style;
  final bool public; // public pages use the warm colours
  final int maxLines;
  final bool autofocus;
  final FocusNode? focusNode;
  const Field({
    super.key,
    this.label,
    this.labelTrailing,
    this.hint,
    this.icon,
    required this.controller,
    this.password = false,
    this.keyboard,
    this.invalid = false,
    this.enabled = true,
    this.onChanged,
    this.onSubmit,
    this.autofill,
    this.maxLength,
    this.prefix,
    this.suffix,
    this.align = TextAlign.start,
    this.style,
    this.public = false,
    this.maxLines = 1,
    this.autofocus = false,
    this.focusNode,
  });
  @override
  State<Field> createState() => _FieldState();
}

class _FieldState extends State<Field> {
  bool _show = false;
  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final ink = widget.public ? c.pubInk : c.ink;
    final muted = widget.public ? c.pubMuted : c.muted;
    final line = widget.invalid ? c.danger : (widget.public ? c.pubLineStrong : c.line);
    final input = TextField(
      controller: widget.controller,
      focusNode: widget.focusNode,
      autofocus: widget.autofocus,
      obscureText: widget.password && !_show,
      keyboardType: widget.keyboard,
      enabled: widget.enabled,
      onChanged: widget.onChanged,
      onSubmitted: widget.onSubmit,
      autofillHints: widget.autofill,
      maxLength: widget.maxLength,
      maxLines: widget.maxLines,
      textAlign: widget.align,
      style: widget.style ?? TextStyle(fontSize: 16, color: ink, fontWeight: FontWeight.w500),
      decoration: InputDecoration(
        counterText: '',
        hintText: widget.hint,
        hintStyle: TextStyle(color: muted.withValues(alpha: .8), fontWeight: FontWeight.w400),
        filled: true,
        fillColor: widget.public ? c.pubBg : c.bg2,
        isDense: true,
        contentPadding: EdgeInsets.symmetric(horizontal: widget.icon == null && widget.prefix == null ? 18 : 4, vertical: 17),
        prefixIcon: widget.prefix ?? (widget.icon == null ? null : Icon(widget.icon, size: 19, color: muted)),
        suffixIcon:
            widget.suffix ??
            (widget.password
                ? IconButton(
                    onPressed: () => setState(() => _show = !_show),
                    icon: Icon(_show ? LucideIcons.eyeOff : LucideIcons.eye, size: 19, color: muted),
                  )
                : null),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: BorderSide(color: line),
        ),
        disabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: BorderSide(color: line),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: BorderSide(color: widget.invalid ? c.danger : c.brand, width: 1.6),
        ),
      ),
    );
    if (widget.label == null) return input;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 8, left: 2),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  widget.label!,
                  style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14.5, color: ink),
                ),
              ),
              ?widget.labelTrailing,
            ],
          ),
        ),
        // no hint: the label names the box for screen readers
        widget.hint == null ? Semantics(label: widget.label, child: input) : input,
      ],
    );
  }
}

// ---------------------------------------------------------------- messages
class Alert extends StatelessWidget {
  final String text;
  final Tone tone;
  final Widget? action;
  const Alert(this.text, {super.key, this.tone = Tone.danger, this.action});
  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final (bg, fg) = switch (tone) {
      Tone.good => (c.goodBg, c.good),
      Tone.warn => (c.warnBg, c.warn),
      Tone.brand => (c.active, c.brandInk),
      _ => (c.dangerBg, c.danger),
    };
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(16)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            text,
            style: TextStyle(color: fg, fontWeight: FontWeight.w600, fontSize: 14, height: 1.45),
          ),
          if (action != null) ...[const SizedBox(height: 8), action!],
        ],
      ),
    );
  }
}

void toast(BuildContext context, String text) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(text)));
}

class Muted extends StatelessWidget {
  final String text;
  final TextAlign align;
  const Muted(this.text, {super.key, this.align = TextAlign.start});
  @override
  Widget build(BuildContext context) => Text(
    text,
    textAlign: align,
    style: TextStyle(color: context.c.muted, fontSize: 14, height: 1.5),
  );
}

// grey shimmer box while loading (components/skeleton)
class Skel extends StatefulWidget {
  final double? w;
  final double h;
  final double r;
  const Skel({super.key, this.w, this.h = 16, this.r = 10});
  @override
  State<Skel> createState() => _SkelState();
}

class _SkelState extends State<Skel> with SingleTickerProviderStateMixin {
  late final AnimationController _a = AnimationController(vsync: this, duration: const Duration(milliseconds: 1200))..repeat(reverse: true);
  @override
  void dispose() {
    _a.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return FadeTransition(
      opacity: Tween(begin: .45, end: 1.0).animate(_a),
      child: Container(
        width: widget.w,
        height: widget.h,
        decoration: BoxDecoration(color: c.chip, borderRadius: BorderRadius.circular(widget.r)),
      ),
    );
  }
}

class SkelList extends StatelessWidget {
  final int rows;
  const SkelList({super.key, this.rows = 4});
  @override
  Widget build(BuildContext context) => Column(
    children: List.generate(
      rows,
      (i) => const Padding(
        padding: EdgeInsets.symmetric(vertical: 8),
        child: Row(
          children: [
            Skel(w: 40, h: 40, r: 20),
            SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Skel(h: 14), SizedBox(height: 6), Skel(w: 120, h: 12)]),
            ),
          ],
        ),
      ),
    ),
  );
}

// "Couldn't load" + Try again
class LoadError extends StatelessWidget {
  final String text;
  final String retry;
  final VoidCallback onRetry;
  const LoadError({super.key, required this.text, required this.retry, required this.onRetry});
  @override
  Widget build(BuildContext context) => Panel(
    child: Column(
      children: [
        Icon(LucideIcons.wifiOff, color: context.c.muted, size: 28),
        const SizedBox(height: 10),
        Muted(text, align: TextAlign.center),
        const SizedBox(height: 14),
        Btn(retry, icon: LucideIcons.refreshCw, onTap: onRetry, small: true),
      ],
    ),
  );
}

// ---------------------------------------------------------------- light / dark
// Appearance: Light · Dark · Same as the phone (kept on the device)
Future<void> pickTheme(BuildContext context) {
  final app = AppState.i;
  final t = app.t;
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (sheet) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
            child: Text(t('app.theme'), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 18)),
          ),
          for (final (k, icon) in [('light', LucideIcons.sun), ('dark', LucideIcons.moon), ('system', LucideIcons.smartphone)])
            ListTile(
              leading: Icon(icon),
              title: Text(t('app.theme.$k')),
              trailing: app.theme == k ? Icon(LucideIcons.check, color: sheet.c.brand) : null,
              onTap: () {
                app.setTheme(k);
                Navigator.pop(sheet);
              },
            ),
          const SizedBox(height: 8),
        ],
      ),
    ),
  );
}

// a round sun / moon button for headers: tap → the Appearance choice
class ThemeBtn extends StatelessWidget {
  const ThemeBtn({super.key});
  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return IconButton(onPressed: () => pickTheme(context), icon: Icon(dark ? LucideIcons.moon : LucideIcons.sun), tooltip: AppState.i.t('app.theme'));
  }
}

// on a "Try demo" sample shop: a small note with the staff PIN, under the PIN pad title
class DemoPinHint extends StatelessWidget {
  const DemoPinHint({super.key});
  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    if (!app.demo || app.demoPin.isEmpty) return const SizedBox.shrink();
    final c = context.c;
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
          decoration: BoxDecoration(color: c.active, borderRadius: BorderRadius.circular(999)),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(LucideIcons.sparkles, size: 14, color: c.brandInk),
              const SizedBox(width: 6),
              Text(app.t('demo.pin', {'pin': app.demoPin}), style: TextStyle(color: c.brandInk, fontWeight: FontWeight.w700)),
            ],
          ),
        ),
      ),
    );
  }
}
