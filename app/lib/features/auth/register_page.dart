import 'dart:async';

import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../core/theme.dart';
import 'auth_controller.dart';

/// Two-step registration, mirroring the login page layout:
/// step 1 collects the email + password, step 2 the 6-digit code that the
/// backend emails. A verified code creates the account and signs the user in.
class RegisterPage extends StatefulWidget {
  const RegisterPage({super.key});

  @override
  State<RegisterPage> createState() => _RegisterPageState();
}

class _RegisterPageState extends State<RegisterPage> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _code = TextEditingController();
  Timer? _timer;
  int _countdown = 0;
  int _step = 1;
  bool _obscurePassword = true;

  @override
  void dispose() {
    _timer?.cancel();
    _email.dispose();
    _password.dispose();
    _code.dispose();
    super.dispose();
  }

  bool get _emailValid => _email.text.contains('@') && _email.text.length > 4;

  bool get _passwordValid => _password.text.length >= 6;

  void _startCountdown() {
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
  }

  /// Step 1: submit email + password, the backend emails the code.
  Future<void> _sendCode() async {
    if (!_emailValid || !_passwordValid) return;
    try {
      await AuthController.to.register(_email.text.trim(), _password.text);
      setState(() => _step = 2);
      _startCountdown();
      Get.snackbar('Check your inbox', 'We sent a verification code to ${_email.text.trim()}');
    } catch (e) {
      Get.snackbar('Failed to send code', '$e');
    }
  }

  /// Step 2: resend (re-issues the code, 60s server cooldown).
  Future<void> _resendCode() async {
    try {
      await AuthController.to.register(_email.text.trim(), _password.text);
      _startCountdown();
      Get.snackbar('Check your inbox', 'We sent a verification code to ${_email.text.trim()}');
    } catch (e) {
      Get.snackbar('Failed to send code', '$e');
    }
  }

  /// Step 2: verify the code, the account is created and the user signed in.
  Future<void> _verify() async {
    if (_code.text.length != 6) return;
    try {
      await AuthController.to.verifyRegistration(_email.text.trim(), _code.text.trim());
      Get.offAllNamed('/shell');
    } catch (e) {
      Get.snackbar('Verification failed', '$e');
    }
  }

  void _back() {
    if (_step == 2) {
      _code.clear();
      setState(() => _step = 1);
    } else {
      Get.back();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.arrow_back, color: VitaColors.text),
                    onPressed: _back,
                  ),
                ],
              ),
              if (_step == 1) ...[
                const SizedBox(height: 24),
                const Text(
                  'Create account',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 24, fontWeight: FontWeight.w700, color: VitaColors.text),
                ),
                const SizedBox(height: 6),
                const Text(
                  'Sign up with your email and a password',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 14, color: VitaColors.subText),
                ),
                const SizedBox(height: 32),
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
                  onSubmitted: (_) => _sendCode(),
                  onChanged: (_) => setState(() {}),
                  decoration: InputDecoration(
                    hintText: 'Password (at least 6 characters)',
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
                    onPressed: (AuthController.to.loading.value || !_emailValid || !_passwordValid)
                        ? null
                        : _sendCode,
                    child: AuthController.to.loading.value
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                          )
                        : const Text('Get verification code'),
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Text(
                      'Already have an account? ',
                      style: TextStyle(fontSize: 13, color: VitaColors.subText),
                    ),
                    TextButton(
                      onPressed: () => Get.back(),
                      child: const Text(
                        'Login',
                        style: TextStyle(color: VitaColors.green, fontSize: 13, fontWeight: FontWeight.w600),
                      ),
                    ),
                  ],
                ),
              ] else ...[
                const SizedBox(height: 24),
                const Text(
                  'Verify your email',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 24, fontWeight: FontWeight.w700, color: VitaColors.text),
                ),
                const SizedBox(height: 6),
                Text(
                  'We sent a 6-digit code to ${_email.text.trim()}',
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 14, color: VitaColors.subText),
                ),
                const SizedBox(height: 32),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _code,
                        keyboardType: TextInputType.number,
                        maxLength: 6,
                        onSubmitted: (_) => _verify(),
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
                        onPressed: (_countdown > 0 || AuthController.to.loading.value) ? null : _resendCode,
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
                    onPressed: (AuthController.to.loading.value || _code.text.length != 6) ? null : _verify,
                    child: AuthController.to.loading.value
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                          )
                        : const Text('Verify and sign in'),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
