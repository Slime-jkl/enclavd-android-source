#!/usr/bin/env python3
"""Guard the committed F-Droid plugin registrant against silent drift.

The fdroid flavor hand-maintains
android/app/src/fdroid/java/io/flutter/plugins/GeneratedPluginRegistrant.java
(firebase cannot be registered there, so the auto-generated file is unusable).
The dart side calls a native plugin that is not registered fail with
MissingPluginException - swallowed inside the plugin wrapper, so a release-only
flavor just silently loses the feature (the quote widget showed its empty state
forever this way).

This compares the registrant against the android plugins Flutter resolved, from
.flutter-plugins-dependencies (run `flutter pub get` first). Only the
native_build entries need registering; Dart-only plugins do not.

Usage: check_fdroid_registrant.py   (repo root, after flutter pub get)
"""
import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
REGISTRANT = (
    ROOT
    / "android/app/src/fdroid/java/io/flutter/plugins/GeneratedPluginRegistrant.java"
)
DEPS = [ROOT / ".flutter-plugins-dependencies", ROOT / ".dart_tool/.flutter-plugins-dependencies"]

# Excluded from this flavor by build.gradle.kts (classes are not on its classpath).
FIREBASE = {"firebase_core", "firebase_messaging"}

deps_path = next((p for p in DEPS if p.exists()), None)
if deps_path is None:
    sys.exit("no .flutter-plugins-dependencies; run `flutter pub get` first")

plugins = json.loads(deps_path.read_text())["plugins"]["android"]
expected = {
    p["name"] for p in plugins if p.get("native_build") and p["name"] not in FIREBASE
}
source = REGISTRANT.read_text()
registered = set(re.findall(r"registering plugin (\w+)", source))

missing = sorted(expected - registered)
if missing:
    print(f"FAIL: fdroid registrant is missing {len(missing)} plugin(s): {', '.join(missing)}")
    print(f"add them to {REGISTRANT.relative_to(ROOT)} (same block shape as the others)")
    sys.exit(1)
print(f"fdroid registrant covers all {len(expected)} android plugins: OK")
