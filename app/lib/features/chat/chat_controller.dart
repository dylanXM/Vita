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

  /// Reason of the last failed send attempt: set when nothing could be queued
  /// or when a queued message failed to deliver. Cleared on a new attempt, so
  /// the chat page can report why a send did not work.
  final sendError = RxnString();
  final companionStatus = ''.obs;
  final companionBusy = false.obs;
  String? _conversationId;
  Timer? _pollTimer;
  bool _polling = false;

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
      await _syncConversation();
      if (_conversationId != null) {
        await _loadMessages();
        _pollTimer ??=
            Timer.periodic(const Duration(seconds: 15), (_) => poll());
      }
    } on ApiException catch (e) {
      if (e.action == 'open_subscription') {
        accessError.value = e.code ?? 'subscription_required';
      }
      // The chat stays usable: send() resolves the conversation again on
      // demand and reports its own failures.
    } finally {
      loading.value = false;
    }
  }

  /// `POST /v1/conversations` (get or create) and picks up the conversation
  /// level state carried by the response.
  Future<void> _syncConversation() async {
    final conv = await ApiClient.instance.post(
      '/v1/conversations',
      data: {'companion_id': companionId},
    );
    final rawId = conv is Map ? conv['conversation_id'] : null;
    _conversationId = rawId is String && rawId.isNotEmpty ? rawId : null;
    final status = conv is Map ? conv['companion_status'] : null;
    if (status is Map) {
      companionStatus.value = status['title'] as String? ?? '';
      companionBusy.value = status['busy'] == true;
    }
    if (conv is Map && conv['can_send'] == false) {
      accessError.value =
          conv['access_code'] as String? ?? 'subscription_required';
    }
  }

  /// Resolves the conversation, creating it on first use.
  ///
  /// Sending goes through here instead of waiting for a successful [load], so
  /// a failed load never leaves the user unable to send.
  Future<String> ensureConversation() async {
    final existing = _conversationId;
    if (existing != null) return existing;
    await _syncConversation();
    final id = _conversationId;
    if (id == null) {
      throw ApiException('conversation unavailable',
          code: 'conversation_unavailable');
    }
    return id;
  }

  Future<void> _loadMessages() async {
    final data = await ApiClient.instance
        .get('/v1/conversations/$_conversationId/messages');
    if (data is List) {
      messages.assignAll(
        data
            .whereType<Map<String, dynamic>>()
            .map((e) => Map<String, dynamic>.from(e)),
      );
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

  /// Sends [text], resolving the conversation on first use.
  ///
  /// Returns `true` when the message was queued — a queued message that fails
  /// to deliver shows up as a failed bubble in the list. Returns `false` when
  /// nothing could be queued, so the caller keeps the draft, and records the
  /// reason in [sendError].
  Future<bool> send(String text) async {
    final content = text.trim();
    if (content.isEmpty) return false;
    if (sending.value) return false;
    sendError.value = null;
    final String conversationId;
    try {
      conversationId = await ensureConversation();
    } on ApiException catch (e) {
      sendError.value = e.message;
      return false;
    }
    final optimisticId = 'local-${DateTime.now().microsecondsSinceEpoch}';
    messages.add({
      'id': optimisticId,
      'conversation_id': conversationId,
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
        '/v1/conversations/$conversationId/messages',
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
          'conversation_id': conversationId,
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
        // The failed bubble is already visible in the list; hand the reason to
        // the page so it can report it too.
        sendError.value = e.message;
      }
    } finally {
      sending.value = false;
    }
    return true;
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

  /// Sends a recorded voice message. Same contract as [send].
  Future<bool> sendVoice(String filePath) async {
    if (sending.value) return false;
    sendError.value = null;
    final String conversationId;
    try {
      conversationId = await ensureConversation();
    } on ApiException catch (e) {
      sendError.value = e.message;
      return false;
    }
    sending.value = true;
    String? optimisticId;
    try {
      final uploaded = await ApiClient.instance
          .upload('/v1/media/upload', filePath, kind: 'audio');
      if (uploaded is! Map || uploaded['id'] is! String) return false;
      final mediaID = uploaded['id'] as String;
      final mediaURL = uploaded['url'] as String? ?? '/v1/media/$mediaID';
      optimisticId = 'local-${DateTime.now().microsecondsSinceEpoch}';
      messages.add({
        'id': optimisticId,
        'conversation_id': conversationId,
        'content': '',
        'sender_type': 'user',
        'message_type': 'voice',
        'media_url': mediaURL,
        'source': 'user',
        'payload': <String, dynamic>{},
        'delivery_status': 'sending',
        'created_at': DateTime.now().toUtc().toIso8601String(),
      });
      final data = await ApiClient.instance.post(
        '/v1/conversations/$conversationId/messages',
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
        sendError.value = e.message;
      }
    } finally {
      sending.value = false;
    }
    return true;
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
