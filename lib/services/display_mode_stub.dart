/// VM / test-runner arm of the display-mode facade.
///
/// There is no window here, so the app is never "an installed PWA". Widget
/// tests therefore exercise the browser (non-standalone) behaviour, which is
/// the honest default for a fresh test environment.
bool isStandaloneDisplay() => false;
bool isStandaloneMobile() => false;
