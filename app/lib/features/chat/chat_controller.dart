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
  final replyStatus = 'none'.obs;
  String? replyPendingMessageId;
  int replyPendingAgeSeconds = 0;
  final trialStatus = 'none'.obs;
  final trialExpiresAt = RxnString();
  String? _conversationId;
  Timer? _pollTimer;
  Timer? _trialTimer;
  DateTime? _replyStartedAt;
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
    _trialTimer?.cancel();
    super.onClose();
  }

  Future<void> load() async {
    loading.value = true;
    try {
      accessError.value = null;
      await _syncConversation();
      if (_conversationId != null) {
        await _loadMessages();
        try {
          await _loadReplyStatus();
        } catch (_) {
          // Message loading and polling must survive a status fetch failure.
        }
        _pollTimer ??=
            Timer.periodic(const Duration(seconds: 5), (_) => poll());
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
      '/v1/conversations/',
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
    if (conv is Map) {
      trialStatus.value = '${conv['trial_status'] ?? 'none'}';
      trialExpiresAt.value = conv['trial_expires_at'] as String?;
      _scheduleTrialRefresh();
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
      if (replyStatus.value != 'none') await _loadReplyStatus();
    } catch (_) {
      // Polling is best effort; the next interval catches up.
    } finally {
      _polling = false;
    }
  }

  Future<void> _loadReplyStatus() async {
    if (_conversationId == null) return;
    final data = await ApiClient.instance
        .get('/v1/conversations/$_conversationId/reply-status');
    if (data is Map && data['status'] is String) {
      replyPendingMessageId = data['trigger_message_id'] as String?;
      replyPendingAgeSeconds = (data['age_seconds'] as num?)?.toInt() ?? 0;
      replyStatus.value = data['status'] as String;
      if (_latestUserHasReply) replyStatus.value = 'none';
    }
  }

  Future<bool> refreshReplyStatus() async {
    try {
      await _loadReplyStatus();
      return true;
    } catch (_) {
      return false;
    }
  }

  bool get _latestUserHasReply {
    DateTime? latestUser;
    DateTime? latestReply;
    for (final message in messages) {
      final at = DateTime.tryParse('${message['created_at'] ?? ''}');
      if (at == null) continue;
      if (message['sender_type'] == 'user' &&
          message['delivery_status'] != 'failed') {
        if (latestUser == null || at.isAfter(latestUser)) latestUser = at;
      } else if (message['sender_type'] == 'assistant' &&
          message['source'] == 'reply') {
        if (latestReply == null || at.isAfter(latestReply)) latestReply = at;
      }
    }
    return latestUser != null &&
        latestReply != null &&
        !latestReply.isBefore(latestUser);
  }

  void _beginReplyWait() {
    _replyStartedAt = DateTime.now();
    replyPendingMessageId = null;
    replyPendingAgeSeconds = 0;
    replyStatus.value = 'none';
  }

  void _applyReplyResponse(Map data) {
    final userMessage = data['user_message'];
    replyPendingMessageId = userMessage is Map
        ? userMessage['id'] as String?
        : data['id'] as String?;
    replyPendingAgeSeconds =
        DateTime.now().difference(_replyStartedAt ?? DateTime.now()).inSeconds;
    if (data['companion_message'] is Map) {
      replyStatus.value = 'none';
    } else {
      replyStatus.value = data['reply_status'] == 'pending'
          ? 'pending'
          : data['reply_status'] == 'none'
              ? 'none'
              : 'failed';
      if (replyStatus.value == 'pending') {
        if (_latestUserHasReply) replyStatus.value = 'none';
      }
    }
  }

  /// Sends [text], resolving the conversation on first use.
  ///
  /// Returns `true` when the message was queued — a queued message that fails
  /// to deliver shows up as a failed bubble in the list. Returns `false` when
  /// nothing could be queued, so the caller keeps the draft, and records the
  /// reason in [sendError].
  Future<bool> send(String text,
      {String? momentEventId, String? journeyVisitId}) async {
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
      'life_event_id': momentEventId ?? '',
      'payload': <String, dynamic>{
        if (journeyVisitId != null) 'journey_visit_id': journeyVisitId,
      },
      'delivery_status': 'sending',
      'created_at': DateTime.now().toUtc().toIso8601String(),
    });
    sending.value = true;
    _beginReplyWait();
    try {
      final data = await ApiClient.instance.post(
        '/v1/conversations/$conversationId/messages',
        data: {
          'content': content,
          'message_type': 'text',
          if (momentEventId != null) 'life_event_id': momentEventId,
          if (journeyVisitId != null) 'journey_visit_id': journeyVisitId,
        },
      );
      if (data is Map) {
        _applyReplyResponse(data);
        _updateTrialFromMessage(data);
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
            'life_event_id': momentEventId ?? '',
            'payload': <String, dynamic>{
              if (journeyVisitId != null) 'journey_visit_id': journeyVisitId,
            },
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
        replyStatus.value = 'none';
        _markFailed(optimisticId);
      }
    } on ApiException catch (e) {
      replyStatus.value = 'none';
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
      final rawReaction = result['reaction_message'];
      if (rawReaction is Map) {
        _addIfNew(Map<String, dynamic>.from(rawReaction));
      }
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
      _beginReplyWait();
      final data = await ApiClient.instance.post(
        '/v1/conversations/$conversationId/messages',
        data: {'message_type': 'voice', 'media_id': mediaID},
      );
      if (data is Map) {
        _applyReplyResponse(data);
        _updateTrialFromMessage(data);
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
      } else if (optimisticId != null) {
        replyStatus.value = 'none';
        _markFailed(optimisticId);
      }
    } on ApiException catch (e) {
      replyStatus.value = 'none';
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

  void _updateTrialFromMessage(Map data) {
    final expiry = data['trial_expires_at'];
    if (expiry is String && expiry.isNotEmpty) {
      trialExpiresAt.value = expiry;
      trialStatus.value = 'active';
      _scheduleTrialRefresh();
    }
  }

  void _scheduleTrialRefresh() {
    _trialTimer?.cancel();
    if (trialStatus.value != 'active') return;
    final expiry = DateTime.tryParse(trialExpiresAt.value ?? '');
    if (expiry == null) return;
    final remaining = expiry.difference(DateTime.now());
    if (remaining.isNegative) return;
    _trialTimer = Timer(remaining + const Duration(seconds: 1), () {
      load();
    });
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
