class NotificationStateModel {
  final String id;
  final String notificationId;
  final String userId;
  final bool isRead;
  final bool isHidden;
  final DateTime updatedAt;

  NotificationStateModel({
    required this.id,
    required this.notificationId,
    required this.userId,
    required this.isRead,
    required this.isHidden,
    required this.updatedAt,
  });

  factory NotificationStateModel.fromJson(Map<String, dynamic> json, String id) {
    return NotificationStateModel(
      id: id,
      notificationId: json['notificationId'] ?? '',
      userId: json['userId'] ?? '',
      isRead: json['isRead'] ?? false,
      isHidden: json['isHidden'] ?? false,
      updatedAt:
          json['updatedAt'] != null ? (json['updatedAt'] as dynamic).toDate() : DateTime.now(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'notificationId': notificationId,
      'userId': userId,
      'isRead': isRead,
      'isHidden': isHidden,
      'updatedAt': updatedAt,
    };
  }

  NotificationStateModel copyWith({
    String? id,
    String? notificationId,
    String? userId,
    bool? isRead,
    bool? isHidden,
    DateTime? updatedAt,
  }) {
    return NotificationStateModel(
      id: id ?? this.id,
      notificationId: notificationId ?? this.notificationId,
      userId: userId ?? this.userId,
      isRead: isRead ?? this.isRead,
      isHidden: isHidden ?? this.isHidden,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}
