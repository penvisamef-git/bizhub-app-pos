import '../../core/customer_display.dart';
import '../restaurant/engine/calc.dart' show J, jmap, jlist, js, nz;
import 'engine/gh_pos.dart';

// Guest display (gh_display) on dual-screen terminals: the open bill for the guest to see (+ the QR while money is owed),
// "thank you" when checked out and paid, welcome otherwise. Same screen as the Mini Mart's (mart_display.dart).
class GhDisplayFeed {
  GhDisplayFeed._();
  static final i = GhDisplayFeed._();
  bool _on = false;

  GhPos get _pos => GhPos.i;

  Future<void> start() async {
    if (_on || jmap(_pos.boot['display'])['on'] != true) return;
    if (!await CustomerDisplay.available(fresh: true)) return;
    _on = true;
    show(null);
  }

  void stop() {
    if (!_on) return;
    _on = false;
    CustomerDisplay.hide();
  }

  Map<String, Object?> get _base => {
    'v': 1,
    'shop': {'name': js(_pos.business['name']), 'logo': js(_pos.business['logo_url'])},
    'color': '',
    'currency': _pos.currency,
  };

  // the bill that is open on the desk (null = none)
  void show(J? stay) {
    if (!_on) return;
    if (stay == null || ['cancelled', 'no_show'].contains(stay['status'])) {
      CustomerDisplay.show({..._base, 'mode': 'idle', 'promos': <String>[]});
      return;
    }
    final b = jmap(stay['bill']);
    final cur = _pos.currency;
    final bal = nz(b['balance']);
    if (bal == 0 && stay['status'] == 'out') {
      CustomerDisplay.show({..._base, 'mode': 'thanks', 'total': nz(b['total']), 'change': 0, 'change_khr': 0, 'earned': 0});
      return;
    }
    final rate = nz(_pos.settings['khr_rate']) == 0 ? 4100 : nz(_pos.settings['khr_rate']);
    final qr = bal > 0 ? js(_pos.settings['pay_qr']) : '';
    CustomerDisplay.show({
      ..._base,
      'mode': qr.isNotEmpty ? 'pay' : 'cart',
      'label': 'due',
      'lines': [
        if (stay['lease'] == null) {'key': 'room', 'name': '${js(stay['room_name'])} · ${js(jmap(stay['guest'])['name'])}', 'qty': nz(b['nights']), 'total': nz(b['room'])},
        for (final c in jlist(stay['charges']))
          {'key': js(c['_id']), 'name': js(c['label']), 'qty': nz(c['qty']) == 0 ? 1 : nz(c['qty']), 'total': nz(c['amount']) * (nz(c['qty']) == 0 ? 1 : nz(c['qty']))},
      ],
      'promos_applied': <J>[],
      'discount': nz(b['discount']),
      'paid': nz(b['paid']),
      'points_value': 0,
      'total': bal < 0 ? 0 : bal,
      'total_khr': cur == 'USD' ? ((bal < 0 ? 0 : bal) * rate / 100).round() * 100 : 0,
      'member': '',
      if (qr.isNotEmpty) ...{'qr': qr, 'qr_label': js(_pos.settings['pay_qr_label'])},
    });
  }
}
