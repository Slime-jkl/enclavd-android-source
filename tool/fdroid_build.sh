#!/usr/bin/env bash
# F-Droid pipe build for the fdroid flavor (called from the metadata build:
#   bash tool/fdroid_build.sh $$flutter$$
# $$flutter$$ is substituted by fdroidserver with the srclib flutter path.
# Everything the pipe needs that must NOT live in the metadata (rewritemeta
# wraps long lines and reformats on every run) lives here instead. Run from
# the repo root; prebuild must have run `flutter pub get` first.
set -euo pipefail
set -x

FLUTTER="${1:?usage: fdroid_build.sh <flutter-dir-or-binary>}"
if [ -d "$FLUTTER" ]; then
    FLUTTER="$FLUTTER/bin/flutter"
fi

# Pipe toolchain: Flutter's gradle plugin does not support AGP 9's new DSL
# (flutter/flutter#180137 still open) and the pipe env ignores the
# android.newDsl opt-out — pin the last AGP 8.x + Gradle 8.x, pipe-only.
sed -i 's/version "9\.1\.0"/version "8.13.0"/' android/settings.gradle.kts
sed -i 's|gradle-9\.3\.1-all\.zip|gradle-8\.14\.3-all\.zip|' android/gradle/wrapper/gradle-wrapper.properties

# Zero Google code in the fdroid build: drop the firebase plugin MODULES (the
# flavor's java-level excludes only kill dependencies; the plugin projects
# still get configured and NPE under the pipe toolchain).
python3 tool/strip_firebase.py

# --no-pub is critical: flutter build would re-run pub get and regenerate
# .flutter-plugins-dependencies, undoing the strip above. pub get already ran
# in prebuild (--enforce-lockfile); reuse its PUB_CACHE location.
export PUB_CACHE="$(pwd)/.pub-cache"

"$FLUTTER" build apk --release --no-pub --flavor fdroid \
    --dart-define=ENCLAVD_FLAVOR=fdroid \
    --dart-define=ENCLAVD_FEATURE_NOTIFICATIONS=true \
    --dart-define=ENCLAVD_FEATURE_CHAT=true \
    --dart-define=ENCLAVD_FEATURE_SEARCH=true
