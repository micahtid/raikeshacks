import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_app/models/connection_model.dart';

void main() {
  final sampleJson = {
    'connection_id': 'abc123_def456',
    'uid1': 'abc123',
    'uid2': 'def456',
    'uid1_accepted': false,
    'uid2_accepted': false,
    'match_percentage': 85.5,
    'uid1_summary': 'Alice is a Flutter developer who can help with mobile.',
    'uid2_summary': 'Bob brings backend expertise in Python and DevOps.',
    'notification_message': 'You matched with Alice! 85% compatible.',
    'created_at': '2025-01-15T10:30:00Z',
    'updated_at': null,
  };

  group('ConnectionModel.fromJson', () {
    test('parses all fields correctly', () {
      final conn = ConnectionModel.fromJson(sampleJson);
      expect(conn.connectionId, 'abc123_def456');
      expect(conn.uid1, 'abc123');
      expect(conn.uid2, 'def456');
      expect(conn.uid1Accepted, false);
      expect(conn.uid2Accepted, false);
      expect(conn.matchPercentage, 85.5);
      expect(conn.uid1Summary, isNotNull);
      expect(conn.uid2Summary, isNotNull);
      expect(conn.notificationMessage, isNotNull);
      expect(conn.createdAt, '2025-01-15T10:30:00Z');
      expect(conn.updatedAt, isNull);
    });

    test('handles missing optional fields', () {
      final minimal = {
        'connection_id': 'a_b',
        'uid1': 'a',
        'uid2': 'b',
        'match_percentage': 70,
        'created_at': '2025-01-01T00:00:00Z',
      };
      final conn = ConnectionModel.fromJson(minimal);
      expect(conn.uid1Accepted, false);
      expect(conn.uid2Accepted, false);
      expect(conn.uid1Summary, isNull);
      expect(conn.uid2Summary, isNull);
    });
  });

  group('Helper methods', () {
    late ConnectionModel conn;

    setUp(() {
      conn = ConnectionModel.fromJson(sampleJson);
    });

    test('otherUid returns the peer UID', () {
      expect(conn.otherUid('abc123'), 'def456');
      expect(conn.otherUid('def456'), 'abc123');
    });

    test('summaryFor returns the correct summary for viewer', () {
      // uid1 viewing: should see uid2's summary (about uid2, written for uid1)
      expect(conn.summaryFor('abc123'), conn.uid2Summary);
      // uid2 viewing: should see uid1's summary (about uid1, written for uid2)
      expect(conn.summaryFor('def456'), conn.uid1Summary);
      // unknown uid
      expect(conn.summaryFor('unknown'), isNull);
    });

    test('hasAccepted checks the correct flag', () {
      expect(conn.hasAccepted('abc123'), false); // uid1_accepted = false
      expect(conn.hasAccepted('def456'), false); // uid2_accepted = false

      final accepted = ConnectionModel.fromJson({
        ...sampleJson,
        'uid1_accepted': true,
        'uid2_accepted': false,
      });
      expect(accepted.hasAccepted('abc123'), true);
      expect(accepted.hasAccepted('def456'), false);
    });

    test('isComplete is true only when both accepted', () {
      expect(conn.isComplete, false);

      final complete = ConnectionModel.fromJson({
        ...sampleJson,
        'uid1_accepted': true,
        'uid2_accepted': true,
      });
      expect(complete.isComplete, true);
    });

    test('isAboveThreshold checks >= 60%', () {
      expect(conn.isAboveThreshold, true); // 85.5%

      final low = ConnectionModel.fromJson({
        ...sampleJson,
        'match_percentage': 45.0,
      });
      expect(low.isAboveThreshold, false);

      final boundary = ConnectionModel.fromJson({
        ...sampleJson,
        'match_percentage': 60.0,
      });
      expect(boundary.isAboveThreshold, true);
    });
  });
}
