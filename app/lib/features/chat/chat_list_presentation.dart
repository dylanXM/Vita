class ChatListPresentation {
  const ChatListPresentation({
    required this.message,
    required this.messageType,
    required this.messageAt,
    required this.unreadCount,
  });

  factory ChatListPresentation.from(Map<dynamic, dynamic> companion) {
    final rawTime = companion['last_message_at'];
    return ChatListPresentation(
      message: companion['last_message'] is String
          ? companion['last_message'] as String
          : '',
      messageType: companion['last_message_type'] is String
          ? companion['last_message_type'] as String
          : 'text',
      messageAt:
          rawTime is String ? DateTime.tryParse(rawTime)?.toLocal() : null,
      unreadCount: companion['unread_count'] is num
          ? (companion['unread_count'] as num).toInt()
          : 0,
    );
  }

  final String message;
  final String messageType;
  final DateTime? messageAt;
  final int unreadCount;

  String preview({
    required String fallback,
    required String voiceLabel,
    required String photoLabel,
  }) {
    if (messageType == 'voice') return '[$voiceLabel]';
    if (messageType == 'image' || messageType == 'image_text') {
      return message.isEmpty ? '[$photoLabel]' : '[$photoLabel] $message';
    }
    return message.isEmpty ? fallback : message;
  }

  String timeLabel(DateTime now, String yesterdayLabel) {
    final value = messageAt;
    if (value == null) return '';
    final today = DateTime(now.year, now.month, now.day);
    final day = DateTime(value.year, value.month, value.day);
    final difference = today.difference(day).inDays;
    if (difference == 0) {
      return '${value.hour.toString().padLeft(2, '0')}:${value.minute.toString().padLeft(2, '0')}';
    }
    if (difference == 1) return yesterdayLabel;
    if (value.year == now.year) return '${value.month}/${value.day}';
    return '${value.year}/${value.month}/${value.day}';
  }
}
