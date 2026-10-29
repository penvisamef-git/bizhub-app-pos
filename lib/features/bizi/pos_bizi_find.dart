// Bizi in the POS (v3.0.0): finding the cashier how-tos — the same rules as the website and the BizHub app
// (bizhub/src/dashboard/bizi/help-find.js): question words dropped, Khmer written together, one typing mistake.

// one small typing mistake (a letter missing, extra, wrong or swapped)
bool near(String a, String b) {
  if (a == b) return true;
  if ((a.length - b.length).abs() > 1 || a.length < 4) return false;
  var i = 0;
  while (i < a.length && i < b.length && a[i] == b[i]) {
    i++;
  }
  String from(String s, int n) => n >= s.length ? '' : s.substring(n);
  return from(a, i + 1) == from(b, i + 1) ||
      from(a, i) == from(b, i + 1) ||
      from(a, i + 1) == from(b, i) ||
      (i + 1 < a.length && i + 1 < b.length && a[i] == b[i + 1] && a[i + 1] == b[i] && from(a, i + 2) == from(b, i + 2));
}

final _splitter = RegExp(r'[\s·,/&()\-]+');

// does the word appear in the text (inside a word = 2, or one mistake away from a whole word = 1)?
int hit(String word, String text, {bool fuzzy = true}) {
  if (text.contains(word)) return 2;
  if (!fuzzy || word.length < 4) return 0;
  return text.split(_splitter).any((t) => near(word, t)) ? 1 : 0;
}

List<String> words(String q) => q.toLowerCase().split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();

// ---------------------------------------------------------------- how-tos
class HelpHit {
  final Map a;
  final int score;
  const HelpHit(this.a, this.score);
  String get id => '${a['id']}';
  String q(String lang) => '${(a[lang] as Map?)?['q'] ?? (a['en'] as Map)['q']}';
  String open(String lang) => '${(a[lang] as Map?)?['open'] ?? ''}';
  List<String> steps(String lang) => (((a[lang] as Map?)?['steps'] ?? (a['en'] as Map)['steps']) as List).map((e) => '$e').toList();
}

const _stop = {
  'how', 'do', 'does', 'did', 'i', 'we', 'you', 'to', 'a', 'an', 'the', 'my', 'our', 'can', 'could', 'should', 'where', 'what', 'which', 'when', 'why', 'is', 'are', 'am', 'it', 'its', 'in', 'on', //
  'at', 'for', 'of', 'with', 'from', 'be', 'get', 'make', 'use', 'using', 'want', 'need', 'please', 'help', 'me', 'there', 'this', 'that', 'any', 'some', 'way',
};
const _kmAsk = ['ដោយរបៀបណា', 'យ៉ាងដូចម្តេច', 'យ៉ាងម៉េច', 'ធ្វើម៉េច', 'ធ្វើយ៉ាងណា', 'នៅឯណា', 'នៅណា', 'របៀប', 'តើ', 'ខ្ញុំ', 'ចង់', 'អាច', 'បានទេ', 'ដើម្បី', 'យ៉ាងណា', '?', '？'];
final _question = RegExp(r'^(how|where|what|can|could|why|when|which|is|do|does|help)\b|\?\s*$|ធ្វើម៉េច|យ៉ាងម៉េច|របៀប|តើ|ដោយរបៀបណា|យ៉ាងដូចម្តេច|នៅឯណា', caseSensitive: false);
final _km = RegExp('[ក-៿]');
final _wordChars = RegExp(r'[^\p{L}\p{N}]+', unicode: true);

// does the text look like a question? (then the answers go first)
bool isQuestion(String q) => _question.hasMatch(q.trim());
bool _isKm(String w) => _km.hasMatch(w);

String _textOf(Map a) => '${(a['en'] as Map)['q']} ${(a['km'] as Map)['q']} ${a['words']}'.toLowerCase();
List<String> _kmWords(Map a) => '${(a['km'] as Map)['q']} ${a['words']}'.split(RegExp(r'[\s·,/()?]+')).where((w) => _isKm(w) && w.length >= 2 && !_kmAsk.contains(w)).toList();

// the how-tos for the words, best first
List<HelpHit> findHelp(String raw, List<Map> list, {int max = 3}) {
  final q = raw.toLowerCase().trim();
  if (q.length < 2) return const [];
  var rest = q;
  for (final k in _kmAsk) {
    rest = rest.split(k).join(' ');
  }
  final ws = rest.replaceAll(RegExp('[?!.,:;"“”\']'), ' ').split(RegExp(r'\s+')).where((w) => w.isNotEmpty && !_stop.contains(w)).toList();
  final asked = isQuestion(q);
  final out = <HelpHit>[];
  for (final a in list) {
    final text = _textOf(a);
    final km = _kmWords(a);
    var score = 0;
    var found = 0;
    for (final w in ws) {
      // short words ("id", "qr", "pin") only as a whole word, else "id" would be in "paid"
      final h = w.length <= 3 && !_isKm(w) ? (text.split(_wordChars).contains(w) ? 2 : 0) : hit(w, text);
      if (h > 0) {
        found += 1;
        score += h == 2 ? 3 : 2;
      } else if (_isKm(w) && km.any((k) => k.length >= 3 && w.contains(k))) {
        found += 1; // Khmer written together: "ភ្ជាប់ម៉ាស៊ីនព្រីន" has "ម៉ាស៊ីនព្រីន" in it
      }
    }
    // the topic's Khmer words inside the whole question (longer = surer)
    for (final k in km) {
      if (q.contains(k)) score += (k.length ~/ 2).clamp(1, 6);
    }
    if (score == 0) continue;
    final need = asked ? (ws.length / 2).ceil() : ws.length;
    if (ws.isNotEmpty && found < need && score < 6) continue;
    out.add(HelpHit(a, score + (asked ? 2 : 0)));
  }
  out.sort((x, y) => y.score.compareTo(x.score));
  return out.take(max).toList();
}
