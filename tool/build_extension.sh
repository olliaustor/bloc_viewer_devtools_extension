#!/usr/bin/env bash
# Compiles the extension web app and copies it to
# packages/bloc_viewer/extension/devtools/build, then validates the layout.
# Re-run after every change you want to see in the REAL DevTools.
set -euo pipefail
cd "$(dirname "$0")/../packages/bloc_viewer_devtools_extension"

flutter pub get
dart run devtools_extensions build_and_copy \
  --source=. \
  --dest=../bloc_viewer/extension/devtools
dart run devtools_extensions validate --package=../bloc_viewer
