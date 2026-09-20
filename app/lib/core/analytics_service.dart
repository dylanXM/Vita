import 'dart:async';
import 'dart:math';

import 'package:flutter/widgets.dart';
import 'package:get/get.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'api_client.dart';

class AnalyticsService extends GetxService with WidgetsBindingObserver {
  static AnalyticsService get to => Get.find();
  static const _installKey = 'vita.analytics.install_id';

  final _random = Random.secure();
  final _queue = <Map<String, dynamic>>[];
  late final String sessionId = _id('session');
  String _anonymousId = '';
  Timer? _timer;
  bool _flushing = false;
  Future<void>? _identityFuture;

  @override
  void onInit() {
    super.onInit();
    WidgetsBinding.instance.addObserver(this);
    _identityFuture = _loadIdentity();
    track('app_started', category: 'system');
  }

  Future<void> _loadIdentity() async {
    final prefs = await SharedPreferences.getInstance();
    _anonymousId = prefs.getString(_installKey) ?? '';
    if (_anonymousId.isEmpty) {
      _anonymousId = _id('install');
      await prefs.setString(_installKey, _anonymousId);
    }
  }

  String _id(String prefix) =>
      '$prefix-${DateTime.now().microsecondsSinceEpoch}-${_random.nextInt(1 << 32)}';

  void track(
    String name, {
    String? category,
    Map<String, Object?> properties = const {},
  }) {
    unawaited(_record(name, category: category, properties: properties));
  }

  void screen(String name) => track(
        'screen_view',
        category: 'navigation',
        properties: {'screen': name},
      );

  Future<void> _record(
    String name, {
    String? category,
    required Map<String, Object?> properties,
  }) async {
    await _identityFuture;
    _queue.add({
      'event_id': _id('event'),
      'name': name,
      'category': category ?? '',
      'anonymous_id': _anonymousId,
      'session_id': sessionId,
      'timestamp': DateTime.now().toUtc().toIso8601String(),
      'properties':
          properties.map((key, value) => MapEntry(key, _safeValue(value))),
    });
    if (_queue.length >= 20) {
      unawaited(flush());
    } else {
      _timer ??= Timer(const Duration(seconds: 2), () {
        _timer = null;
        unawaited(flush());
      });
    }
  }

  Object? _safeValue(Object? value) {
    if (value == null || value is String || value is num || value is bool) {
      return value;
    }
    return value.toString();
  }

  Future<void> flush() async {
    if (_flushing || _queue.isEmpty) return;
    _flushing = true;
    final batch = List<Map<String, dynamic>>.from(_queue);
    _queue.clear();
    try {
      await ApiClient.instance.post('/v1/events', data: {'events': batch});
    } catch (_) {
      _queue.insertAll(0, batch);
    } finally {
      _flushing = false;
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive ||
        state == AppLifecycleState.detached) {
      unawaited(flush());
    }
  }

  @override
  void onClose() {
    WidgetsBinding.instance.removeObserver(this);
    _timer?.cancel();
    super.onClose();
  }
}
