import 'package:cemetery_app/utils/sign_in_error_message.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  const internalMessage =
      'ClientException: Failed to fetch, uri=https://example.supabase.co/auth/v1/token?grant_type=password';

  test('offline sign-in gives connection guidance without service details', () {
    final message = signInErrorMessage(
      AuthRetryableFetchException(message: internalMessage),
    );
    expect(message, contains('check your internet connection'));
    expect(message, isNot(contains('supabase')));
    expect(message, isNot(contains('https://')));
    expect(message, isNot(contains('ClientException')));
  });

  test('unknown auth and transport errors do not expose raw messages', () {
    for (final error in [
      const AuthException(internalMessage),
      Exception(internalMessage),
    ]) {
      expect(
        signInErrorMessage(error),
        'Unable to sign in right now. Please try again later.',
      );
    }
  });

  test('invalid credentials remain actionable without raw server text', () {
    expect(
      signInErrorMessage(
        const AuthException(internalMessage, code: 'invalid_credentials'),
      ),
      'Invalid email or password. Please try again.',
    );
  });
}
