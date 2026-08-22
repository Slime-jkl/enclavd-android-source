#!/usr/bin/env python3
"""Strip Firebase plugin modules from the fdroid flavor build.

The Flutter plugin loader includes EVERY pubspec plugin as a gradle project
(reading .flutter-plugins-dependencies), and included projects get configured
even when no variant depends on them. So the fdroid flavor's java-level
excludes, the dropped registrant, and AppConfig.enableFcm=false keep the APK
GMS-free, but :firebase_core / :firebase_messaging still configure at build
time — which fails the F-Droid pipe (firebase_core NPE under the pipe's
toolchain) and is wrong on principle: zero Google code in the fdroid build.

File structure (verified against flutter_tools 3.47.1, flutter_plugins.dart):
the JSON has a TOP-LEVEL "plugins" key whose values ("android", "ios", ...)
are LISTS of plugin objects, each carrying a "name" field. Anything else
(plugins dicts keyed by name) is the wrong shape and strips nothing.

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
    except json.JSONDecodeError as exc:
        print(f"error: {PATH} is not valid JSON: {exc}")
        return 1

    plugins = data.get("plugins")
    if not isinstance(plugins, dict):
        print(f"error: no top-level 'plugins' object in {PATH}")
        return 1

    stripped = 0
    for platform in ("android", "ios"):
        entries = plugins.get(platform)
        if not isinstance(entries, list):
            continue
        kept = [p for p in entries if p.get("name") not in FIREBASE]
        stripped += len(entries) - len(kept)
        plugins[platform] = kept

    with open(PATH, "w", encoding="utf-8") as f:
        json.dump(data, f, indent=2)
        f.write("\n")

    print(f"stripped {stripped} firebase plugin module(s) from {PATH}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
