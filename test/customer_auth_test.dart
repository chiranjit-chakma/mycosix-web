import 'package:flutter_test/flutter_test.dart';
import 'package:mycosix/state/customer_auth_controller.dart';

void main() {
  group('resolveCustomerAuthStatus', () {
    test('an offline backend always wins, regardless of other inputs', () {
      expect(
        resolveCustomerAuthStatus(
          backendAvailable: false,
          resolving: true,
          signedIn: true,
        ),
        CustomerAuthStatus.backendOffline,
      );
    });

    test('resolving comes next', () {
      expect(
        resolveCustomerAuthStatus(
          backendAvailable: true,
          resolving: true,
          signedIn: true,
        ),
        CustomerAuthStatus.resolving,
      );
    });

    test('signed out when the provider reports no user', () {
      expect(
        resolveCustomerAuthStatus(
          backendAvailable: true,
          resolving: false,
          signedIn: false,
        ),
        CustomerAuthStatus.signedOut,
      );
    });

    test('signed in only with a real provider session', () {
      expect(
        resolveCustomerAuthStatus(
          backendAvailable: true,
          resolving: false,
          signedIn: true,
        ),
        CustomerAuthStatus.signedIn,
      );
    });
  });
}
