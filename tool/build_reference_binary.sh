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
# Usage:
#   tool/build_reference_binary.sh              # build current HEAD
#   tool/build_reference_binary.sh <commit-sha> # build the exact commit the
#                                               # pipe's YML pins
# Output: app-fdroid-release-reference.apk in the current directory.
set -euo pipefail

IMAGE="${FDROID_IMAGE:-registry.gitlab.com/fdroid/fdroidserver:buildserver}"
FLUTTER_VERSION=3.47.1
REF="${1:-HEAD}"

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BUILD="$HOME/fdroid-ref-build"    # persistent working dir (flutter clone reused)
REPO_DIR="$BUILD/repo"            # checkout mounted at the pipe's layout
SRCLIB_DIR="$BUILD/srclib"        # flutter srclib

mkdir -p "$REPO_DIR" "$SRCLIB_DIR"

echo "==> checking out $REF"
git -C "$ROOT" archive "$REF" | tar -x -C "$REPO_DIR"

if [ ! -x "$SRCLIB_DIR/flutter/bin/flutter" ]; then
    echo "==> cloning flutter $FLUTTER_VERSION (one-time)"
    git clone --depth 1 --branch "$FLUTTER_VERSION" \
        https://github.com/flutter/flutter.git "$SRCLIB_DIR/flutter"
fi
chmod -R a+rwX "$REPO_DIR" "$SRCLIB_DIR"

echo "==> building in $IMAGE (first run downloads the Dart SDK + NDK — slow)"
docker run --rm --user root \
    -v "$REPO_DIR":/home/vagrant/build/com.enclavd.app \
    -v "$SRCLIB_DIR":/home/vagrant/build/srclib \
    -v fdroid-android-sdk:/opt/android-sdk \
    -v fdroid-gradle-home:/root/.gradle \
    -w /home/vagrant/build/com.enclavd.app \
    "$IMAGE" bash -euxo pipefail -c '
        mkdir -p /home/runner/work/enclavd-android-source
        bash tool/fdroid_build.sh /home/vagrant/build/srclib/flutter
    '

echo "==> copying result"
cp "$REPO_DIR/build/app/outputs/flutter-apk/app-fdroid-release.apk" \
   ./app-fdroid-release-reference.apk
echo "done: $(pwd)/app-fdroid-release-reference.apk"
