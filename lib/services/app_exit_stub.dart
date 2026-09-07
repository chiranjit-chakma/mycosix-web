/// VM / test-runner arm of the app-exit facade.
///
/// There is no window on the VM, so the app can never close itself here. Tests
/// assert the back-press *behaviour* (scroll, warn, exit decision) without a
/// real exit.
bool get isSupported => false;

void maybeClose() {}
