import 'package:get/get.dart';
import 'package:google_sign_in/google_sign_in.dart';

import '../../core/api_client.dart';
import '../../core/analytics_service.dart';
import '../../core/constants.dart';
import '../../core/push_notification_service.dart';
import '../../core/settings_controller.dart';
import '../../core/token_storage.dart';
import '../billing/billing_controller.dart';

/// Auth state: email + password login, two-step email registration
/// (password first, then a 6-digit verification code) and Google sign-in
/// (self-hosted OIDC — the backend verifies the ID token).
class AuthController extends GetxController {
  static AuthController get to => Get.find();

  final loading = false.obs;
  final profile = Rxn<Map<String, dynamic>>();

  /// Starts registration: the backend checks the email, stores the password
  /// and emails a 6-digit code (60s resend cooldown).
  Future<void> register(String email, String password, String inviteCode,
      {required bool acceptedLegal,
      required String privacyPolicyVersion,
      required String termsVersion}) async {
    loading.value = true;
    AnalyticsService.to
        .track('auth_register_started', category: 'auth', properties: {
      'has_invite_code': inviteCode.trim().isNotEmpty,
    });
    try {
      await ApiClient.instance.post(
        '/v1/auth/app/register',
        data: {
          'email': email,
          'password': password,
          'invite_code': inviteCode.trim().toUpperCase(),
          'accepted_legal': acceptedLegal,
          'privacy_policy_version': privacyPolicyVersion,
          'terms_version': termsVersion,
        },
      );
      AnalyticsService.to.track('auth_register_code_sent', category: 'auth');
    } catch (e) {
      AnalyticsService.to.track('auth_register_failed',
          category: 'auth', properties: {'stage': 'send_code'});
      rethrow;
    } finally {
      loading.value = false;
    }
  }

  /// Completes registration with the emailed code; stores the session token.
  Future<void> verifyRegistration(String email, String code) async {
    loading.value = true;
    try {
      final data = await ApiClient.instance.post(
        '/v1/auth/app/register/verify',
        data: {'email': email, 'code': code},
      );
      await _storeSession(data);
      await fetchProfile();
      AnalyticsService.to.track('auth_register_succeeded', category: 'auth');
      await AnalyticsService.to.flush();
    } catch (e) {
      AnalyticsService.to.track('auth_register_failed',
          category: 'auth', properties: {'stage': 'verify'});
      rethrow;
    } finally {
      loading.value = false;
    }
  }

  Future<void> login(String email, String password) async {
    loading.value = true;
    AnalyticsService.to.track('auth_login_started',
        category: 'auth', properties: {'method': 'password'});
    try {
      final data = await ApiClient.instance.post(
        '/v1/auth/app/login',
        data: {'email': email, 'password': password},
      );
      await _storeSession(data);
      await fetchProfile();
      AnalyticsService.to.track('auth_login_succeeded',
          category: 'auth', properties: {'method': 'password'});
      await AnalyticsService.to.flush();
    } catch (e) {
      AnalyticsService.to.track('auth_login_failed',
          category: 'auth', properties: {'method': 'password'});
      rethrow;
    } finally {
      loading.value = false;
    }
  }

  Future<bool> loginWithGoogle({
    bool acceptedLegal = false,
    String privacyPolicyVersion = '',
    String termsVersion = '',
  }) async {
    loading.value = true;
    AnalyticsService.to.track('auth_login_started',
        category: 'auth', properties: {'method': 'google'});
    try {
      final google = GoogleSignIn(serverClientId: googleServerClientId);
      final account = await google.signIn();
      if (account == null) return false; // user cancelled
      final auth = await account.authentication;
      final idToken = auth.idToken;
      if (idToken == null) {
        throw ApiException('Google sign-in did not return an ID token');
      }
      final data = await ApiClient.instance.post(
        '/v1/auth/google',
        data: {
          'id_token': idToken,
          'accepted_legal': acceptedLegal,
          'privacy_policy_version': privacyPolicyVersion,
          'terms_version': termsVersion,
        },
      );
      await _storeSession(data);
      await fetchProfile();
      AnalyticsService.to.track('auth_login_succeeded',
          category: 'auth', properties: {'method': 'google'});
      await AnalyticsService.to.flush();
      return true;
    } catch (e) {
      AnalyticsService.to.track('auth_login_failed',
          category: 'auth', properties: {'method': 'google'});
      rethrow;
    } finally {
      loading.value = false;
    }
  }

  Future<void> fetchProfile() async {
    profile.value =
        await ApiClient.instance.get('/v1/me') as Map<String, dynamic>?;
    await VitaSettingsController.to.syncLocale();
    final userID = profile.value?['user_id'] as String? ?? '';
    if (userID.isNotEmpty && Get.isRegistered<BillingController>()) {
      await BillingController.to.syncUser(userID);
    }
  }

  String get email => profile.value?['email'] as String? ?? '';

  /// Display name chosen by the user. Falls back to the email on the UI
  /// layer when empty.
  String get nickname => profile.value?['nickname'] as String? ?? '';

  /// Media path returned by POST /v1/media/upload (e.g. `/v1/media/<id>`).
  /// Empty means the bundled default avatar should be used.
  String get avatarUrl => profile.value?['avatar_url'] as String? ?? '';

  /// Updates the signed-in user's display name and/or avatar. Pass null for
  /// a field you do not want to change; pass an empty string to clear it.
  /// Refreshes the in-memory profile on success.
  Future<void> updateProfile({String? nickname, String? avatarUrl}) async {
    final data = <String, dynamic>{};
    if (nickname != null) data['nickname'] = nickname.trim();
    if (avatarUrl != null) data['avatar_url'] = avatarUrl.trim();
    if (data.isEmpty) return;
    await ApiClient.instance.put('/v1/me/profile', data: data);
    await fetchProfile();
  }

  Future<void> logout() async {
    AnalyticsService.to.track('auth_logout', category: 'auth');
    await AnalyticsService.to.flush();
    await PushNotificationService.instance.deactivate();
    try {
      await ApiClient.instance.post('/v1/auth/logout');
    } catch (_) {
      // Local logout must still complete if the server cannot be reached.
    }
    if (Get.isRegistered<BillingController>()) {
      await BillingController.to.clearUser();
    }
    await TokenStorage.clear();
    profile.value = null;
    Get.offAllNamed('/login');
  }

  Future<void> _storeSession(dynamic response) async {
    final data = Map<String, dynamic>.from(response as Map);
    final token = data['token'] as String? ?? '';
    final refreshToken = data['refresh_token'] as String? ?? '';
    if (token.isEmpty || refreshToken.isEmpty) {
      throw ApiException('Server did not return a complete session');
    }
    await TokenStorage.writeSession(token, refreshToken);
  }
}
