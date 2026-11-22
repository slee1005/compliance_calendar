#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
if [[ "$#" != 1 ]]; then
  printf '%s\n' 'Usage: bash tool/capture_preview.sh <native-device-id>' >&2
  exit 2
fi
export COMPLIANCE_DEVICE_ID="$1"
./tool/flutter drive \
  --driver=test_driver/preview_driver.dart \
  --target=integration_test/app_smoke_test.dart \
  --dart-define=CAPTURE_PREVIEW=true \
  -d "$1"
