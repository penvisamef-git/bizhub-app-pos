// The cart divider on the selling screens (v3.1.0): the cashier drags it to make the cart wider or narrower, and puts the
// cart on the left or the right. Each cashier's own choice, kept on this device (another screen, another size).
// Tap the handle: Small / Medium / Large, left / right, back to normal. Double-tap: back to normal.
// The website POS does the same (bizhub/src/pos/CartSplit.jsx). Phones keep their own layout (the screens use this only
// when the screen is wide).
//
//   PosSplit(scope: 'mart', who: staffId, whoName: 'Dara', thing: 'cart', main: grid, panel: (left) => Container(…cart…))
import 'package:flutter/gestures.dart' show DragStartBehavior;
import 'package:flutter/material.dart';

import 'app_state.dart';
import 'theme.dart';

// where the cart is on the screen now (Bizi's bubble keeps out of its way: it starts on the other side)
final posCartLeft = ValueNotifier<bool>(false);

class PosSplit extends StatefulWidget {
  final String scope; // which screen ("rest", "mart") — each has its own size
  final String who; // the cashier (staff id); '' = whoever uses this device
  final String whoName;
  final String thing; // 'cart' | 'order' — what the panel is called
  final double normal; // the usual width
  final Widget main;
  final Widget Function(bool left) panel; // the cart, with its own margins for that side
  const PosSplit({super.key, required this.scope, required this.who, this.whoName = '', this.thing = 'cart', this.normal = 400, required this.main, required this.panel});

  static const small = 320.0, large = 520.0, min = 300.0, handle = 18.0;
  static const minMain = 360.0; // the products keep at least 2 columns

  // the widest the cart may be on a screen this wide (never more than 60%, the products keep their room)
  static double maxFor(double total) => (total * .6).clamp(min, (total - minMain - handle).clamp(min, double.infinity)).toDouble();

  static String keyOf(String scope, String who) => 'pos.cart.$scope.${who.isEmpty ? 'device' : who}';

  @override
  State<PosSplit> createState() => _PosSplitState();
}

class _PosSplitState extends State<PosSplit> {
  double? _w; // null = normal
  bool _left = false;
  double? _dragFrom;
  double _startW = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(PosSplit old) {
    super.didUpdateWidget(old);
    if (old.who != widget.who || old.scope != widget.scope) _load(); // another cashier logged in
  }

  void _load() {
    final v = AppState.i.pref(PosSplit.keyOf(widget.scope, widget.who)) ?? '';
    final parts = v.split('|');
    _w = parts.isNotEmpty ? double.tryParse(parts.first) : null;
    _left = parts.length > 1 && parts[1] == 'left';
    _tell();
  }

  void _tell() => WidgetsBinding.instance.addPostFrameCallback((_) {
    if (mounted) posCartLeft.value = _left;
  });

  @override
  void dispose() {
    posCartLeft.value = false;
    super.dispose();
  }

  void _save() => AppState.i.setPref(PosSplit.keyOf(widget.scope, widget.who), '${_w?.round() ?? ''}|${_left ? 'left' : 'right'}');

  void _set({double? w, bool? left, bool normal = false}) {
    setState(() {
      if (normal) {
        _w = null;
      } else if (w != null) {
        _w = w;
      }
      if (left != null) _left = left;
    });
    _save();
    _tell();
  }

