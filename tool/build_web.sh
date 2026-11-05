#!/usr/bin/env bash
# Builds the browser preview into build/web: the Flutter UI (dart2js) and
# the database worker (web_engine/db_worker.dart, dart2wasm) in build/web/db/.
# On the shared Pi run it through the queue: xbuild tool/build_web.sh
set -euo pipefail
cd "$(dirname "$0")/.."
FLUTTER="${FLUTTER:-flutter}"
DART="${DART:-dart}"
"$FLUTTER" build web --release --no-web-resources-cdn --no-wasm-dry-run
mkdir -p build/web/db
"$DART" compile wasm -O2 web_engine/db_worker.dart -o build/web/db/db_worker.wasm
rm -f build/web/db/db_worker.wasm.map
cp web_engine/db_worker.js build/web/db/
ls -l build/web/db
