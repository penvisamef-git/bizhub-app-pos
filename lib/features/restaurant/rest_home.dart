import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/app_state.dart';
import '../../core/pos_api.dart';
import '../../core/theme.dart';
import '../../widgets/ui.dart';

// Restaurant POS — linked. The selling screens (PIN, tables, menu, order, pay, shift) are built next, on top of this.
class RestHome extends StatelessWidget {
  const RestHome({super.key});
  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final t = app.t;
    final c = context.c;
    final link = app.link ?? const {};
    final logo = str(link['logo']);
    return Scaffold(
      backgroundColor: c.appBg,
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: ListView(
              padding: const EdgeInsets.all(20),
              children: [
                Row(
                  children: [
                    const Logo(height: 24),
                    const SizedBox(width: 8),
                    Text('POS', style: TextStyle(color: c.brand, fontWeight: FontWeight.w800, fontSize: 16)),
                    const Spacer(),
                    TextButton(onPressed: () => app.setLang(app.lang == 'km' ? 'en' : 'km'), child: Text(t('home.lang'))),
                  ],
                ),
                const SizedBox(height: 30),
                Center(
                  child: Container(
                    width: 96,
                    height: 96,
                    clipBehavior: Clip.antiAlias,
                    decoration: BoxDecoration(color: c.active, borderRadius: BorderRadius.circular(28)),
                    child: logo.isNotEmpty ? Image(image: netImage(logo), fit: BoxFit.cover, errorBuilder: (_, _, _) => const TypeIcon('restaurant', size: 96)) : const TypeIcon('restaurant', size: 96),
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  str(link['shop']).isEmpty ? t('type.restaurant') : str(link['shop']),
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 8),
                Center(child: Chip2(t('home.linked'), icon: LucideIcons.link, tone: Tone.good)),
                const SizedBox(height: 8),
                Center(child: Muted(t('home.device', {'name': '${obj(link['device'])['name']} · ${obj(link['device'])['prefix']}'}))),
                const SizedBox(height: 28),
                Panel(
                  child: Row(
                    children: [
                      Icon(LucideIcons.hammer, color: c.brand),
                      const SizedBox(width: 12),
                      Expanded(child: Text(t('home.next'))),
                    ],
                  ),
                ),
                const SizedBox(height: 28),
                Center(
                  child: TextButton.icon(
                    style: TextButton.styleFrom(foregroundColor: c.danger),
                    onPressed: () async {
                      final ok = await showDialog<bool>(
                        context: context,
                        builder: (d) => AlertDialog(
                          content: Text(t('home.unlinkAsk')),
                          actions: [
                            TextButton(onPressed: () => Navigator.pop(d, false), child: Text(t('app.cancel'))),
                            FilledButton(style: FilledButton.styleFrom(backgroundColor: c.danger), onPressed: () => Navigator.pop(d, true), child: Text(t('home.unlink'))),
                          ],
                        ),
                      );
                      if (ok == true) app.unlink();
                    },
                    icon: const Icon(LucideIcons.unlink, size: 16),
                    label: Text(t('home.unlink')),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
