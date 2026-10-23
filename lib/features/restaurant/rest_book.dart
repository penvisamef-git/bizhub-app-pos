import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/format.dart' as f;
import '../../core/theme.dart';
import '../../widgets/ui.dart';
import 'engine/calc.dart';
import 'engine/rest_pos.dart';
import 'pos_ui.dart';

// Table bookings (works offline, syncs like orders) and the guest-order alerts from the table QR.

// new booking: table, name, phone (+ time, guests if known). Only a free table can be booked.
Future<void> showBookingForm(BuildContext context, {J? table}) {
  final t = tr(context);
  final pos = RestPos.i;
  final name = TextEditingController(), phone = TextEditingController(), guests = TextEditingController(), note = TextEditingController();
  final pick = ValueNotifier(js(table?['_id'])); // the table chosen
  String get0() => pick.value;
  TimeOfDay? time;
  final busy = {for (final o in pos.openOrders) js(o['table_id'])};
  final booked = {for (final b in pos.activeBookings) js(b['table_id'])};
  return posSheet(
    context,
    title: t('rpos.bookTable'),
    body: (ctx) => StatefulBuilder(
      builder: (ctx, set) {
        final c = ctx.c;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text.rich(
              TextSpan(
                children: [
                  TextSpan(
                    text: t('rpos.table'),
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  TextSpan(
                    text: '  · ${t('rpos.onlyFreeHint')}',
                    style: TextStyle(color: c.muted, fontSize: 12.5),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            PosChips<String>(
              value: pick.value,
              enabled: (id) => !busy.contains(id) && !booked.contains(id),
              onTap: (v) => set(() => pick.value = v),
              options: [for (final x in pos.tables) (js(x['_id']), js(x['name']))],
            ),
            const SizedBox(height: 14),
            Field(label: '${t('rpos.guestName')} *', controller: name, maxLength: 60, onChanged: (_) => set(() {})),
            const SizedBox(height: 12),
            Field(label: t('rpos.phone'), controller: phone, maxLength: 30, keyboard: TextInputType.phone, hint: '012 345 678'),
            const SizedBox(height: 12),
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8, left: 2),
                        child: Text(t('rpos.time'), style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14.5)),
                      ),
                      OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          minimumSize: const Size.fromHeight(54),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
                        ),
                        onPressed: () async {
                          final v = await showTimePicker(context: ctx, initialTime: time ?? TimeOfDay.now());
                          if (v != null) set(() => time = v);
                        },
                        icon: const Icon(LucideIcons.clock, size: 18),
                        label: Text(time == null ? '--:--' : time!.format(ctx)),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Field(label: t('rpos.guests'), controller: guests, keyboard: TextInputType.number, maxLength: 3),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Field(label: t('rpos.noteItem'), controller: note, maxLength: 200, hint: t('rpos.tableNotePh')),
          ],
        );
      },
    ),
    footer: (ctx) => ListenableBuilder(
      listenable: Listenable.merge([pick, name]),
      builder: (ctx, _) => Row(
        children: [
          Expanded(
            child: Btn(t('rpos.cancel'), kind: BtnKind.ghost, onTap: () => Navigator.pop(ctx)),
          ),
          const SizedBox(width: 8),
          Expanded(
            flex: 2,
            child: Btn(
              t('rpos.saveBooking'),
              icon: LucideIcons.calendarPlus,
              onTap: name.text.trim().isEmpty || get0().isEmpty
                  ? null
                  : () async {
                      String? at;
                      if (time != null) {
                        final now = DateTime.now();
                        var d = DateTime(now.year, now.month, now.day, time!.hour, time!.minute);
                        if (d.isBefore(now.subtract(const Duration(hours: 3)))) d = d.add(const Duration(days: 1)); // a time already gone today → tomorrow
                        at = d.toUtc().toIso8601String();
                      }
                      final tb = pos.tables.firstWhere((x) => js(x['_id']) == get0());
                      await pos.addBooking(table: tb, name: name.text, phone: phone.text, time: at, guests: nz(guests.text).toInt(), note: note.text.trim());
                      if (ctx.mounted) Navigator.pop(ctx);
                    },
            ),
          ),
        ],
      ),
    ),
  );
}

