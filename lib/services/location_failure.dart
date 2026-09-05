/// A location request failed for a known reason.
enum LocationFailure {
  permissionDenied,
  timeout,
  unavailable,
  unsupported,
  mapFailed,
  unknown;

  String get userMessage => switch (this) {
        LocationFailure.permissionDenied =>
          'Location permission was denied. Please allow access, or type or pick a location on the map.',
        LocationFailure.timeout =>
          'We could not get your location in time. Please try again, or pick the location on the map.',
        LocationFailure.unavailable =>
          'Your location is currently unavailable. Please try again, or pick the location on the map.',
        LocationFailure.unsupported =>
          'This browser does not support location. Please pick the location on the map.',
        LocationFailure.mapFailed =>
          'The map could not load. Please check your connection and try again.',
        LocationFailure.unknown =>
          'Something went wrong while getting your location. Please try again.',
      };
}
