import 'dart:async';

import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../core/theme.dart';
import 'auth_controller.dart';

/// Email + verification code login/registration and Google sign-in.
/// One flow covers both register and login: requesting a code auto-creates the
/// account on first use.
class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _email = TextEditingController();
  final _code = TextEditingController();
  Timer? _timer;
  int _countdown = 0;

  @override
  void dispose() {
    _timer?.cancel();
    _email.dispose();
    _code.dispose();
    super.dispose();
  }

  bool get _emailValid => _email.text.contains('@') && _email.text.length > 4;

  void _sendCode() async {
    if (!_emailValid) return;
    try {
      await AuthController.to.sendCode(_email.text.trim());
      setState(() => _countdown = 60);
      _timer?.cancel();
      _timer = Timer.periodic(const Duration(seconds: 1), (t) {
        if (_countdown <= 1) {
          t.cancel();
          setState(() => _countdown = 0);
        } else {
          setState(() => _countdown--);
        }
      });
      Get.snackbar('Check your inbox', 'We sent a login code to ${_email.text.trim()}');
    } catch (e) {
      Get.snackbar('Failed to send code', '$e');
    }
  }

  Future<void> _login() async {
    if (!_emailValid || _code.text.length != 6) return;
    try {
      await AuthController.to.loginWithCode(_email.text.trim(), _code.text.trim());
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
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _code,
                      keyboardType: TextInputType.number,
                      maxLength: 6,
                      onChanged: (_) => setState(() {}),
                      decoration: const InputDecoration(
                        hintText: '6-digit code',
                        counterText: '',
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  SizedBox(
                    height: 48,
                    child: OutlinedButton(
                      onPressed: (_countdown > 0 || !_emailValid) ? null : _sendCode,
                      style: OutlinedButton.styleFrom(
                        foregroundColor: VitaColors.green,
                        side: const BorderSide(color: VitaColors.green),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                      child: Text(_countdown > 0 ? '$_countdown s' : 'Send code'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              Obx(
                () => ElevatedButton(
                  onPressed: (AuthController.to.loading.value) ? null : _login,
                  child: AuthController.to.loading.value
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                        )
                      : const Text('Login / Register'),
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
              const Text(
                'No password needed — we email you a code. '
                'Your first login creates your account.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 12, color: VitaColors.subText),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
