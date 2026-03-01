import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_app/services/ble_discovery_service.dart';

void main() {
  group('BLE UID encoding/decoding', () {
    test('roundtrip for standard UUID', () {
      const uid = '550e8400-e29b-41d4-a716-446655440000';
      final encoded = BleDiscoveryService.encodeUid(uid);
      expect(encoded.length, 16);
      final decoded = BleDiscoveryService.decodeUid(encoded);
      expect(decoded, uid);
    });

    test('roundtrip for random UUID v4', () {
      const uid = 'f47ac10b-58cc-4372-a567-0e02b2c3d479';
      final encoded = BleDiscoveryService.encodeUid(uid);
      expect(encoded.length, 16);
      final decoded = BleDiscoveryService.decodeUid(encoded);
      expect(decoded, uid);
    });

    test('roundtrip preserves all bytes', () {
      const uid = '00000000-0000-0000-0000-000000000000';
      final encoded = BleDiscoveryService.encodeUid(uid);
      expect(encoded, Uint8List(16)); // all zeros
      final decoded = BleDiscoveryService.decodeUid(encoded);
      expect(decoded, uid);
    });

    test('roundtrip for max UUID', () {
      const uid = 'ffffffff-ffff-ffff-ffff-ffffffffffff';
      final encoded = BleDiscoveryService.encodeUid(uid);
      expect(encoded.length, 16);
      expect(encoded.every((b) => b == 0xFF), true);
      final decoded = BleDiscoveryService.decodeUid(encoded);
      expect(decoded, uid);
    });

    test('different UIDs produce different bytes', () {
      const uid1 = '550e8400-e29b-41d4-a716-446655440000';
      const uid2 = 'f47ac10b-58cc-4372-a567-0e02b2c3d479';
      final encoded1 = BleDiscoveryService.encodeUid(uid1);
      final encoded2 = BleDiscoveryService.encodeUid(uid2);
      expect(encoded1, isNot(equals(encoded2)));
    });

    test('encode produces exactly 16 bytes for valid UUID', () {
      const uid = 'a1b2c3d4-e5f6-7890-abcd-ef1234567890';
      final encoded = BleDiscoveryService.encodeUid(uid);
      expect(encoded.length, 16);
    });

    test('fallback for non-UUID string', () {
      const uid = 'not-a-uuid';
      final encoded = BleDiscoveryService.encodeUid(uid);
      // Should use raw UTF-8 fallback
      expect(encoded.length, uid.length);
      final decoded = BleDiscoveryService.decodeUid(encoded);
      expect(decoded, uid);
    });

    test('simulates full BLE advertisement flow', () {
      // This simulates what happens in the BLE advertisement:
      // 1. Advertiser encodes UID into manufacturer data
      // 2. Scanner extracts and decodes UID from manufacturer data
      const myUid = 'f47ac10b-58cc-4372-a567-0e02b2c3d479';
      const magicByte = 0x4B;

      // --- Advertiser side ---
      final uidBytes = BleDiscoveryService.encodeUid(myUid);
      final payloadData = Uint8List(uidBytes.length + 1);
      payloadData[0] = magicByte;
      payloadData.setRange(1, payloadData.length, uidBytes);

      // --- Scanner side ---
      // The scanner receives payloadData as the manufacturer data value
      expect(payloadData[0], magicByte);
      final extractedUidBytes = payloadData.sublist(1);
      final extractedUid = BleDiscoveryService.decodeUid(extractedUidBytes);
      expect(extractedUid, myUid);
    });
  });
}
