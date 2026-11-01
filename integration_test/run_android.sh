#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."
device_id="${1:-emulator-5554}"
response="$PWD/build/ci/signer-response.json"

if [[ "$(adb -s "$device_id" shell getprop ro.kernel.qemu | tr -d '\r')" != 1 ]]; then
  echo 'Use a disposable emulator; this test clears wallet data.' >&2
  exit 1
fi

# Reject stale responses.
rm -f "$response"
device_abi="$(adb -s "$device_id" shell getprop ro.product.cpu.abi | tr -d '\r')"
case "$device_abi" in
  x86_64) target_platform=android-x64 ;;
  arm64-v8a) target_platform=android-arm64 ;;
  *) echo "Unsupported signer test device ABI: $device_abi" >&2; exit 1 ;;
esac

flutter pub get --enforce-lockfile
flutter build apk --debug --no-pub \
  --target=integration_test/signer_flow_test.dart \
  --target-platform="$target_platform"
test_apk="$PWD/build/app/outputs/flutter-apk/app-debug.apk"
# Pre-grant camera permission.
adb -s "$device_id" install -r -g "$test_apk"
flutter drive --no-pub \
  --driver=test_driver/integration_test.dart \
  --target=integration_test/signer_flow_test.dart \
  --use-application-binary="$test_apk" \
  --device-id="$device_id"
test -s "$response"
test_list="$(cargo test --locked --manifest-path rust/Cargo.toml --lib -- --list)"
grep -Fxq 'vizor_flow_tests::verify_android_response: test' <<< "$test_list"
ZIGNER_ANDROID_RESPONSE="$response" \
  cargo test --locked --manifest-path rust/Cargo.toml --lib \
  vizor_flow_tests::verify_android_response -- --ignored --exact
