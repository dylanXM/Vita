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

  @override
  void onInit() {
    super.onInit();
    load();
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
        final data = await ApiClient.instance.get('/v1/conversations/$_conversationId/messages');
        if (data is List) {
          messages.assignAll(
            data.whereType<Map<String, dynamic>>().map((e) => Map<String, dynamic>.from(e)),
          );
        }
      }
    } catch (_) {
      // chat stays usable; send() reports failures
    } finally {
      loading.value = false;
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
      messages.add({
        'id': data['id'],
        'content': content,
        'sender_type': 'user',
        'created_at': data['created_at'],
      });
    } finally {
      sending.value = false;
    }
  }
}
