#!/usr/bin/env bash
# F-Droid pipe build for the fdroid flavor. Called from metadata:
#   build: bash tool/fdroid_build.sh $$flutter$$ [target-platform]
#
# Builds REPRODUCIBLY against the GitHub Actions binary: same toolchain (the
# repo's own pins — AGP 9.1.0 / Gradle 9.3.1, no seds) and the SAME absolute
# build path as Actions (/home/runner/work/enclavd-android-source/
# enclavd-android-source), because Flutter's AOT snapshot embeds the build
# path into libapp.so. The metadata needs the sudo: block to create + chown
# that path. The checkout is moved there for the build and moved back on exit
# so fdroidserver still finds the APK at the expected location.
#
# Optional second arg = flutter target-platform (android-arm, android-arm64,
# android-x64). The fdroiddata metadata has ONE build block per ABI (F-Droid's
# build-flutter template), each pinning its ABI here; when omitted the script
# builds ALL ABIs (CI reference builds all three in one invocation).
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

# Move the checkout to the upstream CI path, build there, move back on exit.
cd "$PARENT"
mv "$CHECKOUT" "$UPSTREAM"
cd "$UPSTREAM"
trap 'cd "$PARENT" && mv "$UPSTREAM" "$CHECKOUT" || true' EXIT

# pub get runs in the metadata prebuild — fdroid's scanner runs right AFTER
# prebuild (build.py scan_source) and must see the resolved dependencies, so
# the packages are fetched there, at the upstream path. The .pub-cache lives
# INSIDE the checkout (moved back after prebuild, moved forward again here),
# so re-exporting the same location makes this build use the scanned cache.
# The firebase strip + pubspec-fdroid.lock move happen in the metadata
# PREBUILD (maintainer order: strip -> pub get --enforce-lockfile -> build),
# so the resolved cache is already firebase-free by the time we get here.
# --no-pub keeps flutter from re-running pub get against the FULL pubspec
# (which would re-add firebase and regenerate .flutter-plugins-dependencies).
export PUB_CACHE="$(pwd)/.pub-cache"
# --split-per-abi: F-Droid requires per-ABI APKs (their request, Oct 2026);
# the version codes come out as base*10 + abi via android/app/build.gradle.kts
# (base*1000 + abi disabled via force-version-code-ignoring-abi in
# android/gradle.properties). Outputs: app-<abi>-fdroid-release.apk.
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

# The pipe's binary check rejects the 'Dependency metadata' signing-block
# entry AGP adds for Play. Strip it from EVERY split APK — v2/v3 signatures
# do NOT cover the signing block (validity preserved), and zip entries are
# untouched (the byte comparison is unaffected). Actions strips identically.
for APK in build/app/outputs/flutter-apk/app-*-fdroid-release.apk; do
    python3 tool/strip_dep_metadata.py "$APK"
done
