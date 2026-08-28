#!/usr/bin/env bash
# F-Droid pipe build for the fdroid flavor. Called from metadata:
#   build: bash tool/fdroid_build.sh $$flutter$$ [target-platform]
#
# Uses the same toolchain and absolute build path as GitHub Actions, since
# Flutter's AOT snapshot embeds the build path into libapp.so. The checkout
# is moved to that path for the build and moved back on exit.
# Optional second arg = target-platform; omitted builds all ABIs.
set -euo pipefail
set -x

FLUTTER="${1:?usage: fdroid_build.sh <flutter-dir-or-binary> [target-platform]}"
if [ -d "$FLUTTER" ]; then
    FLUTTER="$FLUTTER/bin/flutter"
fi
TARGET_PLATFORM="${2:-}"

UPSTREAM="/home/runner/work/enclavd-android-source/enclavd-android-source"
ORIG="$(pwd)"
PARENT="$(dirname "$ORIG")"
CHECKOUT="$(basename "$ORIG")"

cd "$PARENT"
mv "$CHECKOUT" "$UPSTREAM"
cd "$UPSTREAM"
trap 'cd "$PARENT" && mv "$UPSTREAM" "$CHECKOUT" || true' EXIT

# pub get runs in the metadata prebuild, so the resolved (firebase-free)
# .pub-cache lives inside the checkout; --no-pub keeps this build from
# re-running pub get against the full pubspec.
export PUB_CACHE="$(pwd)/.pub-cache"
# --split-per-abi: F-Droid requires per-ABI APKs; version codes are
# base*10 + abi via android/app/build.gradle.kts.
TARGET_ARGS=()
if [ -n "$TARGET_PLATFORM" ]; then
    TARGET_ARGS=(--target-platform="$TARGET_PLATFORM")
fi
"$FLUTTER" build apk --release --no-pub --flavor fdroid --split-per-abi \
    "${TARGET_ARGS[@]}" \
    --dart-define=ENCLAVD_FLAVOR=fdroid \
    --dart-define=ENCLAVD_FEATURE_NOTIFICATIONS=true \
    --dart-define=ENCLAVD_FEATURE_CHAT=true \
    --dart-define=ENCLAVD_FEATURE_SEARCH=true

# Strip AGP's 'Dependency metadata' signing-block entry from every split
# APK (v2/v3 signatures don't cover the signing block; zip entries untouched).
for APK in build/app/outputs/flutter-apk/app-*-fdroid-release.apk; do
    python3 tool/strip_dep_metadata.py "$APK"
done
