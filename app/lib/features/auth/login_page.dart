import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../core/theme.dart';
import 'auth_controller.dart';

/// Email + password login and Google sign-in. New users are directed to the
/// two-step registration page (email + password, then a 6-digit code).
class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _obscurePassword = true;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  bool get _emailValid => _email.text.contains('@') && _email.text.length > 4;

  bool get _canSubmit => _emailValid && _password.text.isNotEmpty;

  Future<void> _login() async {
    if (!_canSubmit) return;
    try {
      await AuthController.to.login(_email.text.trim(), _password.text);
      Get.offAllNamed('/shell');
    } catch (e) {
      Get.snackbar('auth.loginFailed'.tr, '$e');
    }
  }

  Future<void> _googleLogin() async {
    try {
      if (await AuthController.to.loginWithGoogle()) {
        Get.offAllNamed('/shell');
      }
    } catch (e) {
      Get.snackbar('auth.googleFailed'.tr, '$e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.vita.surface,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 48),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 16),
              // A quiet brand mark keeps the authentication screen familiar.
              Center(
                child: Container(
                  width: 88,
                  height: 88,
                  decoration: BoxDecoration(
                    color: context.vita.green,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child:
                      const Icon(Icons.favorite, color: Colors.white, size: 42),
                ),
              ),
              const SizedBox(height: 20),
              Text(
                'Vita',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 32,
                  fontWeight: FontWeight.w800,
                  color: context.vita.text,
                  letterSpacing: 0.5,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'auth.tagline'.tr,
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 14, color: context.vita.subText),
              ),
              const SizedBox(height: 44),
              TextField(
                controller: _email,
                keyboardType: TextInputType.emailAddress,
                autocorrect: false,
                textInputAction: TextInputAction.next,
                decoration: InputDecoration(hintText: 'auth.email'.tr),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: _password,
                obscureText: _obscurePassword,
                autocorrect: false,
                onSubmitted: (_) => _login(),
                decoration: InputDecoration(
                  hintText: 'auth.password'.tr,
                  suffixIcon: IconButton(
                    icon: Icon(
                      _obscurePassword
                          ? Icons.visibility_off
                          : Icons.visibility,
                      color: context.vita.subText,
                      size: 20,
                    ),
                    onPressed: () =>
                        setState(() => _obscurePassword = !_obscurePassword),
                  ),
                ),
              ),
              const SizedBox(height: 28),
              Obx(
                () => ElevatedButton(
                  onPressed: (AuthController.to.loading.value || !_canSubmit)
                      ? null
                      : _login,
                  child: AuthController.to.loading.value
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white),
                        )
                      : Text('auth.login'.tr),
                ),
              ),
              const SizedBox(height: 24),
              Row(
                children: [
                  const Expanded(child: Divider()),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: Text('auth.or'.tr,
                        style: TextStyle(
                            color: context.vita.subText.withValues(alpha: 0.8),
                            fontSize: 13)),
                  ),
                  const Expanded(child: Divider()),
                ],
              ),
              const SizedBox(height: 24),
              OutlinedButton.icon(
                onPressed: _googleLogin,
                icon: Icon(Icons.g_mobiledata,
                    color: context.vita.text, size: 26),
                label: Text('auth.continueGoogle'.tr),
                style: OutlinedButton.styleFrom(
                  foregroundColor: context.vita.text,
                  side: BorderSide(color: context.vita.divider),
                  minimumSize: const Size.fromHeight(50),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(4)),
                ),
              ),
              const SizedBox(height: 24),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    'auth.noAccount'.tr,
                    style:
                        TextStyle(fontSize: 13.5, color: context.vita.subText),
                  ),
                  TextButton(
                    onPressed: () => Get.toNamed('/register'),
                    child: Text(
                      'auth.register'.tr,
                      style: TextStyle(
                          color: context.vita.green,
                          fontSize: 13.5,
                          fontWeight: FontWeight.w600),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
