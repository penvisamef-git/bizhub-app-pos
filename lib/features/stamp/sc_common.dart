import 'dart:math' as math;

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/api.dart';
import '../../core/config.dart';
import '../../core/i18n.dart';
import '../../core/theme.dart';
import '../../widgets/ui.dart';
import 'sc_data.dart';

// Loyalty Stamp Card on the counter (the web's /stamp/desk/<slug>): the owner app's stamp pieces, logged in as the desk
// (PIN) instead of the owner. GET /api/public/stamp/desk/:slug → { shop, max_per_visit, can_reset, read_only, today }

// the desk's API: x-api-key + x-desk-token (+ x-desk-name: who is at the counter); answers stay whole ({ data, pagination })
class DeskApi {
  final String slug, token, name;
  DeskApi(this.slug, {this.token = '', this.name = ''});
  static final Dio _dio = makeDio(
    BaseOptions(baseUrl: Config.apiHost, connectTimeout: const Duration(seconds: 12), receiveTimeout: const Duration(seconds: 30), responseType: ResponseType.json, validateStatus: (_) => true),
  );
  String get base => '/api/public/stamp/desk/$slug';

  Future<Json> call(String method, String path, {Object? body, Map<String, String>? query}) async {
    try {
      final r = await _dio.request<dynamic>(
        path.startsWith('/api/') ? path : '$base$path',
        data: method == 'GET' ? null : (body ?? const {}),
        queryParameters: query == null
            ? null
            : {
                for (final e in query.entries)
                  if (e.value.isNotEmpty) e.key: e.value,
              },
        options: Options(method: method, headers: {'x-api-key': Config.apiKey, if (token.isNotEmpty) 'x-desk-token': token, if (name.isNotEmpty) 'x-desk-name': Uri.encodeComponent(name)}),
      );
      final data = r.data;
      final json = data is Map ? Map<String, dynamic>.from(data) : <String, dynamic>{'data': data};
      final status = r.statusCode ?? 0;
      if (status >= 400 || json['success'] == false) throw ApiError(status, '${json['message'] ?? 'Error $status'}', code: json['code'] as String?, body: json);
      return json;
    } on DioException catch (e) {
      throw ApiError(0, e.message ?? 'network');
    }
  }

  Future<Json> get(String path, [Map<String, String>? query]) => call('GET', path, query: query);
  Future<Json> post(String path, [Object? body]) => call('POST', path, body: body);
}

class ScCtx {
  final DeskApi api;
  final T t;
  final Json data; // GET /desk/:slug
  final Future<void> Function() reload;
  final void Function(String text) notify;
  final VoidCallback authLost; // PIN changed / logged out by the owner
  const ScCtx({required this.api, required this.t, required this.data, required this.reload, required this.notify, required this.authLost});

  String get base => ''; // the desk API adds /api/public/stamp/desk/<slug>
  String get lang => t.lang;
  Json get shopData => obj(data['shop']);
  // the owner app's "program", made from what the desk sees
  Json get program => {
    'goal': shopData['goal'],
    'color': shopData['color'],
    'theme': shopData['theme'],
    'icon': shopData['icon'],
    'logo': shopData['logo'],
    'shop_name': shopData['name'],
    'max_per_visit': data['max_per_visit'],
  };
  Json get today => obj(data['today']);
  List<Json> get levels => objs(shopData['levels']);
  bool get readOnly => data['read_only'] == true;
  bool get canReset => data['can_reset'] == true;
  int get goal => n(shopData['goal']).toInt().clamp(3, 20);
  String get shopName => str(shopData['name']);

  // the owner's words (sc.*) and the customer / desk pages' words (scp.*)
  String m(String key, [Map<String, Object?> vars = const {}]) => t('sc.$key', vars);
  String p(String key, [Map<String, Object?> vars = const {}]) => t('scp.$key', vars);

  ScShop shop() => ScShop(name: shopName, logo: str(shopData['logo']), theme: str(shopData['theme']), color: str(shopData['color']), icon: str(shopData['icon']), goal: goal, levels: levels);

  void fail(Object e) {
    if (e is ApiError && e.status == 401) return authLost();
    if (e is ApiError) return notify(e.network ? t('app.offline') : e.message);
    notify('$e');
  }
}

// what a card shows (StampCard.jsx `shop`)
class ScShop {
  final String name, logo, theme, color, icon;
  final int goal;
  final List<Json> levels;
  const ScShop({required this.name, this.logo = '', this.theme = 'classic', this.color = '', this.icon = 'coffee', this.goal = 10, this.levels = const []});
}

