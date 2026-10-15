import 'dart:async';

import 'package:get/get.dart';
import 'package:flutter/widgets.dart';

import '../../core/api_client.dart';
import '../auth/auth_controller.dart';
import 'chat_list_presentation.dart';

/// Loads the user's companions for the Chat tab.
///
/// Refreshes on three triggers:
///  * pull-to-refresh from the UI,
///  * app foreground resume (lifecycle),
///  * a quiet 10s incremental timer while signed in and foregrounded, so Life Engine proactive
///    messages show up without the user having to enter and exit a chat.
class ChatListController extends GetxController with WidgetsBindingObserver {
  static ChatListController get to => Get.find();

  final loading = false.obs;
  final failed = false.obs;
  final companions = <Map<String, dynamic>>[].obs;
  final appointments = <Map<String, dynamic>>[].obs;
  final searchQuery = ''.obs;
  final currentRoute = ''.obs;

  int get totalUnreadCount => companions.fold<int>(0, (total, companion) {
    if (companion['creation_source'] == 'ai_pet') return total;
    final count = ChatListPresentation.from(companion).unreadCount;
    return total + (count > 0 ? count : 0);
  });

  final _readThrough = <String, DateTime>{};

  /// Keep stale list responses from resurrecting messages already displayed.
  Map<String, dynamic> _withReadState(Map<String, dynamic> item) {
    final read = _readThrough['${item['id']}'];
    final latest = DateTime.tryParse('${item['last_message_at'] ?? ''}');
    return read != null && latest != null && !latest.isAfter(read)
        ? {...item, 'unread_count': 0}
        : item;
  }

  void markMessagesRead(String companionId, Iterable<Map<String, dynamic>> messages) {
    var latest = _readThrough[companionId];
    for (final message in messages) {
      if (message['sender_type'] != 'assistant') continue;
      final at = DateTime.tryParse('${message['created_at'] ?? ''}');
      if (at != null && (latest == null || at.isAfter(latest))) latest = at;
    }
    if (latest == null) return;
    _readThrough[companionId] = latest;
    companions.assignAll(companions.map(_withReadState).toList());
  }

  Timer? _poll;
  bool _silent = false;
  bool _foreground = true;
  bool _polling = false;
  String? _cursor;
  Worker? _authWorker;
  int _requestId = 0;

  bool get _signedIn => Get.isRegistered<AuthController>() &&
      AuthController.to.profile.value != null;

  void _startPolling() {
    _poll?.cancel();
    if (!_foreground || !_signedIn) return;
    _poll = Timer.periodic(const Duration(seconds: 10), (_) => _pollUpdates());
  }

  Future<void> _pollUpdates() async {
    if (!_foreground || !_signedIn || _polling || loading.value || _silent) return;
    final generation = _requestId;
    _polling = true;
    try {
      final data = await ApiClient.instance.get('/v1/companions/updates',
          query: {if (_cursor != null) 'cursor': _cursor});
      if (generation != _requestId || !_signedIn || !_foreground || data is! Map) return;
      final updates = (data['items'] as List? ?? const [])
          .whereType<Map>()
          .map((item) => Map<String, dynamic>.from(item))
          .toList();
      if (updates.any((item) => !companions.any((companion) => companion['id'] == item['id']))) {
        await load(silent: true);
        return;
      }
      final removed = (data['removed_ids'] as List? ?? const []).toSet();
      final changed = {for (final item in updates) item['id']: item};
      if (changed.isNotEmpty || removed.isNotEmpty) {
        companions.assignAll(companions.where((item) => !removed.contains(item['id']))
            .map((item) => <String, dynamic>{
                  ...item,
                  ...?changed[item['id']],
                }).map(_withReadState).toList());
      }
      _cursor = data['cursor'] as String?;
      await _loadAppointments(generation);
    } on ApiException catch (error) {
      if (generation == _requestId && error.statusCode == 400) _cursor = null;
    } catch (_) {
      // Retain the last snapshot and retry on the next foreground tick.
    } finally {
      _polling = false;
    }
  }

