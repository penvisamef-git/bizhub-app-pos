import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/app_state.dart';
import '../../core/i18n.dart';
import '../../core/theme.dart';
import '../../widgets/ui.dart';
import '../attendance/att_link.dart';
import '../stamp/sc_root.dart';
import 'link_page.dart';
import '../updates/updates_page.dart';
import '../updates/changelog.dart' show bizhubVersion;

// more words people may type to find a POS (both languages are searched, whatever the app language is)
const _kindWords = <String, String>{
  'restaurant': 'cafe coffee food kitchen table bar ហាងកាហ្វេ ម្ហូប ផឹក',
  'mart': 'shop store minimart supermarket barcode ហាង លក់ ផ្សារ',
  'guest_house': 'hotel room hostel homestay booking សណ្ឋាគារ បន្ទប់',
  'tg_store': 'telegram online order delivery shop staff screen អនឡាញ ដឹក កម្ម៉ង់',
  'event': 'ticket concert party door gate qr scan សំបុត្រ កម្មវិធី',
  'attendance': 'staff clock in out time shift work បុគ្គលិក ម៉ោង វត្តមាន',
  'stamp_card': 'loyalty stamp reward card member ត្រា រង្វាន់ កាត',
};

// Choose what this device is: one of the POS kinds (search them by name, what they do, or other words).
// The ready ones go on to the link code.
class ChoosePage extends StatefulWidget {
  const ChoosePage({super.key});
  @override
  State<ChoosePage> createState() => _ChoosePageState();
}

class _ChoosePageState extends State<ChoosePage> {
  final _q = TextEditingController();

  @override
  void dispose() {
    _q.dispose();
    super.dispose();
  }

  bool _hit(String k, String q) {
    if (q.isEmpty) return true;
    final en = T.of('en'), km = T.of('km');
    final hay = [en('type.$k'), en('type.$k.sub'), km('type.$k'), km('type.$k.sub'), k.replaceAll('_', ' '), _kindWords[k] ?? ''].join(' ').toLowerCase();
    return q.toLowerCase().split(RegExp(r'\s+')).where((w) => w.isNotEmpty).every(hay.contains);
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final t = app.t;
    final c = context.c;
    final q = _q.text.trim();
    final kinds = posKinds.where((k) => _hit(k, q)).toList();
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
                const SizedBox(height: 16),
                TextField(
                  key: const ValueKey('choose-search'),
                  controller: _q,
                  onChanged: (_) => setState(() {}),
                  textInputAction: TextInputAction.search,
                  decoration: InputDecoration(
                    hintText: t('choose.search'),
                    prefixIcon: const Icon(LucideIcons.search, size: 19),
                    suffixIcon: q.isEmpty ? null : IconButton(icon: const Icon(LucideIcons.x, size: 18), tooltip: t('app.cancel'), onPressed: () => setState(_q.clear)),
                    filled: true,
                    fillColor: c.card,
                    contentPadding: const EdgeInsets.symmetric(vertical: 14),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(16),
                      borderSide: BorderSide(color: c.line),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(16),
                      borderSide: BorderSide(color: c.line),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(16),
                      borderSide: BorderSide(color: c.brand, width: 1.6),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                if (kinds.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 36),
                    child: Column(
                      children: [
                        Icon(LucideIcons.searchX, color: c.muted, size: 30),
                        const SizedBox(height: 8),
                        Muted(t('choose.none', {'q': q}), align: TextAlign.center),
                      ],
                    ),
                  ),
                LayoutBuilder(
                  builder: (context, box) {
                    final cols = box.maxWidth > 560 ? 2 : 1;
                    final w = (box.maxWidth - 14 * (cols - 1)) / cols;
                    return Wrap(
                      spacing: 14,
                      runSpacing: 14,
                      children: [
                        for (final k in kinds)
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
                const SizedBox(height: 18),
                Center(
                  child: TextButton.icon(
                    key: const ValueKey('choose-updates'),
                    onPressed: () => openUpdates(context),
                    icon: Icon(LucideIcons.history, size: 16, color: c.muted),
                    label: Text(
                      '${updatesText(app.lang, 'title')} · v$bizhubVersion',
                      style: TextStyle(color: c.muted, fontWeight: FontWeight.w600),
                    ),
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
