#!/usr/bin/env bash
# Runs both test suites with coverage and fails if any instrumented line is uncovered.
# Not instrumented: lib/main.dart and lib/src/service_manager_backend.dart (web-only, DevTools globals).
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"

summarize() { # lcov file -> prints per-file hits, returns 1 on any miss
  awk -F'[:,]' '/^SF:/{f=$2} /^DA:/{t[f]++; if($3>0)h[f]++} END{bad=0; for(f in t){printf "%-60s %d/%d\n",f,h[f],t[f]; if(h[f]!=t[f])bad=1} exit bad}' "$1"
}

cd "$root/packages/bloc_viewer"
rm -rf coverage
dart test --coverage=coverage
dart run coverage:format_coverage --lcov --in=coverage --out=coverage/lcov.info \
  --report-on=lib --packages=.dart_tool/package_config.json
summarize coverage/lcov.info

cd "$root/packages/bloc_viewer_devtools_extension"
rm -rf coverage
flutter test --coverage
summarize coverage/lcov.info
echo "100% line coverage."
