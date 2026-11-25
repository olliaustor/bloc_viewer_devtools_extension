#!/usr/bin/env bash
# One-time setup: generates the missing platform folders and fetches packages.
# Existing files (lib/, pubspec.yaml, web/index.html, ...) are NOT overwritten.
set -euo pipefail
cd "$(dirname "$0")/.."

(cd packages/bloc_viewer && dart pub get)

(cd packages/bloc_viewer_devtools_extension \
  && flutter create . --platforms web --project-name bloc_viewer_devtools_extension \
  && flutter pub get)

(cd packages/bloc_viewer_example \
  && flutter create . --platforms macos,ios,android --project-name bloc_viewer_example \
  && flutter pub get)

echo "Done. Next: tool/build_extension.sh"
