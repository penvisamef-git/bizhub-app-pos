import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/app_state.dart';
import '../../core/theme.dart';
import '../../widgets/ui.dart';
import '../attendance/att_link.dart';
import '../stamp/sc_root.dart';
import 'link_page.dart';

// Choose what this device is: one of the 5 POS kinds. The ready ones go on to the link code.
class ChoosePage extends StatelessWidget {
  const ChoosePage({super.key});
  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final t = app.t;
    final c = context.c;
    return Scaffold(
      backgroundColor: c.appBg,
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
              children: [
                Row(
                  children: [
                    const Logo(height: 26),
                    const SizedBox(width: 8),
                    Text(
                      'POS',
                      style: TextStyle(color: c.brand, fontWeight: FontWeight.w800, fontSize: 17),
                    ),
                    const Spacer(),
                    const ThemeBtn(),
                    TextButton(
                      onPressed: () => app.setLang(app.lang == 'km' ? 'en' : 'km'),
                      child: Text(app.lang == 'km' ? 'EN' : 'ខ្មែរ', style: const TextStyle(fontWeight: FontWeight.w700)),
                    ),
                  ],
                ),
                const SizedBox(height: 22),
                Text(t('choose.title'), style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800)),
                const SizedBox(height: 6),
                Muted(t('choose.sub')),
                const SizedBox(height: 20),
                LayoutBuilder(
                  builder: (context, box) {
                    final cols = box.maxWidth > 560 ? 2 : 1;
                    final w = (box.maxWidth - 14 * (cols - 1)) / cols;
                    return Wrap(
                      spacing: 14,
                      runSpacing: 14,
                      children: [
                        for (final k in posKinds)
                          SizedBox(
                            width: w,
                            child: _KindCard(
                              kind: k,
                              ready: readyKinds.contains(k),
                              onTap: () {
                                if (!readyKinds.contains(k)) return toast(context, t('app.soonSub'));
                                Navigator.of(
                                  context,
                                ).push(MaterialPageRoute(builder: (_) => k == 'attendance' ? const AttModePage() : (k == 'stamp_card' ? const StampLinkPage() : LinkPage(kind: k))));
                              },
                            ),
                          ),
                      ],
                    );
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _KindCard extends StatelessWidget {
  final String kind;
  final bool ready;
  final VoidCallback onTap;
  const _KindCard({required this.kind, required this.ready, required this.onTap});
  @override
  Widget build(BuildContext context) {
    final t = AppScope.of(context).t;
    final c = context.c;
    return Material(
      color: c.card,
      borderRadius: BorderRadius.circular(22),
      child: InkWell(
        borderRadius: BorderRadius.circular(22),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: c.line),
          ),
          child: Opacity(
            opacity: ready ? 1 : .6,
            child: Row(
              children: [
                TypeIcon(kind, size: 56),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(t('type.$kind'), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 17)),
                          ),
                          if (!ready) ...[const SizedBox(width: 8), Chip2(t('app.soon'))],
                        ],
                      ),
                      const SizedBox(height: 3),
                      Text(t('type.$kind.sub'), style: TextStyle(color: c.muted, fontSize: 13.5, height: 1.4)),
                    ],
                  ),
                ),
                Icon(LucideIcons.chevronRight, color: c.muted),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
