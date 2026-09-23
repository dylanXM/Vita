import 'dart:async';

import 'package:get/get.dart';
import 'package:flutter/widgets.dart';

import '../../core/api_client.dart';

/// Loads the user's companions for the Chat tab.
///
/// Refreshes on three triggers:
///  * pull-to-refresh from the UI,
///  * app foreground resume (lifecycle),
///  * a quiet 30s timer while the page is alive, so Life Engine proactive
///    messages show up without the user having to enter and exit a chat.
class ChatListController extends GetxController with WidgetsBindingObserver {
  static ChatListController get to => Get.find();

  final loading = false.obs;
  final companions = <Map<String, dynamic>>[].obs;
  final searchQuery = ''.obs;

  Timer? _poll;
  bool _silent = false;

  @override
  void onInit() {
    super.onInit();
    WidgetsBinding.instance.addObserver(this);
    load();
    _poll = Timer.periodic(const Duration(seconds: 30), (_) => load(silent: true));
  }

  @override
  void onClose() {
    _poll?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.onClose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      load(silent: true);
    }
  }

  Future<void> load({bool silent = false}) async {
    if (silent && _silent) return;
    _silent = silent;
    if (!silent) loading.value = true;
    try {
      final data = await ApiClient.instance.get('/v1/companions');
      if (data is List) {
        companions.assignAll(
          data.whereType<Map<String, dynamic>>().map((e) => Map<String, dynamic>.from(e)),
        );
      }
    } catch (_) {
      // keep the previous list; the empty state explains itself
    } finally {
      loading.value = false;
      _silent = false;
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
