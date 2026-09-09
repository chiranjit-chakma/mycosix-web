/// Pure helpers for a signed-in user's fcmTokens/{uid}.tokens list - the same
/// array the notification backend (functions/notify_core.js) delivers to and
/// prunes. The browser may only ever touch its OWN token document (Firestore
/// rules), and each signed-in device registers exactly one token: an FCM token
/// is per browser/app install, never shared between devices. These helpers
/// encode the array-union / array-remove semantics so multi-device and log-out
/// behaviour are unit-tested once and reused by the registration keeper.
library;

/// Whether [token] is already present.
bool hasToken(List<String> tokens, String token) => tokens.contains(token);

/// Adds [token] exactly once (array-union semantics): a repeat registration
/// from the same device is a no-op, never a duplicate entry.
List<String> upsertToken(List<String> tokens, String token) {
  if (hasToken(tokens, token)) return List.of(tokens);
  return [...tokens, token];
}

/// Removes [token] (array-remove semantics) so a device that signs out stops
/// only its own pushes and never touches another device's token.
List<String> withoutToken(List<String> tokens, String token) =>
    tokens.where((t) => t != token).toList();
