/// Non-web stand-in for the link opener, so pages that reference [UrlLauncher]
/// compile and run under the VM test runner.
///
/// Navigation is genuinely impossible off the web; every call is a safe no-op.
void open(String url) {}

void navigate(String url) {}
