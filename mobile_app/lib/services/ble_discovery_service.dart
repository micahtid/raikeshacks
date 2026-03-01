import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_ble_peripheral/flutter_ble_peripheral.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// BLE-based peer discovery that works in the background.
///
/// Phone B advertises its UID encoded in BLE manufacturer data.
/// Phone A scans, reads the UID from the advertisement, and calls the backend
/// to create a connection (which triggers FCM to Phone B).
///
/// No BLE connection or handshake is needed — the UID is in the broadcast.
class BleDiscoveryService extends ChangeNotifier {
  /// Custom company ID used to filter our advertisements.
  /// 0xFFFF is reserved for testing/development per Bluetooth SIG.
  static const int _companyId = 0xFFFF;

  /// Prefix byte to identify knkt advertisements.
  static const int _magicByte = 0x4B; // 'K' for knkt

  final _peripheral = FlutterBlePeripheral();
  String? _myUid;
  bool _isAdvertising = false;
  bool _isScanning = false;
  StreamSubscription<List<ScanResult>>? _scanSub;

  /// UIDs discovered via BLE scanning.
  final Set<String> discoveredUids = {};

  /// Called when a new peer UID is discovered via BLE.
  void Function(String peerUid)? onPeerDiscovered;

  bool get isAdvertising => _isAdvertising;
  bool get isScanning => _isScanning;

  /// Initialize — load UID from SharedPreferences.
  Future<void> initialize() async {
    final prefs = await SharedPreferences.getInstance();
    _myUid = prefs.getString('student_uid');
    debugPrint('[knkt-ble] initialized with uid: $_myUid');
  }

  /// Start BLE advertising with our UID embedded in manufacturer data.
  Future<void> startAdvertising() async {
    if (_myUid == null || _myUid!.isEmpty) {
      debugPrint('[knkt-ble] cannot advertise: no UID');
      return;
    }

    if (_isAdvertising) return;

    // Always try to stop first — the native advertiser may still be active
    // from a previous session even when our flag says otherwise.
    try {
      await _peripheral.stop();
    } catch (_) {}

    try {
      // Encode UID as bytes: [magic_byte] + [uid_bytes]
      final uidBytes = encodeUid(_myUid!);
      final payloadData = Uint8List(uidBytes.length + 1);
      payloadData[0] = _magicByte;
      payloadData.setRange(1, payloadData.length, uidBytes);

      final advertiseData = AdvertiseData(
        manufacturerId: _companyId,
        manufacturerData: payloadData,
        includeDeviceName: false,
      );

      await _peripheral.start(
        advertiseData: advertiseData,
        advertiseSettings: AdvertiseSettings(
          advertiseMode: AdvertiseMode.advertiseModeLowLatency,
          connectable: false,
          timeout: 0, // no timeout — advertise indefinitely
          advertiseSet: false, // use legacy API for wider device support
        ),
      );

      _isAdvertising = true;
      notifyListeners();
      debugPrint('[knkt-ble] advertising started with UID: $_myUid');
    } catch (e) {
      final msg = e.toString();
      // "ALREADY_ADVERTISING" means the native side is already broadcasting
      // — treat as success rather than failure.
      if (msg.contains('ALREADY_ADVERTISING')) {
        _isAdvertising = true;
        notifyListeners();
        debugPrint('[knkt-ble] already advertising (treating as success)');
      } else {
        debugPrint('[knkt-ble] advertising failed: $e');
      }
    }
  }

  /// Start BLE scanning for nearby peers.
  Future<void> startScanning() async {
    if (_isScanning) return;

    try {
      // On Android, ensure Bluetooth adapter is on
      if (Platform.isAndroid) {
        await FlutterBluePlus.turnOn();
      }

      _isScanning = true;
      notifyListeners();

      // Start scanning with no filter — we'll filter manufacturer data ourselves
      await FlutterBluePlus.startScan(
        timeout: const Duration(seconds: 0), // scan indefinitely
        continuousUpdates: true,
        androidUsesFineLocation: true,
      );

      _scanSub = FlutterBluePlus.scanResults.listen((results) {
        for (final result in results) {
          _processScanResult(result);
        }
      });

      debugPrint('[knkt-ble] scanning started');
    } catch (e) {
      _isScanning = false;
      notifyListeners();
      debugPrint('[knkt-ble] scanning failed: $e');
    }
  }

