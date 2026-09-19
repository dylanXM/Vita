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
      Get.snackbar('Login failed', '$e');
    }
  }

  Future<void> _googleLogin() async {
    try {
      await AuthController.to.loginWithGoogle();
      Get.offAllNamed('/shell');
    } catch (e) {
      Get.snackbar('Google sign-in failed', '$e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 40),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 32),
              // Brand mark — simple two-tone circle instead of a logo asset.
              Center(
                child: Container(
                  width: 72,
                  height: 72,
                  decoration: const BoxDecoration(
                    color: VitaColors.green,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.favorite, color: Colors.white, size: 36),
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                'Vita',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 28, fontWeight: FontWeight.w700, color: VitaColors.text),
              ),
              const SizedBox(height: 6),
              const Text(
                'A companion who lives somewhere else',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 14, color: VitaColors.subText),
              ),
              const SizedBox(height: 40),
              TextField(
                controller: _email,
                keyboardType: TextInputType.emailAddress,
                autocorrect: false,
                onChanged: (_) => setState(() {}),
                decoration: const InputDecoration(hintText: 'Email'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _password,
                obscureText: _obscurePassword,
                autocorrect: false,
                onSubmitted: (_) => _login(),
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                  hintText: 'Password',
                  suffixIcon: IconButton(
                    icon: Icon(
                      _obscurePassword ? Icons.visibility_off : Icons.visibility,
                      color: VitaColors.subText,
                    ),
                    onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              Obx(
                () => ElevatedButton(
                  onPressed: (AuthController.to.loading.value || !_canSubmit) ? null : _login,
                  child: AuthController.to.loading.value
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                        )
                      : const Text('Login'),
                ),
              ),
              const SizedBox(height: 24),
              Row(
                children: [
                  const Expanded(child: Divider()),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: Text('or', style: TextStyle(color: VitaColors.subText.withValues(alpha: 0.8), fontSize: 13)),
                  ),
                  const Expanded(child: Divider()),
                ],
              ),
              const SizedBox(height: 24),
              OutlinedButton.icon(
                onPressed: _googleLogin,
                icon: const Icon(Icons.g_mobiledata, color: VitaColors.text, size: 28),
                label: const Text('Continue with Google'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: VitaColors.text,
                  side: const BorderSide(color: VitaColors.divider),
                  minimumSize: const Size.fromHeight(48),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
              ),
              const SizedBox(height: 20),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Text(
                    'No account yet? ',
                    style: TextStyle(fontSize: 13, color: VitaColors.subText),
                  ),
                  TextButton(
                    onPressed: () => Get.toNamed('/register'),
                    child: const Text(
                      'Register',
                      style: TextStyle(color: VitaColors.green, fontSize: 13, fontWeight: FontWeight.w600),
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
