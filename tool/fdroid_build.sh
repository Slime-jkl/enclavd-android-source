#!/usr/bin/env bash
# F-Droid pipe build for the fdroid flavor. Called from metadata:
#   build: bash tool/fdroid_build.sh $$flutter$$
#
# Builds REPRODUCIBLY against the GitHub Actions binary: same toolchain (the
# repo's own pins — AGP 9.1.0 / Gradle 9.3.1, no seds) and the SAME absolute
# build path as Actions (/home/runner/work/enclavd-android-source/
# enclavd-android-source), because Flutter's AOT snapshot embeds the build
# path into libapp.so. The metadata needs the sudo: block to create + chown
# that path. The checkout is moved there for the build and moved back on exit
# so fdroidserver still finds the APK at the expected location.
set -euo pipefail
set -x

FLUTTER="${1:?usage: fdroid_build.sh <flutter-dir-or-binary>}"
if [ -d "$FLUTTER" ]; then
    FLUTTER="$FLUTTER/bin/flutter"
fi

UPSTREAM="/home/runner/work/enclavd-android-source/enclavd-android-source"
ORIG="$(pwd)"
PARENT="$(dirname "$ORIG")"
CHECKOUT="$(basename "$ORIG")"

# Move the checkout to the upstream CI path, build there, move back on exit.
cd "$PARENT"
mv "$CHECKOUT" "$UPSTREAM"
cd "$UPSTREAM"
trap 'cd "$PARENT" && mv "$UPSTREAM" "$CHECKOUT" || true' EXIT

# pub get MUST run here, after the move — package_config.json stores absolute
# paths to the pub cache, so it has to be generated at the final location.
export PUB_CACHE="$(pwd)/.pub-cache"
"$FLUTTER" config --no-analytics
"$FLUTTER" pub get --enforce-lockfile

# Zero Google code in the fdroid build: drop the firebase plugin MODULES.
python3 tool/strip_firebase.py

# --no-pub: flutter build would re-run pub get and regenerate
# .flutter-plugins-dependencies, undoing the strip.
"$FLUTTER" build apk --release --no-pub --flavor fdroid \
    --dart-define=ENCLAVD_FLAVOR=fdroid \
    --dart-define=ENCLAVD_FEATURE_NOTIFICATIONS=true \
    --dart-define=ENCLAVD_FEATURE_CHAT=true \
    --dart-define=ENCLAVD_FEATURE_SEARCH=true

# The pipe's binary check rejects the 'Dependency metadata' signing-block
# entry AGP adds for Play. Strip it — v2/v3 signatures do NOT cover the
# signing block (validity preserved), and zip entries are untouched (the
# byte comparison is unaffected). Actions strips identically.
python3 tool/strip_dep_metadata.py \
    build/app/outputs/flutter-apk/app-fdroid-release.apk
