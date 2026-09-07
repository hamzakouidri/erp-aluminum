const authServerUnavailableMessage =
    'The sign-in server is temporarily unavailable. Please try again later.';
const authTimeoutMessage =
    'The sign-in server did not respond in time. Please try again.';
const authUnreachableMessage =
    'Unable to reach the sign-in server. Check your connection or try again later.';

String? authConnectionErrorMessage(String code, String message) {
  final value = '$code $message'.toLowerCase();
  final status = int.tryParse(code.trim());
  // A server response takes precedence over transport keywords such as timeout.
  if ((status != null && status >= 500 && status <= 599) ||
      value.contains('gateway timeout') ||
      value.contains('bad gateway') ||
      value.contains('service unavailable')) {
    return authServerUnavailableMessage;
  }
  if (value.contains('timed out') || value.contains('timeout')) {
    return authTimeoutMessage;
  }
  if (value.contains('network') ||
      value.contains('socketexception') ||
      value.contains('failed host lookup') ||
      value.contains('connection refused') ||
      value.contains('connection reset') ||
      value.contains('connection closed') ||
      value.contains('fetch failed') ||
      value.contains('failed to fetch') ||
      value.contains('xmlhttprequest error') ||
      value.contains('offline') ||
      value.contains('clientexception') ||
      value.contains('handshakeexception')) {
    return authUnreachableMessage;
  }
  return null;
}
