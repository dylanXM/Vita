import 'dart:async';

import 'package:get/get.dart';

import '../../core/api_client.dart';

/// State for a single chat session: get-or-create the conversation, load the
/// messages and send new ones.
class ChatController extends GetxController {
  final String companionId;
  final String companionName;

  ChatController({required this.companionId, required this.companionName});

  final loading = false.obs;
  final sending = false.obs;
  final messages = <Map<String, dynamic>>[].obs;
  String? _conversationId;
  Timer? _pollTimer;
  bool _polling = false;

  @override
  void onInit() {
    super.onInit();
    load();
  }

  @override
  void onClose() {
    _pollTimer?.cancel();
    super.onClose();
  }

  Future<void> load() async {
    loading.value = true;
    try {
      final conv = await ApiClient.instance.post(
        '/v1/conversations',
        data: {'companion_id': companionId},
      );
      _conversationId = conv['conversation_id'] as String?;
      if (_conversationId != null) {
        final data = await ApiClient.instance
            .get('/v1/conversations/$_conversationId/messages');
        if (data is List) {
          messages.assignAll(
            data
                .whereType<Map<String, dynamic>>()
                .map((e) => Map<String, dynamic>.from(e)),
          );
        }
        _pollTimer ??=
            Timer.periodic(const Duration(seconds: 15), (_) => poll());
      }
    } catch (_) {
      // chat stays usable; send() reports failures
    } finally {
      loading.value = false;
    }
  }

  Future<void> poll() async {
    if (_polling || _conversationId == null) return;
    _polling = true;
    try {
      final latest =
          messages.isEmpty ? null : messages.last['created_at'] as String?;
      final data = await ApiClient.instance.get(
        '/v1/conversations/$_conversationId/messages',
        query: latest == null ? null : {'after': latest},
      );
      if (data is List) {
        for (final raw in data.whereType<Map>()) {
          _addIfNew(Map<String, dynamic>.from(raw));
        }
      }
    } catch (_) {
      // Polling is best effort; the next interval catches up.
    } finally {
      _polling = false;
    }
  }

  Future<void> send(String text) async {
    final content = text.trim();
    if (content.isEmpty || _conversationId == null) return;
    sending.value = true;
    try {
      final data = await ApiClient.instance.post(
        '/v1/conversations/$_conversationId/messages',
        data: {'content': content, 'message_type': 'text'},
      );
      if (data is Map) {
        final userMessage = data['user_message'];
        final companionMessage = data['companion_message'];
        if (userMessage is Map) {
          _addIfNew(Map<String, dynamic>.from(userMessage));
        } else {
          _addIfNew({
            'id': data['id'],
            'content': content,
            'sender_type': 'user',
            'message_type': 'text',
            'created_at': data['created_at'],
          });
        }
        if (companionMessage is Map) {
          _addIfNew(Map<String, dynamic>.from(companionMessage));
        }
      }
    } finally {
      sending.value = false;
    }
  }

  void _addIfNew(Map<String, dynamic> message) {
    final id = message['id'];
    if (id != null && messages.any((item) => item['id'] == id)) return;
    messages.add(message);
  }
}
