import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/auth/auth_manager.dart';

void main() {
  test('QR confirmation must be reset before phone authentication', () {
    const state = 'authorizationStateWaitOtherDeviceConfirmation';

    expect(authorizationStateRequiresQrReset(state), isTrue);
    expect(authorizationStateAcceptsPhoneNumber(state), isFalse);
  });

  test('phone authentication is accepted only in supported auth states', () {
    expect(
      authorizationStateAcceptsPhoneNumber('authorizationStateWaitPhoneNumber'),
      isTrue,
    );
    expect(
      authorizationStateAcceptsPhoneNumber('authorizationStateWaitCode'),
      isTrue,
    );
    expect(
      authorizationStateAcceptsPhoneNumber('authorizationStateReady'),
      isFalse,
    );
    expect(
      authorizationStateAcceptsPhoneNumber('authorizationStateClosed'),
      isFalse,
    );
  });
}