  Future<void> _menu(BuildContext context, Offset at, double total) async {
    final t = AppScope.of(context).t;
    final x = t('split.${widget.thing}');
    final c = context.c;
    final max = PosSplit.maxFor(total);
    final now = (_w ?? widget.normal).clamp(PosSplit.min, max);
    PopupMenuItem<String> item(String v, String label, IconData icon, {bool on = false}) => PopupMenuItem(
      key: ValueKey('split-$v'),
      value: v,
      child: Row(
        children: [
          Icon(icon, size: 18, color: on ? c.brandInk : c.muted),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              label,
              style: TextStyle(fontWeight: on ? FontWeight.w800 : FontWeight.w600, color: on ? c.brandInk : c.ink),
            ),
          ),
          if (on) Icon(Icons.check_rounded, size: 18, color: c.brandInk),
        ],
      ),
    );
    final pick = await showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(at.dx, at.dy, at.dx, at.dy),
      color: c.card,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      items: [
        PopupMenuItem(
          enabled: false,
          height: 34,
          child: Text(
            t('split.size', {'x': x}).toUpperCase(),
            style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w800, letterSpacing: .5, color: c.muted),
          ),
        ),
        item('small', t('split.small'), Icons.photo_size_select_small_rounded, on: (now - PosSplit.small.clamp(PosSplit.min, max)).abs() < 1),
        item('medium', t('split.medium'), Icons.crop_portrait_rounded, on: (now - widget.normal.clamp(PosSplit.min, max)).abs() < 1),
        item('large', t('split.large'), Icons.photo_size_select_large_rounded, on: (now - PosSplit.large.clamp(PosSplit.min, max)).abs() < 1),
        const PopupMenuDivider(),
        _left ? item('right', t('split.right', {'x': x}), Icons.east_rounded) : item('left', t('split.left', {'x': x}), Icons.west_rounded),
        item('reset', t('split.reset'), Icons.restart_alt_rounded),
        PopupMenuItem(
          enabled: false,
          height: 34,
          child: Text(t('split.mine', {'name': widget.whoName.isEmpty ? '—' : widget.whoName}), style: TextStyle(fontSize: 12, color: c.muted)),
        ),
      ],
    );
    switch (pick) {
      case 'small':
        _set(w: PosSplit.small);
      case 'medium':
        _set(normal: true);
      case 'large':
        _set(w: PosSplit.large);
      case 'left':
        _set(left: true);
      case 'right':
        _set(left: false);
      case 'reset':
        _set(normal: true, left: false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final t = AppScope.of(context).t;
    return LayoutBuilder(
      builder: (context, box) {
        final total = box.maxWidth;
        final max = PosSplit.maxFor(total);
        final w = (_w ?? widget.normal).clamp(PosSplit.min, max).toDouble();
        final handle = Tooltip(
          message: t('split.drag', {'x': t('split.${widget.thing}')}),
          waitDuration: const Duration(milliseconds: 700),
          child: MouseRegion(
            cursor: SystemMouseCursors.resizeColumn,
            child: GestureDetector(
              key: const ValueKey('pos-split-handle'),
              behavior: HitTestBehavior.opaque,
              dragStartBehavior: DragStartBehavior.down, // measure from where the finger went down (the cart follows it exactly)
              onHorizontalDragStart: (d) => setState(() {
                _dragFrom = d.globalPosition.dx;
                _startW = w;
              }),
              onHorizontalDragUpdate: (d) {
                final from = _dragFrom;
                if (from == null) return;
                final dx = d.globalPosition.dx - from;
                setState(() => _w = (_left ? _startW + dx : _startW - dx).clamp(PosSplit.min, max).toDouble());
              },
              onHorizontalDragEnd: (_) {
                setState(() => _dragFrom = null);
                _save();
              },
              onDoubleTap: () => _set(normal: true),
              onTapUp: (d) => _menu(context, d.globalPosition, total),
              child: SizedBox(
                width: PosSplit.handle,
                child: Center(
                  child: Container(
                    width: 6,
                    height: 54,
                    decoration: BoxDecoration(color: _dragFrom != null ? c.brand : c.muted.withValues(alpha: .45), borderRadius: BorderRadius.circular(3)),
                  ),
                ),
              ),
            ),
          ),
        );
        final cart = SizedBox(key: const ValueKey('pos-split-cart'), width: w, child: widget.panel(_left));
        return Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: _left ? [cart, handle, Expanded(child: widget.main)] : [Expanded(child: widget.main), handle, cart],
        );
      },
    );
  }
}
