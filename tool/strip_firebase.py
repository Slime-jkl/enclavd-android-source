#!/usr/bin/env python3
"""Prepare the F-Droid build: remove every trace of Firebase BEFORE pub get.

The F-Droid maintainer's required order is strip -> pub get --enforce-lockfile
-> build: the fdroid build must not RESOLVE or compile any Google code, so
the pubspec itself is stripped of firebase_core/firebase_messaging and the
committed firebase-free lockfile (pubspec-fdroid.lock) is moved into place
before pub get runs.

What this script does (run in the repo root, BEFORE `flutter pub get`, on
BOTH the CI fdroid job and the pipe's metadata prebuild):

  1. pubspec.yaml - drop the firebase dependency block (the comment and the
     two firebase_* lines).
  2. transport_selector - rewire lib/services/push/transport_selector.dart
     to export the firebase-free stub (fcm_transport_stub.dart) instead of
     the real FCM transport, so no file in the fdroid compile graph imports
     a firebase package.

pubspec-fdroid.lock is generated once (strip -> `flutter pub get` -> copy)
and committed; the prebuild moves it into place before pub get. Regenerate
it whenever pubspec dependencies change. Play/dev builds never run this:
they keep the full pubspec, the FCM selector, and the regular pubspec.lock.
"""

import re
import sys

PUBSPEC = "pubspec.yaml"
SELECTOR = "lib/services/push/transport_selector.dart"
FDROID_SELECTOR = """// F-Droid flavor - rewired by tool/strip_firebase.py before pub get.
// (The play/dev default export lives in git.)
export 'fcm_transport_stub.dart';
"""


def strip_pubspec() -> int:
    lines = open(PUBSPEC, encoding="utf-8").read().splitlines(keepends=True)
    out = []
    in_firebase_block = False
    removed = 0
    for ln in lines:
        if "Push transports: firebase_core" in ln:
            in_firebase_block = True
        if in_firebase_block:
            # The block runs from the comment to the last firebase_* dep;
            # the unifiedpush line ends it.
            if re.match(r"^\s*unifiedpush:", ln):
                in_firebase_block = False
            else:
                removed += 1
                continue
        if re.match(r"^\s*firebase_(core|messaging):", ln):
            removed += 1
            continue
        out.append(ln)
    open(PUBSPEC, "w", encoding="utf-8").writelines(out)
    return removed


def main() -> int:
    removed = strip_pubspec()
    open(SELECTOR, "w", encoding="utf-8").write(FDROID_SELECTOR)
    print(
        f"stripped {removed} firebase line(s) from {PUBSPEC}; "
        f"{SELECTOR} -> fcm_transport_stub"
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