ScTheme scThemeOf(String key) => scThemes[key] ?? scThemes['classic']!;
String scThemeName(String key, String lang) => lang == 'km' ? scThemeOf(key).km : scThemeOf(key).en;
ScPoster scPosterOf(String key) => scPosters[key] ?? scPosters['basic']!;
String scPosterName(String key, String lang) => lang == 'km' ? scPosterOf(key).km : scPosterOf(key).en;

// the 14 stamp pictures (themes.js SC_ICONS)
const scIcons = <String, IconData>{
  'coffee': LucideIcons.coffee,
  'cup': LucideIcons.cupSoda,
  'star': LucideIcons.star,
  'heart': LucideIcons.heart,
  'scissors': LucideIcons.scissors,
  'car': LucideIcons.car,
  'shirt': LucideIcons.shirt,
  'utensils': LucideIcons.utensilsCrossed,
  'gift': LucideIcons.gift,
  'paw': LucideIcons.pawPrint,
  'drop': LucideIcons.droplets,
  'cake': LucideIcons.cake,
  'flower': LucideIcons.flower2,
  'crown': LucideIcons.crown,
};
IconData scIconOf(String key) => scIcons[key] ?? LucideIcons.coffee;

// "#c2410c" → Color (empty / bad → null)
Color? scHex(String v) {
  final h = v.replaceAll('#', '').trim();
  if (h.length != 6) return null;
  final x = int.tryParse(h, radix: 16);
  return x == null ? null : Color(0xFF000000 | x);
}

String scColorHex(Color c) => '#${(c.toARGB32() & 0xFFFFFF).toRadixString(16).padLeft(6, '0')}';

// CSS "160deg" → a Flutter gradient direction
LinearGradient scGradient(List<Color> colors, double deg) {
  if (colors.length == 1) return LinearGradient(colors: [colors.first, colors.first]);
  final r = deg * math.pi / 180;
  final dx = math.sin(r), dy = -math.cos(r);
  return LinearGradient(begin: Alignment(-dx, -dy), end: Alignment(dx, dy), colors: colors);
}

String levelName(Json l, String lang) {
  final en = str(l['en']), km = str(l['km']);
  return lang == 'km' ? (km.isNotEmpty ? km : en) : (en.isNotEmpty ? en : km);
}

// 012 345 678
String prettyPhone(Object? p) {
  final s = str(p);
  final m = RegExp(r'^(\d{3})(\d{3})(\d{3,4})$').firstMatch(s);
  return m == null ? s : '${m[1]} ${m[2]} ${m[3]}';
}

String scAgo(Object? d, ScCtx ctx) {
  final x = DateTime.tryParse('${d ?? ''}');
  if (x == null) return '';
  final min = DateTime.now().difference(x).inMinutes;
  if (min < 1) return ctx.m('justNow');
  if (min < 60) return ctx.m('minAgo', {'n': min});
  if (min < 60 * 24) return ctx.m('hAgo', {'n': min ~/ 60});
  return ctx.m('dAgo', {'n': min ~/ (60 * 24)});
}

const _monEn = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
const _monKm = ['មករា', 'កុម្ភៈ', 'មីនា', 'មេសា', 'ឧសភា', 'មិថុនា', 'កក្កដា', 'សីហា', 'កញ្ញា', 'តុលា', 'វិច្ឆិកា', 'ធ្នូ'];
DateTime? _kh(Object? d) => DateTime.tryParse('${d ?? ''}')?.toUtc().add(const Duration(hours: 7));
String scDate(Object? d, String lang) {
  final x = _kh(d);
  return x == null ? '' : '${x.day} ${(lang == 'km' ? _monKm : _monEn)[x.month - 1]} ${x.year}';
}

String scTime(Object? d, String lang) {
  final x = _kh(d);
  if (x == null) return '';
  return '${x.day} ${(lang == 'km' ? _monKm : _monEn)[x.month - 1]}, ${x.hour.toString().padLeft(2, '0')}:${x.minute.toString().padLeft(2, '0')}';
}

// "2026-10-18" → 18 Oct
String scDay(String day, String lang) {
  final x = DateTime.tryParse('${day}T00:00:00Z');
  return x == null ? day : '${x.day} ${(lang == 'km' ? _monKm : _monEn)[x.month - 1]}';
}

String cardUrl(Object? token) => '${Config.siteUrl}/stamp/c/$token';

Future<void> scCopy(ScCtx ctx, String text) async {
  await Clipboard.setData(ClipboardData(text: text));
  ctx.notify(ctx.m('copied'));
}

