#!/usr/bin/env bash
# Build the fdroid reference binary in the SAME environment as the F-Droid
# pipe, so the pipe's binary comparison passes byte-for-byte.
#
# The pipe builds inside the fdroidserver buildserver image (Android SDK at
# /opt/android-sdk, checkout at /home/vagrant/build/com.enclavd.app, flutter
# srclib at /home/vagrant/build/srclib/flutter). tool/fdroid_build.sh already
# pins the build path and pub-cache location; this script reproduces the rest
# of the environment in a container and runs the same script.
#
# The reference binary must also be signed with the release keystore, or the
# pipe rejects it at the AllowedAPKSigningKeys check (after the content
# comparison passes). To sign (same secrets as the CI workflow):
#   export SIGNING_KEY="$(base64 -w0 /path/to/release-keystore.jks)"
#   export KEY_STORE_PASSWORD=... ALIAS=... KEY_PASSWORD=...
# or set SIGNING_KEY_FILE=/path/to/release-keystore.jks instead of SIGNING_KEY.
# Without them the build still runs but the APK carries the debug key — the
# pipe will fail it at the key check (useful only to isolate the content gate).
#
# Usage:
#   tool/build_reference_binary.sh              # build current HEAD
#   tool/build_reference_binary.sh <commit-sha> # build the exact commit the
#                                               # pipe's YML pins
# Output: app-fdroid-release-reference.apk in the current directory.
set -euo pipefail

IMAGE="${FDROID_IMAGE:-registry.gitlab.com/fdroid/fdroidserver:buildserver-trixie}"
FLUTTER_VERSION=3.47.1
REF="${1:-HEAD}"

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BUILD="$HOME/fdroid-ref-build"     # persistent working dir (flutter clone reused)
CHECKOUT="$BUILD/com.enclavd.app"  # checkout, at the pipe's layout
SRCLIB_DIR="$BUILD/srclib"         # flutter srclib

mkdir -p "$SRCLIB_DIR"

echo "==> checking out $REF (clean)"
rm -rf "$CHECKOUT" && mkdir -p "$CHECKOUT"
git -C "$ROOT" archive "$REF" | tar -x -C "$CHECKOUT"

if [ ! -x "$SRCLIB_DIR/flutter/bin/flutter" ]; then
    echo "==> cloning flutter $FLUTTER_VERSION (one-time)"
    git clone --depth 1 --branch "$FLUTTER_VERSION" \
        https://github.com/flutter/flutter.git "$SRCLIB_DIR/flutter"
fi
chmod -R a+rwX "$CHECKOUT" "$SRCLIB_DIR"

SIGN_ENVS=()
if [ -n "${SIGNING_KEY:-}" ] || [ -n "${SIGNING_KEY_FILE:-}" ]; then
    if [ -n "${SIGNING_KEY:-}" ]; then
        echo "==> decoding SIGNING_KEY into the checkout (release keystore)"
        echo "$SIGNING_KEY" | base64 --decode > "$CHECKOUT/android/app/release-keystore.jks"
    else
        echo "==> copying SIGNING_KEY_FILE into the checkout (release keystore)"
        cp "$SIGNING_KEY_FILE" "$CHECKOUT/android/app/release-keystore.jks"
    fi
    SIGN_ENVS=(-e IS_GITHUB_ACTION=true -e SIGNING_KEY_FILE=release-keystore.jks \
               -e KEY_STORE_PASSWORD -e ALIAS -e KEY_PASSWORD)
else
    echo "!! WARNING: no SIGNING_KEY/SIGNING_KEY_FILE set — APK will be debug-keyed."
    echo "   The pipe rejects that at the AllowedAPKSigningKeys check (3de54b...)."
    echo "   Set the signing envs above for a full pass; this run isolates the"
    echo "   content gate only."
fi

echo "==> building in $IMAGE (first run downloads the Dart SDK + NDK — slow)"
docker run --rm --user root \
    -v "$BUILD":/home/vagrant/build \
    -v fdroid-android-sdk:/opt/android-sdk \
    -v fdroid-gradle-home:/root/.gradle \
    -w /home/vagrant/build/com.enclavd.app \
    "${SIGN_ENVS[@]}" \
    "$IMAGE" bash -euxo pipefail -c '
        mkdir -p /home/runner/work/enclavd-android-source
        bash tool/fdroid_build.sh /home/vagrant/build/srclib/flutter
    '

echo "==> copying result"
cp "$CHECKOUT/build/app/outputs/flutter-apk/app-fdroid-release.apk" \
   ./app-fdroid-release-reference.apk
echo "done: $(pwd)/app-fdroid-release-reference.apk"
