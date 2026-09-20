enum ChatMediaKind { none, voice, image }

class ChatMessageContent {
  const ChatMessageContent({
    required this.type,
    required this.text,
    required this.mediaUrl,
    required this.source,
    required this.payload,
  });

  factory ChatMessageContent.from(Map<dynamic, dynamic> message) {
    String stringValue(String key, [String fallback = '']) {
      final value = message[key];
      return value is String ? value : fallback;
    }

    final rawPayload = message['payload'];
    return ChatMessageContent(
      type: stringValue('message_type', 'text'),
      text: stringValue('content'),
      mediaUrl: stringValue('media_url'),
      source: stringValue('source'),
      payload: rawPayload is Map
          ? Map<String, dynamic>.from(rawPayload)
          : const <String, dynamic>{},
    );
  }

  final String type;
  final String text;
  final String mediaUrl;
  final String source;
  final Map<String, dynamic> payload;

  ChatMediaKind get mediaKind {
    if (mediaUrl.isEmpty) return ChatMediaKind.none;
    if (type == 'voice') return ChatMediaKind.voice;
    return ChatMediaKind.image;
  }

  bool get contentIsTranslationKey => source.startsWith('paid_');
}
