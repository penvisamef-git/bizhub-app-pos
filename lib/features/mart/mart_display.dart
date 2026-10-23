import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/customer_display.dart';
import '../../widgets/ui.dart' show netImage;
import '../restaurant/engine/calc.dart' show J, jmap, jlist, js, nz;
import 'engine/mart_pos.dart';
import 'mart_sell.dart' show cartSum;

// Customer screen (mart_display) on dual-screen terminals — the same pictures as the web's (pos/mart/display.js):
// idle (welcome + deals) → the cart + total → paying (QR) → thank you (+ change, points).

// ---------------------------------------------------------------- the counter side: what to show
class MartDisplayFeed {
  MartDisplayFeed._();
  static final i = MartDisplayFeed._();
  bool _on = false;
  bool _paying = false;
  String _qr = '', _qrLabel = '';
  DateTime _thanksUntil = DateTime(2000);
  Timer? _back;

  MartPos get _pos => MartPos.i;

  // the shop has the add-on and this terminal has a second screen
  Future<void> start() async {
    if (_on || _pos.boot['display'] != true) return;
    if (!await CustomerDisplay.available(fresh: true)) return;
    _on = true;
    _pos.addListener(_push);
    _push();
  }

  void stop() {
    if (!_on) return;
    _on = false;
    _back?.cancel();
    _pos.removeListener(_push);
    CustomerDisplay.hide();
  }

  // the pay sheet is open (with the QR to scan, for a QR method)
  void paying(bool on, {String qr = '', String label = ''}) {
    if (_paying == on && _qr == qr && _qrLabel == label) return;
    _paying = on;
    _qr = qr;
    _qrLabel = label;
    _push();
  }

  // after a sale: "thank you" for 12 seconds, then welcome again
  void thanks(J sale) {
    if (!_on) return;
    _paying = false;
    _thanksUntil = DateTime.now().add(const Duration(seconds: 12));
    CustomerDisplay.show({
      ..._base(),
      'mode': 'thanks',
      'total': nz(sale['total']),
      'change': sale['method'] == 'cash' ? nz(sale['change']) : 0,
      'change_khr': nz(sale['change_khr']),
      'earned': nz(sale['points_earned']).toInt(),
    });
    _back?.cancel();
    _back = Timer(const Duration(seconds: 12), () {
      _thanksUntil = DateTime(2000);
      _push();
    });
  }

  Map<String, Object?> _base() => {
    'v': 1,
    'shop': {'name': js(_pos.business['name']), 'logo': js(_pos.business['logo_url'])},
    'color': js(_pos.boot['pos_color']),
    'currency': _pos.currency,
  };

  void _push() {
    if (!_on || DateTime.now().isBefore(_thanksUntil)) return;
    final cart = _pos.cart;
    final lines = jlist(cart['lines']);
    if (lines.isEmpty) {
      CustomerDisplay.show({
        ..._base(),
        'mode': 'idle',
        'promos': [
          for (final p in jlist(_pos.boot['promos']))
            if (js(p['code']).isEmpty) js(p['name']),
        ].take(6).toList(),
      });
      return;
    }
    final sum = cartSum(cart);
    final m = sum.member;
    CustomerDisplay.show({
      ..._base(),
      'mode': _paying ? 'pay' : 'cart',
      'lines': [
        for (final l in lines) {'key': js(l['key']), 'name': js(l['name']), 'qty': nz(l['qty']), 'total': (nz(l['price']) * nz(l['qty']) * 100).round() / 100},
      ],
      'count': sum.count,
      'promos_applied': [
        for (final p in sum.promo.applied) {'name': js(p['name']), 'amount': nz(p['amount'])},
      ],
      'discount': sum.money.discount,
      'points_value': sum.money.pointsValue,
      'points_used': sum.points,
      'total': sum.money.total,
      'total_khr': sum.money.totalKhr,
      'member': m == null ? '' : (js(m['name']).isNotEmpty ? js(m['name']) : js(m['phone'])),
      'member_points': m == null ? 0 : nz(m['points']).round(),
      if (_paying && _qr.isNotEmpty) ...{'qr': _qr, 'qr_label': _qrLabel},
    });
  }
}

// ---------------------------------------------------------------- the customer side (second Flutter engine)
const _view = MethodChannel('bizhub/display_view');

// started by Android on the second screen (see MainActivity.kt)
void runMartDisplay() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const MartDisplayApp());
}

class MartDisplayApp extends StatefulWidget {
  final J? preview; // a fixed picture (tests / previews)
  const MartDisplayApp({super.key, this.preview});
  @override
  State<MartDisplayApp> createState() => _MartDisplayAppState();
}

