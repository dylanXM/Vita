import 'dart:async';

import 'package:get/get.dart';
import 'package:flutter/widgets.dart';

import '../../core/api_client.dart';
import '../auth/auth_controller.dart';

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
  final searchQuery = ''.obs;
  final currentRoute = ''.obs;

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
                }).toList());
      }
      _cursor = data['cursor'] as String?;
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
            .map((e) => Map<String, dynamic>.from(e)),
      );
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

  /// Filtered companions by name (case-insensitive).
  List<Map<String, dynamic>> get filtered {
    final q = searchQuery.value.trim().toLowerCase();
    if (q.isEmpty) return List.of(companions);
    return companions.where((c) {
      final name = (c['name'] as String? ?? '').toLowerCase();
      return name.contains(q);
    }).toList();
  }
}
