#!/usr/bin/env python3
"""Strip Firebase plugin modules from the fdroid flavor build.

The Flutter plugin loader includes EVERY pubspec plugin as a gradle project
(reading .flutter-plugins-dependencies), and included projects get configured
even when no variant depends on them. So the fdroid flavor's java-level
excludes, the dropped registrant, and AppConfig.enableFcm=false keep the APK
GMS-free, but :firebase_core / :firebase_messaging still configure at build
time — which fails the F-Droid pipe (firebase_core NPE under the pipe's
toolchain) and is wrong on principle: zero Google code in the fdroid build.

Run AFTER `flutter pub get` and BEFORE `flutter build apk` for the fdroid
flavor only (the play/dev builds must keep firebase). Mutates
.flutter-plugins-dependencies in place. `flutter build` will not regenerate it
as long as .dart_tool/package_config.json is fresh (pub get just ran).
"""

import json
import sys

PATH = ".flutter-plugins-dependencies"
FIREBASE = ("firebase_core", "firebase_messaging")


def main() -> int:
    try:
        with open(PATH, encoding="utf-8") as f:
            data = json.load(f)
    except FileNotFoundError:
        print(f"error: {PATH} not found — run 'flutter pub get' first")
        return 1

    stripped = 0
    for platform in ("android", "ios"):
        plugins = data.get(platform, {}).get("plugins", {})
        for name in FIREBASE:
            if plugins.pop(name, None) is not None:
                stripped += 1

    with open(PATH, "w", encoding="utf-8") as f:
        json.dump(data, f, indent=2)
        f.write("\n")

    print(f"stripped {stripped} firebase plugin module(s) from {PATH}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
