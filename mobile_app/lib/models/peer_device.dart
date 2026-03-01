class PeerDevice {
  final String endpointId;
  final String name;

  /// Set when UID payload is received over Bluetooth.
  String? uid;

  PeerDevice({required this.endpointId, required this.name});
}
