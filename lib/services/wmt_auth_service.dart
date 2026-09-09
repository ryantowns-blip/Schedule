enum WmtAuthStep {
  signedOut,
  email,
  password,
  authenticated,
}

class WmtAuthState {
  const WmtAuthState({
    required this.step,
    this.email,
    this.message,
  });

  final WmtAuthStep step;
  final String? email;
  final String? message;
}

/// Models the FAA MyAccess sequence used by WMT Scheduler.
///
/// Actual browser/session integration will be attached to these transitions;
/// credentials are intentionally not stored by this service.
class WmtAuthService {
  WmtAuthState _state = const WmtAuthState(step: WmtAuthStep.signedOut);

  WmtAuthState get state => _state;

  WmtAuthState beginLogin() {
    return _state = const WmtAuthState(step: WmtAuthStep.email);
  }

  WmtAuthState submitEmail(String email) {
    final normalized = email.trim();
    if (normalized.isEmpty || !normalized.contains('@')) {
      return _state = const WmtAuthState(
        step: WmtAuthStep.email,
        message: 'Enter your FAA email address.',
      );
    }

    return _state = WmtAuthState(
      step: WmtAuthStep.password,
      email: normalized,
    );
  }

  WmtAuthState passwordPageReached() {
    return _state = WmtAuthState(
      step: WmtAuthStep.password,
      email: _state.email,
    );
  }

  WmtAuthState authenticationSucceeded() {
    return _state = WmtAuthState(
      step: WmtAuthStep.authenticated,
      email: _state.email,
    );
  }

  WmtAuthState signOut() {
    return _state = const WmtAuthState(step: WmtAuthStep.signedOut);
  }
}
