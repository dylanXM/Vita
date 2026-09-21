import 'package:flutter_test/flutter_test.dart';
import 'package:vita/features/chat/chat_message_content.dart';

void main() {
  test('preserves emoji text and recognizes voice media', () {
    final content = ChatMessageContent.from({
      'message_type': 'voice',
      'content': '晚安 🌙😊',
      'media_url': '/v1/media/audio-id',
      'source': 'reply',
    });

    expect(content.text, '晚安 🌙😊');
    expect(content.mediaKind, ChatMediaKind.voice);
    expect(content.contentIsTranslationKey, isFalse);
  });

  test('recognizes generated images and paid translation keys', () {
    final content = ChatMessageContent.from({
      'message_type': 'image_text',
      'content': 'experience.photo.desc',
      'media_url': 'https://cdn.example/photo.jpg',
      'source': 'paid_photo',
      'payload': {'requested': true},
    });

    expect(content.mediaKind, ChatMediaKind.image);
    expect(content.contentIsTranslationKey, isTrue);
    expect(content.payload['requested'], isTrue);
  });

  test('malformed optional media fields safely fall back to text defaults', () {
    final content = ChatMessageContent.from({
      'message_type': 3,
      'content': ['not', 'text'],
      'media_url': null,
      'payload': 'invalid',
    });

    expect(content.type, 'text');
    expect(content.text, isEmpty);
    expect(content.mediaKind, ChatMediaKind.none);
    expect(content.payload, isEmpty);
  });

  test('recognizes current and legacy gift timeline messages', () {
    final current = ChatMessageContent.from({
      'message_type': 'gift',
      'content': '💐',
      'source': 'paid_gift',
      'payload': {'product_key': 'gift_flowers', 'coins': 30},
    });
    final legacy = ChatMessageContent.from({
      'message_type': 'scene_card',
      'content': '☕',
      'source': 'paid_gift',
    });

    expect(current.isGift, isTrue);
    expect(current.payload['coins'], 30);
    expect(legacy.isGift, isTrue);
  });
}
