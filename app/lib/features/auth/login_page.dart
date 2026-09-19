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
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 48),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 16),
              // Brand mark — gradient circle instead of a logo asset.
              Center(
                child: Container(
                  width: 88,
                  height: 88,
                  decoration: const BoxDecoration(
                    gradient: VitaColors.brandGradient,
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(color: Color(0x3307C160), blurRadius: 24, offset: Offset(0, 8)),
                    ],
                  ),
                  child: const Icon(Icons.favorite, color: Colors.white, size: 42),
                ),
              ),
              const SizedBox(height: 20),
              const Text(
                'Vita',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 32,
                  fontWeight: FontWeight.w800,
                  color: VitaColors.text,
                  letterSpacing: 0.5,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'A companion who lives somewhere else',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 14, color: VitaColors.subText),
              ),
              const SizedBox(height: 44),
              TextField(
                controller: _email,
                keyboardType: TextInputType.emailAddress,
                autocorrect: false,
                textInputAction: TextInputAction.next,
                decoration: const InputDecoration(hintText: 'Email'),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: _password,
                obscureText: _obscurePassword,
                autocorrect: false,
                onSubmitted: (_) => _login(),
                decoration: InputDecoration(
                  hintText: 'Password',
                  suffixIcon: IconButton(
                    icon: Icon(
                      _obscurePassword ? Icons.visibility_off : Icons.visibility,
                      color: VitaColors.subText,
                      size: 20,
                    ),
                    onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
                  ),
                ),
              ),
              const SizedBox(height: 28),
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
                icon: const Icon(Icons.g_mobiledata, color: VitaColors.text, size: 26),
                label: const Text('Continue with Google'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: VitaColors.text,
                  side: const BorderSide(color: VitaColors.divider),
                  minimumSize: const Size.fromHeight(50),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(VitaRadius.pill)),
                ),
              ),
              const SizedBox(height: 24),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Text(
                    'No account yet? ',
                    style: TextStyle(fontSize: 13.5, color: VitaColors.subText),
                  ),
                  TextButton(
                    onPressed: () => Get.toNamed('/register'),
                    child: const Text(
                      'Register',
                      style: TextStyle(color: VitaColors.green, fontSize: 13.5, fontWeight: FontWeight.w600),
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