class _MartDisplayAppState extends State<MartDisplayApp> {
  J? _pic;

  @override
  void initState() {
    super.initState();
    _pic = widget.preview;
    if (widget.preview == null) {
      _view.setMethodCallHandler((call) async {
        if (call.method == 'pic' && call.arguments is String) {
          final p = jmap(jsonDecode(call.arguments as String));
          if (p['mode'] != null && mounted) setState(() => _pic = p);
        }
        return null;
      });
      _view.invokeMethod('hello').catchError((_) => null); // "send me the picture now"
    }
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
    debugShowCheckedModeBanner: false,
    theme: ThemeData(fontFamily: 'PlusJakartaSans', fontFamilyFallback: const ['KantumruyPro'], useMaterial3: true),
    home: MartDisplayScreen(pic: _pic),
  );
}

String _money(Object? v, String cur) {
  final n = nz(v);
  if (cur == 'KHR') return '${_group(n.round().toString())}៛';
  final s = n.toStringAsFixed(2).split('.');
  return '\$${_group(s[0])}.${s[1]}';
}

String _riel(Object? v) => '${_group(nz(v).round().toString())}៛';
String _group(String s) => s.replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (_) => ',');
String _qty(Object? v) {
  final x = nz(v);
  return x == x.roundToDouble() ? x.toInt().toString() : x.toStringAsFixed(3).replaceFirst(RegExp(r'0+$'), '');
}

Color _accentOf(String hex) {
  final h = hex.replaceFirst('#', '');
  final v = int.tryParse(h.length == 6 ? 'FF$h' : '', radix: 16);
  return v == null ? const Color(0xFFE0581A) : Color(v);
}

// every word on this screen in both languages: the customer reads whichever is theirs
const _t = {
  'welcome': ('Welcome', 'សូមស្វាគមន៍'),
  'items': ('items', 'មុខ'),
  'total': ('Total', 'សរុប'),
  'scan': ('Scan to pay', 'ស្កេនដើម្បីបង់ប្រាក់'),
  'thanks': ('Thank you!', 'អរគុណ!'),
  'change': ('Your change', 'លុយអាប់'),
  'points': ('points', 'ពិន្ទុ'),
  'discount': ('Discount', 'បញ្ចុះតម្លៃ'),
  'paid': ('Paid', 'បានបង់'),
  'due': ('To pay', 'ត្រូវបង់'),
  'waiting': ('Waiting for the counter…', 'កំពុងរង់ចាំ…'),
};

class _Both extends StatelessWidget {
  final String k;
  final double size;
  final Color color;
  final FontWeight weight;
  final CrossAxisAlignment align;
  const _Both(this.k, {this.size = 20, required this.color, this.weight = FontWeight.w700, this.align = CrossAxisAlignment.center});
  @override
  Widget build(BuildContext context) {
    final (en, km) = _t[k]!;
    return Column(
      crossAxisAlignment: align,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          en,
          style: TextStyle(fontSize: size, fontWeight: weight, color: color, height: 1.1),
        ),
        Text(
          km,
          style: TextStyle(fontSize: size * .62, fontWeight: FontWeight.w600, color: color.withValues(alpha: .8), height: 1.5),
        ),
      ],
    );
  }
}

class MartDisplayScreen extends StatelessWidget {
  final J? pic;
  const MartDisplayScreen({super.key, required this.pic});

