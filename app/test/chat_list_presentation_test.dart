import 'package:flutter_test/flutter_test.dart';
import 'package:vita/features/chat/chat_list_presentation.dart';

void main() {
  test('uses media labels while preserving image message content', () {
    final voice = ChatListPresentation.from({
      'last_message': 'transcript',
      'last_message_type': 'voice',
      'unread_count': 3,
    });
    final photo = ChatListPresentation.from({
      'last_message': 'At the cafe ☕',
      'last_message_type': 'image_text',
    });

    expect(
      voice.preview(
          fallback: 'fallback', voiceLabel: 'Voice', photoLabel: 'Photo'),
      '[Voice]',
    );
    expect(voice.unreadCount, 3);
    expect(
      photo.preview(
          fallback: 'fallback', voiceLabel: 'Voice', photoLabel: 'Photo'),
      '[Photo] At the cafe ☕',
    );
  });

  test('formats conversation timestamps using chat-list conventions', () {
    final now = DateTime(2026, 9, 20, 18, 0);
    ChatListPresentation item(DateTime value) => ChatListPresentation(
          message: '',
          messageType: 'text',
          messageAt: value,
          unreadCount: 0,
        );

    expect(
        item(DateTime(2026, 9, 20, 9, 5)).timeLabel(now, 'Yesterday'), '09:05');
    expect(item(DateTime(2026, 9, 19, 23, 0)).timeLabel(now, 'Yesterday'),
        'Yesterday');
    expect(item(DateTime(2026, 8, 3)).timeLabel(now, 'Yesterday'), '8/3');
    expect(item(DateTime(2025, 8, 3)).timeLabel(now, 'Yesterday'), '2025/8/3');
  });
}