  @override
  void onInit() {
    super.onInit();
    WidgetsBinding.instance.addObserver(this);
    _foreground = WidgetsBinding.instance.lifecycleState == null ||
        WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed;
    _authWorker = ever(AuthController.to.profile, (profile) {
      if (profile == null) {
        _poll?.cancel();
        ++_requestId;
        _cursor = null;
        companions.clear();
        appointments.clear();
        _readThrough.clear();
        loading.value = false;
        _silent = false;
      } else {
        if (companions.isEmpty && _foreground) load();
        _startPolling();
      }
    });
    if (_signedIn && _foreground) load();
    _startPolling();
  }

  @override
  void onClose() {
    _poll?.cancel();
    _authWorker?.dispose();
    ++_requestId;
    WidgetsBinding.instance.removeObserver(this);
    super.onClose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    _poll?.cancel();
    if (_foreground && _signedIn) {
      load(silent: true);
      _startPolling();
    }
  }

  void prepareInitialLoad() {
    ++_requestId;
    _cursor = null;
    companions.clear();
    appointments.clear();
    loading.value = true;
    failed.value = false;
    _silent = false;
  }

  Future<void> load({bool silent = false}) async {
    if (!_signedIn || !_foreground) return;
    if (silent && (_silent || loading.value)) return;
    final requestId = ++_requestId;
    _silent = silent;
    if (!silent) {
      loading.value = true;
      failed.value = false;
    }
    try {
      final data = await ApiClient.instance.get('/v1/companions');
      if (requestId != _requestId || !_signedIn) return;
      _cursor = null;
      if (data is! List) throw StateError('invalid companions response');
      companions.assignAll(
        data
            .whereType<Map<String, dynamic>>()
            .where((e) => e['creation_source'] != 'ai_pet')
            .map((e) => _withReadState(Map<String, dynamic>.from(e))),
      );
      await _loadAppointments(requestId);
    } catch (_) {
      if (requestId == _requestId && !silent && companions.isEmpty) {
        failed.value = true;
      }
    } finally {
      if (requestId == _requestId) {
        loading.value = false;
        _silent = false;
      }
    }
  }

  Future<void> _loadAppointments(int generation) async {
    try {
      final data = await ApiClient.instance.get('/v1/companions/appointments');
      if (generation != _requestId || !_signedIn || !_foreground) return;
      if (data is! Map || data['items'] is! List) return;
      appointments.assignAll((data['items'] as List).whereType<Map>()
          .map((item) => Map<String, dynamic>.from(item)));
    } catch (_) {
      // Keep chat usable when the optional date strip cannot refresh.
    }
  }

  /// Unread contacts first, then newest message; ties retain the server order.
  List<Map<String, dynamic>> get filtered {
    final q = searchQuery.value.trim().toLowerCase();
    final entries = companions.toList().asMap().entries.where((entry) {
      final name = (entry.value['name'] as String? ?? '').toLowerCase();
      return q.isEmpty || name.contains(q);
    }).toList();
    entries.sort((a, b) {
      final first = ChatListPresentation.from(a.value);
      final second = ChatListPresentation.from(b.value);
      final firstUnread = first.unreadCount > 0;
      final secondUnread = second.unreadCount > 0;
      if (firstUnread != secondUnread) return firstUnread ? -1 : 1;
      final firstAt = first.messageAt;
      final secondAt = second.messageAt;
      if (firstAt == null && secondAt != null) return 1;
      if (firstAt != null && secondAt == null) return -1;
      if (firstAt != null && secondAt != null) {
        final order = secondAt.compareTo(firstAt);
        if (order != 0) return order;
      }
      return a.key.compareTo(b.key);
    });
    return entries.map((entry) => entry.value).toList();
  }
}
