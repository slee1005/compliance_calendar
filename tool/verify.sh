#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

# Use the project SDK when available; never sign or publish.
./tool/flutter pub get --enforce-lockfile
if [[ -x .tools/flutter/bin/dart ]]; then
  compliance_dart=.tools/flutter/bin/dart
else
  compliance_dart=dart
fi
"$compliance_dart" format --output=none --set-exit-if-changed lib test integration_test test_driver packages/flutter_secure_storage_windows/lib
./tool/flutter analyze --fatal-infos --fatal-warnings
"$compliance_dart" analyze --fatal-infos packages/flutter_secure_storage_windows/lib
./tool/flutter test