  /// Process a single scan result — extract UID from manufacturer data.
  void _processScanResult(ScanResult result) {
    final mfgData = result.advertisementData.manufacturerData;
    if (mfgData.isEmpty) return;

    // Check each manufacturer data entry for our company ID
    for (final entry in mfgData.entries) {
      final companyId = entry.key;
      final data = entry.value;

      if (companyId != _companyId) continue;
      if (data.isEmpty || data[0] != _magicByte) continue;

      // Extract UID bytes (skip magic byte)
      final uidBytes = data.sublist(1);
      final peerUid = decodeUid(uidBytes);

      if (peerUid == null || peerUid.isEmpty) continue;
      if (peerUid == _myUid) continue; // ignore our own advertisement

      if (!discoveredUids.contains(peerUid)) {
        discoveredUids.add(peerUid);
        debugPrint('[knkt-ble] discovered peer: $peerUid (rssi: ${result.rssi})');
        onPeerDiscovered?.call(peerUid);
        notifyListeners();
      }
    }
  }

  /// Start both advertising and scanning.
  Future<void> startBoth() async {
    await startAdvertising();
    await startScanning();
  }

  /// Stop advertising.
  Future<void> stopAdvertising() async {
    // Always try the native stop — the native advertiser may be active even
    // when our flag is false (e.g. after crash or hot-reload).
    try {
      await _peripheral.stop();
    } catch (e) {
      debugPrint('[knkt-ble] stop advertising failed: $e');
    }
    _isAdvertising = false;
    notifyListeners();
  }

  /// Stop scanning.
  Future<void> stopScanning() async {
    if (!_isScanning) return;
    await _scanSub?.cancel();
    _scanSub = null;
    try {
      await FlutterBluePlus.stopScan();
    } catch (e) {
      debugPrint('[knkt-ble] stop scan failed: $e');
    }
    _isScanning = false;
    notifyListeners();
  }

  /// Stop everything.
  Future<void> stopAll() async {
    await stopAdvertising();
    await stopScanning();
    discoveredUids.clear();
    notifyListeners();
  }

  @override
  void dispose() {
    stopAll();
    super.dispose();
  }

  // ── UID encoding/decoding ──────────────────────────────────────────────

  /// Encode a UUID string into compact 16-byte binary form.
  /// Input: "550e8400-e29b-41d4-a716-446655440000" (36 chars)
  /// Output: 16 bytes
  @visibleForTesting
  static Uint8List encodeUid(String uid) {
    // Remove hyphens from UUID and parse as hex
    final hex = uid.replaceAll('-', '');
    if (hex.length != 32) {
      // Fallback: encode as raw UTF-8 bytes (truncated to 20 bytes max)
      final bytes = Uint8List.fromList(uid.codeUnits);
      return bytes.length > 20 ? bytes.sublist(0, 20) : bytes;
    }
    final bytes = Uint8List(16);
    for (int i = 0; i < 16; i++) {
      bytes[i] = int.parse(hex.substring(i * 2, i * 2 + 2), radix: 16);
    }
    return bytes;
  }

  /// Decode 16-byte binary back into a UUID string with hyphens.
  /// Output: "550e8400-e29b-41d4-a716-446655440000"
  @visibleForTesting
  static String? decodeUid(List<int> bytes) {
    if (bytes.length == 16) {
      final hex = bytes
          .map((b) => b.toRadixString(16).padLeft(2, '0'))
          .join();
      // Insert hyphens at standard UUID positions: 8-4-4-4-12
      return '${hex.substring(0, 8)}-'
          '${hex.substring(8, 12)}-'
          '${hex.substring(12, 16)}-'
          '${hex.substring(16, 20)}-'
          '${hex.substring(20)}';
    }
    // Fallback: decode as raw UTF-8
    if (bytes.isNotEmpty && bytes.length <= 36) {
      return String.fromCharCodes(bytes);
    }
    return null;
  }
}