// one history line: "+1 stamp" / "Got Free latte" / "Fixed -2" …
String scEvent(Json e, ScCtx ctx) {
  final k = str(e['kind']);
  final nn = n(e['n']).toInt();
  if (k == 'stamp') return ctx.m('ev.stamp', {'n': nn});
  if (k == 'reward') {
    final parts = str(e['reward']).split(' · ');
    return ctx.m('ev.reward', {'reward': parts.length > 1 ? parts[ctx.lang == 'km' ? 0 : 1] : str(e['reward'])});
  }
  if (k == 'adjust') return ctx.m('ev.adjust', {'n': nn > 0 ? '+$nn' : '$nn'});
  if (k == 'expire') return ctx.m('ev.expire', {'n': nn.abs()});
  return ctx.m('ev.join');
}

String scBy(Json e, ScCtx ctx) {
  final by = obj(e['by']);
  final who = ctx.t.or('sc.by.${by['kind']}', str(by['kind']));
  return str(by['name']).isNotEmpty ? '$who (${by['name']})' : who;
}

const scGap = SizedBox(height: 14);

Widget scPanel(List<Widget> children, {EdgeInsets padding = const EdgeInsets.all(16)}) => Panel(
  padding: padding,
  child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: children),
);

Widget scHead(BuildContext context, IconData icon, String title, String sub, {Widget? trailing}) {
  final c = context.c;
  return scPanel([
    Row(
      children: [
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            gradient: LinearGradient(colors: [c.brand, c.brand2]),
            borderRadius: BorderRadius.circular(13),
          ),
          child: Icon(icon, size: 20, color: Colors.white),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(title, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
        ),
        ?trailing,
      ],
    ),
    const SizedBox(height: 8),
    Muted(sub),
  ]);
}

Widget scTitle(BuildContext context, String text, {IconData? icon, String? count}) => Padding(
  padding: const EdgeInsets.only(bottom: 10),
  child: Row(
    children: [
      if (icon != null) ...[Icon(icon, size: 17, color: context.c.brand), const SizedBox(width: 8)],
      Flexible(
        child: Text(text, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15.5)),
      ),
      if (count != null) ...[
        const SizedBox(width: 8),
        Text(
          count,
          style: TextStyle(color: context.c.muted, fontWeight: FontWeight.w700),
        ),
      ],
    ],
  ),
);

class ScAvatar extends StatelessWidget {
  final String name;
  final double size;
  const ScAvatar(this.name, {super.key, this.size = 42});
  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final s = name.trim();
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(color: c.active, shape: BoxShape.circle),
      child: Text(
        s.isEmpty ? '?' : s.characters.first.toUpperCase(),
        style: TextStyle(fontWeight: FontWeight.w800, color: c.brandInk, fontSize: size * .42),
      ),
    );
  }
}

// one customer in a list: name #no · phone · last visit · stamps (dots / bar / reward ready)
class ScMemberRow extends StatelessWidget {
  final ScCtx ctx;
  final Json m;
  final VoidCallback onTap;
  const ScMemberRow({super.key, required this.ctx, required this.m, required this.onTap});
  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final goal = ctx.goal;
    final stamps = n(m['stamps']).toInt();
    final ready = (m['ready'] as List? ?? const []).isNotEmpty;
    final accent = scHex(str(ctx.program['color'])) ?? scThemeOf(str(ctx.program['theme'])).accent;
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 9, horizontal: 4),
        child: Row(
          children: [
            ScAvatar(str(m['name'])),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text.rich(
                    TextSpan(
                      text: str(m['name']),
                      style: TextStyle(fontWeight: FontWeight.w800, color: m['deleted'] == true ? c.muted : c.ink),
                      children: [
                        TextSpan(
                          text: '  #${m['no']}',
                          style: TextStyle(color: c.muted, fontWeight: FontWeight.w600, fontSize: 12.5),
                        ),
                      ],
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(
                    [
                      if (str(m['phone']).isNotEmpty) prettyPhone(m['phone']),
                      m['last_visit_at'] != null ? ctx.m('lastVisit', {'ago': scAgo(m['last_visit_at'], ctx)}) : ctx.m('neverVisit'),
                    ].join(' · '),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: c.muted, fontSize: 12.5),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text('$stamps/$goal', style: const TextStyle(fontWeight: FontWeight.w800)),
                const SizedBox(height: 4),
                if (ready)
                  Chip2(ctx.m('readyNow'), tone: Tone.good)
                else
                  ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: SizedBox(
                      width: 64,
                      height: 6,
                      child: LinearProgressIndicator(value: (stamps / goal).clamp(0, 1).toDouble(), backgroundColor: c.line, color: accent),
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
