#!/usr/bin/env bash
# Build BizHub POS for Mac (production settings) and pack it as a .dmg ("drag to Applications").
#
#   tool/build_macos.sh                       build/dmg/BizHub-POS-<version>.dmg        (production API)
#   ENV_FILE=env.json tool/build_macos.sh     build/dmg/BizHub-POS-<version>-uat.dmg    (a test build on UAT)
#   GitHub's Mac builds it too: Actions → "Build Mac" → Run workflow (.github/workflows/macos.yml)
#
# Optional, once the Apple Developer account is active (so other Macs open it without a warning):
#   SIGN_ID="Developer ID Application: <Name> (<TEAM ID>)"   sign the app and the .dmg with that certificate
#   NOTARY_PROFILE=bizhub-notary                             also send it to Apple to notarize, then staple
#     (make the profile once:  xcrun notarytool store-credentials bizhub-notary --apple-id <id> --team-id <TEAM ID>)
#
# Needs: a Mac with Xcode, and env.prod.json (production API). Only the macos/ desktop app is built here;
# the Android / iPhone apps are not touched.
set -euo pipefail
cd "$(dirname "$0")/.."

[[ "$(uname)" == "Darwin" ]] || { echo "✗ A .dmg can only be made on a Mac."; exit 1; }
[[ -d macos ]] || { echo "✗ The macos/ folder is missing."; exit 1; }
env_file=${ENV_FILE:-env.prod.json}
[[ -f "$env_file" ]] || { echo "✗ $env_file is missing (the server settings)."; exit 1; }
if [[ "$env_file" == "env.prod.json" ]]; then
  grep -q '"API_HOST": *"https://bizhub-api-eight-production.vercel.app"' "$env_file" || { echo "✗ env.prod.json does not point at the production API."; exit 1; }
  server=production; suffix=""
else
  grep -q '"API_HOST": *"https://bizhub-api-eight-production.vercel.app"' "$env_file" && { echo "✗ $env_file points at production — use env.prod.json for that."; exit 1; }
  server=uat; suffix="-uat"
fi

version=$(grep -E '^version: ' pubspec.yaml | sed 's/version: //')
name=${version%%+*}
echo "• building BizHub POS $version for Mac ($server)…"
flutter build macos --release --dart-define-from-file="$env_file"

app="build/macos/Build/Products/Release/BizHub POS.app"
[[ -d "$app" ]] || { echo "✗ build finished but \"$app\" is missing"; exit 1; }

if [[ -n "${SIGN_ID:-}" ]]; then
  echo "• signing with: $SIGN_ID"
  codesign --force --deep --options runtime --timestamp --entitlements macos/Runner/Release.entitlements --sign "$SIGN_ID" "$app"
  codesign --verify --deep --strict "$app"
fi

out=build/dmg
dmg="$out/BizHub-POS-$name$suffix.dmg"
stage="$out/stage"
rm -rf "$stage" "$dmg"
mkdir -p "$stage"
cp -R "$app" "$stage/"
ln -s /Applications "$stage/Applications"
echo "• making ${dmg} …"
hdiutil create -volname "BizHub POS" -srcfolder "$stage" -ov -format UDZO "$dmg" >/dev/null
rm -rf "$stage"

if [[ -n "${SIGN_ID:-}" ]]; then
  codesign --force --timestamp --sign "$SIGN_ID" "$dmg"
  if [[ -n "${NOTARY_PROFILE:-}" ]]; then
    echo "• sending to Apple for notarization (a few minutes)…"
    xcrun notarytool submit "$dmg" --keychain-profile "$NOTARY_PROFILE" --wait
    xcrun stapler staple "$dmg"
  fi
fi

echo
echo "✓ $dmg  ($(du -h "$dmg" | cut -f1), version $version, $server)"
if [[ -z "${SIGN_ID:-}" ]]; then
  echo "  Not signed yet: it opens on this Mac. On another Mac, right-click the app → Open the first time"
  echo "  (or System Settings → Privacy & Security → Open Anyway). Sign + notarize once the Apple account is active."
elif [[ -z "${NOTARY_PROFILE:-}" ]]; then
  echo "  Signed, not notarized: other Macs still warn. Add NOTARY_PROFILE=… to notarize."
else
  echo "  Signed and notarized: any Mac opens it without a warning."
fi