// one booking: guests arrived → start the order · or cancel it
Future<void> showBooking(BuildContext context, String id, {required void Function(J order) onSeated}) {
  final t = tr(context);
  final pos = RestPos.i;
  final b = pos.bookings[id];
  if (b == null) return Future.value();
  var sure = false;
  return posSheet(
    context,
    title: '${t('rpos.booked')} · ${js(b['table_name'])}',
    body: (ctx) => StatefulBuilder(
      builder: (ctx, set) {
        final c = ctx.c;
        final phone = js(b['phone']);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(color: c.limeBg, borderRadius: BorderRadius.circular(18)),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    js(b['name']),
                    style: TextStyle(fontWeight: FontWeight.w800, fontSize: 20, color: c.limeInk),
                  ),
                  if (phone.isNotEmpty)
                    TextButton.icon(
                      style: TextButton.styleFrom(padding: EdgeInsets.zero, foregroundColor: c.limeInk),
                      onPressed: () => launchUrl(Uri.parse('tel:${phone.replaceAll(' ', '')}')),
                      icon: const Icon(LucideIcons.phone, size: 15),
                      label: Text(phone),
                    ),
                  Text(
                    '${js(b['time']).isNotEmpty ? '${t('rpos.bookedAt')} ${f.fmtTime(b['time'])}' : t('rpos.noTime')}${nz(b['guests']) > 0 ? ' · ${nz(b['guests']).toInt()} ${t('rpos.guests').toLowerCase()}' : ''}',
                    style: TextStyle(color: c.limeInk),
                  ),
                  if (js(b['note']).isNotEmpty)
                    Text(
                      js(b['note']),
                      style: TextStyle(color: c.limeInk, fontStyle: FontStyle.italic),
                    ),
                  const SizedBox(height: 4),
                  Text('${t('rpos.bookedBy')} ${js(b['created_by'])}', style: TextStyle(color: c.limeInk.withValues(alpha: .75), fontSize: 12.5)),
                ],
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              height: 54,
              child: Btn(
                t('rpos.guestsArrived'),
                icon: LucideIcons.utensilsCrossed,
                expand: true,
                onTap: pos.blockedReason.isNotEmpty
                    ? null
                    : () async {
                        final o = await pos.seatBooking(id);
                        if (ctx.mounted) Navigator.pop(ctx);
                        onSeated(o);
                      },
              ),
            ),
            const SizedBox(height: 10),
            sure
                ? Btn(
                    t('rpos.cancelBookingSure'),
                    kind: BtnKind.danger,
                    expand: true,
                    onTap: () async {
                      await pos.cancelBooking(id);
                      if (ctx.mounted) Navigator.pop(ctx);
                    },
                  )
                : Btn(t('rpos.cancelBooking'), icon: LucideIcons.x, kind: BtnKind.ghost, expand: true, onTap: () => set(() => sure = true)),
          ],
        );
      },
    ),
  );
}

// a booking in the side list / phone strip
class BookingChip extends StatelessWidget {
  final J b;
  final VoidCallback onTap;
  final bool full;
  const BookingChip(this.b, {super.key, required this.onTap, this.full = false});
  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Material(
      color: c.limeBg,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          child: Row(
            mainAxisSize: full ? MainAxisSize.max : MainAxisSize.min,
            children: [
              Icon(LucideIcons.calendarClock, size: 16, color: c.limeInk),
              const SizedBox(width: 8),
              Text(
                js(b['table_name']).isEmpty ? '—' : js(b['table_name']),
                style: TextStyle(fontWeight: FontWeight.w800, color: c.limeInk),
              ),
              const SizedBox(width: 8),
              if (full)
                Expanded(
                  child: Text(
                    js(b['name']),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: c.limeInk),
                  ),
                )
              else
                Text(js(b['name']), style: TextStyle(color: c.limeInk)),
              if (js(b['time']).isNotEmpty) ...[
                const SizedBox(width: 8),
                Text(
                  f.fmtTime(b['time']),
                  style: TextStyle(color: c.limeInk, fontWeight: FontWeight.w700),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

// guests' orders from the table QR, waiting to be accepted (rings until then)
class GuestAlerts extends StatelessWidget {
  final void Function(String orderId) onOpen;
  const GuestAlerts({super.key, required this.onOpen});
  @override
  Widget build(BuildContext context) {
    final t = tr(context);
    final c = context.c;
    final pos = RestPos.i;
    if (pos.guestAlerts.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
      child: Column(
        children: [
          for (final a in pos.guestAlerts)
            Container(
              margin: const EdgeInsets.only(bottom: 6),
              padding: const EdgeInsets.fromLTRB(14, 8, 8, 8),
              decoration: BoxDecoration(
                color: c.limeBg,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: c.limeInk.withValues(alpha: .4)),
              ),
              child: Row(
                children: [
                  Icon(LucideIcons.bellRing, size: 20, color: c.limeInk),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      t(js(a['guest_name']).isNotEmpty ? 'rpos.guestAlertBy' : 'rpos.guestAlert', {
                        'table': js(a['table_name']).isEmpty ? t('rpos.takeaway1') : js(a['table_name']),
                        'n': nz(a['count']).toInt(),
                        'name': js(a['guest_name']),
                      }),
                      style: TextStyle(color: c.limeInk, fontWeight: FontWeight.w700),
                    ),
                  ),
                  Btn(
                    t('rpos.guestAccept'),
                    icon: LucideIcons.check,
                    small: true,
                    onTap: () {
                      pos.dismissGuestAlert(js(a['id']));
                      if (pos.orders.containsKey(js(a['order_id']))) onOpen(js(a['order_id']));
                    },
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
