import 'package:database_data/services/auth_connection_error.dart';
import 'package:database_data/settings/app_settings.dart';
import 'package:database_data/settings/localization.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('gateway timeout is a server failure, not an offline device', () {
    expect(
      authConnectionErrorMessage('504', 'Gateway Timeout'),
      authServerUnavailableMessage,
    );
    expect(
      authConnectionErrorMessage('', 'Gateway Timeout'),
      authServerUnavailableMessage,
    );
    expect(
      authConnectionErrorMessage('503', 'network timeout'),
      authServerUnavailableMessage,
    );
  });

  test('transport timeout and unreachable server have distinct messages', () {
    expect(
      authConnectionErrorMessage('', 'TimeoutException after 10 seconds'),
      authTimeoutMessage,
    );
    expect(
      authConnectionErrorMessage('', 'SocketException: Failed host lookup'),
      authUnreachableMessage,
    );
    expect(
      authConnectionErrorMessage('network-request-failed', ''),
      authUnreachableMessage,
    );
  });

  test('credential and rate limit errors retain their own handling', () {
    expect(
      authConnectionErrorMessage('400', 'Invalid login credentials'),
      isNull,
    );
    expect(authConnectionErrorMessage('429', 'Too many requests'), isNull);
  });

  test('connection messages have French and Arabic translations', () {
    for (final message in [
      authServerUnavailableMessage,
      authTimeoutMessage,
      authUnreachableMessage,
    ]) {
      expect(
        Localization.translate(message, AppLanguage.french),
        isNot(message),
      );
      expect(
        Localization.translate(message, AppLanguage.arabic),
        isNot(message),
      );
    }
  });
}
