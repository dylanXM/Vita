import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:get/get.dart';

import 'api_client.dart';
import 'app_content_controller.dart';
import 'settings_controller.dart';
import 'supported_locales.dart';
import '../features/auth/auth_controller.dart';
import '../features/ads/admob_controller.dart';
import '../features/billing/billing_controller.dart';

/// One foreground version probe; full payloads refresh only for changed groups.
class ConfigSyncController extends GetxController with WidgetsBindingObserver {
  ConfigSyncController(
      {Future<dynamic> Function()? fetchVersions,
      Future<bool> Function(String, bool)? synchronizeResource,
      DateTime Function()? clock})
      : _fetchVersions = fetchVersions ??
            (() => ApiClient.instance.get('/v1/app-config/versions',
                receiveTimeout: const Duration(seconds: 5))),
        _synchronizeResource = synchronizeResource,
        _clock = clock ?? DateTime.now;
  final Future<dynamic> Function() _fetchVersions;
  final Future<bool> Function(String, bool)? _synchronizeResource;
  final DateTime Function() _clock;

  static ConfigSyncController get to => Get.find();
  final revisions = <String, String>{}.obs;
  int _notificationRevision = 0;

  // A page payload failed: retry on the next bounded probe, never in a loop.
  void invalidate(String resource) {
    _applied.remove(resource);
  }

  final _applied = <String, String>{};
  String? _billingCatalogSignature;
  Future<void>? _flight;
  Timer? _timer;
  Worker? _authWorker;
  Worker? _localeWorker;
  DateTime? _lastProbe;
  DateTime? _nextContentChange;
  DateTime? _retryAfter;
  String _lastIdentity = '';
  String _lastAccount = '';
  bool _foreground = true;
  bool _closed = false;
  bool _rerun = false;
  int _failures = 0;
  bool versionsUnavailable = false;

  String get _identity =>
      '${AuthController.to.profile.value?['user_id'] ?? ''}:${vitaLocaleTag(VitaSettingsController.to.effectiveLocale)}';
  bool get _signedIn => AuthController.to.profile.value != null;

  @override
  void onInit() {
    super.onInit();
    WidgetsBinding.instance.addObserver(this);
    _foreground = WidgetsBinding.instance.lifecycleState == null ||
        WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed;
    _authWorker = ever(AuthController.to.profile, (_) {
      final account = '${AuthController.to.profile.value?['user_id'] ?? ''}';
      if (account != _lastAccount) {
        _lastAccount = account;
        for (final resource in ['billing', 'ads', 'companion', 'experiences']) {
          _applied.remove(resource);
        }
        _billingCatalogSignature = null;
      }
      _schedule();
      if (_identity != _lastIdentity) unawaited(refresh());
    });
    _localeWorker = ever(VitaSettingsController.to.locale, (_) {
      scheduleMicrotask(() => refresh());
    });
    _schedule();
  }

  void _schedule() {
    _timer?.cancel();
    if (!_foreground || _closed || !_signedIn) return;
    // Each device gets a small deterministic offset to avoid synchronized bursts.
    final offset = _clock().millisecond % 15;
    _timer = Timer.periodic(Duration(seconds: 60 + offset), (_) => refresh());
  }

  Future<void> refresh({bool force = false}) {
    if (_closed || !_foreground) return Future.value();
    if (_flight != null) {
      if (_identity != _lastIdentity) _rerun = true;
      return _flight!;
    }
    final now = _clock();
    final identityChanged = _identity != _lastIdentity;
    if (!identityChanged && _retryAfter != null && now.isBefore(_retryAfter!))
      return Future.value();
    final interval =
        force ? const Duration(seconds: 5) : const Duration(seconds: 30);
    if (!identityChanged &&
        _lastProbe != null &&
        now.difference(_lastProbe!) < interval) return Future.value();
    final flight = _run();
    _flight = flight;
    return flight.whenComplete(() {
      _flight = null;
      if (_rerun && !_closed && _foreground) {
        _rerun = false;
        unawaited(refresh());
      }
    });
  }

  Future<void> _run() async {
    await VitaSettingsController.to.ready.future;
    final identity = _identity;
    _lastIdentity = identity;
    _lastProbe = _clock();
    bool manifestLoaded = false;
    try {
      final raw = await _fetchVersions();
      if (_closed || !_foreground || _identity != identity) {
        _rerun = true;
        return;
      }
      final map = raw is Map ? raw['versions'] : null;
      if (map is! Map) throw StateError('Invalid configuration versions');
      final versions = Map<String, String>.fromEntries(map.entries
          .map((entry) => MapEntry('${entry.key}', '${entry.value}')));
      if (!['content', 'billing', 'ads', 'companion', 'experiences']
          .every(versions.containsKey))
        throw StateError('Incomplete configuration versions');
      manifestLoaded = true;
      versionsUnavailable = false;
      final serverTime =
          DateTime.tryParse('${raw['server_time'] ?? ''}') ?? _clock().toUtc();
      if (_nextContentChange != null &&
          !serverTime.isBefore(_nextContentChange!)) _applied.remove('content');
      _nextContentChange =
          DateTime.tryParse('${raw['content_next_change_at'] ?? ''}');
      bool allSucceeded = true;
      for (final resource in [
        'content',
        'billing',
        'ads',
        'companion',
        'experiences'
      ]) {
        final version = versions[resource];
        if (version == null) continue;
        final user = '${AuthController.to.profile.value?['user_id'] ?? ''}';
        final signature = resource == 'content'
            ? version
            : resource == 'ads'
                ? '$version:$user'
                : '$version:$identity';
        if (_applied[resource] == signature) continue;
        if (!_signedIn && resource != 'content') continue;
        bool succeeded = true;
        if (_synchronizeResource != null) {
          final catalogSignature = '$version:$user';
          succeeded = await _synchronizeResource!(
              resource, _billingCatalogSignature != catalogSignature);
          if (resource == 'billing' && succeeded)
            _billingCatalogSignature = catalogSignature;
        } else
          switch (resource) {
            case 'content':
              succeeded = await AppContentController.to.synchronize();
              break;
            case 'billing':
              final catalogSignature = '$version:$user';
              succeeded = await BillingController.to.synchronizeConfiguration(
                  refreshCatalog: _billingCatalogSignature != catalogSignature);
              if (succeeded) _billingCatalogSignature = catalogSignature;
              break;
            case 'ads':
              succeeded = await AdmobController.to.synchronizeConfiguration();
              break;
          }
        if (_closed || !_foreground || _identity != identity) {
          _rerun = true;
          return;
        }
        if (!succeeded) allSucceeded = false;
        if (succeeded) {
          _applied[resource] = signature;
          revisions[resource] = '$signature:${++_notificationRevision}';
        }
      }
      if (!allSucceeded) throw StateError('Configuration refresh failed');
      _failures = 0;
      _retryAfter = null;
    } catch (_) {
      versionsUnavailable = !manifestLoaded;
      _failures = (_failures + 1).clamp(1, 4).toInt();
      _retryAfter =
          _clock().add(Duration(seconds: 30 * (1 << (_failures - 1))));
      // Preserve last valid payload. A later foreground probe retries safely.
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    _schedule();
    if (_foreground) unawaited(refresh(force: true));
  }

  @override
  void didChangeLocales(List<Locale>? locales) {
    if (VitaSettingsController.to.locale.value == null)
      scheduleMicrotask(() => refresh());
  }

  @override
  void onClose() {
    _closed = true;
    _timer?.cancel();
    _authWorker?.dispose();
    _localeWorker?.dispose();
    WidgetsBinding.instance.removeObserver(this);
    super.onClose();
  }
}
