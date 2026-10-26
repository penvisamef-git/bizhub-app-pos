import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../../core/app_state.dart';
import '../../core/theme.dart';
import 'changelog.dart';

// System activity / សកម្មភាពក្នុងប្រព័ន្ធ: what changed in each BizHub version — the same list and words as the website
// (web: dashboard/client/updates/UpdatesPage.jsx · the list: lib/features/updates/changelog.dart, made by tool/gen_changelog.js)
const _text = {
  'en': {
    'title': 'System activity',
    'sub': 'What we built and changed in BizHub, version by version.',
    'live': 'Live',
    'testing': 'Testing · coming soon',
    'latest': 'Latest',
    'more': 'Show all · {n} changes',
    'less': 'Show less',
    'new': 'New',
    'better': 'Better',
    'fix': 'Fixed',
    'safe': 'Safer',
    'version': 'Version {v}',
    'thisApp': 'BizHub POS {v}',
  },
  'km': {
    'title': 'សកម្មភាពក្នុងប្រព័ន្ធ',
    'sub': 'អ្វីដែលយើងបានបង្កើត និងផ្លាស់ប្តូរក្នុង BizHub តាមកំណែនីមួយៗ។',
    'live': 'កំពុងប្រើ',
    'testing': 'កំពុងសាកល្បង · ឆាប់ៗនេះ',
    'latest': 'ថ្មីបំផុត',
    'more': 'បង្ហាញទាំងអស់ · ការផ្លាស់ប្តូរ {n}',
    'less': 'បង្ហាញតិច',
    'new': 'ថ្មី',
    'better': 'ល្អជាងមុន',
    'fix': 'បានជួសជុល',
    'safe': 'សុវត្ថិភាពជាងមុន',
    'version': 'កំណែ {v}',
    'thisApp': 'BizHub POS {v}',
  },
};
String updatesText(String lang, String k) => _text[lang]?[k] ?? _text['en']![k] ?? k;

const _months = {
  'en': ['January', 'February', 'March', 'April', 'May', 'June', 'July', 'August', 'September', 'October', 'November', 'December'],
  'km': ['មករា', 'កុម្ភៈ', 'មីនា', 'មេសា', 'ឧសភា', 'មិថុនា', 'កក្កដា', 'សីហា', 'កញ្ញា', 'តុលា', 'វិច្ឆិកា', 'ធ្នូ'],
};
String _month(String ym, String lang) {
  final p = ym.split('-');
  final y = int.tryParse(p.first) ?? 0, m = int.tryParse(p.length > 1 ? p[1] : '1') ?? 1;
  return y == 0 ? '' : '${(_months[lang] ?? _months['en']!)[(m - 1).clamp(0, 11)]} $y';
}

const _kindOrder = ['new', 'better', 'fix', 'safe'];
const _short = 6; // older versions start folded after this many lines

// this app's own number + build (pubspec.yaml version: 2.0.0+2), e.g. "2.0.0 (2)"
Future<String> appVersion() async {
  try {
    final p = await PackageInfo.fromPlatform();
    return p.buildNumber.isEmpty ? p.version : '${p.version} (${p.buildNumber})';
  } catch (_) {
    return bizhubVersion;
  }
}

void openUpdates(BuildContext context) => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const UpdatesPage()));

// "System activity · v2.0.0" for the more menus of every POS
class UpdatesTile extends StatelessWidget {
  final VoidCallback onTap;
  const UpdatesTile({super.key, required this.onTap});
  @override
  Widget build(BuildContext context) {
    final lang = AppScope.of(context).lang;
    return ListTile(
      leading: const Icon(LucideIcons.history),
      title: Text(updatesText(lang, 'title')),
      trailing: Text(
        'v$bizhubVersion',
        style: TextStyle(color: context.c.muted, fontWeight: FontWeight.w700),
      ),
      onTap: onTap,
    );
  }
}

