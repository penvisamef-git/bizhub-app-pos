// Pull the EN/KM text objects out of the web app source, so the Flutter app uses the exact same words.
const fs = require("fs");
// usage (BizHub POS app): node tool/extract_texts.js ../bizhub/src assets/i18n
const SRC = (process.argv[2] || "../bizhub/src").replace(/\/?$/, "/");
function objAfter(src, marker) {
  const at = src.indexOf(marker);
  if (at < 0) throw new Error("marker not found: " + marker);
  let i = src.indexOf("{", at) , depth = 0, q = null;
  if (src.slice(at + marker.length).trimStart()[0] === "[") i = src.indexOf("[", at);
  const start = i;
  for (; i < src.length; i++) {
    const c = src[i];
    if (q) { if (c === "\\") { i++; continue; } if (c === q) q = null; continue; }
    if (c === '"' || c === "'" || c === "`") { q = c; continue; }
    if (c === "/" && src[i + 1] === "/") { i = src.indexOf("\n", i); continue; }
    if (c === "{" || c === "[") depth++;
    if (c === "}" || c === "]") { depth--; if (depth === 0) return src.slice(start, i + 1); }
  }
  throw new Error("unbalanced " + marker);
}
const evalObj = (code) => new Function(`return (${code});`)();
// functions → text with {n} placeholder
function plain(v) {
  if (typeof v === "function") { try { return String(v("{n}")); } catch { return ""; } }
  if (Array.isArray(v)) return v.map(plain);
  if (v && typeof v === "object") return Object.fromEntries(Object.entries(v).map(([k, x]) => [k, plain(x)]));
  return v;
}
const read = (f) => fs.readFileSync(SRC + f, "utf8");
const pick = (f, marker) => plain(evalObj(objAfter(read(f), marker)));
// objects built with a helper function (pos/restThemes.js: T(en, km, d_en, d_km, {...}))
const pickT = (f, marker) => plain(new Function("T", `return (${objAfter(read(f), marker)});`)((en, km, d_en, d_km) => ({ en, km, d_en, d_km })));

const out = {
  // restaurant POS (pos/text.js) — the web's own words
  rpos: pick("pos/text.js", "const TEXT ="),
  // Mini Mart POS (pos/mart/ptext.js) + the shared mini mart words (methods, debt book…) + loyalty / promotions
  mpos: pick("pos/mart/ptext.js", "export const P ="),
  mart: pick("dashboard/client/mart/text.js", "export const MART_TEXT ="),
  mx: pick("dashboard/client/mart/xtext.js", "export const X_TEXT ="),
  mw: pick("dashboard/client/mart/wtext.js", "export const W_TEXT ="), // online orders (website shop)
  // Guest House: the dashboard words (+ the newer ones in gh3-text.js, merged like text.js does) + the desk POS
  gh: (() => {
    const g = pick("dashboard/client/guesthouse/text.js", "export const GH_TEXT =");
    const more = pick("dashboard/client/guesthouse/gh3-text.js", "export const MORE =");
    for (const l of ["en", "km"]) {
      const { tabs, addonInfo, staffRoles, sources, ...rest } = more[l];
      Object.assign(g[l].tabs, tabs);
      Object.assign(g[l].sources, sources);
      Object.assign(g[l].staffRoles, staffRoles);
      Object.assign(g[l].addonInfo, addonInfo);
      Object.assign(g[l], rest);
    }
    return g;
  })(),
  ghp: pick("pos/guesthouse/GhPosApp.jsx", "const P ="),
  gc: pick("dashboard/client/guesthouse/gh2-text.js", "export const CU_TEXT ="), // website booking requests
  gx: pick("dashboard/client/guesthouse/gh3-text.js", "export const X3_TEXT ="), // housekeeping, long stay, expenses, members, requests
  att: pick("attend/text.js", "export const TEXT ="), // attendance: staff phone
  atte: pick("attend/EngageViews.jsx", "const T ="), // attendance: news + rewards
  attt: pick("attend/TeamView.jsx", "const T ="), // attendance: manager's team
  attk: pick("attend/KioskView.jsx", "export const KT ="), // attendance: door tablet
  attkp: pick("attend/KioskPage.jsx", "const T ="), // attendance: door tablet messages
  sc: pick("dashboard/client/stamp/text.js", "const TEXT ="), // stamp card: the counter, customers, history, stats
  scp: pick("stamp/text.js", "const TEXT ="), // stamp card: the desk page
  evd: pick("pos/event/doorText.js", "const TEXT ="), // event tickets: the door phone
};
// one flat map per language: section.key → text (nested objects keep their path)
const langs = {};
for (const lang of ["en", "km"]) {
  const flat = {};
  const put = (prefix, v) => {
    if (v && typeof v === "object" && !Array.isArray(v)) for (const [k, x] of Object.entries(v)) put(prefix ? `${prefix}.${k}` : k, x);
    else flat[prefix] = v;
  };
  for (const [sec, v] of Object.entries(out)) {
    put(sec, v[lang] ?? v);
  }
  langs[lang] = flat;
}
fs.mkdirSync(process.argv[3], { recursive: true });
for (const [lang, flat] of Object.entries(langs)) fs.writeFileSync(`${process.argv[3]}/${lang}.json`, JSON.stringify(flat, null, 1));
console.log(Object.keys(langs.en).length, "en keys,", Object.keys(langs.km).length, "km keys");
