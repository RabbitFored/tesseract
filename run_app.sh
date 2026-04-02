#!/usr/bin/env bash
# run_app.sh — Build & deploy Tesseract using credentials from .env
#
# Usage:
#   ./run_app.sh          # hot-reload debug run on connected device
#   ./run_app.sh --release  # release build & install on connected device
#   ./run_app.sh --apk      # build release APK only (no device needed)
#
# Requires: Flutter SDK, ADB (for --release / default run)
# Install ADB: sudo apt install adb

set -euo pipefail

ENV_FILE="$(dirname "$0")/.env"
if [[ ! -f "$ENV_FILE" ]]; then
  echo "❌  .env file not found at $ENV_FILE"
  exit 1
fi

# Parse .env (ignore blank lines and comments)
export $(grep -v '^\s*#' "$ENV_FILE" | grep -v '^\s*$' | xargs)

if [[ -z "${TELEGRAM_API_ID:-}" || -z "${TELEGRAM_API_HASH:-}" ]]; then
  echo "❌  TELEGRAM_API_ID or TELEGRAM_API_HASH missing in .env"
  exit 1
fi

DEFINES="--dart-define=TELEGRAM_API_ID=${TELEGRAM_API_ID} --dart-define=TELEGRAM_API_HASH=${TELEGRAM_API_HASH}"

MODE="${1:-}"

case "$MODE" in
  --apk)
    echo "📦  Building release APK (arm64 only)..."
    flutter build apk \
      --release \
      --target-platform android-arm64 \
      --split-per-abi \
      --obfuscate \
      --split-debug-info=build/debug-info \
      $DEFINES
    APK_PATH=$(find build/app/outputs/flutter-apk -name "*arm64*.apk" | head -1)
    echo "✅  APK ready: $APK_PATH ($(du -sh "$APK_PATH" | cut -f1))"
    ;;
  --release)
    echo "📱  Building & installing release APK on device..."
    flutter build apk \
      --release \
      --target-platform android-arm64 \
      --split-per-abi \
      --obfuscate \
      --split-debug-info=build/debug-info \
      $DEFINES
    APK_PATH=$(find build/app/outputs/flutter-apk -name "*arm64*.apk" | head -1)
    adb install -r "$APK_PATH"
    echo "✅  Installed. Starting app..."
    adb shell am start -n com.struthio.tesseract/.MainActivity
    echo "💡  Run 'adb logcat | grep TdLibClient' to see TDLib logs."
    ;;
  *)
    echo "🚀  Running debug build on device (hot-reload enabled)..."
    echo "💡  Watch TDLib logs with: adb logcat | grep -E 'TdLib|Bootstrap|flutter'"
    flutter run $DEFINES
    ;;
esac
