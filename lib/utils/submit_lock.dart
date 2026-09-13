import 'dart:async';

import 'package:flutter/foundation.dart';

/// One write at a time, then a short cooldown before the next one is
/// accepted. A submit spent on a slow request, or on one that failed while
/// the server already stored the row, leaves the send control armed with
/// the text still in the box - which is how a spam tap becomes a second
/// copy. The site's comments.js holds the same rule (the button is
/// re-disabled for 5s after a comment lands).
class SubmitLock {
  SubmitLock({this.cooldown = const Duration(seconds: 5)});

  final Duration cooldown;

  Timer? _timer;
  bool _busy = false;
  bool _cooling = false;

  /// A submit is in flight.
  bool get busy => _busy;

  /// Submits are refused (one in flight, or still cooling down).
  bool get locked => _busy || _cooling;

  /// Claims the write. False = this submit is dropped.
  bool begin() {
    if (locked) return false;
    _busy = true;
    return true;
  }

  /// Ends the attempt and starts the cooldown. [onFree] fires when submits
  /// are accepted again - rebuild there.
  void end(VoidCallback onFree) {
    _busy = false;
    _cooling = true;
    _timer?.cancel();
    _timer = Timer(cooldown, () {
      _cooling = false;
      onFree();
    });
  }

  void dispose() {
    _timer?.cancel();
    _timer = null;
  }
}
