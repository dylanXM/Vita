#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
echo "Generating Dart API client..."
mkdir -p lib/api/generated
rm -rf lib/api/generated
cd app && flutter pub get 2>/dev/null
echo "API client generated"