  @override
  Widget build(BuildContext context) {
    final p = pic;
    final accent = _accentOf(js(p?['color']));
    final mode = js(p?['mode']);
    return Scaffold(
      backgroundColor: mode == 'cart' || mode == 'pay' ? const Color(0xFFF6F4F1) : accent,
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, box) {
            final s = (box.biggest.shortestSide / 600).clamp(.7, 2.2); // the same look on 7" and 21" screens
            return switch (mode) {
              'cart' || 'pay' => _cart(p!, accent, s, box.maxWidth > box.maxHeight),
              'thanks' => _thanks(p!, accent, s),
              'idle' => _idle(p!, accent, s),
              _ => Center(
                child: _Both('waiting', size: 22 * s, color: Colors.white),
              ),
            };
          },
        ),
      ),
    );
  }

  Widget _shop(J p, double s, {Color fg = Colors.white, double logo = 56}) {
    final shop = jmap(p['shop']);
    final url = js(shop['logo']);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: logo * s,
          height: logo * s,
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(logo * s * .28)),
          child: url.isNotEmpty
              ? Image(image: netImage(url), fit: BoxFit.cover, errorBuilder: (_, _, _) => const Icon(LucideIcons.shoppingBasket))
              : Icon(LucideIcons.shoppingBasket, size: logo * s * .5, color: Colors.black54),
        ),
        SizedBox(width: 14 * s),
        Flexible(
          child: Text(
            js(shop['name']).isEmpty ? 'Biz Hub' : js(shop['name']),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(color: fg, fontSize: 24 * s, fontWeight: FontWeight.w800),
          ),
        ),
      ],
    );
  }

  Widget _idle(J p, Color accent, double s) {
    final deals = (p['promos'] is List ? p['promos'] as List : const []).map((e) => '$e').where((e) => e.isNotEmpty).toList(); // names (jlist keeps maps only)
    return Padding(
      padding: EdgeInsets.all(28 * s),
      child: Column(
        children: [
          Align(alignment: Alignment.centerLeft, child: _shop(p, s)),
          const Spacer(),
          _Both('welcome', size: 72 * s, color: Colors.white, weight: FontWeight.w800),
          if (deals.isNotEmpty) ...[
            SizedBox(height: 28 * s),
            Wrap(
              alignment: WrapAlignment.center,
              spacing: 10 * s,
              runSpacing: 10 * s,
              children: [
                for (final d in deals)
                  Container(
                    padding: EdgeInsets.symmetric(horizontal: 16 * s, vertical: 9 * s),
                    decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(999)),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(LucideIcons.tag, size: 18 * s, color: accent),
                        SizedBox(width: 8 * s),
                        Text(
                          d,
                          style: TextStyle(color: const Color(0xFF1C1917), fontSize: 18 * s, fontWeight: FontWeight.w700),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ],
          const Spacer(),
        ],
      ),
    );
  }

  Widget _thanks(J p, Color accent, double s) {
    final cur = js(p['currency']).isEmpty ? 'USD' : js(p['currency']);
    return Center(
      child: Padding(
        padding: EdgeInsets.all(28 * s),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 96 * s,
              height: 96 * s,
              decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
              child: Icon(LucideIcons.check, size: 56 * s, color: accent),
            ),
            SizedBox(height: 22 * s),
            _Both('thanks', size: 60 * s, color: Colors.white, weight: FontWeight.w800),
            SizedBox(height: 10 * s),
            Text(
              _money(p['total'], cur),
              style: TextStyle(color: Colors.white.withValues(alpha: .85), fontSize: 30 * s, fontWeight: FontWeight.w700),
            ),
            if (nz(p['change']) > 0) ...[
              SizedBox(height: 26 * s),
              Container(
                padding: EdgeInsets.symmetric(horizontal: 32 * s, vertical: 18 * s),
                decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(24 * s)),
                child: Column(
                  children: [
                    _Both('change', size: 22 * s, color: const Color(0xFF57534E)),
                    SizedBox(height: 4 * s),
                    Text(
                      cur == 'USD' ? _riel(p['change_khr']) : _money(p['change'], cur),
                      style: TextStyle(color: const Color(0xFF1C1917), fontSize: 54 * s, fontWeight: FontWeight.w800),
                    ),
                  ],
                ),
              ),
            ],
            if (nz(p['earned']) > 0) ...[
              SizedBox(height: 18 * s),
              Text(
                '+${nz(p['earned']).toInt()} ${_t['points']!.$1} · ${_t['points']!.$2}',
                style: TextStyle(color: Colors.white, fontSize: 22 * s, fontWeight: FontWeight.w700),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _cart(J p, Color accent, double s, bool landscape) {
    final cur = js(p['currency']).isEmpty ? 'USD' : js(p['currency']);
    const ink = Color(0xFF1C1917);
    const muted = Color(0xFF78716C);
    final lines = jlist(p['lines']);
    final list = ListView.separated(
      reverse: true, // the newest item stays in view at the bottom
      padding: EdgeInsets.fromLTRB(24 * s, 12 * s, 24 * s, 12 * s),
      itemCount: lines.length,
      separatorBuilder: (_, _) => const Divider(height: 1, color: Color(0xFFE7E5E4)),
      itemBuilder: (_, i) {
        final l = lines[lines.length - 1 - i];
        return Padding(
          padding: EdgeInsets.symmetric(vertical: 12 * s),
          child: Row(
            children: [
              SizedBox(
                width: 58 * s,
                child: Text(
                  '${_qty(l['qty'])}×',
                  style: TextStyle(fontSize: 20 * s, fontWeight: FontWeight.w700, color: accent),
                ),
              ),
              Expanded(
                child: Text(
                  js(l['name']),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 20 * s, fontWeight: FontWeight.w600, color: ink),
                ),
              ),
              SizedBox(width: 12 * s),
              Text(
                _money(l['total'], cur),
                style: TextStyle(fontSize: 20 * s, fontWeight: FontWeight.w700, color: ink),
              ),
            ],
          ),
        );
      },
    );
    final off = <(String, double)>[
      for (final d in jlist(p['promos_applied'])) (js(d['name']), nz(d['amount'])),
      if (nz(p['discount']) > 0) (_t['discount']!.$1, nz(p['discount'])),
      if (nz(p['points_value']) > 0) ('${nz(p['points_used']).toInt()} ${_t['points']!.$1}', nz(p['points_value'])),
      if (nz(p['paid']) > 0) ('${_t['paid']!.$1} · ${_t['paid']!.$2}', nz(p['paid'])), // guest house: paid so far, the big number is what is left
    ];
    final qr = js(p['qr']);
    final side = Container(
      color: accent,
      padding: EdgeInsets.all(26 * s),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (p['mode'] == 'pay' && qr.isNotEmpty) ...[
            Expanded(
              child: Container(
                padding: EdgeInsets.all(14 * s),
                decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20 * s)),
                child: Column(
                  children: [
                    Expanded(
                      child: Image(
                        image: netImage(qr),
                        fit: BoxFit.contain,
                        errorBuilder: (_, _, _) => Icon(LucideIcons.qrCode, size: 120 * s),
                      ),
                    ),
                    if (js(p['qr_label']).isNotEmpty)
                      Text(
                        js(p['qr_label']),
                        style: TextStyle(fontSize: 15 * s, fontWeight: FontWeight.w700, color: muted),
                      ),
                    SizedBox(height: 6 * s),
                    _Both('scan', size: 22 * s, color: ink, weight: FontWeight.w800),
                  ],
                ),
              ),
            ),
            SizedBox(height: 16 * s),
          ] else
            const Spacer(),
          for (final (name, amt) in off)
            Padding(
              padding: EdgeInsets.only(bottom: 6 * s),
              child: Row(
                children: [
                  Icon(LucideIcons.tag, size: 16 * s, color: Colors.white),
                  SizedBox(width: 6 * s),
                  Expanded(
                    child: Text(
                      name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: Colors.white, fontSize: 16 * s, fontWeight: FontWeight.w600),
                    ),
                  ),
                  Text(
                    '−${_money(amt, cur)}',
                    style: TextStyle(color: Colors.white, fontSize: 16 * s, fontWeight: FontWeight.w700),
                  ),
                ],
              ),
            ),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              _Both(p['label'] == 'due' ? 'due' : 'total', size: 24 * s, color: Colors.white, align: CrossAxisAlignment.start),
              const Spacer(),
              if (p['count'] != null)
                Text(
                  '${_qty(p['count'])} ${_t['items']!.$1}',
                  style: TextStyle(color: Colors.white.withValues(alpha: .85), fontSize: 16 * s, fontWeight: FontWeight.w600),
                ),
            ],
          ),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              _money(p['total'], cur),
              style: TextStyle(color: Colors.white, fontSize: 76 * s, fontWeight: FontWeight.w800, height: 1.1),
            ),
          ),
          if (cur == 'USD')
            Text(
              _riel(p['total_khr']),
              style: TextStyle(color: Colors.white.withValues(alpha: .9), fontSize: 28 * s, fontWeight: FontWeight.w700),
            ),
          if (js(p['member']).isNotEmpty) ...[
            SizedBox(height: 10 * s),
            Text(
              '${js(p['member'])} · ${nz(p['member_points']).toInt()} ${_t['points']!.$1}',
              style: TextStyle(color: Colors.white, fontSize: 16 * s, fontWeight: FontWeight.w600),
            ),
          ],
        ],
      ),
    );
    final head = Padding(
      padding: EdgeInsets.fromLTRB(24 * s, 18 * s, 24 * s, 6 * s),
      child: Align(
        alignment: Alignment.centerLeft,
        child: _shop(p, s, fg: ink, logo: 44),
      ),
    );
    return landscape
        ? Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                flex: 11,
                child: Column(
                  children: [
                    head,
                    Expanded(child: list),
                  ],
                ),
              ),
              Expanded(flex: 9, child: side),
            ],
          )
        : Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              head,
              Expanded(child: list),
              SizedBox(height: p['mode'] == 'pay' && qr.isNotEmpty ? 520 * s : 260 * s, child: side),
            ],
          );
  }
}
