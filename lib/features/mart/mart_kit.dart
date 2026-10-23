import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/api.dart' show ApiError;
import '../../core/theme.dart';
import '../../widgets/ui.dart';
import '../restaurant/engine/calc.dart' show J, js;
import '../restaurant/pos_ui.dart';
import 'engine/mart_pos.dart';

// small pieces shared by the manager pages (Expiry dates, Purchase orders)

// a number card: icon, big value, small label
class MartBox extends StatelessWidget {
  final IconData icon;
  final String value, label;
  final Color fg;
  const MartBox({super.key, required this.icon, required this.value, required this.label, required this.fg});
  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: c.card, borderRadius: BorderRadius.circular(16)),
      child: Row(
        children: [
          Icon(icon, color: fg),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    value,
                    style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18, color: fg),
                  ),
                ),
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: c.muted, fontSize: 12),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// a coloured pill: (text, foreground, background)
class MartPill extends StatelessWidget {
  final String text;
  final Color fg, bg;
  const MartPill(this.text, {super.key, required this.fg, required this.bg});
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
    decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(999)),
    child: Text(
      text,
      style: TextStyle(color: fg, fontSize: 11.5, fontWeight: FontWeight.w700),
    ),
  );
}

// the page title + one line under it, with buttons on the right
class MartHead extends StatelessWidget {
  final String title, sub;
  final List<Widget> actions;
  const MartHead({super.key, required this.title, required this.sub, this.actions = const []});
  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (title.isNotEmpty) Text(title, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 18)),
              if (sub.isNotEmpty) Text(sub, maxLines: 2, style: TextStyle(color: c.muted, fontSize: 12.5)),
            ],
          ),
        ),
        ...actions,
      ],
    );
  }
}

// a manager page opened from the menu: its own top bar
Future<void> openMartPage(BuildContext context, String title, Widget body) => Navigator.of(context).push(
  MaterialPageRoute(
    builder: (ctx) => Scaffold(
      backgroundColor: ctx.c.appBg,
      appBar: AppBar(
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w800)),
        backgroundColor: ctx.c.appBg,
        surfaceTintColor: Colors.transparent,
      ),
      body: SafeArea(
        top: false,
        child: Center(
          child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 980), child: body),
        ),
      ),
    ),
  ),
);

// choose one product from this device's copy (name or barcode)
Future<J?> pickMartProduct(BuildContext context, {Set<String> exclude = const {}}) {
  final t = tr(context);
  final q = TextEditingController();
  final all = MartPos.i.products.where((p) => !exclude.contains(js(p['_id']))).toList()..sort((a, b) => js(a['name']).toLowerCase().compareTo(js(b['name']).toLowerCase()));
  return posSheet<J>(
    context,
    title: t('mx.pickProduct'),
    maxWidth: 520,
    body: (ctx) => StatefulBuilder(
      builder: (ctx, set) {
        final s = q.text.trim().toLowerCase();
        final found = (s.isEmpty ? all : all.where((p) => js(p['name']).toLowerCase().contains(s) || js(p['barcode']).startsWith(s))).take(40).toList();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Field(
              controller: q,
              hint: t('mart.search'),
              icon: LucideIcons.search,
              autofocus: true,
              onChanged: (_) => set(() {}),
              onSubmit: (_) => found.isNotEmpty ? Navigator.pop(ctx, found.first) : null,
            ),
            const SizedBox(height: 6),
            if (found.isEmpty)
              Padding(
                padding: const EdgeInsets.all(20),
                child: Muted(t('mx.none'), align: TextAlign.center),
              ),
            for (final p in found)
              ListTile(
                dense: true,
                contentPadding: const EdgeInsets.symmetric(horizontal: 6),
                title: Text(js(p['name']), style: const TextStyle(fontWeight: FontWeight.w700)),
                subtitle: js(p['barcode']).isEmpty ? null : Text(js(p['barcode'])),
                onTap: () => Navigator.pop(ctx, p),
              ),
          ],
        );
      },
    ),
  );
}

// a day as YYYY-MM-DD from the calendar
Future<String?> pickMartDay(BuildContext context, {String initial = '', int back = 365}) async {
  final now = DateTime.now();
  final init = DateTime.tryParse(initial) ?? now.add(const Duration(days: 90));
  final first = now.subtract(Duration(days: back));
  final v = await showDatePicker(context: context, firstDate: init.isBefore(first) ? init : first, lastDate: DateTime(now.year + 10), initialDate: init);
  return v == null ? null : '${v.year}-${v.month.toString().padLeft(2, '0')}-${v.day.toString().padLeft(2, '0')}';
}

// a field for a day: shows the day, opens the calendar
class DayField extends StatelessWidget {
  final String label, value;
  final ValueChanged<String> onPick;
  final String Function(String)? show; // how the day is written (default YYYY-MM-DD)
  const DayField({super.key, required this.label, required this.value, required this.onPick, this.show});
  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 6),
          child: Text(label, style: const TextStyle(fontWeight: FontWeight.w700)),
        ),
        Material(
          color: c.bg2,
          borderRadius: BorderRadius.circular(14),
          child: InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: () async {
              final d = await pickMartDay(context, initial: value);
              if (d != null) onPick(d);
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 15),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: c.line),
              ),
              child: Row(
                children: [
                  Icon(LucideIcons.calendarDays, size: 18, color: c.muted),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      value.isEmpty ? '—' : (show?.call(value) ?? value),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

// the error text for a failed call ("Needs internet." when there is no connection)
String martErr(BuildContext context, Object e) => e is ApiError ? (e.network ? tr(context)('rpos.needInternetShort') : e.message) : '$e';
