class ConnectionModel {
  final String connectionId;
  final String uid1;
  final String uid2;
  final bool uid1Accepted;
  final bool uid2Accepted;
  final double matchPercentage;
  final String? uid1Summary;
  final String? uid2Summary;
  final String? notificationMessage;
  final String createdAt;
  final String? updatedAt;

  ConnectionModel({
    required this.connectionId,
    required this.uid1,
    required this.uid2,
    required this.uid1Accepted,
    required this.uid2Accepted,
    required this.matchPercentage,
    this.uid1Summary,
    this.uid2Summary,
    this.notificationMessage,
    required this.createdAt,
    this.updatedAt,
  });

  factory ConnectionModel.fromJson(Map<String, dynamic> json) {
    return ConnectionModel(
      connectionId: json['connection_id'] as String,
      uid1: json['uid1'] as String,
      uid2: json['uid2'] as String,
      uid1Accepted: json['uid1_accepted'] as bool? ?? false,
      uid2Accepted: json['uid2_accepted'] as bool? ?? false,
      matchPercentage: (json['match_percentage'] as num).toDouble(),
      uid1Summary: json['uid1_summary'] as String?,
      uid2Summary: json['uid2_summary'] as String?,
      notificationMessage: json['notification_message'] as String?,
      createdAt: json['created_at'] as String,
      updatedAt: json['updated_at'] as String?,
    );
  }

  /// Returns the summary the viewer should see (written about the OTHER user).
  String? summaryFor(String viewerUid) {
    if (viewerUid == uid1) return uid2Summary;
    if (viewerUid == uid2) return uid1Summary;
    return null;
  }

  /// Returns the UID of the other user.
  String otherUid(String myUid) {
    return myUid == uid1 ? uid2 : uid1;
  }

  /// Whether this specific user has accepted.
  bool hasAccepted(String myUid) {
    if (myUid == uid1) return uid1Accepted;
    if (myUid == uid2) return uid2Accepted;
    return false;
  }

  /// Both users have accepted.
  bool get isComplete => uid1Accepted && uid2Accepted;

  /// Match is above the display threshold.
  bool get isAboveThreshold => matchPercentage >= 60;
}
