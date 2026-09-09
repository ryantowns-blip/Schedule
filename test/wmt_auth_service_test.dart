import 'package:flutter_test/flutter_test.dart';
import 'package:atc_schedule_manager/services/wmt_auth_service.dart';

void main() {
  test('WMT login follows email then password sequence', () {
    final auth = WmtAuthService();

    expect(auth.state.step, WmtAuthStep.signedOut);
    expect(auth.beginLogin().step, WmtAuthStep.email);

    final passwordState = auth.submitEmail('controller@faa.gov');
    expect(passwordState.step, WmtAuthStep.password);
    expect(passwordState.email, 'controller@faa.gov');

    expect(auth.authenticationSucceeded().step, WmtAuthStep.authenticated);
  });

  test('invalid email remains on email step', () {
    final auth = WmtAuthService()..beginLogin();
    final state = auth.submitEmail('');

    expect(state.step, WmtAuthStep.email);
    expect(state.message, isNotNull);
  });
}