class UpdatesPage extends StatelessWidget {
  const UpdatesPage({super.key});
  @override
  Widget build(BuildContext context) {
    final lang = AppScope.of(context).lang;
    final c = context.c;
    return Scaffold(
      backgroundColor: c.appBg,
      appBar: AppBar(
        backgroundColor: c.appBg,
        surfaceTintColor: Colors.transparent,
        title: Text(updatesText(lang, 'title'), style: const TextStyle(fontWeight: FontWeight.w800)),
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 760),
          child: ListView(
            padding: EdgeInsets.fromLTRB(16, 4, 16, 32 + MediaQuery.of(context).padding.bottom),
            children: [
              Text(updatesText(lang, 'sub'), style: TextStyle(color: c.muted, height: 1.45)),
              const SizedBox(height: 10),
              FutureBuilder<String>(
                future: appVersion(),
                builder: (context, s) => Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  children: [_Pill(updatesText(lang, 'version').replaceAll('{v}', bizhubVersion), bold: true), if (s.hasData) _Pill(updatesText(lang, 'thisApp').replaceAll('{v}', s.data!))],
                ),
              ),
              const SizedBox(height: 16),
              for (var i = 0; i < changelog.length; i++) _Version(r: changelog[i], first: i == 0, lang: lang),
            ],
          ),
        ),
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  final String text;
  final bool bold;
  const _Pill(this.text, {this.bold = false});
  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Container(
      key: ValueKey('up-pill-$text'),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: bold ? c.solid : c.card,
        borderRadius: BorderRadius.circular(999),
        border: bold ? null : Border.all(color: c.line),
      ),
      child: Text(
        text,
        style: TextStyle(color: bold ? c.onSolid : c.ink, fontWeight: FontWeight.w800, fontSize: 13),
      ),
    );
  }
}

class _Version extends StatefulWidget {
  final Release r;
  final bool first;
  final String lang;
  const _Version({required this.r, required this.first, required this.lang});
  @override
  State<_Version> createState() => _VersionState();
}

class _VersionState extends State<_Version> {
  late bool _open = widget.first;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final r = widget.r;
    final lang = widget.lang;
    final km = lang == 'km';
    final live = r.status == 'live';
    final items = [...r.items]..sort((a, b) => _kindOrder.indexOf(a.kind).compareTo(_kindOrder.indexOf(b.kind)));
    final shown = _open ? items : items.take(_short).toList();
    Widget chip(String text, Color bg, Color fg, {IconData? icon}) => Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(999)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[Icon(icon, size: 12, color: fg), const SizedBox(width: 4)],
          Text(
            text,
            style: TextStyle(color: fg, fontSize: 12, fontWeight: FontWeight.w800, height: 1.3),
          ),
        ],
      ),
    );
    (Color, Color, IconData) kindLook(String k) => switch (k) {
      'better' => (c.warnBg, c.warn, LucideIcons.zap),
      'fix' => (c.dangerBg, c.danger, LucideIcons.wrench),
      'safe' => (c.goodBg, c.good, LucideIcons.shieldCheck),
      _ => (c.active, c.brandInk, LucideIcons.sparkles),
    };

    return Container(
      key: ValueKey('up-v-${r.version}'),
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 12),
      decoration: BoxDecoration(color: c.card, borderRadius: BorderRadius.circular(22), boxShadow: c.cardShadow),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 6,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              chip('v${r.version}', c.solid, c.onSolid),
              chip(updatesText(lang, live ? 'live' : 'testing'), live ? c.goodBg : c.warnBg, live ? c.good : c.warn, icon: live ? LucideIcons.rocket : LucideIcons.flaskConical),
              if (widget.first) chip(updatesText(lang, 'latest'), c.chip, c.ink),
            ],
          ),
          const SizedBox(height: 6),
          Text(_month(r.date, lang), style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: 10),
          Text(km ? r.titleKm : r.titleEn, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
          if ((km ? r.subKm : r.subEn).isNotEmpty) ...[const SizedBox(height: 4), Text(km ? r.subKm : r.subEn, style: TextStyle(color: c.muted, height: 1.45))],
          const SizedBox(height: 10),
          for (final it in shown) ...[
            Divider(height: 1, color: c.line),
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Builder(
                    builder: (_) {
                      final (bg, fg, icon) = kindLook(it.kind);
                      return chip(updatesText(lang, it.kind), bg, fg, icon: icon);
                    },
                  ),
                  const SizedBox(height: 6),
                  Text(km ? it.km : it.en, style: const TextStyle(height: 1.5)),
                ],
              ),
            ),
          ],
          if (items.length > _short)
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: () => setState(() => _open = !_open),
                icon: Icon(_open ? LucideIcons.chevronUp : LucideIcons.chevronDown, size: 16),
                label: Text(_open ? updatesText(lang, 'less') : updatesText(lang, 'more').replaceAll('{n}', '${items.length}')),
              ),
            ),
        ],
      ),
    );
  }
}
