import 'dart:async';

import 'package:get/get.dart';

import '../../core/api_client.dart';
import '../../core/analytics_service.dart';

/// State for a single chat session: get-or-create the conversation, load the
/// messages and send new ones.
class ChatController extends GetxController {
  final String companionId;
  final String companionName;

  ChatController({required this.companionId, required this.companionName});

  final loading = false.obs;
  final sending = false.obs;
  final messages = <Map<String, dynamic>>[].obs;
  final accessError = RxnString();
  final companionStatus = ''.obs;
  final companionBusy = false.obs;
  String? _conversationId;
  Timer? _pollTimer;
  bool _polling = false;

  bool get ready => _conversationId != null;

  @override
  void onInit() {
    super.onInit();
    AnalyticsService.to.track('chat_opened',
        category: 'chat', properties: {'companion_id': companionId});
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
      accessError.value = null;
      final conv = await ApiClient.instance.post(
        '/v1/conversations',
        data: {'companion_id': companionId},
      );
      _conversationId = conv['conversation_id'] as String?;
      final status = conv['companion_status'];
      if (status is Map) {
        companionStatus.value = status['title'] as String? ?? '';
        companionBusy.value = status['busy'] == true;
      }
      if (conv['can_send'] == false) {
        accessError.value =
            conv['access_code'] as String? ?? 'subscription_required';
      }
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
    } on ApiException catch (e) {
      if (e.action == 'open_subscription') {
        accessError.value = e.code ?? 'subscription_required';
      }
      // chat stays usable; send() reports failures
    } finally {
      loading.value = false;
    }
  }

  Future<void> poll() async {
    if (_polling || _conversationId == null) return;
    _polling = true;
    try {
      String? latest;
      for (final message in messages.reversed) {
        final id = message['id'];
        final createdAt = message['created_at'];
        if (id is String && !id.startsWith('local-') && createdAt is String) {
          latest = createdAt;
          break;
        }
      }
      final data = await ApiClient.instance.get(
        '/v1/conversations/$_conversationId/messages',
        query: latest == null ? null : {'after': latest},
      );
      if (data is List) {
        for (final raw in data.whereType<Map>()) {
          final message = Map<String, dynamic>.from(raw);
          if (message['source'] == 'paid_gift') {
            message['_animate_gift'] = true;
          }
          _addIfNew(message);
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
    final optimisticId = 'local-${DateTime.now().microsecondsSinceEpoch}';
    messages.add({
      'id': optimisticId,
      'conversation_id': _conversationId,
      'content': content,
      'sender_type': 'user',
      'message_type': 'text',
      'source': 'user',
      'payload': <String, dynamic>{},
      'delivery_status': 'sending',
      'created_at': DateTime.now().toUtc().toIso8601String(),
    });
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
          _replaceOptimistic(
              optimisticId, Map<String, dynamic>.from(userMessage));
        } else {
          _replaceOptimistic(optimisticId, {
            'id': data['id'],
            'content': content,
            'sender_type': 'user',
            'message_type': 'text',
            'source': 'user',
            'payload': <String, dynamic>{},
            'delivery_status': 'delivered',
            'created_at': data['created_at'],
          });
        }
        if (companionMessage is Map) {
          _addIfNew(Map<String, dynamic>.from(companionMessage));
        }
        AnalyticsService.to
            .track('message_sent', category: 'chat', properties: {
          'companion_id': companionId,
          'conversation_id': _conversationId ?? '',
          'message_type': 'text',
          'character_count': content.length,
        });
      } else {
        _markFailed(optimisticId);
      }
    } on ApiException catch (e) {
      _markFailed(optimisticId);
      AnalyticsService.to
          .track('message_send_failed', category: 'chat', properties: {
        'companion_id': companionId,
        'reason': e.code ?? e.message,
      });
      if (e.action == 'open_subscription') {
        accessError.value = e.code ?? 'subscription_required';
      } else {
        rethrow;
      }
    } finally {
      sending.value = false;
    }
  }

  Future<void> experienceCompleted(Map<String, dynamic> response) async {
    final rawResult = response['result'];
    final result = rawResult is Map
        ? Map<String, dynamic>.from(rawResult)
        : const <String, dynamic>{};
    final rawMessage = result['message'];
    if (rawMessage is Map) {
      final message = Map<String, dynamic>.from(rawMessage);
      if (message['source'] == 'paid_gift') {
        message['_animate_gift'] = true;
      }
      _addIfNew(message);
      return;
    }
    await poll();
  }

  Future<void> sendVoice(String filePath) async {
    if (_conversationId == null || sending.value) return;
    sending.value = true;
    String? optimisticId;
    try {
      final uploaded = await ApiClient.instance
          .upload('/v1/media/upload', filePath, kind: 'audio');
      if (uploaded is! Map || uploaded['id'] is! String) return;
      final mediaID = uploaded['id'] as String;
      optimisticId = 'local-${DateTime.now().microsecondsSinceEpoch}';
      messages.add({
        'id': optimisticId,
        'conversation_id': _conversationId,
        'content': '',
        'sender_type': 'user',
        'message_type': 'voice',
        'media_url': '/v1/media/$mediaID',
        'source': 'user',
        'payload': <String, dynamic>{},
        'delivery_status': 'sending',
        'created_at': DateTime.now().toUtc().toIso8601String(),
      });
      final data = await ApiClient.instance.post(
        '/v1/conversations/$_conversationId/messages',
        data: {'message_type': 'voice', 'media_id': mediaID},
      );
      if (data is Map) {
        final userMessage = data['user_message'];
        final companionMessage = data['companion_message'];
        if (userMessage is Map) {
          _replaceOptimistic(
              optimisticId, Map<String, dynamic>.from(userMessage));
        } else {
          _markFailed(optimisticId);
        }
        if (companionMessage is Map) {
          _addIfNew(Map<String, dynamic>.from(companionMessage));
        }
      }
    } on ApiException catch (e) {
      if (optimisticId != null) _markFailed(optimisticId);
      if (e.action == 'open_subscription') {
        accessError.value = e.code ?? 'subscription_required';
      } else {
        rethrow;
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

  void _replaceOptimistic(String optimisticId, Map<String, dynamic> message) {
    final index = messages.indexWhere((item) => item['id'] == optimisticId);
    if (index < 0) {
      _addIfNew(message);
      return;
    }
    messages[index] = message;
  }

  void _markFailed(String optimisticId) {
    final index = messages.indexWhere((item) => item['id'] == optimisticId);
    if (index < 0) return;
    messages[index] = {
      ...messages[index],
      'delivery_status': 'failed',
    };
  }
}
