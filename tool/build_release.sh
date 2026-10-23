#!/usr/bin/env bash
# Build BizHub POS for Google Play (production settings, signed with the upload key).
#
#   tool/build_release.sh            build  build/app/outputs/bundle/release/app-release.aab
#   tool/build_release.sh --bump     first raise the build number in pubspec.yaml (1.0.0+1 → 1.0.0+2), then build
#
# Needs:  env.prod.json (production API)  and  android/key.properties (the upload key; the same key as the owner app).
# It refuses to build without the upload key: a build signed with debug keys is rejected by Google Play.
set -euo pipefail
cd "$(dirname "$0")/.."

[[ -f env.prod.json ]] || { echo "✗ env.prod.json is missing (production settings)."; exit 1; }
[[ -f android/key.properties ]] || { echo "✗ android/key.properties is missing — copy it from ../bizhub-app/android/key.properties (same upload key)."; exit 1; }
store=$(grep -E '^storeFile=' android/key.properties | cut -d= -f2-)
[[ -n "$store" && -f "$store" ]] || { echo "✗ The keystore in android/key.properties (storeFile=$store) was not found."; exit 1; }
grep -q '"API_HOST": *"https://bizhub-api-eight-production.vercel.app"' env.prod.json || { echo "✗ env.prod.json does not point at the production API."; exit 1; }

if [[ "${1:-}" == "--bump" ]]; then
  cur=$(grep -E '^version: ' pubspec.yaml | sed 's/version: //')
  name=${cur%%+*}; build=${cur##*+}
  next="$name+$((build + 1))"
  sed -i.bak "s/^version: .*/version: $next/" pubspec.yaml && rm -f pubspec.yaml.bak
  echo "• version $cur → $next"
fi

version=$(grep -E '^version: ' pubspec.yaml | sed 's/version: //')
echo "• building BizHub POS $version for Google Play (production)…"
flutter build appbundle --release --dart-define-from-file=env.prod.json

out=build/app/outputs/bundle/release/app-release.aab
[[ -f "$out" ]] || { echo "✗ build finished but $out is missing"; exit 1; }
echo
echo "✓ $out  ($(du -h "$out" | cut -f1), version $version)"
echo "  Upload it in Play Console → BizHub POS → Test and release → Closed testing → Alpha → Create new release."
echo "  Every new upload needs a higher build number: run with --bump next time."
