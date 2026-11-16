import 'package:supabase_flutter/supabase_flutter.dart';

/// Keep service URLs and internal exception details out of sign-in alerts.
String signInErrorMessage(Object error) {
  if (error is AuthRetryableFetchException) {
    return 'Unable to connect. Please check your internet connection and try again later.';
  }
  if (error is AuthException) {
    switch (error.code) {
      case 'invalid_credentials':
        return 'Invalid email or password. Please try again.';
      case 'email_not_confirmed':
        return 'Please verify your email address before signing in.';
      case 'over_request_rate_limit':
        return 'Too many sign-in attempts. Please wait a moment and try again.';
    }
  }
  return 'Unable to sign in right now. Please try again later.';
}
