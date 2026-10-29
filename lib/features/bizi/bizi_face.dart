import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

// Bizi's face — the same drawing as the website (bizhub/src/dashboard/bizi/BiziFace.jsx), six moods.
// It bobs a little (still when the phone asks for less motion).
enum BiziMood { idle, listening, thinking, talking, happy, worried }

BiziMood moodOf(String? s) => BiziMood.values.firstWhere((m) => m.name == s, orElse: () => BiziMood.idle);

const _body = '''
<defs><linearGradient id="b" x1="0" y1="0" x2="1" y2="1"><stop offset="0" stop-color="#F08A3C"/><stop offset="1" stop-color="#D9521A"/></linearGradient></defs>
<line x1="100" y1="50" x2="100" y2="30" stroke="#D9521A" stroke-width="6" stroke-linecap="round"/>
<circle cx="100" cy="21" r="11" fill="#FFF7EF" stroke="#E0581A" stroke-width="5"/>
<circle cx="100" cy="21" r="3.5" fill="#E0581A"/>
<ellipse cx="32" cy="130" rx="12" ry="17" fill="#D9521A"/>
<ellipse cx="168" cy="130" rx="12" ry="17" fill="#D9521A"/>
<rect x="32" y="48" width="136" height="134" rx="56" fill="url(#b)"/>
<rect x="49" y="76" width="102" height="74" rx="32" fill="#FFF7EF"/>
<circle cx="65" cy="128" r="6" fill="#F4A27A" opacity="0.75"/>
<circle cx="135" cy="128" r="6" fill="#F4A27A" opacity="0.75"/>
''';

const _faces = <BiziMood, String>{
  BiziMood.idle: '''
<circle cx="80" cy="108" r="8" fill="#16171B"/><circle cx="120" cy="108" r="8" fill="#16171B"/>
<circle cx="83" cy="105" r="2.5" fill="#FFFFFF"/><circle cx="123" cy="105" r="2.5" fill="#FFFFFF"/>
<path d="M88 128 Q100 138 112 128" stroke="#16171B" stroke-width="4" stroke-linecap="round" fill="none"/>''',
  BiziMood.listening: '''
<circle cx="80" cy="107" r="9.5" fill="#16171B"/><circle cx="120" cy="107" r="9.5" fill="#16171B"/>
<circle cx="83.5" cy="103.5" r="3" fill="#FFFFFF"/><circle cx="123.5" cy="103.5" r="3" fill="#FFFFFF"/>
<circle cx="100" cy="132" r="5" fill="#16171B"/>
<path d="M184 96 Q193 116 184 136" stroke="#E0581A" stroke-width="5" stroke-linecap="round" fill="none"/>
<path d="M193 86 Q207 116 193 146" stroke="#E0581A" stroke-width="5" stroke-linecap="round" fill="none" opacity="0.45"/>''',
  BiziMood.thinking: '''
<circle cx="84" cy="101" r="7.5" fill="#16171B"/><circle cx="124" cy="101" r="7.5" fill="#16171B"/>
<path d="M91 131 L109 129" stroke="#16171B" stroke-width="4" stroke-linecap="round" fill="none"/>
<circle cx="150" cy="40" r="4.5" fill="#FFFFFF" stroke="#E0581A" stroke-width="3"/>
<circle cx="164" cy="27" r="6.5" fill="#FFFFFF" stroke="#E0581A" stroke-width="3"/>
<circle cx="182" cy="14" r="9" fill="#FFFFFF" stroke="#E0581A" stroke-width="3"/>''',
  BiziMood.talking: '''
<circle cx="80" cy="106" r="8" fill="#16171B"/><circle cx="120" cy="106" r="8" fill="#16171B"/>
<circle cx="83" cy="103" r="2.5" fill="#FFFFFF"/><circle cx="123" cy="103" r="2.5" fill="#FFFFFF"/>
<path d="M86 123 Q100 147 114 123 Z" fill="#16171B"/><ellipse cx="100" cy="135" rx="6" ry="3.5" fill="#F4A27A"/>''',
  BiziMood.happy: '''
<path d="M71 110 Q80 98 89 110" stroke="#16171B" stroke-width="4.5" stroke-linecap="round" fill="none"/>
<path d="M111 110 Q120 98 129 110" stroke="#16171B" stroke-width="4.5" stroke-linecap="round" fill="none"/>
<path d="M83 122 Q100 145 117 122 Z" fill="#16171B"/>
<path d="M30 44 L34 54 L44 58 L34 62 L30 72 L26 62 L16 58 L26 54 Z" fill="#E8A21A"/>
<path d="M172 56 L175 63 L182 66 L175 69 L172 76 L169 69 L162 66 L169 63 Z" fill="#E8A21A"/>''',
  BiziMood.worried: '''
<path d="M69 92 L88 98" stroke="#16171B" stroke-width="4" stroke-linecap="round"/>
<path d="M131 92 L112 98" stroke="#16171B" stroke-width="4" stroke-linecap="round"/>
<circle cx="80" cy="110" r="7" fill="#16171B"/><circle cx="120" cy="110" r="7" fill="#16171B"/>
<path d="M89 132 Q94.5 126 100 132 Q105.5 138 111 132" stroke="#16171B" stroke-width="4" stroke-linecap="round" fill="none"/>
<path d="M157 60 Q166 74 157 82 Q148 74 157 60 Z" fill="#7DB8EC"/>''',
};

String biziSvg(BiziMood m) => '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 200 200">$_body${_faces[m]}</svg>';

class BiziFace extends StatefulWidget {
  static bool animate = true; // tests turn the bob off (a picture never "settles" while it moves)
  final BiziMood mood;
  final double size;
  const BiziFace({super.key, this.mood = BiziMood.idle, this.size = 56});
  @override
  State<BiziFace> createState() => _BiziFaceState();
}

class _BiziFaceState extends State<BiziFace> with SingleTickerProviderStateMixin {
  late final AnimationController _bob = AnimationController(vsync: this, duration: const Duration(milliseconds: 2400));

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final still = !BiziFace.animate || (MediaQuery.maybeDisableAnimationsOf(context) ?? false);
    if (still) {
      _bob.stop();
    } else if (!_bob.isAnimating) {
      _bob.repeat(reverse: true);
    }
  }

  @override
  void dispose() {
    _bob.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final pic = SvgPicture.string(biziSvg(widget.mood), width: widget.size, height: widget.size, semanticsLabel: 'Bizi');
    return SizedBox(
      width: widget.size,
      height: widget.size,
      child: AnimatedBuilder(
        animation: _bob,
        builder: (_, child) => Transform.translate(offset: Offset(0, -widget.size * .03 * Curves.easeInOut.transform(_bob.value)), child: child),
        child: pic,
      ),
    );
  }
}
