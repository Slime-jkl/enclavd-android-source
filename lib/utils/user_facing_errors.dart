import 'dart:async';
import 'dart:io';

import '../api/api_client.dart';

/// The friendly line for backend failures the user cannot act on.
const String kInternalError =
    'Internal error. If this issue persists, please report it.';

/// Maps any error thrown by a service call to a short, user-facing
/// message: server 4xx -> the server's own message (it is specific);
/// 5xx or unknown status -> [kInternalError]; network/timeout -> a
/// connection message; anything else -> [fallback], the caller's
/// operation-specific line.
String userFacingError(Object error, {required String fallback}) {
  if (error is ApiException) {
    final status = error.status;
    if (status == null || status >= 500) return kInternalError;
    return error.message;
  }
  if (error is SocketException ||
      error is HttpException ||
      error is TimeoutException) {
    return 'Network error. Please check your connection and try again.';
  }
  return fallback;
}
