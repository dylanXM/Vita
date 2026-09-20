import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:get/get.dart';

import '../features/chat/chat_list_controller.dart';
import '../features/chat/chat_page.dart';
import 'api_client.dart';
import 'constants.dart';

class PushNotificationService {
  PushNotificationService._();

  static final instance = PushNotificationService._();

  bool _initialized = false;
  bool _active = false;
  StreamSubscription<String>? _tokenSubscription;
  StreamSubscription<RemoteMessage>? _openSubscription;
  Map<String, dynamic>? _pendingNavigation;
  String? _registeredToken;

  bool get isConfigured {
    final supported = defaultTargetPlatform == TargetPlatform.iOS ||
        defaultTargetPlatform == TargetPlatform.android;
    if (!supported) return false;
    return firebaseProjectId.isNotEmpty &&
        firebaseApiKey.isNotEmpty &&
        firebaseMessagingSenderId.isNotEmpty &&
        (defaultTargetPlatform == TargetPlatform.iOS
            ? firebaseIosAppId.isNotEmpty
            : firebaseAndroidAppId.isNotEmpty);
  }

  Future<void> initialize() async {
    if (_initialized || !isConfigured || kIsWeb) return;
    try {
      final ios = defaultTargetPlatform == TargetPlatform.iOS;
      await Firebase.initializeApp(
        options: FirebaseOptions(
          apiKey: firebaseApiKey,
          appId: ios ? firebaseIosAppId : firebaseAndroidAppId,
          messagingSenderId: firebaseMessagingSenderId,
          projectId: firebaseProjectId,
          iosBundleId: ios && firebaseIosBundleId.isNotEmpty
              ? firebaseIosBundleId
              : null,
        ),
      );
      _initialized = true;
      _openSubscription = FirebaseMessaging.onMessageOpenedApp.listen(
        (message) => _handleNavigation(message.data),
      );
      final initial = await FirebaseMessaging.instance.getInitialMessage();
      if (initial != null) _pendingNavigation = initial.data;
    } catch (error) {
      debugPrint('Push initialization skipped: $error');
    }
  }

  Future<void> activateForSignedInUser() async {
    await initialize();
    if (!_initialized || _active) {
      openPendingNotification();
      return;
    }
    try {
      final messaging = FirebaseMessaging.instance;
      final permission = await messaging.requestPermission(
        alert: true,
        badge: true,
        sound: true,
      );
      if (permission.authorizationStatus == AuthorizationStatus.denied) return;
      final token = await _getTokenWhenReady(messaging);
      if (token != null) await _register(token);
      _tokenSubscription = messaging.onTokenRefresh.listen(
        (token) => _register(token),
        onError: (Object error) =>
            debugPrint('Push token refresh failed: $error'),
      );
      _active = true;
      openPendingNotification();
    } catch (error) {
      _active = false;
      debugPrint('Push activation failed: $error');
    }
  }

  Future<String?> _getTokenWhenReady(FirebaseMessaging messaging) async {
    if (defaultTargetPlatform == TargetPlatform.iOS) {
      for (var attempt = 0; attempt < 10; attempt++) {
        if (await messaging.getAPNSToken() != null) break;
        await Future<void>.delayed(const Duration(milliseconds: 500));
      }
    }
    return messaging.getToken();
  }

  Future<void> _register(String token) async {
    if (token.isEmpty || token == _registeredToken) return;
    await ApiClient.instance.post('/v1/me/push-tokens', data: {
      'token': token,
      'platform':
          defaultTargetPlatform == TargetPlatform.iOS ? 'ios' : 'android',
      'locale': Get.locale?.toLanguageTag() ?? '',
    });
    _registeredToken = token;
  }

  Future<void> deactivate() async {
    String? token = _registeredToken;
    if (token == null && _initialized) {
      try {
        token = await FirebaseMessaging.instance.getToken();
      } catch (_) {
        // Firebase may not have issued a token yet.
      }
    }
    if (token != null) {
      try {
        await ApiClient.instance.delete(
          '/v1/me/push-tokens',
          data: {'token': token},
        );
      } catch (_) {
        // Token expiry and uninstall cleanup are also handled by the backend.
      }
    }
    await _tokenSubscription?.cancel();
    _tokenSubscription = null;
    _registeredToken = null;
    _active = false;
  }

  void openPendingNotification() {
    final data = _pendingNavigation;
    if (data == null) return;
    _pendingNavigation = null;
    WidgetsBinding.instance.addPostFrameCallback((_) => _openChat(data));
  }

  void _handleNavigation(Map<String, dynamic> data) {
    if (Get.currentRoute == '/login' || Get.currentRoute == '/') {
      _pendingNavigation = data;
      return;
    }
    _openChat(data);
  }

  void _openChat(Map<String, dynamic> data) {
    if (data['route'] != 'companion_chat') return;
    final companionId = data['companion_id']?.toString() ?? '';
    if (companionId.isEmpty) return;
    Map<String, dynamic>? companion;
    if (Get.isRegistered<ChatListController>()) {
      for (final item in ChatListController.to.companions) {
        if (item['id'] == companionId) {
          companion = item;
          break;
        }
      }
    }
    final name = companion?['name']?.toString() ??
        data['companion_name']?.toString() ??
        'Vita';
    Get.to(
      () => ChatPage(
        companionId: companionId,
        name: name,
        companion: companion,
      ),
      transition: Transition.cupertino,
    );
  }

  Future<void> dispose() async {
    await _tokenSubscription?.cancel();
    await _openSubscription?.cancel();
  }
}
