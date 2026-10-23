import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/app_state.dart';
import '../../core/theme.dart';
import '../../widgets/ui.dart';

// The 4 welcome pages, the first time the app opens.
class WelcomePage extends StatefulWidget {
  const WelcomePage({super.key});
  @override
  State<WelcomePage> createState() => _WelcomePageState();
}

class _WelcomePageState extends State<WelcomePage> {
  final _pages = PageController();
  int _at = 0;

  static const _slides = [
    ('w1', LucideIcons.store, [Color(0xFFC2410C), Color(0xFFF08A1E)]),
    ('w2', LucideIcons.wifiOff, [Color(0xFF0369A1), Color(0xFF22D3EE)]),
    ('w3', LucideIcons.refreshCw, [Color(0xFF059669), Color(0xFF84CC16)]),
    ('w4', LucideIcons.keyRound, [Color(0xFF7C3AED), Color(0xFFE0581A)]),
  ];

  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final t = app.t;
    final last = _at == _slides.length - 1;
    return Scaffold(
      backgroundColor: Brand.roast,
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 12, 0),
              child: Row(
                children: [
                  const Logo(height: 28, white: true),
                  const SizedBox(width: 8),
                  Text('POS', style: TextStyle(color: Brand.lime, fontWeight: FontWeight.w800, fontSize: 18, letterSpacing: .5)),
                  const Spacer(),
                  TextButton(
                    onPressed: () => app.setLang(app.lang == 'km' ? 'en' : 'km'),
                    child: Text(app.lang == 'km' ? 'EN' : 'ខ្មែរ', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
                  ),
                  if (!last)
                    TextButton(
                      onPressed: app.doneWelcome,
                      child: Text(t('app.skip'), style: TextStyle(color: Colors.white.withValues(alpha: .7))),
                    ),
                ],
              ),
            ),
            Expanded(
              child: PageView(
                controller: _pages,
                onPageChanged: (v) => setState(() => _at = v),
                children: [
                  for (final (k, icon, grad) in _slides)
                    LayoutBuilder(
                      builder: (context, box) => SingleChildScrollView(
                        padding: const EdgeInsets.symmetric(horizontal: 28),
                        child: ConstrainedBox(
                          constraints: BoxConstraints(minHeight: box.maxHeight),
                          child: Center(
                            child: ConstrainedBox(
                              constraints: const BoxConstraints(maxWidth: 460),
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Container(
                                    width: 150,
                                    height: 150,
                                    decoration: BoxDecoration(
                                      borderRadius: BorderRadius.circular(44),
                                      gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: grad),
                                      boxShadow: [BoxShadow(color: grad.last.withValues(alpha: .35), blurRadius: 40, offset: const Offset(0, 18))],
                                    ),
                                    child: Icon(icon, size: 70, color: Colors.white),
                                  ),
                                  const SizedBox(height: 40),
                                  Text(
                                    t('$k.title'),
                                    textAlign: TextAlign.center,
                                    style: const TextStyle(color: Colors.white, fontSize: 28, fontWeight: FontWeight.w800, height: 1.25),
                                  ),
                                  const SizedBox(height: 14),
                                  Text(
                                    t('$k.sub'),
                                    textAlign: TextAlign.center,
                                    style: TextStyle(color: Colors.white.withValues(alpha: .72), fontSize: 16, height: 1.55),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 8, 24, 20),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      for (var i = 0; i < _slides.length; i++)
                        AnimatedContainer(
                          duration: const Duration(milliseconds: 220),
                          width: i == _at ? 26 : 8,
                          height: 8,
                          margin: const EdgeInsets.symmetric(horizontal: 4),
                          decoration: BoxDecoration(color: i == _at ? Brand.lime : Colors.white.withValues(alpha: .25), borderRadius: BorderRadius.circular(8)),
                        ),
                    ],
                  ),
                  const SizedBox(height: 18),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 460),
                    child: SizedBox(
                      width: double.infinity,
                      height: 56,
                      child: FilledButton(
                        style: FilledButton.styleFrom(
                          backgroundColor: last ? Brand.lime : Colors.white,
                          foregroundColor: Brand.roast,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
                          textStyle: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
                        ),
                        onPressed: () => last ? app.doneWelcome() : _pages.nextPage(duration: const Duration(milliseconds: 320), curve: Curves.easeOutCubic),
                        child: Text(last ? t('app.start') : t('app.next')),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
