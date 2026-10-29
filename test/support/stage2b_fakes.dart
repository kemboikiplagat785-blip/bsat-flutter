import 'package:bsat/services/forwarding_transport_selection.dart';

/// In-memory preferences keyed by backend device ID, standing in for a
/// persistence mechanism that has not been approved yet.
class MapForwardingTransportPreferences
    implements ForwardingTransportPreferences {
  final Map<String, Object?> byDeviceId;
  final List<ForwardingDestination> lookups = [];

  MapForwardingTransportPreferences([Map<String, Object?>? values])
      : byDeviceId = {...?values};

  @override
  Future<Object?> storedPreferenceFor(ForwardingDestination destination) async {
    lookups.add(destination);
    return byDeviceId[destination.deviceId];
  }
}

/// A preference store that cannot be read.
class FailingForwardingTransportPreferences
    implements ForwardingTransportPreferences {
  @override
  Future<Object?> storedPreferenceFor(ForwardingDestination destination) =>
      Future.error(StateError('preference store unavailable'));
}
