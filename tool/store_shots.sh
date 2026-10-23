#!/usr/bin/env bash
# The real POS screens for Google Play, with the demo shops' data (test/store/fixtures.json).
#   tool/store_shots.sh            all: restaurant, mart, guest_house × en, km × phone, tablet → test/store/out/
#   then: python3 store/android/compose/build.py   (phone frames + headlines, feature graphics, icon)
# Remake the fixtures after API changes: in bizhub-api,
#   NODE_PATH=~/evtest/node_modules node scripts/demo-pos.js --test --capture=../bizhub-app-pos/test/store/fixtures.json
set -euo pipefail
cd "$(dirname "$0")/.."
rm -f test/store/out/*.png
for lang in en km; do
  for kind in restaurant mart guest_house; do
    for tab in false true; do
      echo "• $lang $kind $([[ $tab == true ]] && echo tablet || echo phone)"
      flutter test test/store/store_shots_test.dart --update-goldens --dart-define=API_HOST=http://demo --dart-define=STORE_SHOTS=true \
        --dart-define=SHOT_KIND=$kind --dart-define=SHOT_LANG=$lang --dart-define=SHOT_TABLET=$tab > /dev/null
    done
  done
done
ls test/store/out | wc -l
