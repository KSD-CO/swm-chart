#!/usr/bin/env bash
# Captures the pub.dev / README screenshots from the example app.
# Usage: tool/screenshots.sh <simulator-udid>
set -euo pipefail
device="$1"
out="$(cd "$(dirname "$0")/.." && pwd)/screenshots"
log="$(mktemp)"
mkdir -p "$out"
xcrun simctl status_bar "$device" override --time 9:41 --batteryState charged --batteryLevel 100 \
  --cellularBars 4 --wifiBars 3
cd "$(dirname "$0")/../example"
flutter test integration_test/screenshots_test.dart -d "$device" > "$log" 2>&1 &
for name in trading_light trading_dark area_dark yield_curve options_chain; do
  until grep -q "CHECKPOINT $name" "$log"; do sleep 0.5; done
  sleep 1.5
  xcrun simctl io "$device" screenshot "$out/$name.png" > /dev/null
  # Keep files small for pub.dev: 900 px tall is plenty.
  sips -Z 900 "$out/$name.png" > /dev/null
done
wait
xcrun simctl status_bar "$device" clear
echo "Screenshots in $out"
