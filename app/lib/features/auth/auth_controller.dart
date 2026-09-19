import 'package:get/get.dart';
import 'package:google_sign_in/google_sign_in.dart';

import '../../core/api_client.dart';
import '../../core/constants.dart';
import '../../core/token_storage.dart';

/// Auth state: email + verification code (auto-registers on first use) and
/// Google sign-in (self-hosted OIDC — the backend verifies the ID token).
class AuthController extends GetxController {
  static AuthController get to => Get.find();

  final loading = false.obs;
  final profile = Rxn<Map<String, dynamic>>();

  /// Requests a 6-digit login code; the backend auto-creates the account on
  /// first use, which covers both registration and login.
  Future<void> sendCode(String email) async {
    loading.value = true;
    try {
      await ApiClient.instance.post(
        '/v1/auth/send-code',
        data: {'email': email, 'purpose': 'login'},
      );
    } finally {
      loading.value = false;
    }
  }

  Future<void> loginWithCode(String email, String code) async {
    loading.value = true;
    try {
      final data = await ApiClient.instance.post(
        '/v1/auth/app/login',
        data: {'email': email, 'code': code},
      );
      await TokenStorage.write(data['token'] as String);
      await fetchProfile();
    } finally {
      loading.value = false;
    }
  }

  Future<void> loginWithGoogle() async {
    loading.value = true;
    try {
      final google = GoogleSignIn(serverClientId: googleServerClientId);
      final account = await google.signIn();
      if (account == null) return; // user cancelled
      final auth = await account.authentication;
      final idToken = auth.idToken;
      if (idToken == null) {
        throw ApiException('Google sign-in did not return an ID token');
      }
      final data = await ApiClient.instance.post(
        '/v1/auth/google',
        data: {'id_token': idToken},
      );
      await TokenStorage.write(data['token'] as String);
      await fetchProfile();
    } finally {
      loading.value = false;
    }
  }

  Future<void> fetchProfile() async {
    profile.value = await ApiClient.instance.get('/v1/me') as Map<String, dynamic>?;
  }

  String get email => profile.value?['email'] as String? ?? '';

  Future<void> logout() async {
    await TokenStorage.clear();
    profile.value = null;
    Get.offAllNamed('/login');
  }
}
